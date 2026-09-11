// Native first-run and developer preview review, with process-local preferences.
// Run exclusively on an explicitly named iOS simulator.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/pages/login_streak_page.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/pages/story_reveal_page.dart';
import 'package:habit_app/utils/companion_story_preview.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_panel.dart';
import 'package:habit_app/widgets/settings_ui.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReviewNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel({required int id}) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'grounded introduction, compact tools, bottle and developer preview',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.musicMuted: true,
        PrefsKeys.sfxMuted: true,
      });
      FlutterLocalNotificationsPlatform.instance = _ReviewNotifications();
      app.main();
      final prefs = await SharedPreferences.getInstance();
      final output = Directory('${Directory.systemTemp.path}/layout-review-v4');
      await output.create(recursive: true);
      Finder keyed(String key) => find.byKey(ValueKey(key));
      Future<void> frames([int count = 15]) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String name) async {
        await frames();
        expect(tester.takeException(), isNull, reason: name);
        if (name.startsWith('timer-') &&
            (name.endsWith('-compact') || name == 'timer-jog-adjusted')) {
          final frame = tester.getRect(find.byType(TimerModeFrame));
          for (final key in ['timer-hero', 'timer-primary-action']) {
            final control = keyed(key);
            expect(control.hitTestable(), findsOneWidget, reason: name);
            final rect = tester.getRect(control);
            expect(rect.top, greaterThanOrEqualTo(frame.top), reason: name);
            expect(rect.bottom, lessThanOrEqualTo(frame.bottom), reason: name);
          }
        }
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(binding.framesEnabled && binding.sendFramesToEngine, isTrue);
        final bytes = await binding.takeScreenshot(name);
        await File('${output.path}/$name.png').writeAsBytes(bytes);
        debugPrint('REVIEW_SCREENSHOT ${output.path}/$name.png');
      }

      Future<void> tap(Finder target) async {
        // Do not scroll controls that are already visible: centering a bottom
        // quick choice would manufacture a cropped clock in the screenshot.
        if (target.hitTestable().evaluate().isEmpty) {
          await Scrollable.ensureVisible(tester.element(target));
          await frames(3);
        }
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await frames(8);
      }

      Future<void> next() => tap(keyed('onboarding-primary'));

      await frames(70);
      expect(find.byType(OnboardingPage), findsOneWidget);
      await capture('01-arrival');
      await next();
      await capture('02-hello');
      await next();
      await capture('03-a-new-routine');
      await next();
      await capture('04-a-name');
      await tester.ensureVisible(keyed('onboarding-mascot-name'));
      await frames(3);
      await tester.tap(keyed('onboarding-mascot-name'));
      await tester.enterText(keyed('onboarding-mascot-name'), '小白');
      await capture('04b-name-keyboard');
      await next();
      await capture('05-your-name');
      // The optional name remains empty; no invented user profile is required.
      await next();
      await capture('06-a-beginning');
      await next();
      await frames(70);

      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(LoginStreakPage), findsNothing);
      expect(find.byType(StoryRevealPage), findsNothing);
      expect(keyed('main_navigation'), findsOneWidget);
      expect(keyed('roommate_entry'), findsNothing);
      expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
      expect(prefs.getString(PrefsKeys.mascotName), '小白');
      expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
      expect(jsonDecode(prefs.getString(PrefsKeys.habits) ?? '[]'), isEmpty);
      expect(prefs.containsKey(PrefsKeys.weightRecords), isFalse);
      expect(prefs.containsKey(PrefsKeys.children), isFalse);
      expect(prefs.getInt(PrefsKeys.coinBalance), greaterThan(0));
      expect(CompanionStoryProgress.instance.state.days, 1);
      expect(
        CompanionStoryProgress.instance.state.completed['story_01']!.read,
        isTrue,
      );
      await capture('07-home');

      final nav = keyed('main_navigation');
      for (final entry in const [
        ('計時', '08-timers'),
        ('喝水', '09-water'),
        ('體重', '10-weight'),
        ('家庭', '11-family'),
        ('衣櫃', '12-wardrobe'),
      ]) {
        await tap(find.descendant(of: nav, matching: find.text(entry.$1)));
        await capture(entry.$2);
      }
      await tap(find.descendant(of: nav, matching: find.text('計時')));
      for (final mode in ['focus', 'exercise', 'metronome', 'game']) {
        await tap(keyed('timer-mode-$mode'));
        await capture('timer-$mode-compact');
      }
      await tap(keyed('timer-mode-exercise'));
      await tap(keyed('exercise-kind-jog'));
      await capture('timer-jog-compact');
      await tap(keyed('jog-bpm-faster'));
      await capture('timer-jog-adjusted');
      await tap(find.byType(MascotToggleBar).hitTestable());
      for (final mode in ['exercise', 'focus', 'metronome', 'game']) {
        await tap(keyed('timer-mode-$mode'));
        await capture('timer-$mode-expanded');
      }
      await tap(find.byType(MascotToggleBar).hitTestable());
      await tap(find.descendant(of: nav, matching: find.text('喝水')));
      await tap(keyed('water-add-cup'));
      await capture('water-one-cup-compact');
      await tap(find.byType(MascotToggleBar).hitTestable());
      await capture('water-expanded');
      await tap(find.byType(MascotToggleBar).hitTestable());
      for (var cup = 1; cup < 8; cup++) {
        await tap(keyed('water-add-cup'));
      }
      await capture('water-goal-compact');
      await tap(find.descendant(of: nav, matching: find.text('習慣')));
      await tap(find.byTooltip('設定').first);
      final developer = find.widgetWithText(SettingsTileCard, '開發者測試');
      await tester.scrollUntilVisible(
        developer,
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await frames();
      await tap(developer);
      await tester.scrollUntilVisible(
        keyed('companion-preview-all'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await frames();
      await Scrollable.ensureVisible(
        tester.element(keyed('companion-preview-all')),
        alignment: 0.15,
      );
      await capture('13-developer-preview-entry');
      final savedBefore = {
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      await tap(keyed('onboarding-open-preview'));
      expect(
        tester.widget<OnboardingPage>(find.byType(OnboardingPage)).preview,
        isTrue,
      );
      await capture('14-preview-arrival');
      await next();
      await next();
      await next();
      await tester.ensureVisible(keyed('onboarding-mascot-name'));
      await tester.enterText(keyed('onboarding-mascot-name'), '試讀');
      await next();
      await tester.ensureVisible(keyed('onboarding-nickname'));
      await tester.enterText(keyed('onboarding-nickname'), '小日');
      await next();
      await capture('15-preview-ending');
      await next();
      expect(find.byType(OnboardingPage), findsNothing);
      expect({
        for (final key in prefs.getKeys()) key: prefs.get(key),
      }, savedBefore);
      final progressBeforeWardrobe = prefs.getString(
        PrefsKeys.companionStoryProgress,
      );
      await tap(keyed('companion-preview-all'));
      expect(CompanionStoryPreview.active, isTrue);
      await tap(find.byType(BackButton).hitTestable());
      await frames();
      await tap(find.byType(BackButton).hitTestable());
      await frames();
      await tap(find.descendant(of: nav, matching: find.text('衣櫃')));
      await tap(find.byType(MascotToggleBar).hitTestable());
      await tap(find.text('回憶').hitTestable());
      await capture('16-wardrobe-memory-preview');
      final firstMemory = keyed('memory-story_01');
      await tester.scrollUntilVisible(
        firstMemory,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await frames();
      await tap(firstMemory);
      expect(
        tester.widget<OnboardingPage>(find.byType(OnboardingPage)).preview,
        isTrue,
      );
      await capture('17-onboarding-from-wardrobe');
      await tap(keyed('onboarding-skip'));
      expect(
        prefs.getString(PrefsKeys.companionStoryProgress),
        progressBeforeWardrobe,
      );
      CompanionStoryPreview.setEnabled(false);
      await tester.pumpWidget(const SizedBox());
      await frames(30);
    },
  );
}
