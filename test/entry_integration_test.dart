import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/app_entry_page.dart';
import 'package:habit_app/utils/account_service.dart';
import 'package:habit_app/utils/app_entry_intent.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/audio_asset_cache.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/entry_audio.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_service_test.dart' show FakeBackend;
import 'shared_preferences_failure_test_helper.dart';

class _EntryAudioBackend extends EntryAudioBackend {
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

Finder _key(String value) => find.byKey(ValueKey(value));

Map<String, Object?> _snapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Widget _entryApp({
  bool returning = false,
  double textScale = 1,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: buildAppTheme(),
  locale: const Locale('zh', 'TW'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: AppEntryPage(onboardingDone: returning),
  routes: {
    '/onboarding': (_) => const Scaffold(body: Text('route-onboarding')),
    '/home': (_) => const Scaffold(body: Text('route-home')),
  },
);

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await _frames(tester, 2);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await _frames(tester);
}

Future<void> _mount(WidgetTester tester, Widget widget) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
  await tester.pumpWidget(widget);
  await _frames(tester);
}

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeBackend backend;
  late AccountService previousAccount;
  setUp(() async {
    PreferenceWriteGuard.debugReset();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.musicMuted: true,
      PrefsKeys.sfxMuted: true,
      PrefsKeys.legacyBgmMuted: true,
      PrefsKeys.audioAssetCacheVersion: AudioAssetCache.currentVersion,
    });
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    previousAccount = AccountService.instance;
    AccountService.instance = AccountService(backend: backend, prefs: prefs);
    EntryAudio.debugInstance = EntryAudio(backend: _EntryAudioBackend());
    AudioSettingsService.musicMuted.value = true;
    AudioSettingsService.sfxMuted.value = true;
    AppEntryIntent.openBackup = false;
    AppEntryIntent.restoringRevision = null;
    AppEntryIntent.restoringUid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() async {
    AccountService.instance.dispose();
    AccountService.instance = previousAccount;
    EntryAudio.debugInstance = null;
    PreferenceWriteGuard.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('only explicit Guest selection writes the new guest marker', (
    tester,
  ) async {
    _screen(tester, const Size(375, 667));
    final before = _snapshot(prefs);
    await _mount(tester, _entryApp());
    expect(_snapshot(prefs), before);
    await _press(tester, 'entry-primary');
    expect(_key('entry-apple'), findsOneWidget);
    expect(_key('entry-google'), findsOneWidget);
    expect(_key('entry-guest'), findsOneWidget);
    expect(_snapshot(prefs), before);
    await _press(tester, 'entry-guest');
    expect(find.text('route-onboarding'), findsOneWidget);
    expect(_snapshot(prefs), {...before, PrefsKeys.accountGuestChosen: true});
    expect(prefs.containsKey(PrefsKeys.onboardingDone), isFalse);
    expect(backend.writes, 0);
  });

  for (final signedIn in [false, true]) {
    testWidgets('returning signedIn=$signedIn preserves the existing save', (
      tester,
    ) async {
      _screen(tester, const Size(375, 667));
      await prefs.setBool(PrefsKeys.onboardingDone, true);
      await prefs.setBool(PrefsKeys.accountGuestChosen, !signedIn);
      await prefs.setString(PrefsKeys.userBirthday, '1995-06-15');
      await prefs.setBool(PrefsKeys.waterEnabled, false);
      await prefs.setBool(PrefsKeys.timerEnabled, true);
      await prefs.setBool(PrefsKeys.familyEnabled, false);
      await prefs.setString(PrefsKeys.wardrobeSelectedOutfit, 'original');
      if (signedIn) {
        backend.currentUser = const AccountIdentity(uid: 'returning');
      }
      final before = _snapshot(prefs);
      await _mount(tester, _entryApp(returning: true));
      expect(find.text('繼續一起生活'), findsOneWidget);
      await _press(tester, 'entry-primary');
      expect(find.text('route-home'), findsOneWidget);
      expect(find.text('route-onboarding'), findsNothing);
      expect(_snapshot(prefs), before);
      expect(backend.writes, 0);
    });
  }

  testWidgets('credentials plus failed read shows unknown rather than empty', (
    tester,
  ) async {
    _screen(tester, const Size(375, 667));
    backend.currentUser = const AccountIdentity(uid: 'existing-cloud-user');
    backend.readFailure = const AccountFailure('offline');
    final before = _snapshot(prefs);
    await _mount(tester, _entryApp());
    await _press(tester, 'entry-primary');
    expect(find.text('找回原本的日常'), findsOneWidget);
    expect(_key('entry-restore-retry'), findsOneWidget);
    expect(_key('entry-new-signed'), findsNothing);
    expect(find.text('已確認此帳號目前沒有雲端備份。你可以開始新的旅程。'), findsNothing);
    await _press(tester, 'entry-restore-retry');
    expect(_key('entry-new-signed'), findsNothing);
    expect(_snapshot(prefs), before);
    expect(backend.writes, 0);
  });

  testWidgets('cancelled provider leaves entry and local state unchanged', (
    tester,
  ) async {
    _screen(tester, const Size(375, 667));
    backend.signInFailure = const AccountFailure('cancelled');
    final before = _snapshot(prefs);
    await _mount(tester, _entryApp());
    await _press(tester, 'entry-primary');
    await _press(tester, 'entry-apple');
    expect(find.text('從這裡，開始我們的日常'), findsOneWidget);
    expect(_key('app-entry'), findsOneWidget);
    expect(find.text('route-onboarding'), findsNothing);
    expect(AccountService.instance.user, isNull);
    expect(_snapshot(prefs), before);
    await tester.tap(find.byTooltip('關閉'));
    await _frames(tester);
    expect(_key('entry-primary').hitTestable(), findsOneWidget);
    expect(backend.writes, 0);
  });

  for (final size in [const Size(375, 667), const Size(320, 568)]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets('save error stays reachable at $size and text $scale', (
        tester,
      ) async {
        _screen(tester, size);
        await _mount(tester, _entryApp(textScale: scale));
        await _press(tester, 'entry-primary');
        installFailFirstWriteStore('flutter.${PrefsKeys.accountGuestChosen}');
        await _press(tester, 'entry-guest');
        final error = find.text('這一段還沒存好，請再試一次。');
        await tester.ensureVisible(error);
        await _frames(tester, 2);
        expect(error.hitTestable(), findsOneWidget);
        expect(prefs.containsKey(PrefsKeys.accountGuestChosen), isFalse);
        expect(find.text('route-onboarding'), findsNothing);
        await _press(tester, 'entry-primary');
        await _press(tester, 'entry-guest');
        expect(find.text('route-onboarding'), findsOneWidget);
        expect(prefs.getBool(PrefsKeys.accountGuestChosen), isTrue);
      });
    }
  }

  testWidgets('Reduce Motion preserves action feedback without press scaling', (
    tester,
  ) async {
    _screen(tester, const Size(375, 667));
    await _mount(tester, _entryApp(returning: true, reduceMotion: true));
    final action = _key('entry-primary');
    final press = find.descendant(
      of: action,
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(press).scale, 1);
    final gesture = await tester.startGesture(tester.getCenter(action));
    await _frames(tester, 2);
    expect(tester.widget<AnimatedScale>(press).scale, 1);
    expect(tester.widget<AnimatedScale>(press).duration, Duration.zero);
    await gesture.cancel();
    await _frames(tester, 2);
    await _press(tester, 'entry-primary');
    expect(find.text('route-home'), findsOneWidget);
  });
}
