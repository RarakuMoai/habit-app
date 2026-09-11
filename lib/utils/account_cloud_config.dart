// Build defines intentionally override these defaults in configured builds.
// The analyzer otherwise treats absent local defines as redundant arguments.
// ignore_for_file: avoid_redundant_argument_values

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public app identifiers only. Private Apple keys and service-account keys
/// belong in the provider console, never in the app or its build defines.
class AccountCloudConfig {
  const AccountCloudConfig({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    required this.iosBundleId,
    this.googleClientId = '',
    this.googleServerClientId = '',
    this.authDomain = '',
    this.appleEnabled = false,
    this.googleEnabled = false,
    this.namespace = 'redesign',
  });

  static const fromEnvironment = AccountCloudConfig(
    apiKey: String.fromEnvironment('TUMI_FIREBASE_API_KEY'),
    appId: String.fromEnvironment('TUMI_FIREBASE_APP_ID'),
    projectId: String.fromEnvironment('TUMI_FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment(
      'TUMI_FIREBASE_MESSAGING_SENDER_ID',
    ),
    iosBundleId: String.fromEnvironment(
      'TUMI_IOS_BUNDLE_ID',
      defaultValue: 'com.yayoi991331.habitapp.redesign',
    ),
    googleClientId: String.fromEnvironment('TUMI_GOOGLE_IOS_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment(
      'TUMI_GOOGLE_SERVER_CLIENT_ID',
    ),
    authDomain: String.fromEnvironment('TUMI_FIREBASE_AUTH_DOMAIN'),
    appleEnabled: bool.fromEnvironment('TUMI_APPLE_SIGN_IN_ENABLED'),
    googleEnabled: bool.fromEnvironment('TUMI_GOOGLE_SIGN_IN_ENABLED'),
    namespace: String.fromEnvironment(
      'TUMI_BACKUP_NAMESPACE',
      defaultValue: 'redesign',
    ),
  );

  final String apiKey, appId, projectId, messagingSenderId, iosBundleId;
  final String googleClientId, googleServerClientId, authDomain, namespace;
  final bool appleEnabled, googleEnabled;

  bool get configured =>
      [
        apiKey,
        appId,
        projectId,
        messagingSenderId,
      ].every((value) => value.trim().isNotEmpty) &&
      RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(namespace);
  bool get supportsApple =>
      configured &&
      appleEnabled &&
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  bool get supportsGoogle =>
      configured &&
      googleEnabled &&
      (kIsWeb ||
          (defaultTargetPlatform == TargetPlatform.iOS &&
              googleClientId.isNotEmpty) ||
          defaultTargetPlatform == TargetPlatform.android);

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    iosBundleId: iosBundleId,
    authDomain: authDomain.isEmpty ? null : authDomain,
  );
}
