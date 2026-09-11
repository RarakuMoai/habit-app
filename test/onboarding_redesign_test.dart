import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, String key) async {
  expect(_key(key).hitTestable(), findsOneWidget);
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _field(WidgetTester tester, String key, String value) async {
  final field = _key(key);
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await _settle(tester);
  expect(field.hitTestable(), findsOneWidget);
  await tester.enterText(field, value);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Nunito', 'assets/fonts/Nunito-Regular.ttf'),
      ('Baloo 2', 'assets/fonts/Baloo2-Bold.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
      testWidgets(
        'six scenes reachable at $size ${locale.languageCode}, text 2x, keyboard 300',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            PrefsKeys.musicMuted: true,
            PrefsKeys.sfxMuted: true,
          });
          AudioSettingsService.musicMuted.value = true;
          AudioSettingsService.sfxMuted.value = true;
          final reduced = ValueNotifier(true);
          final keyboard = ValueNotifier(0.0);
          addTearDown(reduced.dispose);
          addTearDown(keyboard.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => ListenableBuilder(
                listenable: Listenable.merge([reduced, keyboard]),
                builder: (context, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: reduced.value,
                    padding: EdgeInsets.only(
                      top: size.height > 800 ? 59 : 20,
                      bottom: keyboard.value > 0
                          ? 0
                          : size.height > 800
                          ? 34
                          : 0,
                    ),
                    viewInsets: EdgeInsets.only(bottom: keyboard.value),
                  ),
                  child: child!,
                ),
              ),
              home: const OnboardingPage(preview: true),
            ),
          );
          await _settle(tester);
          expect(_key('onboarding-scene-arrival'), findsOneWidget);
          expect(find.byType(MascotScene), findsNothing);
          for (var i = 0; i < 3; i++) {
            await _press(tester, 'onboarding-primary');
          }
          keyboard.value = 300;
          await _settle(tester);
          expect(_key('onboarding-room'), findsNothing);
          await _field(tester, 'onboarding-mascot-name', 'CloudSunbeam');
          expect(
            tester.getSize(_key('onboarding-primary')).height,
            greaterThanOrEqualTo(48),
          );
          expect(_key('onboarding-primary').hitTestable(), findsOneWidget);
          await _press(tester, 'onboarding-primary');
          await _field(tester, 'onboarding-nickname', '小晴');
          reduced.value = false;
          await _settle(tester);
          expect(
            tester
                .widget<TextField>(_key('onboarding-nickname'))
                .controller!
                .text,
            '小晴',
          );
          await _press(tester, 'onboarding-back');
          expect(
            tester
                .widget<TextField>(_key('onboarding-mascot-name'))
                .controller!
                .text,
            'CloudSunbeam',
          );
          reduced.value = true;
          keyboard.value = 0;
          await _settle(tester);
          await _press(tester, 'onboarding-primary');
          await _press(tester, 'onboarding-primary');
          expect(_key('onboarding-scene-together'), findsOneWidget);
          for (final mascot in tester.widgetList<MascotScene>(
            find.byType(MascotScene),
          )) {
            expect(mascot.reduceMotion, isTrue);
          }
          expect(_key('onboarding-primary').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.containsKey(PrefsKeys.mascotName), isFalse);
          expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
          expect(prefs.containsKey(PrefsKeys.onboardingDone), isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
        },
      );
    }
  }
}
