import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> backupFixture() => {
  PrefsKeys.onboardingDone: true,
  PrefsKeys.onboardingDate: '2026-06-12T08:00:00.000',
  PrefsKeys.onboardingStoryVersion: 1,
  PrefsKeys.userNickname: '小日',
  PrefsKeys.mascotName: '兔咪',
  PrefsKeys.userGender: '女',
  PrefsKeys.userBirthday: '1990-05-10',
  PrefsKeys.userHeight: 168.0,
  PrefsKeys.userWeight: 59.4,
  PrefsKeys.targetWeight: 58.0,
  PrefsKeys.userActivityLevel: '輕度',
  PrefsKeys.habits: '[{"id":"h1","name":"看書","done":true,"frequency":"daily"}]',
  PrefsKeys.habitTombstones:
      '[{"id":"deleted","name":"舊習慣","frequency":"daily","createdAt":"2026-05-01","deletedAt":"2026-06-01"}]',
  PrefsKeys.habitDoneDay('2026-09-10'): '["h1"]',
  PrefsKeys.lastOpenDate: '2026-09-11',
  PrefsKeys.streak: 42,
  PrefsKeys.logicalDayJournal:
      '{"settledDay":"2026-09-10","streakAfter":42,"yesterdayAllDone":true,"previousOpenDate":"2026-09-10"}',
  PrefsKeys.coinBalance: 1234,
  PrefsKeys.coinLoginStreak: 22,
  PrefsKeys.coinLoginLevel: 7,
  PrefsKeys.coinLastLoginDate: '2026-09-11',
  PrefsKeys.coinLedger:
      '[{"at":"2026-09-11T08:00:00.000","src":"dailyLogin","amt":12}]',
  PrefsKeys.coinClaim('dailyLogin', '2026-09-11'): true,
  PrefsKeys.waterEnabled: true,
  PrefsKeys.waterCupMl: 250,
  PrefsKeys.waterGoalMl: 2000,
  PrefsKeys.waterGoalDate: '2026-09-10',
  PrefsKeys.waterDay('2026-09-11'): 3,
  PrefsKeys.waterExtra('2026-09-11'): 100,
  PrefsKeys.waterEntries('2026-09-11'):
      '[{"ml":250,"kind":"cup","at":"2026-09-11T08:00:00.000"},100]',
  PrefsKeys.waterSaved('2026-09-11'): 2,
  PrefsKeys.waterEntriesSaved('2026-09-11'): '[250,250]',
  PrefsKeys.weightTrackingEnabled: true,
  PrefsKeys.weightRecords:
      '[{"date":"2026-09-11","time":"08:00","weight":59.4}]',
  PrefsKeys.timerEnabled: true,
  PrefsKeys.timerMode: 'exercise',
  PrefsKeys.timerFocusProfileName(0): '安靜閱讀',
  PrefsKeys.timerFocusProfileFocus(0): 25,
  PrefsKeys.timerFocusProfileLongEnabled(0): true,
  PrefsKeys.timerCustomName(2): '舊方案',
  PrefsKeys.timerCustomFocus(2): 30,
  PrefsKeys.timerTomatoes('2026-09-10'): 4,
  PrefsKeys.timerFocusMinutesDay('2026-09-10'): 100,
  PrefsKeys.exerciseSubMode: 'jog',
  PrefsKeys.exerciseBpm('jog'): 180,
  PrefsKeys.exerciseMetronomeOn('jog'): true,
  PrefsKeys.exerciseMetronomeVolume('jog'): 0.7,
  PrefsKeys.exerciseSessions('2026-09-11'): 1,
  PrefsKeys.exerciseMinutesDay('2026-09-11'): 10,
  PrefsKeys.metronomeBpm: 96,
  PrefsKeys.metronomeSubdivision: 'legacy-eighth',
  PrefsKeys.metronomeVolume: 0.5,
  PrefsKeys.gameTableConfig:
      '{"v":1,"mode":"party","players":[{"name":"小日","color":0},{"name":"兔咪","color":1}]}',
  PrefsKeys.gameTableRoster: '["小日","兔咪"]',
  PrefsKeys.gameTablePresets: '[]',
  PrefsKeys.familyEnabled: true,
  PrefsKeys.children: '[{"id":"child-1","name":"小花","avatar":"🐼","points":5}]',
  PrefsKeys.childHabits:
      '[{"id":"ch1","child_id":"child-1","name":"收玩具","points":5}]',
  PrefsKeys.familyWaterGoal('child-1'): 6,
  PrefsKeys.deductionItems:
      '[{"id":"d1","child_id":"child-1","name":"遲到","points":1}]',
  PrefsKeys.rewardItems:
      '[{"id":"r1","name":"去公園","points_cost":3,"child_ids":["child-1"]}]',
  PrefsKeys.voucherLogs:
      '[{"id":"v1","reward_id":"r1","child_id":"child-1","redeemed_at":"2026-09-11 08:00","used":false}]',
  PrefsKeys.legacyRedemptionLogs:
      '[{"id":"v0","reward_id":"r1","child_id":"child-1","time":"2026-09-01 08:00"}]',
  PrefsKeys.pointRecords:
      '[{"id":"p1","child_id":"child-1","time":"2026-09-11 08:00","reason":"收玩具","delta":5,"total":5}]',
  PrefsKeys.companionStoryProgress: jsonEncode(
    CompanionProgressState(days: 5).toJson(),
  ),
  PrefsKeys.roommateEventHistory:
      '{"firstMeetHandled":true,"handledDay":"2026-09-11"}',
  PrefsKeys.storyUnlocked:
      '[{"id":"first_meet","date":"2026-06-12T08:00:00.000"}]',
  PrefsKeys.storyUnread: <String>['first_meet'],
  PrefsKeys.storyPendingReveal: <String>['first_meet'],
  PrefsKeys.wardrobeOwnedOutfits: <String>['moon_pajamas'],
  PrefsKeys.wardrobeSelectedOutfit: 'moon_pajamas',
  PrefsKeys.bgmOwnedTracks: <String>['piano'],
  PrefsKeys.bgmPlaylist: <String>['piano'],
  PrefsKeys.bgmSelectedTrack: 'piano',
  PrefsKeys.musicMuted: false,
  PrefsKeys.sfxMuted: true,
  PrefsKeys.tabOrder: <String>['habits', 'water', 'timers', 'wardrobe'],
  PrefsKeys.dayStartHour: 4,
  PrefsKeys.unitSystem: 'metric',
  PrefsKeys.snakeArcadeData:
      '{"version":1,"entries":[],"lastName":"小日","recent":["小日"]}',
};

