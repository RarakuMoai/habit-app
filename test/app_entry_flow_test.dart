import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/account_backup_page.dart';
import 'package:habit_app/pages/app_entry_page.dart';
import 'package:habit_app/pages/settings_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/app_entry_intent.dart';
import 'package:habit_app/utils/entry_audio.dart';
import 'package:habit_app/utils/parent_pin.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_backup_ui_test.dart' show accountTestApp;
import 'account_service_test.dart' show FakeBackend;
import 'shared_preferences_failure_test_helper.dart';

class _EntryAudio extends EntryAudioBackend {
  @override
  String? loadedAsset;
  @override
  String get selectedAsset => 'sounds/chosen.m4a';
  @override
  Future<void> prepare() async {}
  @override
  Future<void> setEntryActive(bool active) async {}
  @override
  Future<void> play(String asset, {required bool deferFade}) async {
    loadedAsset = asset;
  }
}

// The live cover never settles. Advance complete route/sheet transitions in
// bounded frames, then assert the actual destination and data in each test.
Future<void> settleEntryUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountService oldAccount;
  late FakeBackend backend;
  late SharedPreferences prefs;
  late _EntryAudio audio;
  setUp(() async {
    PreferenceWriteGuard.debugReset();
    SharedPreferences.setMockInitialValues({PrefsKeys.musicMuted: true});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    oldAccount = AccountService.instance;
    AccountService.instance = AccountService(backend: backend, prefs: prefs);
    audio = _EntryAudio();
    EntryAudio.debugInstance = EntryAudio(backend: audio);
    AppEntryIntent.openBackup = false;
    AppEntryIntent.restoringRevision = null;
    AppEntryIntent.restoringUid = null;
  });
  tearDown(() {
    PreferenceWriteGuard.debugReset();
    AccountService.instance.dispose();
    AccountService.instance = oldAccount;
    EntryAudio.debugInstance = null;
    AppEntryIntent.openBackup = false;
    AppEntryIntent.restoringRevision = null;
    AppEntryIntent.restoringUid = null;
  });

  testWidgets(
    'first guest enters onboarding only after deliberately continuing',
    (tester) async {
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: false)),
      );
      await settleEntryUi(tester);
      expect(find.byKey(const ValueKey('app-entry')), findsOneWidget);
      expect(find.text('destination-onboarding'), findsNothing);
      expect(audio.loadedAsset, EntryAudio.coverAsset);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-guest')));
      await tester.tap(find.byKey(const ValueKey('entry-guest')));
      await settleEntryUi(tester);
      expect(find.text('destination-onboarding'), findsOneWidget);
      expect(prefs.getBool(PrefsKeys.accountGuestChosen), isTrue);
      expect(prefs.getBool(PrefsKeys.onboardingDone), isNull);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completed user returns to home and selected music without replaying onboarding',
    (tester) async {
      await prefs.setBool(PrefsKeys.onboardingDone, true);
      await prefs.setInt(PrefsKeys.coinBalance, 123);
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.text('destination-home'), findsOneWidget);
      expect(find.text('destination-onboarding'), findsNothing);
      expect(audio.loadedAsset, 'sounds/chosen.m4a');
      expect(prefs.getInt(PrefsKeys.coinBalance), 123);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'start exposes provider choices and unconfigured Guest reaches onboarding',
    (tester) async {
      AccountService.instance.dispose();
      AccountService.instance = AccountService(
        backend: const UnavailableAccountBackend(),
        prefs: prefs,
      );
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: false)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.byType(AccountBackupPage), findsNothing);
      for (final provider in ['google', 'apple']) {
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(ValueKey('entry-$provider')))
              .onPressed,
          isNull,
        );
      }
      await tester.ensureVisible(find.byKey(const ValueKey('entry-guest')));
      await tester.tap(find.byKey(const ValueKey('entry-guest')));
      await settleEntryUi(tester);
      expect(find.text('destination-onboarding'), findsOneWidget);
      expect(prefs.getBool(PrefsKeys.accountGuestChosen), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'guest preference write failure stays on entry and retry can continue',
    (tester) async {
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: false)),
      );
      await settleEntryUi(tester);
      installFailFirstWriteStore('flutter.${PrefsKeys.accountGuestChosen}');
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-guest')));
      await tester.tap(find.byKey(const ValueKey('entry-guest')));
      await settleEntryUi(tester);
      expect(find.byKey(const ValueKey('app-entry')), findsOneWidget);
      expect(find.text('destination-onboarding'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-guest')));
      await tester.tap(find.byKey(const ValueKey('entry-guest')));
      await settleEntryUi(tester);
      expect(find.text('destination-onboarding'), findsOneWidget);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'restored family without PIN opens protection settings and cancelling cannot enter home',
    (tester) async {
      await prefs.setBool(PrefsKeys.familyRestoreNeedsPin, true);
      await prefs.setBool(PrefsKeys.onboardingDone, true);
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('destination-home'), findsNothing);
      expect(prefs.getBool(PrefsKeys.familyRestoreNeedsPin), isTrue);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop(); // close the automatically opened PIN settings sheet
      await settleEntryUi(tester);
      if (find.byType(SettingsPage).evaluate().isNotEmpty) {
        navigator.pop();
        await settleEntryUi(tester);
      }
      expect(find.byKey(const ValueKey('app-entry')), findsOneWidget);
      expect(find.text('destination-home'), findsNothing);
      expect(prefs.getBool(PrefsKeys.familyRestoreNeedsPin), isTrue);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed PIN setup keeps the family gate through returning and restarting entry',
    (tester) async {
      await prefs.setBool(PrefsKeys.familyRestoreNeedsPin, true);
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      await tester.tap(find.text('設定密碼'));
      await settleEntryUi(tester);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.tap(find.text('確認'));
      await settleEntryUi(tester);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      final store = installFailFirstWriteStore(
        'flutter.${PrefsKeys.parentPinHash}',
      );
      await tester.tap(find.text('確認'));
      await settleEntryUi(tester);

      expect(store.didFail, isTrue);
      expect(find.text('密碼已設定'), findsNothing);
      expect(find.text('設定救援問題'), findsNothing);
      expect(find.text('設定密碼'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await settleEntryUi(tester);
      navigator.pop();
      await settleEntryUi(tester);
      expect(find.byKey(const ValueKey('app-entry')), findsOneWidget);
      expect(find.text('destination-home'), findsNothing);
      await prefs.reload();
      expect(await ParentPin.hasPin(prefs), isFalse);
      expect(prefs.getBool(PrefsKeys.familyRestoreNeedsPin), isTrue);

      await tester.pumpWidget(const SizedBox());
      await settleEntryUi(tester);
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('設定密碼'), findsOneWidget);
      expect(find.text('destination-home'), findsNothing);
      expect(prefs.getBool(PrefsKeys.familyRestoreNeedsPin), isTrue);
      await tester.pumpWidget(const SizedBox());
      await settleEntryUi(tester);
    },
  );

  testWidgets(
    'optimistic PIN cache alone cannot release the restored family gate',
    (tester) async {
      await prefs.setBool(PrefsKeys.familyRestoreNeedsPin, true);
      installFailFirstWriteStore('flutter.${PrefsKeys.parentPinHash}');
      expect(
        await prefs.setString(PrefsKeys.parentPinHash, 'optimistic-only'),
        isFalse,
      );
      expect(prefs.getString(PrefsKeys.parentPinHash), 'optimistic-only');
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('destination-home'), findsNothing);
      expect(prefs.getBool(PrefsKeys.familyRestoreNeedsPin), isTrue);
      await prefs.reload();
      expect(await ParentPin.hasPin(prefs), isFalse);
      await tester.pumpWidget(const SizedBox());
      await settleEntryUi(tester);
    },
  );

  testWidgets(
    'restored family with a newly configured PIN clears gate then enters home',
    (tester) async {
      await prefs.setBool(PrefsKeys.familyRestoreNeedsPin, true);
      await ParentPin.save(prefs, '1234');
      await tester.pumpWidget(
        accountTestApp(const AppEntryPage(onboardingDone: true)),
      );
      await settleEntryUi(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('entry-primary')));
      await tester.tap(find.byKey(const ValueKey('entry-primary')));
      await settleEntryUi(tester);
      expect(find.text('destination-home'), findsOneWidget);
      expect(prefs.containsKey(PrefsKeys.familyRestoreNeedsPin), isFalse);
      expect(await ParentPin.verify(prefs, '1234'), isTrue);
      expect(backend.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    for (final completed in [false, true]) {
      testWidgets(
        'entry actions remain reachable at 320x568 with text 1.3 ($locale, completed=$completed)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            accountTestApp(
              AppEntryPage(onboardingDone: completed),
              locale: locale,
              textScale: 1.3,
            ),
          );
          await settleEntryUi(tester);
          await tester.ensureVisible(
            find.byKey(const ValueKey('entry-primary')),
          );
          await settleEntryUi(tester);
          expect(
            find.byKey(const ValueKey('entry-primary')).hitTestable(),
            findsOneWidget,
          );
          if (!completed) {
            await tester.tap(find.byKey(const ValueKey('entry-primary')));
            await settleEntryUi(tester);
          }
          if (completed) {
            await tester.tap(find.byKey(const ValueKey('entry-settings')));
            await settleEntryUi(tester);
          }
          final secondary = find.byKey(
            ValueKey(completed ? 'entry-account' : 'entry-guest'),
          );
          await tester.ensureVisible(secondary);
          await settleEntryUi(tester);
          expect(secondary.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(backend.writes, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
