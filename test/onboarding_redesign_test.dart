import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/units.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _primary = ValueKey('onboarding-primary');
const _secondary = ValueKey('onboarding-secondary');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final (family, asset) in [
      ('Nunito', 'assets/fonts/Nunito-Regular.ttf'),
      ('Baloo 2', 'assets/fonts/Baloo2-Bold.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder.hitTestable());
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String id, String value) async {
    final field = find.byKey(ValueKey('onboarding-$id'));
    await tester.ensureVisible(field);
    await settle(tester);
    await tester.enterText(field, value);
    await settle(tester);
  }

  Future<void> pumpFlow(
    WidgetTester tester, {
    required Size size,
    required Locale locale,
    required ValueNotifier<bool> reduced,
    required ValueNotifier<double> keyboard,
    UnitSystem unit = UnitSystem.metric,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.unitSystem: unit.name,
      PrefsKeys.sfxMuted: true,
      PrefsKeys.musicMuted: true,
    });
    AudioSettingsService.sfxMuted.value = true;
    AudioSettingsService.musicMuted.value = true;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => ListenableBuilder(
          listenable: Listenable.merge([reduced, keyboard]),
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              disableAnimations: reduced.value,
              padding: EdgeInsets.only(
                top: size.height > 800 ? 59 : 20,
                bottom: keyboard.value > 0 ? 0 : (size.height > 800 ? 34 : 0),
              ),
              viewInsets: EdgeInsets.only(bottom: keyboard.value),
            ),
            child: child!,
          ),
        ),
        home: const OnboardingPage(),
        routes: {'/home': (_) => const Scaffold(body: Text('setup-complete'))},
      ),
    );
    await settle(tester);
  }

  for (final size in [const Size(320, 667), const Size(430, 932)]) {
    for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
      testWidgets(
        '9 steps, keyboard and choices: $size ${locale.languageCode}, text 1.3',
        (tester) async {
          final reduced = ValueNotifier(true);
          final keyboard = ValueNotifier(0.0);
          addTearDown(reduced.dispose);
          addTearDown(keyboard.dispose);
          await pumpFlow(
            tester,
            size: size,
            locale: locale,
            reduced: reduced,
            keyboard: keyboard,
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(OnboardingPage)),
          );
          final primary = find.byKey(_primary);
          void step(int number) =>
              expect(find.text('$number / 9'), findsOneWidget);
          step(1);
          expect(find.text('嗯...你來了。\n我平常有點愛睡。\n你想開始時，我會陪你。'), findsOneWidget);
          await press(tester, primary);
          step(2);
          keyboard.value = 300;
          await settle(tester);
          await enter(tester, 'mascot-name', '麻糬');
          expect(
            tester.getRect(primary).bottom,
            lessThanOrEqualTo(size.height - 300),
          );
          await press(tester, primary);
          keyboard.value = 0;
          await settle(tester);
          step(3);
          expect(tester.widget<FilledButton>(primary).onPressed, isNull);
          keyboard.value = 300;
          await settle(tester);
          await enter(tester, 'nickname', '小日');
          await press(tester, primary);
          keyboard.value = 0;
          await settle(tester);
          step(4);
          await press(tester, primary);
          step(5);
          await press(tester, primary);
          step(6);
          await press(tester, primary);
          step(7);
          for (final habit in ['刷牙', '閱讀', '運動', '冥想']) {
            final card = find.byKey(ValueKey('onboarding-habit-$habit'));
            await tester.ensureVisible(card);
            await settle(tester);
            await press(tester, card);
          }
          final weekly = find.byKey(const ValueKey('weekly-stepper-閱讀'));
          await tester.ensureVisible(weekly);
          await settle(tester);
          await press(
            tester,
            find.descendant(
              of: weekly,
              matching: find.byIcon(Icons.add_rounded),
            ),
          );
          // Going back and forward keeps all draft choices and frequency values.
          await press(tester, find.byKey(const ValueKey('onboarding-back')));
          await press(tester, primary);
          expect(find.text(l10n.obTimesPerWeek(4)), findsOneWidget);
          await press(tester, primary);
          step(8);
          await press(tester, primary);
          step(8); // Validation must not advance an empty body profile.
          final gender = find.text(l10n.genderFemale);
          await tester.ensureVisible(gender);
          await settle(tester);
          await press(tester, gender);
          keyboard.value = 300;
          await settle(tester);
          await enter(tester, 'height', '168');
          await enter(tester, 'weight', '60');
          await enter(tester, 'target-weight', '58');
          expect(primary.hitTestable(), findsOneWidget);
          expect(find.byKey(_secondary).hitTestable(), findsOneWidget);
          expect(
            tester.getRect(primary).bottom,
            lessThanOrEqualTo(size.height - 300),
          );
          FocusManager.instance.primaryFocus?.unfocus();
          keyboard.value = 0;
          await settle(tester);
          final birthday = find.byKey(const ValueKey('onboarding-birthday'));
          await tester.ensureVisible(birthday);
          await settle(tester);
          await press(tester, birthday);
          await press(tester, find.text(l10n.bpDone));
          await press(tester, primary);
          step(9);
          await press(tester, primary);
          expect(find.text('setup-complete'), findsOneWidget);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
          expect(prefs.getString(PrefsKeys.mascotName), '麻糬');
          expect(prefs.getString(PrefsKeys.userNickname), '小日');
          expect(prefs.getBool(PrefsKeys.waterEnabled), isTrue);
          expect(prefs.getBool(PrefsKeys.timerEnabled), isTrue);
          expect(prefs.getBool(PrefsKeys.familyEnabled), isTrue);
          expect(prefs.getDouble(PrefsKeys.userHeight), 168);
          expect(prefs.getDouble(PrefsKeys.userWeight), 60);
          expect(prefs.getDouble(PrefsKeys.targetWeight), 58);
          expect(prefs.getString(PrefsKeys.userBirthday), isNotNull);
          final habits =
              (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
                  .cast<Map<String, dynamic>>();
          expect(
            habits.singleWhere((h) => h['name'] == '閱讀')['weeklyTarget'],
            4,
          );
          expect(habits.where((h) => h['name'] == '喝足夠的水'), hasLength(1));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'reduced motion toggles retain welcome text, page and entered names',
    (tester) async {
      final reduced = ValueNotifier(false);
      final keyboard = ValueNotifier(0.0);
      addTearDown(reduced.dispose);
      addTearDown(keyboard.dispose);
      await pumpFlow(
        tester,
        size: const Size(320, 667),
        locale: const Locale('en'),
        reduced: reduced,
        keyboard: keyboard,
      );
      reduced.value = true;
      await settle(tester);
      expect(find.text('Continue'), findsOneWidget);
      expect(
        tester
            .widgetList<MascotStage>(find.byType(MascotStage))
            .every((s) => s.reduceMotion && s.paused),
        isTrue,
      );
      await press(tester, find.byKey(_primary));
      await enter(tester, 'mascot-name', 'Mochi');
      reduced.value = false;
      await settle(tester);
      expect(find.text('2 / 9'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('onboarding-mascot-name')),
            )
            .controller!
            .text,
        'Mochi',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'imperial body fields keep metric persistence on narrow English UI',
    (tester) async {
      final reduced = ValueNotifier(true);
      final keyboard = ValueNotifier(0.0);
      addTearDown(reduced.dispose);
      addTearDown(keyboard.dispose);
      await pumpFlow(
        tester,
        size: const Size(320, 667),
        locale: const Locale('en'),
        reduced: reduced,
        keyboard: keyboard,
        unit: UnitSystem.imperial,
      );
      final primary = find.byKey(_primary);
      await press(tester, primary);
      await press(tester, primary);
      await enter(tester, 'nickname', 'Robin');
      await press(tester, primary);
      for (var page = 4; page <= 7; page++) {
        await press(tester, primary);
      }
      final gender = find.text('Female');
      await tester.ensureVisible(gender);
      await settle(tester);
      await press(tester, gender);
      keyboard.value = 300;
      await settle(tester);
      await enter(tester, 'height', '5');
      await enter(tester, 'height-inches', '6');
      await enter(tester, 'weight', '132');
      await enter(tester, 'target-weight', '130');
      FocusManager.instance.primaryFocus?.unfocus();
      keyboard.value = 0;
      await settle(tester);
      final birthday = find.byKey(const ValueKey('onboarding-birthday'));
      await tester.ensureVisible(birthday);
      await settle(tester);
      await press(tester, birthday);
      await press(tester, find.text('Done').hitTestable());
      await press(tester, primary);
      await press(tester, primary);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(PrefsKeys.userHeight),
        closeTo(UnitConvert.ftInToCm(5, 6), 0.001),
      );
      expect(
        prefs.getDouble(PrefsKeys.userWeight),
        closeTo(UnitConvert.lbToKg(132), 0.001),
      );
      expect(
        prefs.getDouble(PrefsKeys.targetWeight),
        closeTo(UnitConvert.lbToKg(130), 0.001),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('decline requires confirmation; optional steps can be skipped', (
    tester,
  ) async {
    final reduced = ValueNotifier(true);
    final keyboard = ValueNotifier(0.0);
    addTearDown(reduced.dispose);
    addTearDown(keyboard.dispose);
    await pumpFlow(
      tester,
      size: const Size(320, 667),
      locale: const Locale('en'),
      reduced: reduced,
      keyboard: keyboard,
    );
    final primary = find.byKey(_primary);
    await press(tester, primary);
    await press(tester, primary);
    await enter(tester, 'nickname', 'Robin');
    await press(tester, primary);
    await press(tester, find.byKey(_secondary));
    await press(tester, find.text('Keep it'));
    expect(find.text('4 / 9'), findsOneWidget);
    for (var page = 4; page <= 6; page++) {
      await press(tester, find.byKey(_secondary));
      await press(tester, find.text('Turn it off'));
    }
    await press(tester, primary);
    await press(tester, find.byKey(_secondary));
    await press(tester, primary);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.waterEnabled), isFalse);
    expect(prefs.getBool(PrefsKeys.timerEnabled), isFalse);
    expect(prefs.getBool(PrefsKeys.familyEnabled), isFalse);
    expect(prefs.getDouble(PrefsKeys.userWeight), isNull);
    expect(prefs.getBool(PrefsKeys.weightTrackingEnabled), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
