// Native review of the real home -> story -> settings -> developer -> archive flow.
// Seeded mock preferences only; run exclusively on a named iOS simulator.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/pages/dev_test_page.dart';
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
      await tester.tap(find.byTooltip('設定').first);
      await capture('02b-settings');
      await tester.scrollUntilVisible(
        find.widgetWithText(SettingsTileCard, '開發者測試'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await capture('02c-settings-developer-entry');
      expect(
        find.widgetWithText(SettingsTileCard, '開發者測試').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(SettingsTileCard, '開發者測試'));
      await settle();
      expect(find.byType(DevTestPage), findsOneWidget);
      await settle();
      await tester.scrollUntilVisible(
        keyed('companion-preview-all'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tapKey('companion-preview-all');
      expect(CompanionStoryPreview.active, true);
      await capture('03-developer-preview-option');
      await tapKey('companion-open-review');
      await capture('04-preview-collection');
      final progressBefore = prefs.getString(PrefsKeys.companionStoryProgress);
      await tapKey('memory-story_01');
      final episode = companionEpisodeById('story_01')!;
      var reader = CompanionSession(episode);
      for (var i = 0; i < 30 && reader.choices.isEmpty; i++) {
        await tapKey('companion_next');
        reader = CompanionSession(episode, reader.advance());
      }
      await capture('05-first-meeting-choices');
      await tapKey('companion_close');
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
      await tester.tap(find.byType(BackButton).hitTestable());
      await settle();
      await tapKey('companion-preview-all');
      await tapKey('companion-open-review');
      await capture('08-real-unlocks-restored');
      expect(CompanionStoryPreview.active, false);
      expect(CompanionStoryProgress.instance.state.days, 1);
    },
  );
}
