import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_backend.dart';
import 'preference_write_guard.dart';
import 'prefs_keys.dart';

export 'account_backend.dart';

enum AccountPhase {
  guest,
  unavailable,
  connecting,
  ready,
  reconcileRequired,
  backingUp,
  error,
}

/// Coordinates identity and explicit backup decisions. It never writes or
/// clears habit data. The caller applies a cloud archive using BackupRestore.
class AccountService extends ChangeNotifier {
  AccountService({required AccountBackend backend, SharedPreferences? prefs})
    : _backend = backend,
      _prefs = prefs;
  static AccountService instance = AccountService(
    backend: const UnavailableAccountBackend(),
  );

  final AccountBackend _backend;
  SharedPreferences? _prefs;
  String? _ownerUid;
  int? _localRevision;
  AccountPhase phase = AccountPhase.guest;
  AccountIdentity? user;
  CloudBackup? latestBackup;
  DateTime? lastSuccessfulBackupAt;
  String? errorCode;
  bool _busy = false;
  bool _cloudChecked = false;
  bool _reconciled = false;
  bool _ownerMismatch = false;
  bool initialized = false;
  Future<bool>? _initializing;

  bool get busy => _busy;
  bool get configured => _backend.configured;
  Set<AccountProvider> get availableProviders => _backend.availableProviders;
  bool get needsReconciliation =>
      _ownerMismatch || (latestBackup != null && !_reconciled);

  Future<bool> initialize({bool force = false}) {
    if (_initializing != null) return _initializing!;
    if (initialized && !force) return Future.value(true);
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<bool> _initialize() async {
    final success = await _operate(AccountPhase.connecting, () async {
      await _loadDeviceState();
      await _backend.initialize();
      _syncAuthIdentity();
      if (!configured) {
        phase = AccountPhase.unavailable;
      } else if (user == null) {
        lastSuccessfulBackupAt = null;
        phase = AccountPhase.guest;
      } else {
        await _readCloud();
      }
    });
    if (success) initialized = true;
    return success;
  }

  Future<bool> signIn(AccountProvider provider) =>
      _operate(AccountPhase.connecting, () async {
        await _loadDeviceState();
        if (!availableProviders.contains(provider)) {
          throw const AccountFailure('provider-unavailable');
        }
        // A sign-in never uploads the current device's data. This also avoids
        // transferring one person's local save to a different account.
        user = await _backend.signIn(provider);
        latestBackup = null;
        lastSuccessfulBackupAt = null;
        _cloudChecked = false;
        _reconciled = false;
        await _readCloud();
      });

  Future<bool> refreshBackup() => _operate(AccountPhase.connecting, _readCloud);

  Future<void> _readCloud() async {
    if (user == null) throw const AccountFailure('signed-out');
    final uid = user!.uid;
    if (_backend.currentUser?.uid != uid) {
      throw const AccountFailure('account-changed');
    }
    _cloudChecked = false;
    final backup = await _backend.readLatest();
    if (_backend.currentUser?.uid != uid) {
      throw const AccountFailure('account-changed');
    }
    latestBackup = backup;
    _cloudChecked = true;
    _ownerMismatch = _ownerUid != null && _ownerUid != user!.uid;
    _reconciled =
        !_ownerMismatch &&
        _ownerUid == user!.uid &&
        _localRevision == latestBackup?.revision;
    lastSuccessfulBackupAt = _reconciled ? latestBackup?.createdAt : null;
    phase = needsReconciliation
        ? AccountPhase.reconcileRequired
        : AccountPhase.ready;
  }

  /// Explicitly choose this device's save. The backend compares the revision
  /// seen in the cloud preview before replacing the cloud head.
  Future<bool> keepLocal(String encodedArchive) =>
      _save(encodedArchive, explicitReplacement: true);

  Future<bool> backupNow(String encodedArchive) =>
      _save(encodedArchive, explicitReplacement: false);

  Future<bool> _save(
    String encodedArchive, {
    required bool explicitReplacement,
  }) => _operate(AccountPhase.backingUp, () async {
    if (user == null) throw const AccountFailure('signed-out');
    if (_backend.currentUser?.uid != user!.uid) {
      throw const AccountFailure('account-changed');
    }
    if (!_cloudChecked) throw const AccountFailure('cloud-not-checked');
    if (needsReconciliation && !explicitReplacement) {
      throw const AccountFailure('reconciliation-required');
    }
    final uid = user!.uid;
    final saved = await _backend.writeSnapshot(
      encodedArchive,
      expectedRevision: latestBackup?.revision ?? 0,
    );
    if (_backend.currentUser?.uid != uid) {
      throw const AccountFailure('account-changed');
    }
    latestBackup = saved;
    lastSuccessfulBackupAt = saved.createdAt;
    await _saveDeviceState(saved);
    phase = AccountPhase.ready;
  });

  /// Caller must validate/stage this archive, then restart through recovery.
  /// Reading it is deliberately not recorded as a completed restore.
  String? get cloudArchiveForRestore => latestBackup?.encodedArchive;

  Future<bool> confirmCloudRestored(int revision) =>
      _operate(AccountPhase.connecting, () async {
        if (revision != latestBackup?.revision || user == null) {
          throw const AccountFailure('conflict');
        }
        await _saveDeviceState(latestBackup!);
        phase = AccountPhase.ready;
      });

  Future<bool> linkProvider(AccountProvider provider) =>
      _operate(AccountPhase.connecting, () async {
        if (!availableProviders.contains(provider)) {
          throw const AccountFailure('provider-unavailable');
        }
        user = await _backend.linkProvider(provider);
        phase = needsReconciliation
            ? AccountPhase.reconcileRequired
            : AccountPhase.ready;
      });

  Future<bool> unlinkProvider(AccountProvider provider) =>
      _operate(AccountPhase.connecting, () async {
        user = await _backend.unlinkProvider(provider);
        phase = needsReconciliation
            ? AccountPhase.reconcileRequired
            : AccountPhase.ready;
      });

  /// The UI confirms account/cloud deletion. Local records remain available
  /// as a guest save, and can be exported before this operation.
  Future<bool> deleteAccount(AccountProvider provider) =>
      _operate(AccountPhase.connecting, () async {
        await _backend.deleteAccount(provider);
        user = null;
        latestBackup = null;
        lastSuccessfulBackupAt = null;
        final prefs = _prefs ??= await SharedPreferences.getInstance();
        await PreferenceWriteGuard.write(
          prefs,
          () => prefs.remove(PrefsKeys.accountDeviceState),
          PrefsKeys.accountDeviceState,
        );
        _ownerUid = null;
        _localRevision = null;
        _ownerMismatch = false;
        _cloudChecked = false;
        _reconciled = false;
        phase = AccountPhase.guest;
      });

  /// Sign-out does not delete this device's habits or memories.
  Future<bool> signOut() => _operate(AccountPhase.connecting, () async {
    await _backend.signOut();
    user = null;
    latestBackup = null;
    lastSuccessfulBackupAt = null;
    _cloudChecked = false;
    _reconciled = false;
    _ownerMismatch = false;
    phase = configured ? AccountPhase.guest : AccountPhase.unavailable;
  });

  Future<void> _loadDeviceState() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await PreferenceWriteGuard.ensureHealthy(prefs);
    final raw = prefs.getString(PrefsKeys.accountDeviceState);
    if (raw == null) {
      _ownerUid = null;
      _localRevision = null;
      lastSuccessfulBackupAt = null;
      _reconciled = false;
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _ownerUid = data['ownerUid'] as String;
      _localRevision = data['revision'] as int;
      if (_ownerUid!.isEmpty || _localRevision! < 1) {
        throw const FormatException();
      }
      lastSuccessfulBackupAt = DateTime.tryParse(data['backupAt'] as String);
    } catch (_) {
      // A corrupt device receipt must never authorize automatic replacement.
      _ownerUid = 'invalid-receipt';
      _localRevision = null;
    }
  }

