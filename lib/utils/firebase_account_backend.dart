import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'account_backend.dart';
import 'account_cloud_config.dart';
import 'backup_archive.dart';
import 'cloud_backup_codec.dart';
import 'cloud_backup_write_guard.dart';

/// Real Firebase adapter. Missing configuration fails closed; local guest
/// functionality remains independent from this service.
class FirebaseAccountBackend implements AccountBackend {
  FirebaseAccountBackend({this.config = AccountCloudConfig.fromEnvironment});
  final AccountCloudConfig config;
  FirebaseAuth? _auth;
  FirebaseFirestore? _db;
  bool _googleInitialized = false;
  bool _initialized = false;
  final _writes = CloudBackupWriteGuard();

  @override
  bool get configured => config.configured;
  @override
  Set<AccountProvider> get availableProviders => {
    if (config.supportsApple) AccountProvider.apple,
    if (config.supportsGoogle) AccountProvider.google,
  };
  @override
  AccountIdentity? get currentUser => _identity(_auth?.currentUser);

  AccountIdentity? _identity(User? user) => user == null || user.isAnonymous
      ? null
      : AccountIdentity(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
          providers: {
            for (final provider in user.providerData)
              if (provider.providerId == 'apple.com')
                AccountProvider.apple
              else if (provider.providerId == 'google.com')
                AccountProvider.google,
          },
        );

  @override
  Future<void> initialize() async {
    if (!configured || _initialized) return;
    await _mapErrors(() async {
      final name = 'tumi-${config.namespace}';
      final existing = Firebase.apps.where((app) => app.name == name);
      final FirebaseApp app;
      if (existing.isEmpty) {
        app = await Firebase.initializeApp(name: name, options: config.options);
      } else {
        app = existing.first;
        if (app.options.projectId != config.projectId ||
            app.options.appId != config.appId) {
          throw const AccountFailure('configuration-mismatch');
        }
      }
      _auth = FirebaseAuth.instanceFor(app: app);
      _db = FirebaseFirestore.instanceFor(app: app);
      // Disable disk persistence of account data. Memory write queuing still
      // exists; staging bounds and the publication guard handle offline waits.
      _db!.settings = const Settings(persistenceEnabled: false);
      _initialized = true;
    });
  }

