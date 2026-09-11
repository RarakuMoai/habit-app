import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/profile_edit_page.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

Future<void> _pumpEnglishProfile(
  WidgetTester tester, {
  required Map<String, Object> initialValues,
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  tester.view.physicalSize = const Size(320, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousUnit = UnitSystem.notifier.value;
  final previousMascotName = MascotName.value;
  addTearDown(() {
    UnitSystem.notifier.value = previousUnit;
    MascotName.set(previousMascotName);
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileEditPage(),
                      ),
                    )
                    .ignore();
              },
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open profile'));
  await tester.pumpAndSettle();
  expect(find.byType(ProfileEditPage), findsOneWidget);
  expect(tester.takeException(), isNull);
}

// The production cards render their label above the TextField, rather than
// using InputDecoration.labelText. Match that card's immediate Column.
Finder _fieldUnderLabel(String label) {
  final cardContent = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Column &&
          widget.children.any((child) => child is TextField),
    ),
  );
  return find.descendant(of: cardContent, matching: find.byType(TextField));
}

Finder _fieldWithSuffix(String suffix) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.suffixText == suffix,
);

Future<void> _revealLabel(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _enterProfileText(
  WidgetTester tester,
  Finder field,
  String value,
) async {
  expect(field, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _saveEnglishProfile(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Save');
  expect(save, findsOneWidget);
  expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  await Scrollable.ensureVisible(tester.element(save));
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(find.byType(ProfileEditPage), findsNothing);
  expect(find.text('Open profile'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('基本資料以彩色大字分區呈現，SE 尺寸可完整捲動', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.userNickname: '小優',
      PrefsKeys.mascotName: '小白',
      PrefsKeys.userHeight: 165.0,
      PrefsKeys.userWeight: 55.0,
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(l10nTestApp(home: const ProfileEditPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-edit-intro')), findsOneWidget);
    expect(find.text('讓小白更認識你'), findsOneWidget);
    expect(find.text('稱呼'), findsOneWidget);
    expect(find.text('你和小白想怎麼被叫'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('關於你'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('關於你'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('身體數據'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('身體數據'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('一週大概運動幾天？'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('活動量'), findsOneWidget);
    expect(find.text('一週大概運動幾天？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'imperial body fields persist metric values with no nickname on narrow English UI',
    (tester) async {
      await _pumpEnglishProfile(
        tester,
        initialValues: {
          PrefsKeys.unitSystem: UnitSystem.imperial.prefsValue,
          PrefsKeys.mascotName: 'Tumi',
        },
      );
      await _revealLabel(tester, 'Nickname');
      expect(
        tester.widget<TextField>(_fieldUnderLabel('Nickname')).controller!.text,
        isEmpty,
      );

      await _revealLabel(tester, 'Height');
      await _enterProfileText(tester, _fieldWithSuffix('ft'), '5');
      await _enterProfileText(tester, _fieldWithSuffix('in'), '6');
      await _revealLabel(tester, 'Weight');
      await _enterProfileText(tester, _fieldUnderLabel('Weight'), '132');
      await _revealLabel(tester, 'Target weight');
      await _enterProfileText(tester, _fieldUnderLabel('Target weight'), '130');
      await _saveEnglishProfile(tester);

      final prefs = await SharedPreferences.getInstance();
      // Explicit expected values keep this contract independent of UnitConvert.
      expect(prefs.getDouble(PrefsKeys.userHeight), closeTo(167.64, 0.001));
      expect(
        prefs.getDouble(PrefsKeys.userWeight),
        closeTo(59.87419284, 0.001),
      );
      expect(
        prefs.getDouble(PrefsKeys.targetWeight),
        closeTo(58.9670081, 0.001),
      );
      expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
    },
  );

  testWidgets('clearing an optional nickname removes its stored key', (
    tester,
  ) async {
    await _pumpEnglishProfile(
      tester,
      initialValues: {
        PrefsKeys.unitSystem: UnitSystem.metric.prefsValue,
        PrefsKeys.userNickname: 'Robin',
        PrefsKeys.mascotName: 'Tumi',
      },
    );
    await _revealLabel(tester, 'Nickname');
    final nickname = _fieldUnderLabel('Nickname');
    expect(tester.widget<TextField>(nickname).controller!.text, 'Robin');
    await _enterProfileText(tester, nickname, '   ');
    await _saveEnglishProfile(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
    expect(prefs.getString(PrefsKeys.mascotName), 'Tumi');
  });
}
