import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/app_entry_page.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/pages/onboarding_preparation_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/app_locale_settings.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/entry_audio.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_service_test.dart' show FakeBackend;
import 'shared_preferences_failure_test_helper.dart';

class _SilentAudio extends EntryAudioBackend {
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

void main() {
  late SharedPreferences prefs;
  late AccountService originalAccount;
  late FakeBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({PrefsKeys.musicMuted: true});
    PreferenceWriteGuard.debugReset();
    prefs = await SharedPreferences.getInstance();
    originalAccount = AccountService.instance;
    backend = FakeBackend();
    AccountService.instance = AccountService(backend: backend, prefs: prefs);
    EntryAudio.debugInstance = EntryAudio(backend: _SilentAudio());
  });
  tearDown(() {
    AccountService.instance.dispose();
    AccountService.instance = originalAccount;
    EntryAudio.debugInstance = null;
    PreferenceWriteGuard.debugReset();
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> mount(
    WidgetTester tester, {
    bool cover = false,
    bool returning = false,
    Size size = const Size(430, 932),
    double scale = 1,
    bool reduce = false,
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppLocaleSettings(prefs: prefs);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 44, bottom: 34),
            disableAnimations: reduce,
            accessibleNavigation: reduce,
          ),
          child: child!,
        ),
        home: cover
            ? AppEntryPage(onboardingDone: returning)
            : OnboardingPreparationPage(localeSettings: settings),
        routes: {
          '/onboarding': (_) =>
              OnboardingPreparationPage(localeSettings: settings),
          '/home': (_) => const Scaffold(body: Text('home-destination')),
        },
      ),
    );
    await frames(tester);
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.tap(key(value));
    await frames(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  for (final provider in ['guest', 'google', 'apple']) {
    testWidgets('$provider first entry reaches preparation before the story', (
      tester,
    ) async {
      await mount(tester, cover: true);
      await tap(tester, 'entry-primary');
      await tap(tester, 'entry-$provider');
      expect(key('preparation-step-0'), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(prefs.getBool(PrefsKeys.onboardingDone), isNull);
      expect(backend.writes, 0);
      await dispose(tester);
    });
  }

  testWidgets('returning journey bypasses preparation', (tester) async {
    await prefs.setBool(PrefsKeys.onboardingDone, true);
    await mount(tester, cover: true, returning: true);
    await tap(tester, 'entry-primary');
    expect(find.text('home-destination'), findsOneWidget);
    expect(find.byType(OnboardingPreparationPage), findsNothing);
    await dispose(tester);
  });

  testWidgets(
    'birthday persists leap date; information precedes story without granting data consent',
    (tester) async {
      await mount(tester);
      await tap(tester, 'preparation-language-traditionalChinese');
      await tap(tester, 'preparation-next');
      expect(prefs.getString(PrefsKeys.appLanguage), 'zh-TW');
      await tap(tester, 'preparation-birthday');
      await tester.enterText(find.byType(TextField), '20000229');
      await tester.pump();
      await tester.tap(find.text('完成'));
      await frames(tester);
      expect(find.text('2000 / 02 / 29'), findsOneWidget);
      await tap(tester, 'preparation-next');
      expect(prefs.getString(PrefsKeys.userBirthday), '2000-02-29');
      await tap(tester, 'preparation-document-data');
      expect(find.textContaining('語言偏好、個人資料'), findsOneWidget);
      Navigator.of(tester.element(find.textContaining('語言偏好、個人資料'))).pop();
      await frames(tester);
      await tap(tester, 'preparation-next');
      expect(find.byType(OnboardingPage), findsOneWidget);
      final receipt = jsonDecode(
        prefs.getString(PrefsKeys.onboardingPreparationReceipt)!,
      );
      expect(receipt.containsKey('use'), false);
      expect(receipt.containsKey('data'), false);
      expect(DateTime.tryParse(receipt['continuedAt'] as String), isNotNull);
      expect(prefs.getBool(PrefsKeys.onboardingDone), isNull);
      await dispose(tester);
    },
  );

  testWidgets(
    'interruption resumes saved step; birthday can stay empty; failed receipt can retry',
    (tester) async {
      await mount(tester);
      await tap(tester, 'preparation-next');
      await dispose(tester);
      await mount(tester);
      expect(key('preparation-step-1'), findsOneWidget);
      await tap(tester, 'preparation-next');
      expect(prefs.containsKey(PrefsKeys.userBirthday), false);
      final store = installFailFirstWriteStore(
        'flutter.${PrefsKeys.onboardingPreparationReceipt}',
      );
      await tap(tester, 'preparation-next');
      expect(store.didFail, true);
      expect(key('preparation-error'), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      await prefs.reload();
      expect(prefs.containsKey(PrefsKeys.onboardingPreparationReceipt), false);
      await tap(tester, 'preparation-next');
      expect(find.byType(OnboardingPage), findsOneWidget);
      await dispose(tester);
      await mount(tester);
      expect(find.byType(OnboardingPage), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'failed language write stays on language and malformed receipt never bypasses it',
    (tester) async {
      await prefs.setString(PrefsKeys.onboardingPreparationReceipt, '{broken');
      await mount(tester);
      final store = installFailFirstWriteStore(
        'flutter.${PrefsKeys.appLanguage}',
      );
      await tap(tester, 'preparation-next');
      expect(store.didFail, true);
      expect(key('preparation-step-0'), findsOneWidget);
      expect(prefs.getInt(PrefsKeys.onboardingPreparationStep), isNull);
      await tap(tester, 'preparation-next');
      expect(key('preparation-step-1'), findsOneWidget);
      await tap(tester, 'preparation-back');
      expect(key('preparation-step-0'), findsOneWidget);
      await dispose(tester);
    },
  );

  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
      testWidgets(
        'all steps remain usable at $size $locale with large text and reduced motion',
        (tester) async {
          await mount(
            tester,
            size: size,
            scale: 1.3,
            reduce: true,
            locale: locale,
          );
          for (var step = 0; step < 3; step++) {
            expect(key('preparation-step-$step'), findsOneWidget);
            expect(key('preparation-next').hitTestable(), findsOneWidget);
            if (step < 2) {
              await tap(tester, 'preparation-next');
            }
          }
          expect(tester.takeException(), isNull);
          await dispose(tester);
        },
      );
    }
  }
}