String resignBackup(Map<String, dynamic> document) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    return item;
  }

  document.remove('checksum');
  final payload = jsonEncode(sorted(document));
  document['checksum'] = sha256.convert(utf8.encode(payload)).toString();
  return jsonEncode(document);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'all user domains round trip preserving types, exact JSON and list order',
    () async {
      final fixture = backupFixture();
      SharedPreferences.setMockInitialValues(fixture);
      final archive = await BackupArchive.create(
        await SharedPreferences.getInstance(),
        createdAt: DateTime.utc(2026, 9, 11),
      );
      final decoded = BackupArchive.decode(archive.encode());
      expect(decoded.values, fixture);
      expect(decoded.values[PrefsKeys.userHeight], isA<double>());
      expect(decoded.values[PrefsKeys.coinBalance], isA<int>());
      expect(decoded.entryCount, fixture.length);
      expect(decoded.createdAt, DateTime.utc(2026, 9, 11));
      expect(decoded.checksum, archive.checksum);
      expect(decoded.encode(), archive.encode());
      expect(decoded.values.clear, throwsUnsupportedError);
      expect(
        () => (decoded.values[PrefsKeys.bgmPlaylist] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'credentials, PIN, device, preview and unrelated namespaces never export',
    () async {
      final excluded = <String, Object>{
        PrefsKeys.parentPinHash: 'hash',
        PrefsKeys.legacyParentPin: '1234',
        PrefsKeys.parentPinQuestion: 'private',
        PrefsKeys.parentPinAnswerHash: 'hash',
        PrefsKeys.pinDigits: 4,
        PrefsKeys.familyRestoreNeedsPin: true,
        PrefsKeys.debugDaySnapshot: 'private snapshot',
        PrefsKeys.debugDayShift: 42,
        PrefsKeys.debugStartTab: 5,
        PrefsKeys.audioAssetCacheVersion: 7,
        PrefsKeys.subscriptionActive: true,
        'account_device_state_v1': '{}',
        'auth_access_token': 'token',
        'notification_token': 'token',
        'story_preview_all': true,
        'water_auth_token': 'token',
        'family_water_goal_../auth': 3,
        'exercise_unknown_bpm': 123,
        'timer_focus_profile_9_name': 'unknown',
        PrefsKeys.waterDay('2026-02-30'): 3,
      };
      SharedPreferences.setMockInitialValues({...backupFixture(), ...excluded});
      final archive = await BackupArchive.create(
        await SharedPreferences.getInstance(),
      );
      expect(archive.values, backupFixture());
      for (final key in excluded.keys) {
        expect(BackupArchive.allowsKey(key), isFalse, reason: key);
      }
      expect(BackupArchive.allowsKey(PrefsKeys.waterDay('2024-02-29')), isTrue);
    },
  );

  test('checksum detects changed data before accepting entries', () async {
    SharedPreferences.setMockInitialValues(backupFixture());
    final archive = await BackupArchive.create(
      await SharedPreferences.getInstance(),
    );
    final json = jsonDecode(archive.encode()) as Map<String, dynamic>;
    ((json['entries'] as Map)[PrefsKeys.coinBalance] as Map)['value'] = 9999;
    expect(() => BackupArchive.decode(jsonEncode(json)), throwsFormatException);
  });

  test(
    'reject unsupported version, unknown fields, wrong type or namespace even with valid checksum',
    () async {
      SharedPreferences.setMockInitialValues(backupFixture());
      final archive = await BackupArchive.create(
        await SharedPreferences.getInstance(),
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (doc) => doc['version'] = 2,
        (doc) => doc['version'] = '1',
        (doc) => doc['extra'] = true,
        (doc) => doc['createdAt'] = '2026-02-30T00:00:00.000Z',
        (doc) => (doc['entries'] as Map)[PrefsKeys.coinBalance] = {
          'type': 'string',
          'value': '999',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.coinBalance] = {
          'type': 'int',
          'value': 2.5,
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.bgmPlaylist] = {
          'type': 'stringList',
          'value': ['piano', 4],
        },
        (doc) => (doc['entries'] as Map)['auth_token'] = {
          'type': 'string',
          'value': 'token',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.habits] = {
          'type': 'string',
          'value': '{}',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.habits] = {
          'type': 'string',
          'value': '[{"name":1,"done":true}]',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.children] = {
          'type': 'string',
          'value': '[{"id":"c","name":1}]',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.companionStoryProgress] = {
          'type': 'string',
          'value': '{"version":99}',
        },
        (doc) => (doc['entries'] as Map)[PrefsKeys.gameTableConfig] = {
          'type': 'string',
          'value': '{"v":99}',
        },
      ]) {
        final document = jsonDecode(archive.encode()) as Map<String, dynamic>;
        mutate(document);
        expect(
          () => BackupArchive.decode(resignBackup(document)),
          throwsFormatException,
        );
      }
      for (final raw in ['bad JSON', 'null', '[]', '{}']) {
        expect(() => BackupArchive.decode(raw), throwsFormatException);
      }
    },
  );

  test(
    'invalid live value blocks backup rather than silently dropping user data',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.coinBalance: 'wrong type',
      });
      await expectLater(
        BackupArchive.create(await SharedPreferences.getInstance()),
        throwsFormatException,
      );
      SharedPreferences.setMockInitialValues({PrefsKeys.habits: 'broken json'});
      await expectLater(
        BackupArchive.create(await SharedPreferences.getInstance()),
        throwsFormatException,
      );
    },
  );

  test('reject oversized input before parsing', () {
    expect(
      () => BackupArchive.decode(' ' * (BackupArchive.maxBytes + 1)),
      throwsFormatException,
    );
  });
}
