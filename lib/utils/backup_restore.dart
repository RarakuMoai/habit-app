import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_archive.dart';
import 'prefs_keys.dart';

/// Stage during normal use, apply only before *any* startup reader or writer.
/// A failed recovery must keep the app on its recovery gate, never enter home.
/// This is a replayable journal, not a multi-key SharedPreferences transaction.
final class BackupRestore {
  BackupRestore({
    required SharedPreferences prefs,
    Future<bool> Function(String key, Object? value)? writePreference,
  }) : _prefs = prefs,
       _writePreference = writePreference;

  final SharedPreferences _prefs;
  final Future<bool> Function(String key, Object? value)? _writePreference;

  Future<bool> hasPending() => BackupStorageLock.run(() async {
    await _prefs.reload();
    return _prefs.containsKey(PrefsKeys.backupRestoreJournal);
  });

  /// A durable single-key journal; existing personal data is not touched.
  /// Repeating the same stage is safe, replacing a pending restore is forbidden.
  Future<void> stage(BackupArchive archive) => BackupStorageLock.run(() async {
    await _prefs.reload();
    final raw = BackupArchive.decode(archive.encode()).encode();
    if (_prefs.containsKey(PrefsKeys.backupRestoreJournal)) {
      if (_prefs.get(PrefsKeys.backupRestoreJournal) == raw) return;
      throw StateError('Another restore is already pending');
    }
    await _write(PrefsKeys.backupRestoreJournal, raw);
    await _prefs.reload();
    if (_prefs.get(PrefsKeys.backupRestoreJournal) != raw) {
      throw StateError('Restore journal was not persisted');
    }
  });

  /// Returns true after completing a restore, false when no journal exists.
  /// Validation or unfinished storage failures leave a retryable journal. A
  /// final commit may already be durable even if its acknowledgement fails;
  /// the next startup reloads and either resumes or observes completion.
  Future<bool> recoverPending() => BackupStorageLock.run(() async {
    // Always refresh first: even a failed remove/set may have changed the cache.
    await _prefs.reload();
    if (!_prefs.containsKey(PrefsKeys.backupRestoreJournal)) return false;
    final raw = _prefs.get(PrefsKeys.backupRestoreJournal);
    if (raw is! String) throw const FormatException('Invalid restore journal');
    final archive = BackupArchive.decode(raw);
    final keys = archive.values.keys.toList()..sort();
    for (final key in keys) {
      final value = archive.values[key]!;
      if (!_equal(_prefs.get(key), value)) await _write(key, value);
    }
    // Remove only values owned by the backup schema. PINs, auth, plugin and
    // device state retain their local values, even on an empty restored archive.
    final obsolete =
        _prefs
            .getKeys()
            .where(
              (key) =>
                  BackupArchive.allowsKey(key) &&
                  !archive.values.containsKey(key),
            )
            .toList()
          ..sort();
    for (final key in obsolete) {
      await _write(key, null);
    }
    await _prefs.reload();
    for (final key in _prefs.getKeys().where(BackupArchive.allowsKey)) {
      if (!archive.values.containsKey(key) ||
          !_equal(_prefs.get(key), archive.values[key])) {
        throw StateError('Restored data verification failed: $key');
      }
    }
    for (final key in keys) {
      if (!_equal(_prefs.get(key), archive.values[key])) {
        throw StateError('Restored data is missing: $key');
      }
    }
    // Restored family records on a new device must not silently become
    // editable without parent protection. This gate is local, never imported.
    final childrenRaw = archive.values[PrefsKeys.children];
    final hasChildren =
        childrenRaw is String && (jsonDecode(childrenRaw) as List).isNotEmpty;
    final hash = _prefs.get(PrefsKeys.parentPinHash);
    final legacyPin = _prefs.get(PrefsKeys.legacyParentPin);
    final hasLocalPin =
        hash is String && hash.isNotEmpty ||
        legacyPin is String && legacyPin.isNotEmpty;
    final needsPin = hasChildren && !hasLocalPin;
    final marker = needsPin ? true : null;
    if (_prefs.get(PrefsKeys.familyRestoreNeedsPin) != marker) {
      await _write(PrefsKeys.familyRestoreNeedsPin, marker);
    }
    await _prefs.reload();
    if (_prefs.get(PrefsKeys.familyRestoreNeedsPin) != marker) {
      throw StateError('Restored family protection gate was not persisted');
    }

    // Commit last. If removal fails, replay sees the same target values and
    // retries only the remaining work. Never discard the source before verify.
    await _write(PrefsKeys.backupRestoreJournal, null);
    await _prefs.reload();
    if (_prefs.containsKey(PrefsKeys.backupRestoreJournal)) {
      throw StateError('Restore commit was not persisted');
    }
    return true;
  });

  Future<void> _write(String key, Object? value) async {
    try {
      final writer = _writePreference;
      final saved = writer != null
          ? await writer(key, value)
          : await switch (value) {
              null => _prefs.remove(key),
              final bool flag => _prefs.setBool(key, flag),
              final int number => _prefs.setInt(key, number),
              final double number => _prefs.setDouble(key, number),
              final String text => _prefs.setString(key, text),
              final List<String> list => _prefs.setStringList(key, list),
              _ => throw ArgumentError.value(value, 'value'),
            };
      if (!saved) throw StateError('Backup preference write failed: $key');
    } catch (_) {
      try {
        await _prefs.reload();
      } catch (_) {
        /* The next operation must reload again. */
      }
      rethrow;
    }
  }

  static bool _equal(Object? first, Object? second) {
    if (first is List<String> && second is List<String>) {
      return first.length == second.length &&
          Iterable<int>.generate(
            first.length,
          ).every((i) => first[i] == second[i]);
    }
    if (first is int && second is double || first is double && second is int) {
      return false;
    }
    return first == second;
  }
}
