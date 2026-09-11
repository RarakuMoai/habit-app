import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/backup_restore.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_archive_test.dart' show backupFixture;
import 'shared_preferences_failure_test_helper.dart';

Map<String, Object?> snapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Future<BackupArchive> fixtureArchive() async {
  SharedPreferences.setMockInitialValues(backupFixture());
  return BackupArchive.create(await SharedPreferences.getInstance());
}

class FailRestoreStore extends SharedPreferencesStorePlatform {
  FailRestoreStore(
    this.delegate,
    this.failKey, {
    this.removeOnly = false,
    this.throwAfterSave = false,
    this.ackWithoutSave = false,
  });
  final SharedPreferencesStorePlatform delegate;
  final String failKey;
  final bool removeOnly;
  final bool throwAfterSave;
  final bool ackWithoutSave;
  bool failed = false;

  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  Future<bool> perform(
    String key,
    bool removing,
    Future<bool> Function() action,
  ) async {
    if (key != 'flutter.$failKey' || failed || removeOnly && !removing) {
      return action();
    }
    failed = true;
    if (throwAfterSave) {
      await action();
      throw StateError('Interrupted after native persistence');
    }
    if (ackWithoutSave) return true;
    return false;
  }

  @override
  Future<bool> remove(String key) =>
      perform(key, true, () => delegate.remove(key));
  @override
  Future<bool> setValue(String type, String key, Object value) =>
      perform(key, false, () => delegate.setValue(type, key, value));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'stage leaves live data untouched; restart restores all domains and prunes only allowed keys',
    () async {
      final archive = await fixtureArchive();
      final local = <String, Object>{
        PrefsKeys.coinBalance: 1,
        PrefsKeys.userNickname: 'old name',
        PrefsKeys.waterDay('2020-01-01'): 9,
        PrefsKeys.parentPinHash: 'keep-pin',
        'auth_token': 'keep-token',
        'notification_state': 'keep-device',
        PrefsKeys.debugStartTab: 2,
      };
      SharedPreferences.setMockInitialValues(local);
      final prefs = await SharedPreferences.getInstance();
      final restore = BackupRestore(prefs: prefs);
      await restore.stage(archive);
      for (final entry in local.entries) {
        expect(prefs.get(entry.key), entry.value);
      }
      expect(await restore.hasPending(), isTrue);
      await expectLater(BackupArchive.create(prefs), throwsStateError);
      final restarted = BackupRestore(prefs: prefs);
      expect(await restarted.recoverPending(), isTrue);
      for (final entry in archive.values.entries) {
        expect(prefs.get(entry.key), entry.value, reason: entry.key);
      }
      expect(prefs.containsKey(PrefsKeys.waterDay('2020-01-01')), isFalse);
      for (final entry in local.entries.where(
        (entry) => !BackupArchive.allowsKey(entry.key),
      )) {
        expect(prefs.get(entry.key), entry.value);
      }
      expect(await restarted.hasPending(), isFalse);
      final complete = snapshot(prefs);
      expect(await restarted.recoverPending(), isFalse);
      expect(snapshot(prefs), complete);
    },
  );

  test(
    'staging the same archive is idempotent and a different archive cannot replace it',
    () async {
      final first = await fixtureArchive();
      SharedPreferences.setMockInitialValues({PrefsKeys.coinBalance: 8});
      final prefs = await SharedPreferences.getInstance();
      final second = await BackupArchive.create(prefs);
      final restore = BackupRestore(prefs: prefs);
      await Future.wait([
        restore.stage(first),
        BackupRestore(prefs: prefs).stage(first),
      ]);
      await expectLater(restore.stage(second), throwsStateError);
      expect(prefs.get(PrefsKeys.coinBalance), 8);
      expect(prefs.get(PrefsKeys.backupRestoreJournal), first.encode());
    },
  );

  for (final throws in [false, true]) {
    test(
      'failed journal write ($throws) and failed reload do not use optimistic cache',
      () async {
        final archive = await fixtureArchive();
        SharedPreferences.setMockInitialValues({PrefsKeys.coinBalance: 8});
        final prefs = await SharedPreferences.getInstance();
        installFailFirstWriteStore(
          'flutter.${PrefsKeys.backupRestoreJournal}',
          throwSynchronously: throws,
          failFirstRecoveryReload: true,
        );
        final restore = BackupRestore(prefs: prefs);
        await expectLater(restore.stage(archive), throwsStateError);
        expect(await restore.hasPending(), isFalse);
        expect(prefs.getInt(PrefsKeys.coinBalance), 8);
        await restore.stage(archive);
        expect(await restore.recoverPending(), isTrue);
        expect(prefs.getInt(PrefsKeys.coinBalance), 1234);
      },
    );
  }

  for (final failureKey in [
    PrefsKeys.coinBalance,
    PrefsKeys.habits,
    PrefsKeys.familyRestoreNeedsPin,
    PrefsKeys.waterDay('2020-01-01'),
    PrefsKeys.backupRestoreJournal,
  ]) {
    for (final mode in ['false', 'after-save', 'false-ack']) {
      test(
        '$mode during $failureKey blocks completion, then restart converges exactly',
        () async {
          final archive = await fixtureArchive();
          SharedPreferences.setMockInitialValues({
            PrefsKeys.coinBalance: 8,
            PrefsKeys.waterDay('2020-01-01'): 4,
            'auth_token': 'keep',
          });
          final prefs = await SharedPreferences.getInstance();
          await BackupRestore(prefs: prefs).stage(archive);
          SharedPreferencesStorePlatform.instance = FailRestoreStore(
            SharedPreferencesStorePlatform.instance,
            failureKey,
            removeOnly:
                failureKey == PrefsKeys.backupRestoreJournal ||
                failureKey == PrefsKeys.waterDay('2020-01-01'),
            throwAfterSave: mode == 'after-save',
            ackWithoutSave: mode == 'false-ack',
          );
          await expectLater(
            BackupRestore(prefs: prefs).recoverPending(),
            throwsStateError,
          );
          final restart = BackupRestore(prefs: prefs);
          await restart.recoverPending();
          expect(await restart.hasPending(), isFalse);
          expect(snapshot(prefs), {
            ...archive.values,
            PrefsKeys.familyRestoreNeedsPin: true,
            'auth_token': 'keep',
          });
          expect(await restart.recoverPending(), isFalse);
        },
      );
    }
  }

  test(
    'unknown or corrupt journal blocks startup and leaves every live preference untouched',
    () async {
      for (final raw in <Object>['not json', '{"version":99}', 42]) {
        SharedPreferences.setMockInitialValues({
          PrefsKeys.backupRestoreJournal: raw,
          PrefsKeys.coinBalance: 8,
          'auth_token': 'keep',
        });
        final prefs = await SharedPreferences.getInstance();
        final before = snapshot(prefs);
        await expectLater(
          BackupRestore(prefs: prefs).recoverPending(),
          throwsFormatException,
        );
        expect(snapshot(prefs), before);
        await expectLater(BackupArchive.create(prefs), throwsStateError);
      }
    },
  );

  test(
    'empty archive removes only app-owned data and never clears storage',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final archive = await BackupArchive.create(prefs);
      await prefs.setInt(PrefsKeys.coinBalance, 25);
      await prefs.setBool(PrefsKeys.familyRestoreNeedsPin, true);
      await prefs.setString(PrefsKeys.parentPinHash, 'keep');
      await prefs.setString('plugin_future_key', 'keep');
      await BackupRestore(prefs: prefs).stage(archive);
      await BackupRestore(prefs: prefs).recoverPending();
      expect(snapshot(prefs), {
        PrefsKeys.parentPinHash: 'keep',
        'plugin_future_key': 'keep',
      });
    },
  );
}