  Future<void> _saveDeviceState(CloudBackup backup) async {
    final uid = user?.uid;
    if (uid == null) throw const AccountFailure('signed-out');
    if (_backend.currentUser?.uid != uid) {
      throw const AccountFailure('account-changed');
    }
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'ownerUid': uid,
      'revision': backup.revision,
      'backupAt': backup.createdAt.toUtc().toIso8601String(),
    });
    try {
      await PreferenceWriteGuard.write(
        prefs,
        () => prefs.setString(PrefsKeys.accountDeviceState, encoded),
        PrefsKeys.accountDeviceState,
      );
    } catch (_) {
      _cloudChecked = false;
      _reconciled = false;
      throw const AccountFailure('device-state-write-failed');
    }
    _ownerUid = uid;
    _localRevision = backup.revision;
    _ownerMismatch = false;
    _reconciled = true;
    lastSuccessfulBackupAt = backup.createdAt;
  }

  void _syncAuthIdentity({bool invalidateCloud = false}) {
    final next = _backend.currentUser;
    if (invalidateCloud || next?.uid != user?.uid) {
      latestBackup = null;
      lastSuccessfulBackupAt = null;
      _cloudChecked = false;
      _reconciled = false;
      _ownerMismatch =
          next != null && _ownerUid != null && _ownerUid != next.uid;
    }
    user = next;
  }

  Future<bool> _operate(
    AccountPhase active,
    Future<void> Function() action,
  ) async {
    if (_busy) return false;
    _busy = true;
    errorCode = null;
    phase = active;
    notifyListeners();
    try {
      await action();
      return true;
    } on AccountFailure catch (error) {
      errorCode = error.code;
      // Authentication may have succeeded while the cloud read failed.
      // Keep the real account state, but disallow upload until a fresh read.
      _syncAuthIdentity(
        invalidateCloud:
            error.code == 'account-changed' || error.code == 'backup-pending',
      );
      if (error.code == 'conflict') {
        _cloudChecked = false;
        _reconciled = false;
      }
      phase = error.code == 'cancelled'
          ? (user == null
                ? AccountPhase.guest
                : needsReconciliation
                ? AccountPhase.reconcileRequired
                : AccountPhase.ready)
          : AccountPhase.error;
      return false;
    } catch (_) {
      _syncAuthIdentity();
      errorCode = 'unknown';
      phase = AccountPhase.error;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
