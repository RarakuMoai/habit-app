// Native review of the actual app root. Only state and notification delivery
// are isolated: no alternate MaterialApp, room, theme, or feature implementation.
// Run only through scripts/review/run_entry_integration.py on a named simulator.
import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/pages/account_backup_page.dart';
import 'package:habit_app/pages/app_entry_page.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/pages/timer_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/widgets/timer_mode_frame.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only interception of the process-local preference store.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _ReviewNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel({required int id}) async {}
}

/// Process-local identity fixture. A successful simulated identity deliberately
/// has no backup receipt and this backend refuses every cloud mutation.
class _ReviewAccountBackend implements AccountBackend {
  _ReviewAccountBackend({required bool signedIn})
    : currentUser = signedIn
          ? const AccountIdentity(
              uid: 'entry-review-simulated-identity',
              displayName: '模擬登入・小日',
              providers: {AccountProvider.apple},
            )
          : null;

  @override
  bool get configured => true;
  @override
  Set<AccountProvider> get availableProviders => AccountProvider.values.toSet();
  @override
  AccountIdentity? currentUser;
  @override
  Future<void> initialize() async {}
  CloudBackup? cloud;
  AccountFailure? signInFailure;
  AccountFailure? readFailure;
  int writes = 0;

  @override
  Future<CloudBackup?> readLatest() async {
    if (readFailure != null) throw readFailure!;
    return cloud;
  }

  @override
  Future<AccountIdentity> signIn(AccountProvider provider) async {
    if (signInFailure != null) throw signInFailure!;
    return currentUser = AccountIdentity(
      uid: 'entry-review-simulated-identity',
      displayName: '模擬登入・小日',
      providers: {provider},
    );
  }

  @override
  Future<void> signOut() async => currentUser = null;
  @override
  Future<AccountIdentity> linkProvider(AccountProvider provider) async =>
      throw StateError('Review fixtures never link real providers.');
  @override
  Future<AccountIdentity> unlinkProvider(AccountProvider provider) async =>
      throw StateError('Review fixtures never unlink real providers.');
  @override
  Future<void> deleteAccount(AccountProvider reauthenticateWith) async =>
      throw StateError('Review fixtures never delete accounts.');
  @override
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  }) async {
    writes++;
    throw StateError('Review fixtures never publish cloud backups.');
  }
}

class _FailNextReadStore extends SharedPreferencesStorePlatform {
  _FailNextReadStore(this.delegate);
  final SharedPreferencesStorePlatform delegate;
  bool didFail = false;
  @override
  Future<Map<String, Object>> getAll() async {
    if (!didFail) {
      didFail = true;
      throw StateError('Simulated initialization preference read failure');
    }
    return delegate.getAll();
  }

  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setValue(String type, String key, Object value) =>
      delegate.setValue(type, key, value);
}

