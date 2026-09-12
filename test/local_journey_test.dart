import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/local_journey.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalJourneyInspection> inspect(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final result = LocalJourneyInspection.inspect(prefs);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, values);
    return result;
  }

  test('completed household continues even when it has no records', () async {
    final result = await inspect({PrefsKeys.onboardingDone: true});
    expect(result.hasJourney, isTrue);
    expect(result.needsReview, isFalse);
    expect(result.evidenceKeys, {PrefsKeys.onboardingDone});
  });

  test(
    'credentials, Guest choice and startup defaults are not a journey',
    () async {
      final result = await inspect({
        PrefsKeys.accountDeviceState: '{"uid":"someone","revision":7}',
        PrefsKeys.accountGuestChosen: true,
        PrefsKeys.habits: '[]',
        PrefsKeys.children: '[]',
        PrefsKeys.weightRecords: '[]',
        PrefsKeys.lastOpenDate: '2026-09-12',
        PrefsKeys.logicalDayJournal: '{}',
        PrefsKeys.musicMuted: false,
        PrefsKeys.coinBalance: 0,
        PrefsKeys.timerEnabled: true,
        PrefsKeys.mascotName: '兔咪',
        PrefsKeys.userBirthday: '1990-08-17',
        PrefsKeys.waterDay('2026-09-12'): 0,
      });
      expect(result.hasJourney, isFalse);
      expect(result.needsReview, isFalse);
    },
  );

  test(
    'real legacy records continue without changing the missing marker',
    () async {
      final cases = <Map<String, Object>>[
        {PrefsKeys.onboardingDate: '2026-09-01T10:00:00.000'},
        {
          PrefsKeys.habits: jsonEncode([
            {'name': '散步', 'done': false},
          ]),
        },
        {
          PrefsKeys.weightRecords: jsonEncode([
            {'date': '2026-09-11', 'weight': 62.5},
          ]),
        },
        {
          PrefsKeys.children: jsonEncode([
            {'id': 'child-1', 'name': '小月'},
          ]),
        },
        {
          PrefsKeys.waterEntries('2026-09-11'): jsonEncode([
            {'ml': 250, 'kind': 'cup'},
          ]),
        },
        {PrefsKeys.waterDay('2026-09-11'): 2},
        {PrefsKeys.timerFocusMinutesDay('2026-09-11'): 25},
        {PrefsKeys.habitDoneDay('2026-09-11'): '["habit-1"]'},
      ];
      for (final values in cases) {
        final result = await inspect(values);
        expect(result.hasJourney, isTrue, reason: values.keys.single);
        expect(result.needsReview, isFalse, reason: values.keys.single);
      }
    },
  );

  test(
    'unknown populated journey records need review, never a new save',
    () async {
      for (final raw in ['broken JSON', '{"futureVersion":2}', '[{}]']) {
        final result = await inspect({PrefsKeys.habits: raw});
        expect(result.hasJourney, isFalse);
        expect(result.needsReview, isTrue);
        expect(result.unreadableKeys, contains(PrefsKeys.habits));
      }
    },
  );

  test(
    'water configuration and invalid date suffixes are not diary data',
    () async {
      final result = await inspect({
        PrefsKeys.waterCupMl: 250,
        PrefsKeys.waterGoalMl: 2000,
        PrefsKeys.waterDay('2026-02-31'): 2,
        PrefsKeys.timerFocusMinutes: 25,
        PrefsKeys.waterEntries('2026-09-11'): '[]',
      });
      expect(result.hasJourney, isFalse);
      expect(result.needsReview, isFalse);
    },
  );

  test(
    'partial onboarding does not bypass the existing setup recovery',
    () async {
      final result = await inspect({
        PrefsKeys.onboardingDone: false,
        PrefsKeys.companionStoryProgress: jsonEncode({
          'version': 1,
          'days': 1,
          'completed': {
            'story_01': {
              'firstCompletedAt': '2026-09-12',
              'skipped': true,
              'read': false,
              'choices': <String, String>{},
            },
          },
        }),
      });
      expect(result.hasJourney, isFalse);
      expect(result.needsReview, isFalse);
    },
  );
}
