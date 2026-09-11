import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/family/family_models.dart';
import 'companion_story_progress.dart';
import 'prefs_keys.dart';
import 'storage_snapshot_gate.dart';

/// All backup operations share this queue, including separate service instances.
/// App mutations still need the app's storage coordinator before taking a backup.
abstract final class BackupStorageLock {
  static Future<void>? _tail;

  static Future<T> run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final next = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final release = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = release;
    unawaited(
      release.whenComplete(() {
        if (identical(_tail, release)) _tail = null;
      }),
    );
    return next;
  }
}

/// A portable, integrity-checked snapshot. The checksum detects corruption;
/// it is not encryption or proof of ownership. Never put credentials in it.
final class BackupArchive {
  BackupArchive._(this.createdAt, Map<String, Object> values)
    : values = Map.unmodifiable({
        for (final entry in values.entries)
          entry.key: entry.value is List<String>
              ? List<String>.unmodifiable(entry.value as List<String>)
              : entry.value,
      });

  static const format = 'tumi-backup';
  static const version = 1;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxEntryCount = 100000;

  final DateTime createdAt;
  final Map<String, Object> values;
  int get entryCount => values.length;
  String get checksum =>
      sha256.convert(utf8.encode(_canonical(_payload))).toString();

  Map<String, Object> get _payload => {
    'format': format,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'entries': {
      for (final entry in values.entries)
        entry.key: {'type': _typeOf(entry.value), 'value': entry.value},
    },
  };

  String encode() => _canonical({..._payload, 'checksum': checksum});

  /// Call after pending app writes have settled. Reload and copy synchronously
  /// so stale/optimistic SharedPreferences values cannot enter the archive.
  static Future<BackupArchive> create(
    SharedPreferences prefs, {
    DateTime? createdAt,
  }) => StorageSnapshotGate.snapshot(
    () => BackupStorageLock.run(() async {
      await prefs.reload();
      if (prefs.containsKey(PrefsKeys.backupRestoreJournal)) {
        throw StateError('A restore is pending; exporting is blocked');
      }
      final values = <String, Object>{};
      for (final key in prefs.getKeys()) {
        if (!allowsKey(key)) continue;
        final value = prefs.get(key);
        _validateValue(key, value);
        values[key] = value!;
      }
      final result = BackupArchive._(
        (createdAt ?? DateTime.now()).toUtc(),
        values,
      );
      // Enforce the same limits for files we create and files we accept.
      return BackupArchive.decode(result.encode());
    }),
  );

