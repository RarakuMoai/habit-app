import 'dart:async';

class _StorageLease {
  bool active = true;
  final Set<Future<void>> children = {};
}

/// Coordinates a backup snapshot with complete, high-level storage mutations.
///
/// Normal writes retain their existing concurrency and may call nested writes.
/// A snapshot waits for all tracked work, then delays new writes until the
/// snapshot owner finishes. Wrap complete business operations, never user
/// dialogs. Existing write guards still own failure recovery: this barrier does
/// not supply transactions or rollbacks for failed preference operations.
abstract final class StorageSnapshotGate {
  static final Set<Future<void>> _mutations = {};
  static Future<void>? _snapshotDone;
  static Future<void>? _snapshotTail;
  static final Object _snapshotZoneKey = Object();
  static final Object _writeZoneKey = Object();

  static _StorageLease? get _snapshotOwner {
    final lease = Zone.current[_snapshotZoneKey] as _StorageLease?;
    return lease?.active == true ? lease : null;
  }

  static Future<T> write<T>(Future<T> Function() operation) {
    final owner = _snapshotOwner;
    if (owner != null) {
      // The exclusive owner can enter existing storage coordinators. Track
      // even unawaited nested work so ownership cannot end before its writes.
      return _track(operation, owner.children);
    }
    final snapshot = _snapshotDone;
    if (snapshot != null) return snapshot.then((_) => write(operation));
    return _track(operation, _mutations);
  }

  static Future<T> _track<T>(
    Future<T> Function() operation,
    Set<Future<void>> pending,
  ) {
    final lease = _StorageLease();
    final result = runZoned(
      () => Future<T>.sync(operation),
      zoneValues: {_writeZoneKey: lease},
    );
    final completion = result.then<void>(
      (_) => lease.active = false,
      onError: (Object _, StackTrace _) {
        lease.active = false;
      },
    );
    pending.add(completion);
    unawaited(completion.whenComplete(() => pending.remove(completion)));
    return result;
  }

  static Future<T> snapshot<T>(Future<T> Function() operation) {
    final owner = _snapshotOwner;
    if (owner != null) return _track(operation, owner.children);
    final writer = Zone.current[_writeZoneKey] as _StorageLease?;
    if (writer?.active == true) {
      return Future<T>.error(StateError('A write cannot snapshot itself'));
    }
    final previous = _snapshotTail;
    final result = previous == null
        ? _capture(operation)
        : previous.then((_) => _capture(operation));
    final release = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _snapshotTail = release;
    unawaited(
      release.whenComplete(() {
        if (identical(_snapshotTail, release)) _snapshotTail = null;
      }),
    );
    return result;
  }

  static Future<T> _capture<T>(Future<T> Function() operation) async {
    // Do not block nested writes while draining their parents. No await may
    // occur between the empty check and installing the snapshot barrier.
    while (_mutations.isNotEmpty) {
      await Future.wait(_mutations.toList());
    }
    final done = Completer<void>();
    final owner = _StorageLease();
    _snapshotDone = done.future;
    try {
      return await runZoned(operation, zoneValues: {_snapshotZoneKey: owner});
    } finally {
      while (owner.children.isNotEmpty) {
        await Future.wait(owner.children.toList());
      }
      owner.active = false;
      _snapshotDone = null;
      done.complete();
    }
  }
}
