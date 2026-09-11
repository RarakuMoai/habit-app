import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/account_backend.dart';
import 'package:habit_app/utils/cloud_backup_write_guard.dart';

Matcher failure(String code) =>
    isA<AccountFailure>().having((error) => error.code, 'code', code);

void main() {
  const waitLimit = Duration(milliseconds: 10);

  test(
    'late staged write cannot continue to publish after waiting times out',
    () async {
      final guard = CloudBackupWriteGuard(waitLimit: waitLimit);
      final queuedWrite = Completer<void>();
      var publications = 0;
      Future<void> upload() async {
        await guard.stage(() => queuedWrite.future);
        await guard.publish(() async => publications++);
      }

      await expectLater(upload(), throwsA(failure('network')));
      queuedWrite.complete();
      await Future<void>.delayed(Duration.zero);
      expect(publications, 0);
      expect(guard.ensureSettled, returnsNormally);
    },
  );

  test(
    'publication wait expires without unlocking a late native commit',
    () async {
      final guard = CloudBackupWriteGuard(waitLimit: waitLimit);
      final nativeCommit = Completer<int>();
      await expectLater(
        guard.publish(() => nativeCommit.future),
        throwsA(failure('backup-pending')),
      );
      expect(guard.ensureSettled, throwsA(failure('backup-pending')));
      var retried = false;
      await expectLater(
        guard.publish(() async => retried = true),
        throwsA(failure('backup-pending')),
      );
      expect(retried, isFalse);
      nativeCommit.complete(2);
      await Future<void>.delayed(Duration.zero);
      expect(guard.ensureSettled, returnsNormally);
    },
  );

  test(
    'late native failure is observed and allows a fresh server check',
    () async {
      final guard = CloudBackupWriteGuard(waitLimit: waitLimit);
      final nativeCommit = Completer<void>();
      await expectLater(
        guard.publish(() => nativeCommit.future),
        throwsA(failure('backup-pending')),
      );
      nativeCommit.completeError(const AccountFailure('conflict'));
      await Future<void>.delayed(Duration.zero);
      expect(guard.ensureSettled, returnsNormally);
    },
  );

  test(
    'lost acknowledgement after commit reports uncertainty and permits fresh read',
    () async {
      final guard = CloudBackupWriteGuard(waitLimit: waitLimit);
      final serverRead = Completer<int>();
      expect(await guard.publish(() async => 2), 2);
      await expectLater(
        guard.confirm(() => serverRead.future),
        throwsA(failure('backup-pending')),
      );
      expect(guard.ensureSettled, returnsNormally);
      serverRead.complete(2);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        guard.confirm<int>(() async => throw const AccountFailure('network')),
        throwsA(failure('backup-pending')),
      );
    },
  );

  test('acknowledged publication is not held by offline cleanup', () async {
    final guard = CloudBackupWriteGuard(waitLimit: waitLimit);
    final offlineDelete = Completer<void>();
    var sweeps = 0;
    Future<void> cleanup() async {
      sweeps++;
      await guard.boundedUnpublishedWrite(() => offlineDelete.future);
    }

    expect(await guard.publish(() async => 2), 2);
    guard.prune(cleanup);
    guard.prune(cleanup);
    expect(sweeps, 1);
    expect(guard.ensureSettled, returnsNormally);
    await Future<void>.delayed(waitLimit * 2);
    guard.prune(() async => sweeps++);
    expect(sweeps, 2);
    offlineDelete.completeError(const AccountFailure('network'));
    await Future<void>.delayed(Duration.zero);
  });
}
