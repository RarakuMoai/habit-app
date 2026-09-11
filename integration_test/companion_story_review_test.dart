// Native review of the real home -> story -> settings -> developer -> archive flow.
// Seeded mock preferences only; run exclusively on a named iOS simulator.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/pages/dev_test_page.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/utils/companion_story_catalog.dart';
import 'package:habit_app/utils/companion_story_preview.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_panel.dart';
import 'package:habit_app/widgets/settings_ui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'review_fixture.dart';

class _ReviewNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel({required int id}) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'story progress, native reader, developer preview and real archive',
    (tester) async {
      seedExperienceReview();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefsKeys.habits, '[]');
      FlutterLocalNotificationsPlatform.instance = _ReviewNotifications();
      app.main();
      Future<void> settle([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final output = Directory('${Directory.systemTemp.path}/companion-review');
      await output.create(recursive: true);
      Future<void> capture(String name) async {
        await settle();
        expect(tester.takeException(), isNull, reason: name);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        final bytes = await binding.takeScreenshot(name);
        await File('${output.path}/$name.png').writeAsBytes(bytes);
        debugPrint('REVIEW_SCREENSHOT ${output.path}/$name.png');
      }

      Finder keyed(String key) => find.byKey(ValueKey(key));
      Future<void> tapKey(String key) async {
        final target = keyed(key);
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await settle(3);
        expect(target.hitTestable(), findsOneWidget, reason: key);
        await tester.tap(target);
        await settle(6);
      }

      Future<void> openDeveloper() async {
        await tester.tap(find.byTooltip('設定').hitTestable().first);
        await settle();
        final developer = find.widgetWithText(SettingsTileCard, '開發者測試');
        await tester.scrollUntilVisible(
          developer,
          350,
          scrollable: find.byType(Scrollable).last,
        );
        await settle(3);
        expect(developer.hitTestable(), findsOneWidget);
        await tester.tap(developer);
        await settle();
        expect(find.byType(DevTestPage), findsOneWidget);
        await tester.scrollUntilVisible(
          keyed('companion-preview-all'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await settle(3);
      }

      Future<void> returnToWardrobeMemories() async {
        await tester.tap(find.byType(BackButton).hitTestable());
        await settle();
        await tester.tap(find.byType(BackButton).hitTestable());
        await settle();
        final wardrobeTab = find.descendant(
          of: keyed('main_navigation'),
          matching: find.text('衣櫃'),
        );
        expect(wardrobeTab.hitTestable(), findsOneWidget);
        await tester.tap(wardrobeTab);
        await settle();
        expect(find.byType(WardrobePage).hitTestable(), findsOneWidget);
        await tester.tap(find.text('回憶').hitTestable());
        await settle();
      }

      await settle(70);
      expect(keyed('main_navigation'), findsOneWidget);
      // Expanded scene is the production state where the quiet invitation appears.
      if (MascotPanelPrefs.openValue.value < 0.85) {
        await tester.tap(find.byType(MascotToggleBar).hitTestable().first);
        await settle();
      }
      await capture('01-home-invitation');
      expect(keyed('roommate_entry'), findsOneWidget);
      await tapKey('roommate_entry');
      await capture('02-first-meeting');
      await tapKey('companion_next');
      final cursor = CompanionStoryProgress.instance.state.active!.toJson();
      await tapKey('companion_close');
      expect(CompanionStoryProgress.instance.state.days, 0);
      await tapKey('roommate_entry');
      expect(CompanionStoryProgress.instance.state.active!.toJson(), cursor);
      await tapKey('companion_skip');
      expect(CompanionStoryProgress.instance.state.days, 1);
      expect(
        CompanionStoryProgress.instance.state.completed['story_01']!.read,
        false,
      );
      expect(keyed('roommate_entry'), findsNothing);
      await openDeveloper();
      await tapKey('companion-preview-all');
      expect(CompanionStoryPreview.active, true);
      await capture('03-developer-preview-option');
      expect(keyed('companion-open-review'), findsNothing);
      await returnToWardrobeMemories();
      await capture('04-wardrobe-preview-collection');
      final progressBefore = prefs.getString(PrefsKeys.companionStoryProgress);
      await tapKey('memory-story_01');
      final opening = tester.widget<OnboardingPage>(
        find.byType(OnboardingPage),
      );
      expect(opening.preview, isTrue);
      expect(opening.onReplayFinished, isNull);
      await tapKey('onboarding-primary');
      await capture('05-first-meeting-greeting');
      await tapKey('onboarding-skip');
      expect(find.byType(OnboardingPage), findsNothing);
      await tapKey('memory-story_08');
      await capture('06-trust-story');
      var grief = CompanionSession(companionEpisodeById('story_08')!);
      while (grief.choices.isEmpty && !grief.atEnd) {
        await tapKey('companion_next');
        grief = CompanionSession(grief.episode, grief.advance());
      }
      await capture('06b-grief-choices');
      await tapKey('companion_choice_${grief.choices.last.id}');

      await tapKey('companion_close');
      await tapKey('memory-story_14');
      await capture('07-season-ending');
      var ending = CompanionSession(companionEpisodeById('story_14')!);
      while (ending.choices.isEmpty && !ending.atEnd) {
        await tapKey('companion_next');
        ending = CompanionSession(ending.episode, ending.advance());
      }
      await capture('07b-ending-choices');
      await tapKey('companion_choice_${ending.choices.last.id}');

      await tapKey('companion_close');
      expect(prefs.getString(PrefsKeys.companionStoryProgress), progressBefore);
      await openDeveloper();
      await tapKey('companion-preview-all');
      await returnToWardrobeMemories();
      await capture('08-wardrobe-real-unlocks-restored');
      expect(CompanionStoryPreview.active, false);
      final lockedEnding = find.descendant(
        of: keyed('memory-story_14'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(lockedEnding).onTap, isNull);
      expect(prefs.getString(PrefsKeys.companionStoryProgress), progressBefore);
      expect(CompanionStoryProgress.instance.state.days, 1);
    },
  );
}
