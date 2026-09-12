import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/app_locale_settings.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/app_language_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';
import 'shared_preferences_failure_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferenceWriteGuard.debugReset();
  });

  test(
    'automatic uses only finished locales and loads without writing',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppLocaleSettings(prefs: prefs);
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.locale, isNull);
      expect(AppLocaleSettings.supportedLocales, [const Locale('zh', 'TW')]);
      expect(prefs.getKeys(), isEmpty);
      expect(
        basicLocaleListResolution([
          const Locale('ja'),
          const Locale('en'),
        ], AppLocaleSettings.supportedLocales),
        const Locale('zh', 'TW'),
      );
    },
  );

  test('manual and automatic selections survive a fresh service', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppLocaleSettings(prefs: prefs);
    final reloaded = AppLocaleSettings(prefs: prefs);
    addTearDown(settings.dispose);
    addTearDown(reloaded.dispose);
    await settings.select(AppLanguagePreference.traditionalChinese);
    await reloaded.load();
    expect(reloaded.preference, AppLanguagePreference.traditionalChinese);
    expect(reloaded.locale, const Locale('zh', 'TW'));
    await settings.select(AppLanguagePreference.automatic);
    await reloaded.load();
    expect(reloaded.preference, AppLanguagePreference.automatic);
    expect(reloaded.locale, isNull);
  });

  test(
    'unsupported stored preference is preserved but never activated',
    () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.appLanguage: 'ja',
        PrefsKeys.userBirthday: '1990-08-17',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppLocaleSettings(prefs: prefs);
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.preference, AppLanguagePreference.automatic);
      expect(prefs.getString(PrefsKeys.appLanguage), 'ja');
      expect(prefs.getString(PrefsKeys.userBirthday), '1990-08-17');
    },
  );

  test('failed native save retains locale, then retry can persist', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppLocaleSettings(prefs: prefs);
    addTearDown(settings.dispose);
    var notifications = 0;
    settings.addListener(() => notifications++);
    installFailFirstWriteStore('flutter.${PrefsKeys.appLanguage}');
    await expectLater(
      settings.select(AppLanguagePreference.traditionalChinese),
      throwsStateError,
    );
    expect(settings.preference, AppLanguagePreference.automatic);
    expect(prefs.containsKey(PrefsKeys.appLanguage), isFalse);
    expect(notifications, 0);
    await settings.select(AppLanguagePreference.traditionalChinese);
    await prefs.reload();
    expect(prefs.getString(PrefsKeys.appLanguage), 'zh-TW');
    expect(notifications, 1);
  });

  testWidgets('shared sheet offers no selectable unfinished language', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppLocaleSettings(prefs: prefs);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(body: AppLanguageButton(settings: settings)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('app-language')));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('自動選擇'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('英文與日文尚未完成，暫未開放選擇。'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('app-language-traditionalChinese')),
    );
    await tester.pumpAndSettle();
    expect(settings.preference, AppLanguagePreference.traditionalChinese);
    expect(find.byType(ListTile), findsNothing);
  });
}