  FirebaseAuth get _readyAuth =>
      _auth ?? (throw const AccountFailure('not-configured'));
  FirebaseFirestore get _readyDb =>
      _db ?? (throw const AccountFailure('not-configured'));
  User get _requiredUser {
    final user = _readyAuth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const AccountFailure('signed-out');
    }
    return user;
  }

  void _checkProvider(AccountProvider provider) {
    if (!availableProviders.contains(provider)) {
      throw const AccountFailure('provider-unavailable');
    }
  }

  Future<AuthCredential> _googleCredential() async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(
        clientId: config.googleClientId.isEmpty ? null : config.googleClientId,
        serverClientId: config.googleServerClientId.isEmpty
            ? null
            : config.googleServerClientId,
      );
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw const AccountFailure('credential-unavailable');
    return GoogleAuthProvider.credential(idToken: token);
  }

  AuthProvider _provider(AccountProvider provider) => switch (provider) {
    AccountProvider.apple => AppleAuthProvider(),
    AccountProvider.google => GoogleAuthProvider(),
  };

  @override
  Future<AccountIdentity> signIn(
    AccountProvider provider,
  ) => _mapErrors(() async {
    _checkProvider(provider);
    final UserCredential result;
    if (kIsWeb) {
      result = await _readyAuth.signInWithPopup(_provider(provider));
    } else if (provider == AccountProvider.google) {
      result = await _readyAuth.signInWithCredential(await _googleCredential());
    } else {
      result = await _readyAuth.signInWithProvider(AppleAuthProvider());
    }
    return _identity(result.user) ?? (throw const AccountFailure('signed-out'));
  });

  @override
  Future<AccountIdentity> linkProvider(AccountProvider provider) =>
      _mapErrors(() async {
        _checkProvider(provider);
        final user = _requiredUser;
        final UserCredential result;
        if (kIsWeb) {
          result = await user.linkWithPopup(_provider(provider));
        } else if (provider == AccountProvider.google) {
          result = await user.linkWithCredential(await _googleCredential());
        } else {
          result = await user.linkWithProvider(AppleAuthProvider());
        }
        if (result.user?.uid != user.uid) {
          throw const AccountFailure('account-changed');
        }
        return _identity(result.user)!;
      });

  @override
  Future<AccountIdentity> unlinkProvider(AccountProvider provider) =>
      _mapErrors(() async {
        final user = _requiredUser;
        if (user.providerData.length <= 1) {
          throw const AccountFailure('last-provider');
        }
        final result = await user.unlink(
          provider == AccountProvider.apple ? 'apple.com' : 'google.com',
        );
        return _identity(result)!;
      });

  @override
  Future<void> signOut() => _mapErrors(() async {
    await _auth?.signOut();
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
  });

  DocumentReference<Map<String, dynamic>> _owner(String uid) =>
      _readyDb.collection('tumi_backups_${config.namespace}').doc(uid);
  DocumentReference<Map<String, dynamic>> _head(String uid) =>
      _owner(uid).collection('state').doc('head');

  @override
  Future<CloudBackup?> readLatest() => _mapErrors(() async {
    _writes.ensureSettled();
    final uid = _requiredUser.uid;
    final doc = await _head(
      uid,
    ).get(const GetOptions(source: Source.server)).boundedServerRead();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final snapshotId = data['snapshotId'];
    final count = data['chunkCount'];
    final byteLength = data['byteLength'];
    final checksum = data['checksum'];
    final revision = data['revision'];
    final createdAt = data['createdAt'];
    if (snapshotId is! String ||
        !RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(snapshotId) ||
        count is! int ||
        count < 1 ||
        count > CloudBackupCodec.maxChunks ||
        byteLength is! int ||
        byteLength < 1 ||
        byteLength > CloudBackupCodec.maxBytes ||
        checksum is! String ||
        revision is! int ||
        revision < 1 ||
        createdAt is! Timestamp) {
      throw const AccountFailure('backup-invalid');
    }
    final ref = _owner(uid).collection('snapshots').doc(snapshotId);
    final chunks = <String>[];
    for (var offset = 0; offset < count; offset += 8) {
      final loaded = await Future.wait([
        for (var i = offset; i < count && i < offset + 8; i++)
          ref
              .collection('chunks')
              .doc('$i')
              .get(const GetOptions(source: Source.server))
              .boundedServerRead(),
      ]);
      for (final part in loaded) {
        final payload = part.data()?['payload'];
        if (payload is! String) throw const AccountFailure('backup-invalid');
        chunks.add(payload);
      }
    }
    if (_requiredUser.uid != uid) throw const AccountFailure('account-changed');
    final encoded = CloudBackupCodec.join(
      chunks,
      byteLength: byteLength,
      expectedChecksum: checksum,
    );
    try {
      BackupArchive.decode(encoded);
    } catch (_) {
      throw const AccountFailure('backup-invalid');
    }
    return CloudBackup(
      revision: revision,
      createdAt: createdAt.toDate().toUtc(),
      encodedArchive: encoded,
      byteLength: byteLength,
    );
  });

  @override
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  }) => _mapErrors(() async {
    _writes.ensureSettled();
    final uid = _requiredUser.uid;
    if (expectedRevision < 0) throw const AccountFailure('conflict');
    try {
      BackupArchive.decode(encodedArchive);
    } catch (_) {
      throw const AccountFailure('backup-invalid');
    }
    final chunks = CloudBackupCodec.split(encodedArchive);
    final length = utf8.encode(encodedArchive).length;
    final checksum = CloudBackupCodec.checksum(encodedArchive);
    final snapshot = _owner(uid).collection('snapshots').doc();
    // This staging manifest also lets a later successful backup remove old
    // interrupted uploads. No staged snapshot is visible as a usable backup.
    await _writes.stage(
      () => snapshot.set({
        'createdAt': FieldValue.serverTimestamp(),
        'chunkCount': chunks.length,
        'byteLength': length,
        'checksum': checksum,
        'schemaVersion': 1,
      }),
    );
    for (var offset = 0; offset < chunks.length; offset += 8) {
      final batch = _readyDb.batch();
      for (var i = offset; i < chunks.length && i < offset + 8; i++) {
        batch.set(snapshot.collection('chunks').doc('$i'), {
          'index': i,
          'payload': chunks[i],
        });
      }
      await _writes.stage(batch.commit);
    }
    if (_requiredUser.uid != uid) throw const AccountFailure('account-changed');
    // A wait timeout means "still confirming", not cancellation. Keep the
    // native transaction observed and block another cloud operation until it
    // settles. FlutterFire's iOS timeout bounds the Dart callback only.
    await _writes.publish(
      () => _readyDb.runTransaction((transaction) async {
        if (_requiredUser.uid != uid) {
          throw const AccountFailure('account-changed');
        }
        final headRef = _head(uid);
        final current = await transaction.get(headRef).boundedServerRead();
        if (_requiredUser.uid != uid) {
          throw const AccountFailure('account-changed');
        }
        final data = current.data();
        final revision = data?['revision'] ?? 0;
        if (revision != expectedRevision) {
          throw const AccountFailure('conflict');
        }
        transaction.set(headRef, {
          'snapshotId': snapshot.id,
          'previousSnapshotId': data?['snapshotId'],
          'revision': expectedRevision + 1,
          'createdAt': FieldValue.serverTimestamp(),
          'chunkCount': chunks.length,
          'byteLength': length,
          'checksum': checksum,
          'schemaVersion': 1,
        });
      }, maxAttempts: 1),
    );
    final committed = await _writes.confirm(
      () => _head(uid).get(const GetOptions(source: Source.server)),
    );
    final head = committed.data();
    if (head?['snapshotId'] != snapshot.id ||
        head?['createdAt'] is! Timestamp) {
      throw const AccountFailure('conflict');
    }
    final result = CloudBackup(
      revision: expectedRevision + 1,
      createdAt: (head!['createdAt'] as Timestamp).toDate().toUtc(),
      encodedArchive: encodedArchive,
      byteLength: length,
    );
    // Retain current and previous snapshots. Cleanup failures cannot turn a
    // successfully acknowledged backup into a failure in the UI.
    _writes.prune(() => _prune(uid));
    return result;
  });

  Future<void> _prune(String uid) async {
    final latest = (await _head(
      uid,
    ).get(const GetOptions(source: Source.server)).boundedServerRead()).data();
    final protected = {latest?['snapshotId'], latest?['previousSnapshotId']};
    final candidates = await _owner(uid)
        .collection('snapshots')
        .orderBy('createdAt')
        .limit(120)
        .get(const GetOptions(source: Source.server))
        .boundedServerRead();
    final committedAt = latest?['createdAt'];
    if (committedAt is! Timestamp) return;
    // Server time avoids pruning another device's active upload when this
    // device's clock is incorrectly set far into the future.
    final cutoff = committedAt.toDate().toUtc().subtract(
      const Duration(days: 1),
    );
    for (final snapshot in candidates.docs) {
      final createdAt = snapshot.data()['createdAt'];
      if (protected.contains(snapshot.id) ||
          createdAt is! Timestamp ||
          !createdAt.toDate().isBefore(cutoff)) {
        continue;
      }
      // Re-read head immediately before delete so another device's backup
      // doesn't accidentally lose the prior version it just selected.
      final current =
          (await _head(uid)
                  .get(const GetOptions(source: Source.server))
                  .boundedServerRead())
              .data();
      if (current?['snapshotId'] == snapshot.id ||
          current?['previousSnapshotId'] == snapshot.id) {
        continue;
      }
      await _deleteSnapshot(snapshot.reference);
    }
  }

  Future<void> _deleteSnapshot(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    while (true) {
      final chunks = await ref
          .collection('chunks')
          .limit(100)
          .get(const GetOptions(source: Source.server))
          .boundedServerRead();
      if (chunks.docs.isEmpty) break;
      final batch = _readyDb.batch();
      for (final chunk in chunks.docs) {
        batch.delete(chunk.reference);
      }
      await _writes.boundedUnpublishedWrite(batch.commit);
    }
    await _writes.boundedUnpublishedWrite(ref.delete);
  }

  @override
  Future<void> deleteAccount(AccountProvider reauthenticateWith) => _mapErrors(
    () async {
      _writes.ensureSettled();
      _checkProvider(reauthenticateWith);
      final user = _requiredUser;
      final UserCredential reauthenticated;
      if (kIsWeb) {
        reauthenticated = await user.reauthenticateWithPopup(
          _provider(reauthenticateWith),
        );
      } else if (reauthenticateWith == AccountProvider.google) {
        reauthenticated = await user.reauthenticateWithCredential(
          await _googleCredential(),
        );
      } else {
        reauthenticated = await user.reauthenticateWithProvider(
          AppleAuthProvider(),
        );
      }
      if (reauthenticated.user?.uid != user.uid) {
        throw const AccountFailure('account-changed');
      }
      // Apple recommends revoking its token before removing the account.
      if (reauthenticateWith == AccountProvider.apple) {
        final code = reauthenticated.additionalUserInfo?.authorizationCode;
        if (code == null) throw const AccountFailure('credential-unavailable');
        await _readyAuth.revokeTokenWithAuthorizationCode(code);
      }
      // A tombstone blocks other devices from uploading during deletion.
      await _owner(user.uid).set({'deleting': true});
      await _head(user.uid).delete();
      while (true) {
        final snapshots = await _owner(user.uid)
            .collection('snapshots')
            .limit(50)
            .get(const GetOptions(source: Source.server))
            .boundedServerRead();
        if (snapshots.docs.isEmpty) break;
        for (final snapshot in snapshots.docs) {
          await _deleteSnapshot(snapshot.reference);
        }
      }
      await user.delete();
      // Keep the deletion tombstone: it contains no profile or records and
      // prevents still-valid tokens from recreating data before expiry.
      if (_googleInitialized) await GoogleSignIn.instance.signOut();
    },
  );

  Future<T> _mapErrors<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AccountFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw AccountFailure(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'cancelled'
            : 'google-sign-in-failed',
      );
    } on FirebaseException catch (error) {
      final code = switch (error.code) {
        'network-request-failed' ||
        'unavailable' ||
        'deadline-exceeded' => 'network',
        'web-context-cancelled' ||
        'canceled' ||
        'cancelled-popup-request' ||
        'popup-closed-by-user' => 'cancelled',
        'permission-denied' => 'permission-denied',
        'requires-recent-login' => 'reauthentication-required',
        'credential-already-in-use' ||
        'account-exists-with-different-credential' =>
          'credential-already-in-use',
        'provider-already-linked' => 'provider-already-linked',
        'user-disabled' ||
        'user-token-expired' ||
        'invalid-user-token' ||
        'user-not-found' => 'session-expired',
        'operation-not-allowed' ||
        'invalid-api-key' ||
        'app-not-authorized' => 'provider-unavailable',
        'resource-exhausted' => 'quota-exceeded',
        'aborted' => 'conflict',
        _ => 'cloud-failed',
      };
      throw AccountFailure(code);
    }
  }
}

extension _ServerReadTimeout<T> on Future<T> {
  Future<T> boundedServerRead() => timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw const AccountFailure('network'),
  );
}
