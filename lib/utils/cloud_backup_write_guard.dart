import 'dart:async';

import 'account_backend.dart';

/// Bounds the caller's wait without pretending a Firestore write was cancelled.
/// Immutable staging may finish late, but can never publish a backup by itself.
/// Publication keeps an in-flight guard until the native operation settles.
class CloudBackupWriteGuard {
  CloudBackupWriteGuard({this.waitLimit = const Duration(seconds: 20)});

  final Duration waitLimit;
  Future<void>? _publication;
  bool _pruning = false;

  void ensureSettled() {
    if (_publication != null) throw const AccountFailure('backup-pending');
  }

  Future<void> stage(Future<void> Function() write) {
    ensureSettled();
    return boundedUnpublishedWrite(write);
  }

  /// Only for immutable staging or deletion of obsolete snapshots. Never pass
  /// a head write here: a timeout abandons waiting, not the underlying write.
  Future<void> boundedUnpublishedWrite(Future<void> Function() write) =>
      Future<void>.sync(write).timeout(
        waitLimit,
        onTimeout: () => throw const AccountFailure('network'),
      );

  Future<T> publish<T>(Future<T> Function() commit) async {
    ensureSettled();
    final operation = Future<T>.sync(commit);
    // Keep observing both late success and late failure. The UI may have
    // stopped waiting, but no new read/write may claim a stable cloud head yet.
    final settled = operation.then<void>((_) {}, onError: (Object _) {});
    _publication = settled;
    unawaited(
      settled.then((_) {
        if (identical(_publication, settled)) _publication = null;
      }),
    );
    return operation.timeout(
      waitLimit,
      onTimeout: () => throw const AccountFailure('backup-pending'),
    );
  }

  /// The commit already completed, so a failed acknowledgement read is an
  /// uncertain result. A fresh server read must precede another user decision.
  Future<T> confirm<T>(Future<T> Function() read) async {
    try {
      return await Future<T>.sync(read).timeout(waitLimit);
    } catch (_) {
      throw const AccountFailure('backup-pending');
    }
  }

  /// Cleanup must not delay an already acknowledged result. At most one sweep
  /// runs, and its individual writes must use boundedUnpublishedWrite above.
  void prune(Future<void> Function() cleanup) {
    if (_pruning) return;
    _pruning = true;
    unawaited(
      Future<void>.sync(cleanup)
          .catchError((Object _) {
            // A later manually requested backup can retry obsolete cleanup.
          })
          .whenComplete(() => _pruning = false),
    );
  }
}
