import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/onboarding_setup.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_failure_test_helper.dart';

Map<String, Object?> _snapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Future<bool> _finish(
  OnboardingSetup setup, {
  String mascot = '  麻糬  ',
  String nickname = '  小日  ',
  String day = '2026-09-12',
  bool skipped = false,
}) => setup.finish(
  mascotName: mascot,
  nickname: nickname,
  skipped: skipped,
  dayKey: day,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'new setup trims names, opens four optional tabs and completes only real first meeting',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
      expect(await _finish(setup), isTrue);
      expect(prefs.getString(PrefsKeys.mascotName), '麻糬');
      expect(prefs.getString(PrefsKeys.userNickname), '小日');
      for (final key in [
        PrefsKeys.waterEnabled,
        PrefsKeys.timerEnabled,
        PrefsKeys.familyEnabled,
        PrefsKeys.weightTrackingEnabled,
      ]) {
        expect(prefs.getBool(key), isTrue);
      }
      expect(prefs.getInt(PrefsKeys.onboardingStoryVersion), 1);
      expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
      for (final key in [
        PrefsKeys.userHeight,
        PrefsKeys.userWeight,
        PrefsKeys.userGender,
        PrefsKeys.userBirthday,
        PrefsKeys.userActivityLevel,
        PrefsKeys.targetWeight,
        PrefsKeys.weightRecords,
        PrefsKeys.habits,
        PrefsKeys.children,
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: 'Do not invent $key');
      }
      expect(story.state.days, 1);
      expect(story.state.active, isNull);
      expect(story.state.completed.keys, ['story_01']);
      final record = story.state.completed['story_01']!;
      expect(record.choices, isEmpty);
      expect(record.read, isTrue);
      expect(record.skipped, isFalse);
      expect(record.firstCompletedAt, '2026-09-12');
    },
  );

  test(
    'blank optional names remove keys and skipping leaves an unread memory',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.mascotName: 'draft mascot',
        PrefsKeys.userNickname: 'draft user',
      });
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      expect(
        await _finish(
          OnboardingSetup(prefs: prefs, storyProgress: story),
          mascot: ' ',
          nickname: ' ',
          skipped: true,
        ),
        isTrue,
      );
      expect(prefs.containsKey(PrefsKeys.mascotName), isFalse);
      expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
      expect(story.state.completed['story_01']!.read, isFalse);
      expect(story.state.completed['story_01']!.skipped, isTrue);
      expect(story.state.completed['story_01']!.choices, isEmpty);
    },
  );

  test(
    'existing profile, habits, historical metadata and explicit false flags survive setup',
    () async {
      final oldStory = CompanionProgressState(
        days: 12,
        creditedDayKeys: {'2026-09-12'},
        completed: {
          'future_episode': CompanionCompletion(
            firstCompletedAt: '2025-12-01',
            read: true,
            skipped: false,
            choices: const {'future_beat': 'future_choice'},
            extra: const {'future_record': 8},
          ),
        },
        extra: const {
          'future_root': {'keep': true},
        },
      ).toJson();
      SharedPreferences.setMockInitialValues({
        PrefsKeys.companionStoryProgress: jsonEncode(oldStory),
        PrefsKeys.userHeight: 168.0,
        PrefsKeys.userWeight: 60.0,
        PrefsKeys.targetWeight: 58.0,
        PrefsKeys.userGender: '女',
        PrefsKeys.userBirthday: '1992-04-20',
        PrefsKeys.userActivityLevel: '輕度',
        PrefsKeys.onboardingDate: '2025-12-01T12:00:00.000',
        PrefsKeys.habits: '[{"name":"閱讀","done":true}]',
        PrefsKeys.weightRecords: '[{"date":"2026-09-10","weight":60}]',
        PrefsKeys.children: '[{"id":"existing_child"}]',
        PrefsKeys.waterEnabled: false,
        PrefsKeys.timerEnabled: false,
        PrefsKeys.familyEnabled: false,
        PrefsKeys.weightTrackingEnabled: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final before = _snapshot(prefs)..remove(PrefsKeys.companionStoryProgress);
      final story = CompanionStoryProgress(prefs: prefs);
      expect(
        await _finish(OnboardingSetup(prefs: prefs, storyProgress: story)),
        isTrue,
      );
      for (final entry in before.entries) {
        expect(prefs.get(entry.key), entry.value, reason: entry.key);
      }
      expect(
        story.state.days,
        12,
        reason: 'Same logical day cannot count twice',
      );
      final after = story.state.toJson();
      expect(after['future_root'], oldStory['future_root']);
      expect(
        (after['completed'] as Map)['future_episode'],
        (oldStory['completed'] as Map)['future_episode'],
      );
    },
  );

  test(
    'already finished setup is read-only even with unknown story schema and different inputs',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.onboardingDone: true,
        PrefsKeys.mascotName: '小白',
        PrefsKeys.userNickname: '小優',
        PrefsKeys.waterEnabled: false,
        PrefsKeys.companionStoryProgress: '{"version": 99}',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = _snapshot(prefs);
      var writes = 0;
      final story = CompanionStoryProgress(prefs: prefs);
      final setup = OnboardingSetup(
        prefs: prefs,
        storyProgress: story,
        writePreference: (_, _) async {
          writes++;
          return false;
        },
      );
      expect(
        await _finish(setup, mascot: '', nickname: '', day: 'not a day'),
        isTrue,
      );
      expect(_snapshot(prefs), before);
      expect(story.loaded, isFalse);
      expect(writes, 0);
      expect(prefs.containsKey(PrefsKeys.onboardingStoryVersion), isFalse);
    },
  );

  test(
    'concurrent repeated calls use one completed setup and preserve the first result',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
      expect(
        await Future.wait(List.generate(10, (_) => _finish(setup))),
        everyElement(isTrue),
      );
      final before = _snapshot(prefs);
      expect(
        await _finish(setup, mascot: '另一個', nickname: '另外', day: '2026-09-13'),
        isTrue,
      );
      expect(_snapshot(prefs), before);
      expect(story.state.days, 1);
      expect(story.state.creditedDayKeys, {'2026-09-12'});
    },
  );

  for (final throws in [false, true]) {
    test(
      'story write ${throws ? 'throw' : 'false'} does not complete preferences and can retry',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final story = CompanionStoryProgress(prefs: prefs);
        final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
        installFailFirstWriteStore(
          'flutter.${PrefsKeys.companionStoryProgress}',
          throwSynchronously: throws,
        );
        expect(await _finish(setup), isFalse);
        expect(prefs.getKeys(), isEmpty);
        expect(story.state.days, 0);
        expect(story.state.active, isNull);
        expect(await _finish(setup), isTrue);
        expect(story.state.days, 1);
      },
    );

    test(
      'done write ${throws ? 'throw' : 'false'} cross-day retry never recounts the first meeting',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final story = CompanionStoryProgress(prefs: prefs);
        final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
        installFailFirstWriteStore(
          'flutter.${PrefsKeys.onboardingDone}',
          throwSynchronously: throws,
          failFirstRecoveryReload: true,
        );
        expect(await _finish(setup, skipped: true), isFalse);
        expect(story.state.days, 1);
        // Recovery itself failed once. The next attempt must reload before reading
        // the optimistic SharedPreferences cache's potentially cached done=true.
        expect(await _finish(setup, day: '2026-09-13'), isTrue);
        expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
        final rebuilt = CompanionStoryProgress(prefs: prefs);
        await rebuilt.load();
        expect(rebuilt.state.days, 1);
        expect(rebuilt.state.creditedDayKeys, {'2026-09-12'});
        expect(
          rebuilt.state.completed['story_01']!.firstCompletedAt,
          '2026-09-12',
        );
        expect(rebuilt.state.completed['story_01']!.skipped, isTrue);
        expect(rebuilt.state.completed['story_01']!.read, isFalse);
      },
    );
  }

  test(
    'write callback sees version before done and failure stops completion',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      final keys = <String>[];
      var failVersion = true;
      final setup = OnboardingSetup(
        prefs: prefs,
        storyProgress: story,
        writePreference: (key, value) async {
          keys.add(key);
          if (key == PrefsKeys.onboardingStoryVersion && failVersion) {
            return false;
          }
          return switch (value) {
            null => prefs.remove(key),
            final String text => prefs.setString(key, text),
            final bool flag => prefs.setBool(key, flag),
            final int number => prefs.setInt(key, number),
            _ => throw StateError('Unexpected write'),
          };
        },
      );
      expect(await _finish(setup), isFalse);
      expect(keys, isNot(contains(PrefsKeys.onboardingDone)));
      expect(prefs.getBool(PrefsKeys.onboardingDone), isNull);
      failVersion = false;
      expect(await _finish(setup, day: '2026-09-13'), isTrue);
      expect(keys.last, PrefsKeys.onboardingDone);
      expect(keys[keys.length - 2], PrefsKeys.onboardingStoryVersion);
      expect(story.state.days, 1);
    },
  );

  test(
    'overlong mascot name and invalid logical date fail before writing anything',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
      expect(await _finish(setup, mascot: '一二三四五六七'), isFalse);
      expect(await _finish(setup, day: '2026-02-30'), isFalse);
      expect(prefs.getKeys(), isEmpty);
      expect(story.loaded, isFalse);
    },
  );

  test(
    'name validation uses existing display width and 12-grapheme nickname limit',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      final setup = OnboardingSetup(prefs: prefs, storyProgress: story);
      expect(await _finish(setup, nickname: '1234567890123'), isFalse);
      expect(await _finish(setup, mascot: '1234567890123'), isFalse);
      expect(prefs.getKeys(), isEmpty);
      expect(
        await _finish(setup, mascot: 'GoldenRabbit', nickname: '123456789012'),
        isTrue,
      );
      expect(prefs.getString(PrefsKeys.mascotName), 'GoldenRabbit');
    },
  );

  test(
    'onboarding completion is one atomic commit with no invented cursor or answer',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<bool>();
      String? pending;
      final story = CompanionStoryProgress(
        prefs: prefs,
        writeString: (_, value) {
          pending = value;
          return gate.future;
        },
      );
      await story.load();
      var notifications = 0;
      story.addListener(() => notifications++);
      final writing = story.completeOnboarding(
        dayKey: '2026-09-12',
        skipped: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(story.state.days, 0);
      expect(story.state.completed, isEmpty);
      expect(story.state.active, isNull);
      expect(notifications, 0);
      final doc = jsonDecode(pending!) as Map;
      expect(doc['active'], isNull);
      expect(
        ((doc['completed'] as Map)['story_01'] as Map)['choices'],
        isEmpty,
      );
      await prefs.setString(PrefsKeys.companionStoryProgress, pending!);
      gate.complete(true);
      expect(await writing, isTrue);
      expect(notifications, 1);
      expect(story.state.days, 1);
    },
  );

  test(
    'completed first meeting retry preserves original read state, answers and metadata',
    () async {
      final state = CompanionProgressState(
        days: 9,
        creditedDayKeys: {'2026-09-01'},
        completed: {
          'story_01': CompanionCompletion(
            firstCompletedAt: '2026-09-01',
            read: false,
            skipped: true,
            choices: const {'real_beat': 'real_choice'},
            extra: const {'preserved_metadata': 5},
          ),
        },
        extra: const {'root_metadata': 'keep'},
      );
      final raw = jsonEncode(state.toJson());
      SharedPreferences.setMockInitialValues({
        PrefsKeys.companionStoryProgress: raw,
      });
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      expect(
        await story.completeOnboarding(dayKey: '2026-09-12', skipped: false),
        isTrue,
      );
      expect(prefs.getString(PrefsKeys.companionStoryProgress), raw);
      expect(story.state.toJson(), state.toJson());
    },
  );

  test(
    'same-story active answers survive completion and the 90-day cap is respected',
    () async {
      final state = CompanionProgressState(
        days: 90,
        active: CompanionCursor(
          episodeId: 'story_01',
          choices: const {'real_beat': 'real_choice'},
        ),
      );
      SharedPreferences.setMockInitialValues({
        PrefsKeys.companionStoryProgress: jsonEncode(state.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final story = CompanionStoryProgress(prefs: prefs);
      expect(
        await story.completeOnboarding(dayKey: '2026-09-12', skipped: true),
        isTrue,
      );
      expect(story.state.days, 90);
      expect(story.state.active, isNull);
      expect(story.state.completed['story_01']!.choices, {
        'real_beat': 'real_choice',
      });
    },
  );

  for (final raw in [
    '{"version": 99}',
    'corrupt',
    jsonEncode(
      CompanionProgressState(
        active: CompanionCursor(episodeId: 'daily_02'),
      ).toJson(),
    ),
    jsonEncode(
      CompanionProgressState(
        active: CompanionCursor(episodeId: 'future_episode'),
      ).toJson(),
    ),
  ]) {
    test(
      'unknown save or another active story blocks setup without any writes: $raw',
      () async {
        SharedPreferences.setMockInitialValues({
          PrefsKeys.companionStoryProgress: raw,
        });
        final prefs = await SharedPreferences.getInstance();
        final before = _snapshot(prefs);
        final story = CompanionStoryProgress(prefs: prefs);
        expect(
          await _finish(OnboardingSetup(prefs: prefs, storyProgress: story)),
          isFalse,
        );
        expect(_snapshot(prefs), before);
      },
    );
  }
}
