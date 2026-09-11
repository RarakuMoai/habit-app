enum AccountProvider { apple, google }

class AccountIdentity {
  const AccountIdentity({
    required this.uid,
    this.displayName,
    this.email,
    this.providers = const {},
  });
  final String uid;
  final String? displayName;
  final String? email;
  final Set<AccountProvider> providers;
}

class CloudBackup {
  const CloudBackup({
    required this.revision,
    required this.createdAt,
    required this.encodedArchive,
    required this.byteLength,
  });
  final int revision;
  final DateTime createdAt;
  final String encodedArchive;
  final int byteLength;
}

/// Stable codes for localized UI; never expose raw provider error messages.
class AccountFailure implements Exception {
  const AccountFailure(this.code);
  final String code;
  @override
  String toString() => 'AccountFailure($code)';
}

abstract interface class AccountBackend {
  bool get configured;
  Set<AccountProvider> get availableProviders;
  AccountIdentity? get currentUser;
  Future<void> initialize();
  Future<AccountIdentity> signIn(AccountProvider provider);
  Future<void> signOut();
  Future<AccountIdentity> linkProvider(AccountProvider provider);
  Future<AccountIdentity> unlinkProvider(AccountProvider provider);
  Future<void> deleteAccount(AccountProvider reauthenticateWith);
  Future<CloudBackup?> readLatest();
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  });
}

class UnavailableAccountBackend implements AccountBackend {
  const UnavailableAccountBackend();
  @override
  bool get configured => false;
  @override
  Set<AccountProvider> get availableProviders => const {};
  @override
  AccountIdentity? get currentUser => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<AccountIdentity> signIn(AccountProvider provider) async =>
      throw const AccountFailure('not-configured');
  @override
  Future<void> signOut() async {}
  @override
  Future<AccountIdentity> linkProvider(AccountProvider provider) async =>
      throw const AccountFailure('not-configured');
  @override
  Future<AccountIdentity> unlinkProvider(AccountProvider provider) async =>
      throw const AccountFailure('not-configured');
  @override
  Future<void> deleteAccount(AccountProvider reauthenticateWith) async =>
      throw const AccountFailure('not-configured');
  @override
  Future<CloudBackup?> readLatest() async =>
      throw const AccountFailure('not-configured');
  @override
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  }) async => throw const AccountFailure('not-configured');
}
