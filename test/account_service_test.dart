import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBackend implements AccountBackend {
  @override
  bool configured = true;
  @override
  Set<AccountProvider> availableProviders = AccountProvider.values.toSet();
  @override
  AccountIdentity? currentUser;
  AccountIdentity nextUser = const AccountIdentity(uid: 'one');
  CloudBackup? cloud;
  AccountFailure? initializeFailure, signInFailure, readFailure, writeFailure;
  int writes = 0, initializations = 0;
  Completer<void>? initializeGate;
  @override
  Future<void> initialize() async {
    initializations++;
    if (initializeFailure != null) throw initializeFailure!;
    await initializeGate?.future;
  }

  @override
  Future<AccountIdentity> signIn(AccountProvider provider) async {
    if (signInFailure != null) throw signInFailure!;
    return currentUser = nextUser;
  }

  @override
  Future<void> signOut() async => currentUser = null;
  @override
  Future<AccountIdentity> linkProvider(AccountProvider provider) async =>
      currentUser!;
  @override
  Future<AccountIdentity> unlinkProvider(AccountProvider provider) async =>
      currentUser!;
  @override
  Future<void> deleteAccount(AccountProvider reauthenticateWith) async =>
      currentUser = null;
  @override
  Future<CloudBackup?> readLatest() async {
    if (readFailure != null) throw readFailure!;
    return cloud;
  }

  @override
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    if ((cloud?.revision ?? 0) != expectedRevision) {
      throw const AccountFailure('conflict');
    }
    writes++;
    return cloud = backup(expectedRevision + 1, encodedArchive);
  }
}