  factory BackupArchive.decode(String raw) {
    if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Backup is too large');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Backup is not valid JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        !_exactKeys(decoded, const {
          'format',
          'version',
          'createdAt',
          'entries',
          'checksum',
        }) ||
        decoded['format'] != format ||
        decoded['version'] is! int ||
        decoded['version'] != version) {
      throw const FormatException('Unsupported backup format or version');
    }
    final timestamp = decoded['createdAt'];
    final date = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if (date == null || !date.isUtc || date.toIso8601String() != timestamp) {
      throw const FormatException('Invalid backup date');
    }
    final digest = decoded['checksum'];
    if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid backup checksum');
    }
    final payload = Map<String, dynamic>.of(decoded)..remove('checksum');
    if (sha256.convert(utf8.encode(_canonical(payload))).toString() != digest) {
      throw const FormatException('Backup checksum does not match');
    }
    final entries = decoded['entries'];
    if (entries is! Map<String, dynamic> || entries.length > maxEntryCount) {
      throw const FormatException('Invalid backup entries');
    }
    final values = <String, Object>{};
    for (final entry in entries.entries) {
      final record = entry.value;
      if (!allowsKey(entry.key) ||
          record is! Map<String, dynamic> ||
          !_exactKeys(record, const {'type', 'value'})) {
        throw FormatException('Invalid backup entry: ${entry.key}');
      }
      Object? value = record['value'];
      if (record['type'] == 'stringList' &&
          value is List &&
          value.every((item) => item is String)) {
        value = List<String>.from(value);
      }
      // JSON numbers without a fractional part can still represent stored doubles.
      if (record['type'] == 'double' && value is num) value = value.toDouble();
      if (value == null || _typeOf(value) != record['type']) {
        throw FormatException('Invalid preference type: ${entry.key}');
      }
      _validateValue(entry.key, value);
      values[entry.key] = value;
    }
    return BackupArchive._(date, values);
  }

  /// Explicit allowlist: new auth, plugin, review or device keys stay excluded.
  /// Prefixes are matched only with valid dates or the app's known identifiers.
  static bool allowsKey(String key) => _typesFor(key) != null;

  static String? _typesFor(String key) {
    final exact = _exactTypes[key];
    if (exact != null) return exact;
    for (final entry in _datedTypes.entries) {
      if (key.startsWith(entry.key) &&
          _validDay(key.substring(entry.key.length))) {
        return entry.value;
      }
    }
    for (final source in const [
      'dailyLogin',
      'allHabitsDone',
      'waterGoal',
      'weeklyStreak',
    ]) {
      final prefix = '${PrefsKeys.coinClaimPrefix}${source}_';
      if (key.startsWith(prefix) && _validDay(key.substring(prefix.length))) {
        return 'bool';
      }
    }
    // Child ids are generated locally; no arbitrary preference namespace escape.
    final familyPrefix = PrefsKeys.familyWaterGoal('');
    if (key.startsWith(familyPrefix) &&
        RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(key.substring(familyPrefix.length))) {
      return 'int';
    }
    return null;
  }

  static const _exerciseIds = ['tabata', 'hiit', 'emom', 'gym', 'jog'];

  static final Map<String, String> _exactTypes = {
    for (final key in const [
      PrefsKeys.onboardingDone,
      PrefsKeys.mascotPanelHintSeen,
      PrefsKeys.timerLongBreakEnabled,
      PrefsKeys.metronomeAccent,
      PrefsKeys.metronomeHaptic,
      PrefsKeys.gameTableRememberAddToRoster,
      PrefsKeys.timerEnabled,
      PrefsKeys.waterEnabled,
      PrefsKeys.weightTrackingEnabled,
      PrefsKeys.familyEnabled,
      PrefsKeys.waterGoalSuggestionDismissed,
      PrefsKeys.musicMuted,
      PrefsKeys.sfxMuted,
      PrefsKeys.legacyBgmMuted,
    ])
      key: 'bool',
    for (final key in const [
      PrefsKeys.onboardingStoryVersion,
      PrefsKeys.coinBalance,
      PrefsKeys.coinLoginLevel,
      PrefsKeys.coinLoginStreak,
      PrefsKeys.timerFocusMinutes,
      PrefsKeys.timerShortBreakMinutes,
      PrefsKeys.timerLongBreakMinutes,
      PrefsKeys.timerRounds,
      PrefsKeys.timerSelectedPreset,
      PrefsKeys.timerCustomSlot,
      PrefsKeys.metronomeBpm,
      PrefsKeys.metronomeBeats,
      PrefsKeys.metronomeBeatUnit,
      PrefsKeys.gameTableCustomTurnSeconds,
      PrefsKeys.gameTableCustomWarnSeconds,
      PrefsKeys.gameTableCustomBankSeconds,
      PrefsKeys.gameTableDiceCount,
      PrefsKeys.streak,
      PrefsKeys.waterCupMl,
      PrefsKeys.waterGoalMl,
      PrefsKeys.waterGoalSuggestionBaseline,
      PrefsKeys.dayStartHour,
    ])
      key: 'int',
    // The current reader intentionally accepts the old string subdivision format.
    PrefsKeys.metronomeSubdivision: 'int|string',
    for (final key in const [
      PrefsKeys.userHeight,
      PrefsKeys.userWeight,
      PrefsKeys.targetWeight,
      PrefsKeys.metronomeVolume,
    ])
      key: 'double',
    for (final key in const [
      PrefsKeys.tabOrder,
      PrefsKeys.wardrobeOwnedOutfits,
      PrefsKeys.bgmPlaylist,
      PrefsKeys.bgmOwnedTracks,
      PrefsKeys.storyUnread,
      PrefsKeys.storyPendingReveal,
    ])
      key: 'stringList',
    for (final key in const [
      PrefsKeys.onboardingDate,
      PrefsKeys.userNickname,
      PrefsKeys.mascotName,
      PrefsKeys.userGender,
      PrefsKeys.userBirthday,
      PrefsKeys.userActivityLevel,
      PrefsKeys.roommateEventHistory,
      PrefsKeys.coinLedger,
      PrefsKeys.coinLastLoginDate,
      PrefsKeys.timerMode,
      PrefsKeys.exerciseSubMode,
      PrefsKeys.metronomeTone,
      PrefsKeys.metronomeTempoNote,
      PrefsKeys.gameTableConfig,
      PrefsKeys.gameTableRoster,
      PrefsKeys.gameTablePresets,
      PrefsKeys.snakeArcadeData,
      PrefsKeys.habits,
      PrefsKeys.lastOpenDate,
      PrefsKeys.habitTombstones,
      PrefsKeys.logicalDayJournal,
      PrefsKeys.waterGoalDate,
      PrefsKeys.weightRecords,
      PrefsKeys.children,
      PrefsKeys.childHabits,
      PrefsKeys.deductionItems,
      PrefsKeys.rewardItems,
      PrefsKeys.voucherLogs,
      PrefsKeys.legacyRedemptionLogs,
      PrefsKeys.pointRecords,
      PrefsKeys.wardrobeSelectedOutfit,
      PrefsKeys.bgmMode,
      PrefsKeys.bgmSelectedTrack,
      PrefsKeys.companionStoryProgress,
      PrefsKeys.storyUnlocked,
      PrefsKeys.unitSystem,
      PrefsKeys.sceneFixedPeriod,
    ])
      key: 'string',
    for (var i = 0; i < 4; i++) ...{
      PrefsKeys.timerFocusProfileName(i): 'string',
      PrefsKeys.timerFocusProfileFocus(i): 'int',
      PrefsKeys.timerFocusProfileShort(i): 'int',
      PrefsKeys.timerFocusProfileRounds(i): 'int',
      PrefsKeys.timerFocusProfileLong(i): 'int',
      PrefsKeys.timerFocusProfileLongEnabled(i): 'bool',
    },
    for (var i = 0; i < 3; i++) ...{
      PrefsKeys.timerCustomFocus(i): 'int',
      PrefsKeys.timerCustomShort(i): 'int',
      PrefsKeys.timerCustomRounds(i): 'int',
      PrefsKeys.timerCustomName(i): 'string',
    },
    for (final id in _exerciseIds) ...{
      PrefsKeys.exerciseWork(id): 'int',
      PrefsKeys.exerciseRest(id): 'int',
      PrefsKeys.exerciseRounds(id): 'int',
      PrefsKeys.exercisePrep(id): 'int',
      PrefsKeys.exerciseWarmupOn(id): 'bool',
      PrefsKeys.exerciseWarmup(id): 'int',
      PrefsKeys.exerciseCooldownOn(id): 'bool',
      PrefsKeys.exerciseCooldown(id): 'int',
      PrefsKeys.exerciseBpm(id): 'int',
      PrefsKeys.exerciseMetronomeOn(id): 'bool',
      PrefsKeys.exerciseMetronomeSoundOn(id): 'bool',
      PrefsKeys.exerciseMetronomeVolume(id): 'double',
      PrefsKeys.exerciseMetronomeTone(id): 'string',
    },
  };

  static const _datedTypes = {
    PrefsKeys.timerTomatoesPrefix: 'int',
    PrefsKeys.timerFocusMinutesDayPrefix: 'int',
    PrefsKeys.exerciseSessionsPrefix: 'int',
    PrefsKeys.exerciseMinutesDayPrefix: 'int',
    PrefsKeys.habitDoneDayPrefix: 'string',
    PrefsKeys.waterDayPrefix: 'int',
    PrefsKeys.waterEntriesPrefix: 'string',
    PrefsKeys.waterExtraPrefix: 'int',
    PrefsKeys.waterSavedPrefix: 'int',
    PrefsKeys.waterEntriesSavedPrefix: 'string',
    PrefsKeys.usageDayPrefix: 'string',
  };

  static void _validateValue(String key, Object? value) {
    final allowed = _typesFor(key);
    if (allowed == null ||
        value == null ||
        !allowed.split('|').contains(_typeOf(value))) {
      throw FormatException('Unsupported preference value: $key');
    }
    if (value is double && !value.isFinite) {
      throw FormatException('Non-finite value: $key');
    }
    if (value is String) _validateJsonValue(key, value);
  }

  static void _validateJsonValue(String key, String raw) {
    const recordLists = {
      PrefsKeys.habits,
      PrefsKeys.habitTombstones,
      PrefsKeys.coinLedger,
      PrefsKeys.weightRecords,
      PrefsKeys.children,
      PrefsKeys.childHabits,
      PrefsKeys.deductionItems,
      PrefsKeys.rewardItems,
      PrefsKeys.voucherLogs,
      PrefsKeys.legacyRedemptionLogs,
      PrefsKeys.pointRecords,
      PrefsKeys.storyUnlocked,
      PrefsKeys.gameTablePresets,
    };
    final stringList =
        key == PrefsKeys.gameTableRoster ||
        key.startsWith(PrefsKeys.habitDoneDayPrefix);
    final waterEntries = key.startsWith(PrefsKeys.waterEntriesPrefix);
    final usage = key.startsWith(PrefsKeys.usageDayPrefix);
    const maps = {
      PrefsKeys.roommateEventHistory,
      PrefsKeys.companionStoryProgress,
      PrefsKeys.logicalDayJournal,
      PrefsKeys.gameTableConfig,
      PrefsKeys.snakeArcadeData,
    };
    if (!recordLists.contains(key) &&
        !stringList &&
        !waterEntries &&
        !usage &&
        !maps.contains(key)) {
      return;
    }
    try {
      final value = jsonDecode(raw);
      if (stringList) {
        if (value is! List || value.any((item) => item is! String)) {
          throw const FormatException();
        }
      } else if (waterEntries) {
        if (value is! List ||
            value.any(
              (item) => !(item is num || item is Map && item['ml'] is num),
            )) {
          throw const FormatException();
        }
      } else if (recordLists.contains(key)) {
        if (value is! List ||
            value.any((item) => item is! Map<String, dynamic>)) {
          throw const FormatException();
        }
        for (final item in value.cast<Map<String, dynamic>>()) {
          // Reuse the consumers' type contracts, retaining original fields/JSON.
          switch (key) {
            case PrefsKeys.children:
              ChildData.fromJson(item);
            case PrefsKeys.childHabits:
              ChildHabit.fromJson(item);
            case PrefsKeys.deductionItems:
              DeductionItem.fromJson(item);
            case PrefsKeys.rewardItems:
              RewardItem.fromJson(item);
            case PrefsKeys.voucherLogs || PrefsKeys.legacyRedemptionLogs:
              VoucherLog.fromJson(item);
            case PrefsKeys.pointRecords:
              PointRecord.fromJson(item);
            case PrefsKeys.habits:
              if (item['name'] is! String ||
                  item['done'] is! bool ||
                  item['frequency'] != null && item['frequency'] is! String ||
                  item['weeklyDates'] != null &&
                      (item['weeklyDates'] is! List ||
                          (item['weeklyDates'] as List).any(
                            (day) => day is! String,
                          ))) {
                throw const FormatException();
              }
            case PrefsKeys.weightRecords:
              if (item['date'] is! String || item['weight'] is! num) {
                throw const FormatException();
              }
            case PrefsKeys.gameTablePresets:
              if (item['name'] is! String || item['config'] is! String) {
                throw const FormatException();
              }
              _validateJsonValue(
                PrefsKeys.gameTableConfig,
                item['config'] as String,
              );
            case PrefsKeys.coinLedger:
              if (item['at'] is! String ||
                  item['src'] is! String ||
                  item['amt'] is! num ||
                  item['note'] != null && item['note'] is! String) {
                throw const FormatException();
              }
            case PrefsKeys.storyUnlocked:
              if (item['id'] is! String || item['date'] is! String) {
                throw const FormatException();
              }
          }
        }
      } else {
        if (value is! Map<String, dynamic>) throw const FormatException();
        if (usage && value.values.any((count) => count is! int || count < 0)) {
          throw const FormatException();
        }
        if (key == PrefsKeys.companionStoryProgress) {
          CompanionProgressState.fromJson(value);
        }
        if (key == PrefsKeys.snakeArcadeData &&
            (value['version'] != 1 || value['entries'] is! List)) {
          throw const FormatException();
        }
        if (key == PrefsKeys.gameTableConfig) {
          final players = value['players'];
          if (value['v'] != 1 ||
              value['mode'] is! String ||
              players is! List ||
              players.any(
                (player) => player is! Map || player['name'] is! String,
              )) {
            throw const FormatException();
          }
        }
        if (key == PrefsKeys.logicalDayJournal &&
            (value['settledDay'] is! String ||
                value['streakAfter'] is! num ||
                value['yesterdayAllDone'] is! bool ||
                value['previousOpenDate'] != null &&
                    value['previousOpenDate'] is! String)) {
          throw const FormatException();
        }
        if (key == PrefsKeys.roommateEventHistory &&
            (value['firstMeetHandled'] is! bool ||
                value['handledDay'] != null &&
                    value['handledDay'] is! String)) {
          throw const FormatException();
        }
      }
    } catch (_) {
      throw FormatException('Invalid stored JSON: $key');
    }
  }

  static String _typeOf(Object value) => switch (value) {
    bool() => 'bool',
    int() => 'int',
    double() => 'double',
    String() => 'string',
    List<String>() => 'stringList',
    _ => 'unsupported',
  };

  static bool _validDay(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null && date.toIso8601String().substring(0, 10) == value;
  }

  static bool _exactKeys(Map<String, dynamic> map, Set<String> keys) =>
      map.length == keys.length && keys.every(map.containsKey);

  static String _canonical(Object? value) {
    Object? sorted(Object? item) {
      if (item is Map) {
        final keys = item.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: sorted(item[key])};
      }
      if (item is List) return item.map(sorted).toList();
      return item;
    }

    return jsonEncode(sorted(value));
  }
}
