import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/account_backup_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/backup_archive.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/prefs_keys.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_backup_ui_test.dart'
    show accountStrings, accountTestApp, revealAccountText, settleAccountUi;
import 'account_service_test.dart' show FakeBackend, backup;

class _PendingBackend extends FakeBackend {
  int reads = 0;
  int uploadAttempts = 0;

  @override
  Future<CloudBackup?> readLatest() {
    reads++;
    return super.readLatest();
  }

  @override
  Future<CloudBackup> writeSnapshot(
    String encodedArchive, {
    required int expectedRevision,
  }) {
    uploadAttempts++;
    return super.writeSnapshot(
      encodedArchive,
      expectedRevision: expectedRevision,
    );
  }
}

class _PendingShareProbe extends SharePlatform {
  final files = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    files.add(params);
    return const ShareResult('', ShareResultStatus.dismissed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountService oldAccount;
  late SharePlatform oldShare;
  late _PendingBackend backend;
  final share = _PendingShareProbe();
  late SharedPreferences prefs;

  setUpAll(() {
    // SharePlus retains its platform delegate once first used.
    oldShare = SharePlatform.instance;
    SharePlatform.instance = share;
  });
  tearDownAll(() => SharePlatform.instance = oldShare);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.onboardingDone: true,
      PrefsKeys.coinBalance: 37,
      PrefsKeys.userNickname: '晴晴',
    });
    prefs = await SharedPreferences.getInstance();
    final archive = await BackupArchive.create(prefs);
    backend = _PendingBackend()
      ..currentUser = const AccountIdentity(
        uid: 'one',
        displayName: 'A family member',
        providers: {AccountProvider.google},
      )
      ..cloud = backup(3, archive.encode());
    oldAccount = AccountService.instance;
    final service = AccountService(backend: backend, prefs: prefs);
    AccountService.instance = service;
    expect(await service.initialize(), isTrue);
    expect(service.needsReconciliation, isTrue);
    // Enter through the actual service failure path with an existing cloud
    // revision. Pending must suppress both ordinary and reconciliation actions.
    backend.writeFailure = const AccountFailure('backup-pending');
    expect(await service.keepLocal(archive.encode()), isFalse);
    expect(service.errorCode, 'backup-pending');
    backend.readFailure = const AccountFailure('backup-pending');
    share.files.clear();
  });

  tearDown(() async {
    AccountService.instance.dispose();
    AccountService.instance = oldAccount;
    await LogicalDayCoordinator.resetForRestore();
  });

  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    for (final atEntry in [true, false]) {
      testWidgets(
        'pending ${locale.languageCode} entry=$atEntry: refresh, export and return work at 320pt',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            accountTestApp(
              Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey('open-pending-account'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => AccountBackupPage(
                            atEntry: atEntry,
                            offerContinue: atEntry,
                          ),
                        ),
                      ),
                      child: const Text('Open account'),
                    ),
                  ),
                ),
              ),
              locale: locale,
              textScale: 1.3,
            ),
          );
          await tester.tap(find.byKey(const ValueKey('open-pending-account')));
          await settleAccountUi(tester);
          final l = accountStrings(tester);
          await revealAccountText(tester, l.accountBackupPending);
          expect(find.text(l.accountBackupPending), findsOneWidget);
          expect(find.text(l.accountError), findsNothing);
          expect(find.text(l.accountNoBackup), findsNothing);
          await revealAccountText(tester, l.accountBackupNow);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, l.accountBackupNow),
                )
                .onPressed,
            isNull,
          );
          expect(find.text(l.accountUseCloud), findsNothing);
          expect(find.text(l.accountKeepLocal), findsNothing);
          expect(backend.uploadAttempts, 1);
          expect(backend.writes, 0);

          await revealAccountText(tester, l.accountRefresh);
          final readsBeforeRefresh = backend.reads;
          await tester.tap(find.text(l.accountRefresh));
          await settleAccountUi(tester);
          expect(backend.reads, readsBeforeRefresh + 1);
          expect(AccountService.instance.errorCode, 'backup-pending');
          expect(backend.uploadAttempts, 1);

          await revealAccountText(tester, l.backupExport);
          await tester.tap(find.text(l.backupExport));
          await settleAccountUi(tester);
          expect(share.files, hasLength(1));
          final exported = BackupArchive.decode(
            await share.files.single.files!.single.readAsString(),
          );
          expect(exported.values[PrefsKeys.coinBalance], 37);
          expect(exported.values[PrefsKeys.userNickname], '晴晴');
          expect(backend.uploadAttempts, 1);
          expect(prefs.containsKey(PrefsKeys.backupRestoreJournal), isFalse);
          expect(AccountService.instance.lastSuccessfulBackupAt, isNull);
          expect(find.text(l.accountBackupDone), findsNothing);

          await tester.tap(find.byType(BackButton));
          await settleAccountUi(tester);
          expect(find.byType(AccountBackupPage), findsNothing);
          await tester.tap(find.byKey(const ValueKey('open-pending-account')));
          await settleAccountUi(tester);
          await revealAccountText(tester, l.accountBackupPending);
          // A new page has no local notice state. This text must come from the
          // service's still-pending result, with no implicit refresh or upload.
          expect(find.text(l.accountBackupPending), findsOneWidget);
          expect(find.text(l.accountError), findsNothing);
          expect(backend.reads, readsBeforeRefresh + 1);
          expect(backend.uploadAttempts, 1);
          await revealAccountText(tester, l.accountBackupNow);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, l.accountBackupNow),
                )
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