CloudBackup backup(int revision, [String payload = 'archive']) => CloudBackup(
  revision: revision,
  createdAt: DateTime.utc(2026, 9, 11, 10),
  encodedArchive: payload,
  byteLength: utf8.encode(payload).length,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeBackend backend;
  late AccountService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({PrefsKeys.habits: 'local-data'});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    service = AccountService(backend: backend, prefs: prefs);
  });
  tearDown(() => service.dispose());

  test(
    'failed force initialization invalidates earlier empty-cloud proof',
    () async {
      backend.currentUser = const AccountIdentity(uid: 'same-person');
      expect(await service.initialize(), isTrue);
      expect(service.cloudReadConfirmed, isTrue);
      expect(service.latestBackup, isNull);
      backend.initializeFailure = const AccountFailure('offline');
      expect(await service.initialize(force: true), isFalse);
      expect(service.user?.uid, 'same-person');
      expect(service.latestBackup, isNull);
      expect(service.cloudReadConfirmed, isFalse);
      expect(service.errorCode, 'offline');
      expect(backend.writes, 0);
    },
  );

  test(
    'only a successful cloud read proves whether a remote save exists',
    () async {
      await service.initialize();
      expect(service.cloudReadConfirmed, isFalse);
      backend.readFailure = const AccountFailure('offline');
      expect(await service.signIn(AccountProvider.apple), isFalse);
      expect(service.user, isNotNull);
      expect(service.latestBackup, isNull);
      expect(service.cloudReadConfirmed, isFalse);
      backend.readFailure = null;
      expect(await service.refreshBackup(), isTrue);
      expect(service.latestBackup, isNull);
      expect(service.cloudReadConfirmed, isTrue);
      backend.readFailure = const AccountFailure('offline');
      expect(await service.refreshBackup(), isFalse);
      expect(service.cloudReadConfirmed, isFalse);
    },
  );

  test(
    'uncertain publication releases busy but invalidates cloud authority until refresh',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      expect(await service.backupNow('first'), isTrue);
      final receipt = prefs.getString(PrefsKeys.accountDeviceState);
      backend.writeFailure = const AccountFailure('backup-pending');
      expect(await service.backupNow('second'), isFalse);
      expect(service.busy, isFalse);
      expect(service.errorCode, 'backup-pending');
      expect(service.latestBackup, isNull);
      expect(service.cloudArchiveForRestore, isNull);
      expect(service.lastSuccessfulBackupAt, isNull);
      expect(prefs.getString(PrefsKeys.accountDeviceState), receipt);

      backend.writeFailure = null;
      expect(await service.backupNow('third'), isFalse);
      expect(service.errorCode, 'cloud-not-checked');
      expect(backend.writes, 1);
      // The native request eventually committed. A fresh server read discovers
      // it; the stale local receipt cannot silently authorize its replacement.
      backend.cloud = backup(2, 'second');
      expect(await service.refreshBackup(), isTrue);
      expect(service.needsReconciliation, isTrue);
      expect(await service.backupNow('third'), isFalse);
      expect(service.errorCode, 'reconciliation-required');
      expect(backend.writes, 1);
    },
  );

  test(
    'restart after an unacknowledged commit requires reconciliation',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      await service.backupNow('first');
      // A native commit succeeded immediately before process termination, so
      // only the old confirmed revision is present in SharedPreferences.
      backend.cloud = backup(2, 'unacknowledged');
      final restarted = AccountService(backend: backend, prefs: prefs);
      addTearDown(restarted.dispose);
      expect(await restarted.initialize(), isTrue);
      expect(restarted.needsReconciliation, isTrue);
      expect(restarted.lastSuccessfulBackupAt, isNull);
      expect(await restarted.backupNow('third'), isFalse);
      expect(backend.writes, 1);
    },
  );

  test(
    'unconfigured backend reports unavailable and cannot invent an account',
    () async {
      final unavailable = AccountService(
        backend: const UnavailableAccountBackend(),
        prefs: prefs,
      );
      addTearDown(unavailable.dispose);
      expect(await unavailable.initialize(), isTrue);
      expect(unavailable.phase, AccountPhase.unavailable);
      expect(await unavailable.signIn(AccountProvider.google), isFalse);
      expect(unavailable.user, isNull);
      expect(prefs.getString(PrefsKeys.habits), 'local-data');
    },
  );
  test(
    'initialization coalesces concurrent calls and remains idempotent',
    () async {
      backend.initializeGate = Completer<void>();
      final a = service.initialize();
      final b = service.initialize();
      await Future<void>.delayed(Duration.zero);
      backend.initializeGate!.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(await service.initialize(), isTrue);
      expect(backend.initializations, 1);
    },
  );
  test(
    'guest signup into empty cloud preserves records without uploading',
    () async {
      await service.initialize();
      expect(await service.signIn(AccountProvider.google), isTrue);
      expect(service.phase, AccountPhase.ready);
      expect(backend.writes, 0);
      expect(prefs.getString(PrefsKeys.habits), 'local-data');
      expect(await service.backupNow('first'), isTrue);
      expect(service.lastSuccessfulBackupAt, backend.cloud!.createdAt);
    },
  );
  test(
    'existing cloud requires an explicit decision before any upload',
    () async {
      backend.cloud = backup(4);
      await service.initialize();
      await service.signIn(AccountProvider.apple);
      expect(service.phase, AccountPhase.reconcileRequired);
      expect(await service.backupNow('local'), isFalse);
      expect(backend.writes, 0);
      expect(service.cloudArchiveForRestore, 'archive');
      expect(prefs.getString(PrefsKeys.habits), 'local-data');
      expect(await service.keepLocal('local'), isTrue);
      expect(backend.cloud!.revision, 5);
    },
  );
  test('a stale revision cannot overwrite another device', () async {
    await service.initialize();
    await service.signIn(AccountProvider.google);
    backend.cloud = backup(1, 'other-device');
    expect(await service.backupNow('local'), isFalse);
    expect(service.errorCode, 'conflict');
    expect(backend.cloud!.encodedArchive, 'other-device');
    expect(await service.keepLocal('local'), isFalse);
    expect(service.errorCode, 'cloud-not-checked');
    await service.refreshBackup();
    expect(service.needsReconciliation, isTrue);
  });
  test('failed cloud read after login does not mark backups ready', () async {
    backend.readFailure = const AccountFailure('network');
    await service.initialize();
    expect(await service.signIn(AccountProvider.google), isFalse);
    expect(service.user!.uid, 'one');
    expect(await service.backupNow('local'), isFalse);
    expect(service.lastSuccessfulBackupAt, isNull);
    expect(backend.writes, 0);
  });
  test('failed upload retains last successful timestamp and backup', () async {
    await service.initialize();
    await service.signIn(AccountProvider.google);
    await service.backupNow('first');
    final lastSuccess = service.lastSuccessfulBackupAt;
    backend.writeFailure = const AccountFailure('network');
    expect(await service.backupNow('second'), isFalse);
    expect(service.lastSuccessfulBackupAt, lastSuccess);
    expect(backend.cloud!.encodedArchive, 'first');
  });
  test('cancelling sign in leaves local data untouched', () async {
    await service.initialize();
    backend.signInFailure = const AccountFailure('cancelled');
    expect(await service.signIn(AccountProvider.apple), isFalse);
    expect(service.phase, AccountPhase.guest);
    expect(service.user, isNull);
    expect(prefs.getString(PrefsKeys.habits), 'local-data');
  });
  test(
    'matching persisted owner and revision avoid repeated reconciliation',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      await service.backupNow('first');
      final reopened = AccountService(backend: backend, prefs: prefs);
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.phase, AccountPhase.ready);
      expect(reopened.needsReconciliation, isFalse);
      expect(reopened.lastSuccessfulBackupAt, backend.cloud!.createdAt);
    },
  );
  test(
    'another account with no backup still cannot auto-upload prior owner data',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      await service.backupNow('first');
      await service.signOut();
      backend.nextUser = const AccountIdentity(uid: 'two');
      backend.cloud = null;
      await service.signIn(AccountProvider.apple);
      expect(service.needsReconciliation, isTrue);
      expect(await service.backupNow('first'), isFalse);
      expect(backend.writes, 1);
      expect(await service.keepLocal('first'), isTrue);
    },
  );
  test(
    'restore is only acknowledged by the explicit matching revision',
    () async {
      backend.cloud = backup(5);
      await service.initialize();
      await service.signIn(AccountProvider.apple);
      expect(await service.confirmCloudRestored(4), isFalse);
      expect(service.needsReconciliation, isTrue);
      await service.refreshBackup();
      expect(await service.confirmCloudRestored(5), isTrue);
      expect(service.needsReconciliation, isFalse);
      expect(prefs.getString(PrefsKeys.habits), 'local-data');
    },
  );
  test('a malformed owner receipt blocks automatic backup', () async {
    await prefs.setString(PrefsKeys.accountDeviceState, 'invalid');
    await service.initialize();
    await service.signIn(AccountProvider.google);
    expect(service.needsReconciliation, isTrue);
    expect(await service.backupNow('local'), isFalse);
  });
  test(
    'forced startup after local reset discards prior owner receipt',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      await service.backupNow('first');
      await prefs.remove(PrefsKeys.accountDeviceState);
      await service.initialize(force: true);
      expect(service.needsReconciliation, isTrue);
      expect(service.lastSuccessfulBackupAt, isNull);
      expect(await service.backupNow('empty-reset-save'), isFalse);
      expect(backend.cloud!.encodedArchive, 'first');
    },
  );
  test('unexpected native account change blocks upload', () async {
    await service.initialize();
    await service.signIn(AccountProvider.google);
    backend.currentUser = const AccountIdentity(uid: 'unexpected');
    expect(await service.backupNow('local'), isFalse);
    expect(service.errorCode, 'account-changed');
    expect(backend.writes, 0);
    expect(service.latestBackup, isNull);
    expect(await service.backupNow('second-attempt'), isFalse);
    expect(service.errorCode, 'cloud-not-checked');
    expect(backend.writes, 0);
  });
  test(
    'native switch invalidates a previously confirmed matching revision',
    () async {
      await service.initialize();
      await service.signIn(AccountProvider.google);
      await service.backupNow('owner-one-save');
      backend.currentUser = const AccountIdentity(uid: 'two');
      backend.cloud = backup(1, 'owner-two-save');
      expect(await service.backupNow('owner-one-save'), isFalse);
      expect(await service.backupNow('owner-one-save'), isFalse);
      expect(backend.cloud!.encodedArchive, 'owner-two-save');
      expect(backend.writes, 1);
      await service.refreshBackup();
      expect(service.needsReconciliation, isTrue);
      expect(await service.backupNow('owner-one-save'), isFalse);
      expect(backend.writes, 1);
    },
  );
  test('account deletion preserves guest records and clears receipt', () async {
    await service.initialize();
    await service.signIn(AccountProvider.google);
    await service.backupNow('first');
    expect(await service.deleteAccount(AccountProvider.google), isTrue);
    expect(service.user, isNull);
    expect(service.phase, AccountPhase.guest);
    expect(prefs.containsKey(PrefsKeys.accountDeviceState), isFalse);
    expect(prefs.getString(PrefsKeys.habits), 'local-data');
  });
}
