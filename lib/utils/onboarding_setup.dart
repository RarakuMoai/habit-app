import 'dart:async';

import 'package:characters/characters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companion_story_progress.dart';
import 'input_formatters.dart';
import 'prefs_keys.dart';

/// Completes a new save only after all required writes have succeeded.
/// This service neither navigates nor changes global display/audio state.
class OnboardingSetup {
  OnboardingSetup({
    SharedPreferences? prefs,
    CompanionStoryProgress? storyProgress,
    Future<bool> Function(String key, Object? value)? writePreference,
  }) : _prefs = prefs,
       _story = storyProgress ?? CompanionStoryProgress.instance,
       _writePreference = writePreference;

  SharedPreferences? _prefs;
  final CompanionStoryProgress _story;

  /// Optional test/adapter hook. null means remove; other values are String,
  /// bool or int. Return true only after the preference has been saved.
  final Future<bool> Function(String key, Object? value)? _writePreference;
  Future<void> _tail = Future<void>.value();

  Future<bool> finish({
    required String mascotName,
    required String nickname,
    required bool skipped,
    required String dayKey,
  }) {
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      try {
        result.complete(
          await _finish(
            mascotName: mascotName.trim(),
            nickname: nickname.trim(),
            skipped: skipped,
            dayKey: dayKey,
          ),
        );
      } catch (_) {
        // Recovery is retried at the start of every finish attempt. In
        // particular, a failed legacy setBool may have cached a false success.
        try {
          await _prefs?.reload();
        } catch (_) {
          // Never trust or commit an optimistic cache after a failed reload.
        }
        result.complete(false);
      }
    });
    return result.future;
  }

  Future<bool> _finish({
    required String mascotName,
    required String nickname,
    required bool skipped,
    required String dayKey,
  }) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(PrefsKeys.onboardingDone) == true) return true;
    if (displayWidth(mascotName) > kMascotNameMaxUnits ||
        nickname.characters.length > 12 ||
        !_isDayKey(dayKey)) {
      return false;
    }

    // Saving the first meeting is idempotent even across logical days. If a
    // later preference write fails, retry setup without awarding another day.
    if (!await _story.completeOnboarding(dayKey: dayKey, skipped: skipped)) {
      return false;
    }
    await _write(
      prefs,
      PrefsKeys.mascotName,
      mascotName.isEmpty ? null : mascotName,
    );
    await _write(
      prefs,
      PrefsKeys.userNickname,
      nickname.isEmpty ? null : nickname,
    );
    for (final key in const [
      PrefsKeys.waterEnabled,
      PrefsKeys.timerEnabled,
      PrefsKeys.familyEnabled,
      PrefsKeys.weightTrackingEnabled,
    ]) {
      if (!prefs.containsKey(key)) await _write(prefs, key, true);
    }
    // Distinguishes this all-features-visible introduction from the old flow
    // which opted into a linked water habit while enabling its tab.
    await _write(prefs, PrefsKeys.onboardingStoryVersion, 1);
    await _write(prefs, PrefsKeys.onboardingDone, true);
    return true;
  }

  Future<void> _write(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (value == null ? !prefs.containsKey(key) : prefs.get(key) == value) {
      return;
    }
    final writer = _writePreference;
    final bool saved;
    if (writer != null) {
      saved = await writer(key, value);
    } else {
      saved = switch (value) {
        null => await prefs.remove(key),
        final String text => await prefs.setString(key, text),
        final bool flag => await prefs.setBool(key, flag),
        final int version => await prefs.setInt(key, version),
        _ => throw ArgumentError.value(value, 'value'),
      };
    }
    if (!saved) throw StateError('Onboarding preference write failed: $key');
  }

  bool _isDayKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final day = DateTime.tryParse(value);
    return day != null && day.toIso8601String().substring(0, 10) == value;
  }
}
