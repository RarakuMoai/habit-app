// Native simulator review: real app root, bundled fonts/assets and seeded in-memory data.
// Run explicitly on an iOS simulator; never includes or writes real user records.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/widgets/mascot_panel.dart';
import 'package:integration_test/integration_test.dart';

import 'review_fixture.dart';

// UI captures do not test notification authorization or scheduling.
class _ReviewNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel({required int id}) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Review all six production tabs with repeatable local fixtures', (
    tester,
  ) async {
    seedExperienceReview();
    FlutterLocalNotificationsPlatform.instance = _ReviewNotifications();
    app.main();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byKey(const ValueKey('main_navigation')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('main_navigation')), findsOneWidget);
    final output = Directory('${Directory.systemTemp.path}/experience-review');
    await output.create(recursive: true);
    Future<void> settle() async {
      // Raster/image decoding and native route transitions need successive frames,
      // not one pump after a long delay (which can capture a half-built page).
      for (var i = 0; i < 20; i++) {
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

    await capture('01-habits');
    final nav = find.byKey(const ValueKey('main_navigation'));
    const labels = ['計時', '喝水', '體重', '家庭', '衣櫃'];
    const names = [
      '02-timer',
      '03-water',
      '04-weight',
      '05-family',
      '06-wardrobe',
    ];
    for (var i = 0; i < labels.length; i++) {
      await tester.tap(
        find.descendant(of: nav, matching: find.text(labels[i])),
      );
      await capture(names[i]);
    }
    await tester.tap(find.descendant(of: nav, matching: find.text('習慣')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('設定').first);
    await capture('07-settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -620));
    await capture('07-settings-details');
    await tester.tap(find.byType(BackButton).hitTestable());
    await settle();
    await tester.tap(find.byTooltip('足跡與足跡幣').first);
    await capture('08-review');
    await tester.tap(find.byType(BackButton).hitTestable());
    await settle();
    await tester.tap(find.descendant(of: nav, matching: find.text('喝水')));
    await settle();
    await tester.tap(find.byType(MascotToggleBar).hitTestable());
    await capture('09-water-expanded');
    await tester.tap(find.text('我喝了一杯'));
    await capture('10-water-added');
    expect(find.text('1250'), findsOneWidget);
    await tester.tap(find.byType(MascotToggleBar).hitTestable());
    await settle();
    await tester.tap(find.descendant(of: nav, matching: find.text('習慣')));
    await settle();
    for (
      var i = 0;
      i < 160 &&
          find.byKey(const ValueKey('roommate_entry')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await capture('11-invitation');
    await tester.tap(find.byKey(const ValueKey('roommate_entry')));
    await capture('11-roommate');
    await tester.tap(find.byKey(const ValueKey('roommate_exit')));
    await settle();
    await tester.tap(find.descendant(of: nav, matching: find.text('計時')));
    await settle();
    for (final mode in ['focus', 'exercise', 'metronome', 'game']) {
      final item = find.byKey(ValueKey('timer-mode-$mode'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await capture('timer-$mode-compact');
    }
    await tester.tap(find.byKey(const ValueKey('timer-mode-exercise')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('exercise-kind-jog')));
    await capture('timer-jog-compact');
    await tester.tap(find.byKey(const ValueKey('jog-bpm-faster')));
    await capture('timer-jog-adjusted');
    await tester.tap(find.byKey(const ValueKey('timer-mode-game')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('game-quick-chess')));
    await capture('timer-chess-compact');
    await tester.tap(find.byKey(const ValueKey('game-quick-party')));
    await tester.tap(find.byType(MascotToggleBar).hitTestable());
    const expanded = [
      ('習慣', '20-habits-expanded'),
      ('計時', '21-timer-expanded'),
      ('喝水', '22-water-expanded'),
      ('體重', '23-weight-expanded'),
      ('家庭', '24-family-expanded'),
      ('衣櫃', '25-wardrobe-expanded'),
    ];
    for (final page in expanded) {
      await tester.tap(find.descendant(of: nav, matching: find.text(page.$1)));
      await capture(page.$2);
    }
    await tester.tap(find.descendant(of: nav, matching: find.text('計時')));
    await settle();
    for (final mode in ['game', 'metronome', 'exercise', 'focus']) {
      final item = find.byKey(ValueKey('timer-mode-$mode'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await capture('timer-$mode-expanded');
    }
    await tester.tap(find.byKey(const ValueKey('timer-primary-action')));
    await capture('timer-focus-running');
    await tester.tap(find.byKey(const ValueKey('timer-primary-action')));
    await capture('timer-focus-paused');
    debugPrint('REVIEW_COMPLETE ${output.path}');
  });
}
