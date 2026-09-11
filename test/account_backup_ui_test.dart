import 'dart:convert';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/account_backup_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/app_entry_intent.dart';
import 'package:habit_app/utils/app_restart.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/prefs_keys.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_service_test.dart' show FakeBackend, backup;

class _ShareProbe extends SharePlatform {
  final calls = <ShareParams>[];
  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return const ShareResult('', ShareResultStatus.dismissed);
  }
}

class _FileProbe extends FileSelectorPlatform {
  XFile? result;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => result;
}

Widget accountTestApp(
  Widget home, {
  Locale locale = const Locale('zh', 'TW'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
  routes: {
    '/home': (_) => const Scaffold(body: Text('destination-home')),
    '/onboarding': (_) => const Scaffold(body: Text('destination-onboarding')),
  },
);

Future<void> settleAccountUi(WidgetTester tester) async {
  await tester.pump();
  // A pending confirmation legitimately leaves the page's busy spinner active.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

AppLocalizations accountStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AccountBackupPage)));

Future<void> revealAccountText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('account-backup-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const AccountBackupPage();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeBackend backend;
  late AccountService oldAccount;
  final share = _ShareProbe();
  final files = _FileProbe();
  late SharePlatform oldShare;
  late FileSelectorPlatform oldFiles;

  setUpAll(() {
    oldShare = SharePlatform.instance;
    SharePlatform.instance = share;
    oldFiles = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = files;
  });
  tearDownAll(() {
    SharePlatform.instance = oldShare;
    FileSelectorPlatform.instance = oldFiles;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.coinBalance: 37,
      PrefsKeys.onboardingDone: true,
    });
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    oldAccount = AccountService.instance;
    AccountService.instance = AccountService(backend: backend, prefs: prefs);
    await AccountService.instance.initialize();
    share.calls.clear();
    files.result = null;
    AppEntryIntent.openBackup = false;
    AppEntryIntent.restoringUid = null;
    AppEntryIntent.restoringRevision = null;
  });
  tearDown(() {
    AccountService.instance.dispose();
    AccountService.instance = oldAccount;
    AppEntryIntent.openBackup = false;
    AppEntryIntent.restoringUid = null;
    AppEntryIntent.restoringRevision = null;
  });

  testWidgets(
    'unconfigured sign-in buttons are disabled while guest continue remains available',
    (tester) async {
      AccountService.instance.dispose();
      AccountService.instance = AccountService(
        backend: const UnavailableAccountBackend(),
        prefs: prefs,
      );
      await AccountService.instance.initialize();
      await tester.pumpWidget(
        accountTestApp(
          const AccountBackupPage(atEntry: true, offerContinue: true),
        ),
      );
      await settleAccountUi(tester);
      for (final provider in ['apple', 'google']) {
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(ValueKey('account-$provider')))
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('account-continue')))
            .onPressed,
        isNotNull,
      );
      expect(
        find.text(accountStrings(tester).accountUnavailable),
        findsOneWidget,
      );
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'settings exports an actual archive; dismissing share never claims cloud backup',
    (tester) async {
      await tester.pumpWidget(accountTestApp(const AccountBackupPage()));
      await settleAccountUi(tester);
      final l = accountStrings(tester);
      await revealAccountText(tester, l.backupExport);
      await tester.tap(find.text(l.backupExport));
      await settleAccountUi(tester);
      expect(share.calls, hasLength(1));
      final exported = BackupArchive.decode(
        await share.calls.single.files!.single.readAsString(),
      );
      expect(exported.values[PrefsKeys.coinBalance], 37);
      expect(share.calls.single.sharePositionOrigin, isNotNull);
      expect(backend.writes, 0);
      expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
      expect(find.text(l.accountBackupDone), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'settings restore action rebuilds through the entrance and preserves local data',
    (tester) async {
      var mounts = 0;
      await tester.pumpWidget(
        RootRestart(
          child: accountTestApp(_MountProbe(onMount: () => mounts++)),
        ),
      );
      await settleAccountUi(tester);
      final l = accountStrings(tester);
      await revealAccountText(tester, l.backupRestoreEntry);
      await tester.tap(find.text(l.backupRestoreEntry));
      await settleAccountUi(tester);
      expect(mounts, 2);
      expect(AppEntryIntent.openBackup, isTrue);
      expect(prefs.getInt(PrefsKeys.coinBalance), 37);
      expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'provider failure is visible and cancellation stays quiet without changing local data',
    (tester) async {
      backend.signInFailure = const AccountFailure('network');
      await tester.pumpWidget(
        accountTestApp(
          const AccountBackupPage(atEntry: true, offerContinue: true),
        ),
      );
      await settleAccountUi(tester);
      await tester.tap(find.byKey(const ValueKey('account-google')));
      await settleAccountUi(tester);
      expect(find.byKey(const ValueKey('account-notice')), findsOneWidget);
      expect(find.text(accountStrings(tester).accountError), findsOneWidget);
      expect(prefs.getInt(PrefsKeys.coinBalance), 37);
      backend.signInFailure = const AccountFailure('cancelled');
      await tester.tap(find.byKey(const ValueKey('account-google')));
      await settleAccountUi(tester);
      expect(find.byKey(const ValueKey('account-notice')), findsNothing);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reading cloud and cancelling both reconciliation dialogs never restores or uploads',
    (tester) async {
      final archive = await BackupArchive.create(prefs);
      await prefs.setInt(PrefsKeys.coinBalance, 99);
      backend.currentUser = const AccountIdentity(
        uid: 'one',
        displayName: 'Cloud user',
      );
      backend.cloud = backup(4, archive.encode());
      await AccountService.instance.initialize(force: true);
      expect(AccountService.instance.needsReconciliation, isTrue);
      await tester.pumpWidget(
        accountTestApp(const AccountBackupPage(atEntry: true)),
      );
      await settleAccountUi(tester);
      final l = accountStrings(tester);
      await tester.pump(const Duration(minutes: 3));
      expect(backend.writes, 0);
      expect(prefs.getInt(PrefsKeys.coinBalance), 99);
      await revealAccountText(tester, l.accountUseCloud);
      await tester.tap(find.text(l.accountUseCloud));
      await settleAccountUi(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
      await tester.tap(find.text(l.commonCancel));
      await settleAccountUi(tester);
      await revealAccountText(tester, l.accountKeepLocal);
      await tester.tap(find.text(l.accountKeepLocal));
      await settleAccountUi(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l.commonCancel));
      await settleAccountUi(tester);
      expect(prefs.getInt(PrefsKeys.coinBalance), 99);
      expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
      expect(backend.writes, 0);
      expect(AccountService.instance.needsReconciliation, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'invalid imported file shows an error without staging or mutating user data',
    (tester) async {
      files.result = XFile.fromData(
        Uint8List.fromList(utf8.encode('{"version":99}')),
        name: 'invalid.json',
      );
      await tester.pumpWidget(
        accountTestApp(const AccountBackupPage(atEntry: true)),
      );
      await settleAccountUi(tester);
      final l = accountStrings(tester);
      await revealAccountText(tester, l.backupImport);
      await tester.tap(find.text(l.backupImport));
      await settleAccountUi(tester);
      expect(find.text(l.backupInvalid), findsOneWidget);
      expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
      expect(prefs.getInt(PrefsKeys.coinBalance), 37);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    testWidgets(
      'account and restore confirmation fit 320x568 at 1.3 text scale in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final archive = await BackupArchive.create(prefs);
        backend.currentUser = const AccountIdentity(
          uid: 'one',
          displayName: 'A long family companion account name',
          email: 'family-companion@example.com',
        );
        backend.cloud = backup(2, archive.encode());
        await AccountService.instance.initialize(force: true);
        await tester.pumpWidget(
          accountTestApp(
            const AccountBackupPage(atEntry: true),
            locale: locale,
            textScale: 1.3,
          ),
        );
        await settleAccountUi(tester);
        final l = accountStrings(tester);
        await revealAccountText(tester, l.accountUseCloud);
        await tester.tap(find.text(l.accountUseCloud));
        await settleAccountUi(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l.commonCancel).hitTestable(), findsOneWidget);
        expect(find.text(l.backupRestoreConfirm).hitTestable(), findsOneWidget);
        await tester.tap(find.text(l.commonCancel));
        await settleAccountUi(tester);
        await revealAccountText(tester, l.backupExport);
        expect(find.text(l.backupExport).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
