import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

/// Read-only entry routing evidence, not a migration or archive integrity check.
/// Call after startup has reloaded preferences and recovered any staged restore.
class LocalJourneyInspection {
  LocalJourneyInspection._(this.evidenceKeys, this.unreadableKeys);

  final Set<String> evidenceKeys;
  final Set<String> unreadableKeys;

  bool get hasJourney => evidenceKeys.isNotEmpty;

  /// Unknown populated records must not be treated as a fresh empty device.
  bool get needsReview => !hasJourney && unreadableKeys.isNotEmpty;

  static LocalJourneyInspection inspect(SharedPreferences prefs) {
    if (prefs.get(PrefsKeys.onboardingDone) == true) {
      return LocalJourneyInspection._(const {PrefsKeys.onboardingDone}, const {});
    }
    final evidence = <String>{};
    final unreadable = <String>{};
    final marker = prefs.get(PrefsKeys.onboardingDone);
    if (marker != null && marker is! bool) {
      unreadable.add(PrefsKeys.onboardingDone);
    }

    // HomePage creates this only after entering the actual household. A date
    // preserves an established but currently empty home after habits are removed.
    final arrival = prefs.get(PrefsKeys.onboardingDate);
    if (arrival is String && arrival.trim().isNotEmpty) {
      if (DateTime.tryParse(arrival) != null) {
        evidence.add(PrefsKeys.onboardingDate);
      } else {
        unreadable.add(PrefsKeys.onboardingDate);
      }
    } else if (arrival != null && arrival != '') {
      unreadable.add(PrefsKeys.onboardingDate);
    }

    void inspectList(String key, bool Function(Object?) isRecord) {
      final raw = prefs.get(key);
      if (raw == null || raw == '') return;
      try {
        final Object? decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is! List) {
          unreadable.add(key);
        } else if (decoded.isNotEmpty) {
          if (decoded.any(isRecord)) evidence.add(key);
          if (decoded.any((value) => !isRecord(value))) unreadable.add(key);
        }
      } on FormatException {
        unreadable.add(key);
      }
    }

    bool named(Object? value) =>
        value is Map<String, dynamic> && _text(value['name']);

    inspectList(PrefsKeys.habits, named);
    inspectList(PrefsKeys.habitTombstones, named);
    inspectList(
      PrefsKeys.weightRecords,
      (value) =>
          value is Map<String, dynamic> &&
          _date(value['date']) &&
          value['weight'] is num &&
          (value['weight'] as num).isFinite,
    );
    inspectList(
      PrefsKeys.children,
      (value) =>
          value is Map<String, dynamic> &&
          _text(value['id']) &&
          _text(value['name']),
    );

    for (final key in prefs.getKeys()) {
      if (_datedKey(key, PrefsKeys.habitDoneDayPrefix)) {
        inspectList(key, _text);
      } else if (_datedKey(key, PrefsKeys.waterEntriesPrefix)) {
        inspectList(
          key,
          (value) => value is Map<String, dynamic> && _positive(value['ml']),
        );
      } else if (_datedKey(key, PrefsKeys.waterDayPrefix) ||
          _datedKey(key, PrefsKeys.waterExtraPrefix) ||
          _datedKey(key, PrefsKeys.timerFocusMinutesDayPrefix) ||
          _datedKey(key, PrefsKeys.timerTomatoesPrefix)) {
        final value = prefs.get(key);
        if (_positive(value)) {
          evidence.add(key);
        } else if (value is! num || !value.isFinite || value < 0) {
          unreadable.add(key);
        }
      }
    }

    // Identity, Guest choice, lastOpenDate, empty collections, preferences,
    // currency defaults and the partially saved story_01 are not journey proof.
    // In particular, story_01 is written before OnboardingSetup's final marker.
    return LocalJourneyInspection._(
      Set.unmodifiable(evidence),
      Set.unmodifiable(unreadable),
    );
  }

  static bool _text(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static bool _positive(Object? value) =>
      value is num && value.isFinite && value > 0;

  static bool _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value);
  }

  static bool _datedKey(String key, String prefix) =>
      key.startsWith(prefix) && _date(key.substring(prefix.length));
}
