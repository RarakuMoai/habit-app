// Native visual matrix: production app, synthetic in-memory records only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_panel.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'review_fixture.dart';

class _ReviewNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel({required int id}) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Exercise layout matrix and other production pages', (
    tester,
  ) async {
    seedExperienceReview();
    final prefs = await SharedPreferences.getInstance();
    // Keep real exercise state changes and pendulum, exclude sound/permission UI.
    await prefs.setBool(PrefsKeys.exerciseMetronomeSoundOn('jog'), false);
    FlutterLocalNotificationsPlatform.instance = _ReviewNotifications();
    app.main();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const ValueKey('main_navigation')).evaluate().isNotEmpty) {
        break;
      }
    }
    final output = Directory('${Directory.systemTemp.path}/experience-review');
    await output.create(recursive: true);
    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      await settle();
      expect(binding.lifecycleState, AppLifecycleState.resumed, reason: name);
      expect(binding.sendFramesToEngine, isTrue, reason: name);
      final bytes = await binding.takeScreenshot(name);
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      debugPrint('REVIEW_SCREENSHOT ${output.path}/$name.png');
      expect(tester.takeException(), isNull, reason: name);
    }

    final nav = find.byKey(const ValueKey('main_navigation'));
    await tester.tap(find.descendant(of: nav, matching: find.text('計時')));
    await settle();
    for (final room in [true, false]) {
      final layout = room ? 'compact' : 'expanded';
      if (!room) {
        await tester.tap(find.byType(MascotToggleBar).hitTestable());
        await settle();
      }
      await tester.tap(find.byKey(const ValueKey('timer-mode-exercise')));
      await settle();
      for (final kind in ['tabata', 'hiit', 'emom', 'gym', 'jog']) {
        final tile = find.byKey(ValueKey('exercise-kind-$kind'));
        if (!room) await tester.ensureVisible(tile);
        await tester.tap(tile);
        if (!room) {
          final scroll = find
              .descendant(
                of: find.byType(TimerModeFrame),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
        }
        await capture('exercise-$kind-$layout');
        final primary = find.byKey(const ValueKey('timer-primary-action'));
        await tester.tap(primary);
        await settle();
        // Advance preparatory phases using actual production controls.
        for (var i = 0; i < 3; i++) {
          final phase =
              (tester.widget<TimerModeFrame>(find.byType(TimerModeFrame)).status
                      as TimerStatusPill)
                  .stateKey
                  .toString();
          if (phase.contains('work')) break;
          await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          (tester.widget<TimerModeFrame>(find.byType(TimerModeFrame)).status
                  as TimerStatusPill)
              .stateKey
              .toString(),
          contains('work'),
        );
        await capture('exercise-$kind-$layout-running');
        await tester.tap(primary);
        await capture('exercise-$kind-$layout-paused');
        await tester.tap(find.byIcon(Icons.replay_rounded).hitTestable());
        await settle();
      }
      for (final mode in ['focus', 'metronome', 'game']) {
        await tester.tap(find.byKey(ValueKey('timer-mode-$mode')));
        await capture('timer-$mode-$layout');
      }
    }
    await tester.tap(find.byKey(const ValueKey('timer-mode-exercise')));
    await settle();
    final settings = find.byKey(const ValueKey('timer-settings-action'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await capture('exercise-settings');
    await tester.drag(
      find.byKey(const ValueKey('exercise-settings-kind-picker')),
      const Offset(0, -500),
    );
    await capture('exercise-settings-options');
    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('exercise-settings-kind-picker')),
      ),
    ).pop();
    await settle();
    await tester.tap(find.byType(MascotToggleBar).hitTestable());
    await settle();
    for (final page in [
      ('習慣', 'habits'),
      ('喝水', 'water'),
      ('體重', 'weight'),
      ('家庭', 'family'),
      ('衣櫃', 'wardrobe'),
    ]) {
      await tester.tap(find.descendant(of: nav, matching: find.text(page.$1)));
      await capture('page-${page.$2}');
    }
    await tester.tap(find.byTooltip('設定').first);
    await capture('page-settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -620));
    await capture('page-settings-lower');
    debugPrint('REVIEW_COMPLETE ${output.path}');
  });
}
