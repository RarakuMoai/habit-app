// Real native frames with synthetic records; no physical-device operations.
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
  testWidgets('Jog header BPM: native layout and complete controls', (
    tester,
  ) async {
    seedExperienceReview();
    final prefs = await SharedPreferences.getInstance();
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

    Finder key(String value) => find.byKey(ValueKey(value));
    String phase() =>
        (tester.widget<TimerModeFrame>(find.byType(TimerModeFrame)).status
                as TimerStatusPill)
            .stateKey
            .toString();
    final nav = key('main_navigation');
    await tester.tap(find.descendant(of: nav, matching: find.text('計時')));
    await settle();
    await tester.tap(key('timer-mode-exercise'));
    await settle();
    await tester.tap(key('exercise-kind-tabata'));
    await capture('exercise-tabata-compact');
    final primary = key('timer-primary-action');
    final baseline = tester.getRect(primary);
    await tester.tap(key('exercise-kind-jog'));
    await capture('exercise-jog-compact');
    final jog = tester.getRect(primary);
    expect(jog.top, closeTo(baseline.top, 0.5));
    expect(jog.bottom, closeTo(baseline.bottom, 0.5));
    expect(
      tester.getCenter(key('jog-bpm-control')).dy,
      closeTo(tester.getCenter(key('timer-settings-action')).dy, 0.5),
    );
    await tester.tap(key('jog-bpm-faster'));
    await capture('jog-compact-step');
    await tester.tap(key('jog-bpm-edit'));
    await capture('jog-compact-editor');
    await tester.enterText(key('jog-bpm-input'), '200');
    await tester.tap(key('jog-bpm-save'));
    await capture('jog-compact-precise');
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 200);

    await tester.tap(primary);
    await capture('jog-compact-preparing');
    for (var i = 0; i < 3 && !phase().contains('work'); i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(phase(), contains('work'));
    await capture('jog-compact-running');
    await tester.tap(key('jog-bpm-slower'));
    await capture('jog-running-adjusted');
    expect(prefs.getInt(PrefsKeys.exerciseBpm('jog')), 199);
    await tester.tap(primary);
    await capture('jog-compact-paused');
    await tester.tap(find.byIcon(Icons.replay_rounded).hitTestable());
    await settle();
    await tester.tap(find.byType(MascotToggleBar).hitTestable());
    await capture('exercise-jog-expanded');
    await tester.tap(key('jog-bpm-edit'));
    await capture('jog-expanded-editor');
    await tester.tap(find.text('取消').hitTestable());
    await settle();
    await tester.tap(primary);
    await settle();
    for (var i = 0; i < 3 && !phase().contains('work'); i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded).hitTestable());
      await tester.pump(const Duration(milliseconds: 100));
    }
    await capture('jog-expanded-running');
    await tester.tap(primary);
    await capture('jog-expanded-paused');
    await tester.tap(find.byIcon(Icons.replay_rounded).hitTestable());
    await settle();
    debugPrint('REVIEW_COMPLETE ${output.path}');
  });
}
