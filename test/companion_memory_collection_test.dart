import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/companion_dialogue_page.dart';
import 'package:habit_app/pages/memory_book_reader.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/companion_story_catalog.dart';
import 'package:habit_app/utils/companion_story_preview.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:habit_app/utils/story_catalog.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/utils/usage_stats.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:habit_app/widgets/companion_memory_collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Map<String, Object?> _snapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _frames(tester);
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _finishOpening(WidgetTester tester) async {
  for (var scene = 0; scene < 6; scene++) {
    await _tap(tester, _key('onboarding-primary'));
  }
  expect(find.byType(OnboardingPage), findsNothing);
}

void main() {
  // One end-to-end scenario keeps the production singleton and its native save
  // consistent throughout preview -> locked collection -> normal replay.
  testWidgets(
    'all 18+4 memories preview without writes; disabling restores locks; replay only marks read',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      WardrobeStore.reset();
      SceneTimeController.debugInstance = SceneTimeController(
        clock: () => DateTime(2026, 9, 12, 13),
      );
      addTearDown(() {
        CompanionStoryPreview.setEnabled(false);
        WardrobeStore.reset();
        SceneTimeController.instance.dispose();
        SceneTimeController.debugInstance = null;
        StoryStore.unlocked.value = [];
        StoryStore.unread.value = {};
        StoryStore.pendingReveal.value = [];
      });

      final collected = companionEpisodes.first;
      final chosenBeat = collected.beats.firstWhere(
        (b) => b.choices.isNotEmpty,
      );
      final savedChoices = {chosenBeat.id: chosenBeat.choices.first.id};
      final originalState = CompanionProgressState(
        days: 7,
        creditedDayKeys: {for (var day = 1; day <= 7; day++) '2026-01-0$day'},
        completed: {
          collected.id: CompanionCompletion(
            firstCompletedAt: '2026-01-01',
            skipped: true,
            read: false,
            choices: savedChoices,
          ),
        },
        active: CompanionCursor(episodeId: 'daily_02', lineIndex: 1),
      );
      final legacy = storyCatalog.first;
      final legacyUnlock = StoryUnlock(legacy.id, DateTime(2026));
      SharedPreferences.setMockInitialValues({
        PrefsKeys.companionStoryProgress: jsonEncode(originalState.toJson()),
        PrefsKeys.storyUnlocked: jsonEncode([
          {'id': legacy.id, 'date': legacyUnlock.date.toIso8601String()},
        ]),
        // Unknown legacy metadata must not be migrated/cleaned merely because a
        // developer opens the preview collection.
        PrefsKeys.storyUnread: [legacy.id, 'future_special'],
        PrefsKeys.storyPendingReveal: ['future_special'],
        PrefsKeys.usageDay('2001-01-01'): jsonEncode({
          UsageEvents.memoryBookOpen: 7,
          UsageEvents.storyOpen: 3,
        }),
        'unrelated_saved_record': 'keep me',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = CompanionStoryProgress.instance;
      expect(await store.load(), isTrue);
      // MainPage owns legacy loading. Seed its already-loaded notifiers without
      // asking the old store to migrate intentionally unknown persisted data.
      StoryStore.unlocked.value = [legacyUnlock];
      StoryStore.unread.value = {legacy.id, 'future_special'};
      StoryStore.pendingReveal.value = ['future_special'];
      final preferencesBefore = _snapshot(prefs);
      final progressBefore = store.state.toJson();
      final unreadBefore = Set<String>.of(StoryStore.unread.value);
      final pendingBefore = List<String>.of(StoryStore.pendingReveal.value);
      CompanionStoryPreview.setEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              padding: const EdgeInsets.only(top: 24, bottom: 34),
            ),
            child: child!,
          ),
          home: const CompanionMemoryReviewPage(),
        ),
      );
      await _frames(tester);
      expect(companionEpisodes, hasLength(18));
      expect(storyCatalog, hasLength(4));

      for (final episode in companionEpisodes) {
        final row = _key('memory-${episode.id}');
        expect(row, findsOneWidget);
        final ink = tester.widget<InkWell>(
          find.descendant(of: row, matching: find.byType(InkWell)),
        );
        expect(ink.onTap, isNotNull, reason: '${episode.id} is previewable');
        await _tap(tester, row);
        if (episode.id == 'story_01') {
          final opening = tester.widget<OnboardingPage>(
            find.byType(OnboardingPage),
          );
          expect(opening.preview, isTrue);
          expect(opening.onReplayFinished, isNull);
          await _finishOpening(tester);
        } else {
          final reader = tester.widget<CompanionDialoguePage>(
            find.byType(CompanionDialoguePage),
          );
          expect(reader.episode.id, episode.id);
          expect(reader.preview, isTrue);
          expect(reader.onSave, isNull);
          expect(reader.onFinish, isNull);
          await _tap(tester, _key('companion_close'));
        }
        expect(store.state.toJson(), progressBefore);
        expect(_snapshot(prefs), preferencesBefore);
      }

      for (var index = 0; index < storyCatalog.length; index++) {
        final event = storyCatalog[index];
        await _tap(tester, _key('memory-${event.id}'));
        final reader = tester.widget<MemoryBookReader>(
          find.byType(MemoryBookReader),
        );
        expect(reader.preview, isTrue);
        expect(reader.initialIndex, index);
        expect(
          reader.entries.map((item) => item.id),
          storyCatalog.map((item) => item.id),
        );
        // Exercise onPageChanged as well as initState: both have read side effects
        // in normal legacy reading, neither may write during preview.
        await tester.drag(find.byType(PageView), const Offset(-310, 0));
        await _frames(tester);
        Navigator.of(tester.element(find.byType(MemoryBookReader))).pop();
        await _frames(tester);
        expect(StoryStore.unread.value, unreadBefore);
        expect(StoryStore.pendingReveal.value, pendingBefore);
        expect(_snapshot(prefs), preferencesBefore);
      }

      CompanionStoryPreview.setEnabled(false);
      await _frames(tester);
      for (final episode in companionEpisodes) {
        final row = _key('memory-${episode.id}');
        final ink = tester.widget<InkWell>(
          find.descendant(of: row, matching: find.byType(InkWell)),
        );
        expect(ink.onTap != null, episode.id == collected.id);
      }
      for (final event in storyCatalog) {
        final row = _key('memory-${event.id}');
        final ink = tester.widget<InkWell>(
          find.descendant(of: row, matching: find.byType(InkWell)),
        );
        expect(ink.onTap != null, event.id == legacy.id);
      }
      await _tap(tester, _key('memory-${companionEpisodes.last.id}'));
      expect(find.byType(CompanionDialoguePage), findsNothing);
      expect(_snapshot(prefs), preferencesBefore);

      await _tap(tester, _key('memory-${collected.id}'));
      final replay = tester.widget<OnboardingPage>(find.byType(OnboardingPage));
      expect(replay.preview, isFalse);
      expect(replay.onReplayFinished, isNotNull);
      expect(find.byType(TextField), findsNothing);
      await _finishOpening(tester);
      final record = store.state.completed[collected.id]!;
      expect(record.read, isTrue);
      expect(record.skipped, isTrue);
      expect(record.firstCompletedAt, '2026-01-01');
      expect(record.choices, savedChoices);
      expect(store.state.days, originalState.days);
      expect(store.state.active!.toJson(), originalState.active!.toJson());
      expect(store.state.creditedDayKeys, originalState.creditedDayKeys);
      expect(StoryStore.unread.value, unreadBefore);
      expect(StoryStore.pendingReveal.value, pendingBefore);
      final expectedProgress = jsonDecode(jsonEncode(progressBefore)) as Map;
      ((expectedProgress['completed'] as Map)[collected.id] as Map)['read'] =
          true;
      final expectedPreferences = {
        ...preferencesBefore,
        PrefsKeys.companionStoryProgress: jsonEncode(expectedProgress),
      };
      expect(_snapshot(prefs), expectedPreferences);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 25));
    },
  );
}