class _LifecycleLog with WidgetsBindingObserver {
  final states = <AppLifecycleState>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const before = bool.fromEnvironment('ENTRY_REVIEW_BEFORE');
  const scenario = String.fromEnvironment(
    'ENTRY_REVIEW_SCENARIO',
    defaultValue: 'first',
  );
  const skipMeeting = bool.fromEnvironment('ENTRY_REVIEW_SKIP_MEETING');
  const largeText = bool.fromEnvironment('ENTRY_REVIEW_LARGE_TEXT');
  const reduceMotion = bool.fromEnvironment('ENTRY_REVIEW_REDUCE_MOTION');
  testWidgets('real app entry integration ($scenario, before=$before)', (
    tester,
  ) async {
    // takeException below keeps the run strict, but its later assertion loses
    // the original rendering stack. Preserve that evidence before forwarding
    // to the binding's handler; never suppress the framework failure.
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrintSynchronously(
        'ENTRY_REVIEW_FLUTTER_ERROR ${details.exceptionAsString()}',
      );
      if (details.stack != null) {
        debugPrintSynchronously(details.stack.toString());
      }
      if (previousErrorHandler != null) {
        previousErrorHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    if (!kDebugMode || !Platform.isIOS) {
      throw StateError('Entry review requires an iOS simulator debug test.');
    }
    if (!const [
      'first',
      'returningGuest',
      'returningSignedIn',
      'authErrors',
      'appleNew',
      'googleRestore',
      'credentialsOffline',
      'initFailure',
      'background',
    ].contains(scenario)) {
      throw ArgumentError.value(scenario, 'ENTRY_REVIEW_SCENARIO');
    }
    final returning = const [
      'returningGuest',
      'returningSignedIn',
      'background',
    ].contains(scenario);
    final signedIn = const [
      'returningSignedIn',
      'credentialsOffline',
    ].contains(scenario);
    if (before &&
        !const [
          'first',
          'returningGuest',
          'returningSignedIn',
        ].contains(scenario)) {
      throw ArgumentError('Failure scenarios belong to the AFTER review.');
    }
    if (largeText) {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final lifecycle = _LifecycleLog();
    binding.addObserver(lifecycle);
    addTearDown(() => binding.removeObserver(lifecycle));
    final today = LogicalDate.stringFor(
      DateTime.now(),
      LogicalDate.defaultHour,
    );
    // Established journeys already experienced their first meeting and first
    // habit reveal. These are distinct production stores: first_habit is the
    // legacy memory event, while story_01 belongs to CompanionStoryProgress.
    final existingJourney = <String, Object>{
      PrefsKeys.onboardingDone: true,
      PrefsKeys.onboardingStoryVersion: 1,
      PrefsKeys.onboardingDate: '2026-01-01T12:00:00.000',
      PrefsKeys.lastOpenDate: today,
      PrefsKeys.coinLastLoginDate: DateTime.now()
          .toIso8601String()
          .split('T')
          .first,
      PrefsKeys.coinBalance: 128,
      PrefsKeys.mascotPanelHintSeen: true,
      PrefsKeys.userNickname: '小日',
      // Existing birthday is a preservation sentinel, never an entry field.
      PrefsKeys.userBirthday: '1995-06-15',
      PrefsKeys.storyUnlocked: jsonEncode([
        {'id': 'first_habit', 'date': '2026-01-01T12:00:00.000'},
      ]),
      PrefsKeys.storyUnread: const <String>[],
      PrefsKeys.storyPendingReveal: const <String>[],
      PrefsKeys.companionStoryProgress: jsonEncode(
        CompanionProgressState(
          days: 1,
          creditedDayKeys: {'2026-01-01'},
          completed: {
            'story_01': CompanionCompletion(
              firstCompletedAt: '2026-01-01',
              skipped: false,
              read: true,
            ),
          },
        ).toJson(),
      ),
    };
    final fixture = <String, Object>{
      PrefsKeys.musicMuted: true,
      PrefsKeys.sfxMuted: true,
      PrefsKeys.legacyBgmMuted: true,
      if (returning) ...{
        ...existingJourney,
        PrefsKeys.accountGuestChosen: !signedIn,
        PrefsKeys.habits: jsonEncode([
          {
            'id': 'entry-review-read',
            'name': '閱讀 20 分鐘',
            'createdAt': '2026-01-01',
            'frequency': 'daily',
            'done': false,
          },
        ]),
      },
    };
    final backend = _ReviewAccountBackend(signedIn: signedIn);
    if (scenario == 'googleRestore') {
      SharedPreferences.setMockInitialValues({
        ...existingJourney,
        PrefsKeys.habits: jsonEncode([
          {
            'id': 'entry-review-restored-read',
            'name': '閱讀 20 分鐘',
            'createdAt': '2026-01-01',
            'frequency': 'daily',
            'done': false,
          },
        ]),
      });
      final archive = await BackupArchive.create(
        await SharedPreferences.getInstance(),
      );
      final payload = archive.encode();
      backend.cloud = CloudBackup(
        revision: 4,
        createdAt: archive.createdAt,
        encodedArchive: payload,
        byteLength: utf8.encode(payload).length,
      );
    }
    if (scenario == 'credentialsOffline') {
      backend.readFailure = const AccountFailure('network');
    }
    SharedPreferences.setMockInitialValues(fixture);
    FlutterLocalNotificationsPlatform.instance = _ReviewNotifications();
    final prefs = await SharedPreferences.getInstance();
    _FailNextReadStore? readFailure;
    if (scenario == 'initFailure') {
      readFailure = _FailNextReadStore(SharedPreferencesStorePlatform.instance);
      SharedPreferencesStorePlatform.instance = readFailure;
    }
    final ackDirectory = await Directory.systemTemp.createTemp(
      'entry-integration-review-',
    );
    var captureCount = 0;
    OverlayEntry? fixtureLabel;
    void labelFixture() {
      if (before) return;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      fixtureLabel = OverlayEntry(
        builder: (_) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: const Color(0xDA594C42),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    child: Text(
                      '模擬情境・測試資料',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      navigator.overlay!.insert(fixtureLabel!);
    }

    Finder keyed(String name) => find.byKey(ValueKey(name));

    Future<void> frames([int count = 8]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> waitFor(Finder target) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (target.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Real app control did not appear: $target');
        }
        await frames(2);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await frames();
    }

    Future<void> acknowledge(String marker, String name) async {
      final ack = File('${ackDirectory.path}/$name.ready');
      debugPrint('$marker $name ${ack.path}');
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Host did not acknowledge $marker $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await ack.delete();
      });
    }

    Future<void> capture(String name) async {
      await frames(12);
      expect(binding.lifecycleState, AppLifecycleState.resumed, reason: name);
      expect(binding.sendFramesToEngine, isTrue, reason: name);
      final context = tester.element(find.byType(Scaffold).first);
      final media = MediaQuery.of(context);
      debugPrint(
        'ENTRY_REVIEW_FRAME ${jsonEncode({
          'name': name,
          'size': [media.size.width, media.size.height],
          'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
          'textScale': media.textScaler.scale(1),
          'disableAnimations': media.disableAnimations,
          'locale': Localizations.localeOf(context).toLanguageTag(),
          'realRoot': 'RootRestart > MyApp',
          'processLocalPreferences': true,
          'simulatedIdentity': !before,
          'requestedTextScale': largeText ? 2.0 : 'system',
          'requestedReduceMotion': reduceMotion ? true : 'system',
          'accessibilityInjection': largeText || reduceMotion ? 'Flutter test platformDispatcher values, not OS settings' : 'none',
          'notifications': 'fake; permissions and scheduling not tested',
        })}',
      );
      await acknowledge('ENTRY_CAPTURE', name);
      captureCount++;
    }

    Future<void> tap(Finder target) async {
      await waitFor(target);
      await tester.ensureVisible(target);
      await frames(3);
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await frames(10);
    }

    debugPrint(
      'ENTRY_REVIEW_META ${jsonEncode({'before': before, 'scenario': scenario, 'skipMeeting': skipMeeting, 'fixture': 'integration_test process-local preferences; no native preference writes', 'audio': 'existing real services muted by isolated preferences', 'scope': 'real app.main and production routes'})}',
    );
    // Host ACK ensures video is already recording before real app.main starts.
    // This records Flutter root initialization, not a physical cold-launch time.
    await acknowledge('ENTRY_RECORD_START', 'walkthrough');
    app.main();
    if (!before || scenario == 'returningSignedIn') {
      AccountService.instance.dispose();
      AccountService.instance = AccountService(backend: backend, prefs: prefs);
    }
    if (scenario == 'initFailure') {
      await waitFor(keyed('startup-error'));
      labelFixture();
      await capture('00-init-error');
      expect(readFailure!.didFail, isTrue);
      final l = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      await tap(find.text(l.csRetry));
    }
    await waitFor(find.byType(AppEntryPage));
    labelFixture();
    await capture('01-cover');

    if (returning) {
      await tap(keyed('entry-primary'));
      expect(find.byType(OnboardingPage), findsNothing);
    } else {
      if (before) {
        await tap(keyed('entry-primary'));
        await waitFor(find.byType(AccountBackupPage));
        await capture('02-account-choice');
        await tap(keyed('account-continue'));
      } else if (scenario == 'credentialsOffline') {
        expect(AccountService.instance.user, isNotNull);
        expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
        await tap(keyed('entry-primary'));
        await capture('02-cloud-unknown');
        // Exercise the actual retry control: a fresh successful query can now
        // establish empty cloud. The prior network failure never did so.
        backend.readFailure = null;
        await tap(keyed('entry-restore-retry'));
        await capture('02b-cloud-empty-confirmed');
        await tap(keyed('entry-new-signed'));
      } else {
        await tap(keyed('entry-primary'));
        await capture('02-account-choice');
        if (scenario == 'authErrors') {
          backend.signInFailure = const AccountFailure('cancelled');
          await tap(keyed('entry-apple'));
          expect(prefs.getBool(PrefsKeys.onboardingDone), isNot(true));
          expect(AccountService.instance.user, isNull);
          await capture('02b-login-cancelled');
          backend.signInFailure = const AccountFailure('unknown');
          await tap(keyed('entry-google'));
          await capture('02c-login-failed');
          backend.signInFailure = const AccountFailure('network');
          await tap(keyed('entry-apple'));
          await capture('02d-offline-login');
          expect(prefs.getBool(PrefsKeys.onboardingDone), isNot(true));
          expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
          await tap(keyed('entry-guest'));
        } else if (scenario == 'appleNew' || scenario == 'googleRestore') {
          await tap(
            keyed(scenario == 'appleNew' ? 'entry-apple' : 'entry-google'),
          );
          expect(AccountService.instance.user, isNotNull);
          expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
          if (scenario == 'googleRestore') {
            await capture('02b-cloud-found');
            await tap(keyed('entry-restore-account'));
            await waitFor(find.byType(AccountBackupPage));
            await capture('02b-restore-existing');
            final l = AppLocalizations.of(
              tester.element(find.byType(AccountBackupPage)),
            );
            await tap(find.text(l.accountUseCloud));
            await capture('02c-restore-confirmation');
            await tap(
              find.widgetWithText(FilledButton, l.backupRestoreConfirm),
            );
            await waitFor(find.byType(AppEntryPage));
            labelFixture();
            await capture('02d-restored-cover');
            await tap(keyed('entry-primary'));
          }
        } else {
          await tap(keyed('entry-guest'));
        }
      }
      if (scenario != 'googleRestore') {
        await waitFor(find.byType(OnboardingPage));
        await capture('03-first-meeting');
        if (skipMeeting) {
          await tap(keyed('onboarding-skip'));
        } else {
          // The baseline has six existing scenes. The bounded loop also supports
          // an integrated, shorter first meeting using the same production key.
          for (var scene = 1; scene <= 8; scene++) {
            if (find.byType(OnboardingPage).evaluate().isEmpty) break;
            await tap(keyed('onboarding-primary'));
            if (find.byType(OnboardingPage).evaluate().isNotEmpty) {
              await capture('03-meeting-step-${scene + 1}');
            }
          }
        }
      }
    }
    await waitFor(keyed('main_navigation').hitTestable());
    expect(find.byType(app.MainPage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
    if (returning) {
      expect(prefs.getString(PrefsKeys.userBirthday), '1995-06-15');
      expect(prefs.getString(PrefsKeys.habits), contains('entry-review-read'));
    }
    if (returning || scenario == 'googleRestore') {
      expect(StoryStore.isUnlocked('first_habit'), isTrue);
      expect(StoryStore.pendingReveal.value, isEmpty);
      expect(
        CompanionStoryProgress.instance.state.completed['story_01']?.read,
        isTrue,
      );
    }
    if (scenario == 'returningSignedIn') {
      expect(AccountService.instance.user, isNotNull);
      expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
    }
    await capture('04-real-home');
    await tap(
      find.descendant(of: keyed('main_navigation'), matching: find.text('計時')),
    );
    expect(find.byType(TimerPage), findsOneWidget);
    await capture('05-real-timer');
    await tap(keyed('timer-mode-focus'));
    await tap(keyed('timer-primary-action'));
    expect(
      tester
          .widget<TimerStatusPill>(find.byType(TimerStatusPill))
          .stateKey
          .toString(),
      contains('focus'),
    );
    expect(find.byIcon(Icons.pause_rounded).hitTestable(), findsOneWidget);
    await capture('06-real-timer-running');
    if (scenario == 'background') {
      final mainState = tester.state(find.byType(app.MainPage));
      lifecycle.states.clear();
      await acknowledge('ENTRY_BACKGROUND_REQUEST', 'background');
      await frames(10);
      expect(lifecycle.states, contains(AppLifecycleState.paused));
      expect(lifecycle.states.last, AppLifecycleState.resumed);
      expect(
        identical(tester.state(find.byType(app.MainPage)), mainState),
        isTrue,
      );
      expect(find.byType(AppEntryPage), findsNothing);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byIcon(Icons.pause_rounded).hitTestable(), findsOneWidget);
      debugPrint(
        'ENTRY_REVIEW_LIFECYCLE ${jsonEncode(lifecycle.states.map((e) => e.name).toList())}',
      );
      await capture('06b-resumed-same-timer');
    }
    await tap(keyed('timer-primary-action'));
    expect(find.byIcon(Icons.play_arrow_rounded).hitTestable(), findsOneWidget);
    await capture('07-real-timer-paused');
    expect(backend.writes, 0);
    debugPrint('ENTRY_REVIEW_COMPLETE $captureCount');
    debugPrint('ENTRY_RECORD_STOP');
    if (fixtureLabel?.mounted ?? false) fixtureLabel!.remove();
    await tester.pumpWidget(const SizedBox());
    await frames(20);
    await ackDirectory.delete(recursive: true);
  });
}
