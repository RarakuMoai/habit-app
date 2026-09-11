import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:habit_app/widgets/water_bottle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final nunito = FontLoader('Nunito');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      nunito.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    final digits = FontLoader('Baloo 2');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      digits.addFont(rootBundle.load('assets/fonts/Baloo2-$weight.ttf'));
    }
    await Future.wait([nunito.load(), digits.load()]);
  });

  setUp(() {
    MascotPersona.voiceMuted = true;
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    StoryEvents.debugCatalog = const [];
  });
  tearDown(() {
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = false;
    LogicalDayCoordinator.debugInstance = null;
    StoryStore.pendingReveal.value = [];
    StoryEvents.debugCatalog = null;
  });

  Future<AppLocalizations> openWater(
    WidgetTester tester, {
    required Size size,
    required Locale locale,
    required double panel,
    required int total,
    bool imperial = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = size.width >= 400
        ? const FakeViewPadding(top: 59, bottom: 34)
        : const FakeViewPadding(top: 20);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final today = LogicalDate.stringFor(now, LogicalDate.defaultHour);
    final calendar =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: today,
      PrefsKeys.coinLastLoginDate: calendar,
      PrefsKeys.onboardingDone: true,
      PrefsKeys.onboardingStoryVersion: 1,
      PrefsKeys.waterEnabled: true,
      PrefsKeys.timerEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.familyEnabled: true,
      PrefsKeys.waterGoalSuggestionDismissed: true,
      PrefsKeys.waterGoalSuggestionBaseline: 2000,
      PrefsKeys.waterCupMl: 250,
      PrefsKeys.waterGoalMl: 2000,
      PrefsKeys.waterEntries(today): jsonEncode([
        for (var i = 0; i < total ~/ 250; i++)
          {'at': now.toIso8601String(), 'ml': 250},
      ]),
      PrefsKeys.unitSystem: imperial ? 'imperial' : 'metric',
    });
    await LogicalDayCoordinator.instance.start();
    MascotPanelPrefs.openValue.value = panel;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const MainPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final l = AppLocalizations.of(tester.element(find.byType(MainPage)));
    final nav = find.byKey(const ValueKey('main_navigation'));
    await tester.tap(
      find.descendant(
        of: nav,
        matching: find.byWidgetPredicate(
          (w) => w is AppPressable && w.semanticsLabel == l.tabWater,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return l;
  }

  for (final size in [const Size(320, 667), const Size(430, 932)]) {
    for (final panel in [0.0, 1.0]) {
      for (final total in [0, 2000, 6000]) {
        testWidgets(
          'Water main constraints $size panel=$panel total=$total en 1.3',
          (tester) async {
            await openWater(
              tester,
              size: size,
              locale: const Locale('en'),
              panel: panel,
              total: total,
              imperial: total == 2000,
            );
            expect(tester.takeException(), isNull);
            final water = find.byType(WaterPage);
            final shell = tester.widget<MascotPageShell>(
              find.descendant(
                of: water,
                matching: find.byType(MascotPageShell),
              ),
            );
            final panelRect = tester.getRect(find.byWidget(shell.child));
            final bottle = find.byKey(const ValueKey('water-bottle-stage'));
            final bottleRect = tester.getRect(bottle);
            final heroRect = tester.getRect(
              find.byKey(const ValueKey('water-today-card')),
            );
            final addRect = tester.getRect(
              find.byKey(const ValueKey('water-add-cup')),
            );
            final toolsRect = tester.getRect(
              find.byKey(const ValueKey('water-tools')),
            );
            for (final paragraph
                in find
                    .descendant(
                      of: find.byKey(const ValueKey('water-today-card')),
                      matching: find.byType(RichText),
                    )
                    .evaluate()) {
              expect(
                (paragraph.renderObject! as RenderParagraph).didExceedMaxLines,
                isFalse,
                reason: 'Water amount and goal must not be clipped',
              );
            }
            expect(bottle.hitTestable(), findsOneWidget);
            expect(bottleRect.height, greaterThanOrEqualTo(92));
            expect(bottleRect.top, greaterThanOrEqualTo(panelRect.top));
            expect(heroRect.bottom, lessThanOrEqualTo(addRect.top));
            expect(toolsRect.bottom, lessThanOrEqualTo(panelRect.bottom - 16));
            if (panel == 0 && size.width == 430) {
              expect(bottleRect.height, greaterThanOrEqualTo(250));
            }
            for (final id in [
              'water-add-cup',
              'water-custom-action',
              'water-goal-action',
              'water-records-action',
            ]) {
              final control = find.byKey(ValueKey(id));
              expect(control.hitTestable(), findsOneWidget, reason: id);
              expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
            }
            final removeRect = tester.getRect(
              find.byKey(const ValueKey('water-remove-cup')),
            );
            final customRect = tester.getRect(
              find.byKey(const ValueKey('water-custom-action')),
            );
            expect(removeRect.center.dy, addRect.center.dy);
            expect(customRect.center.dy, addRect.center.dy);
            expect(removeRect.height, addRect.height);
            expect(customRect.height, addRect.height);
            final bottleWidget = tester.widget<WaterBottle>(
              find.descendant(of: water, matching: find.byType(WaterBottle)),
            );
            expect(
              bottleWidget.panelOpenValue,
              0,
              reason:
                  'Reaching the goal must not replace the bottle with a badge',
            );
            expect(bottleWidget.reached, total >= 2000);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 12));
          },
        );
      }
    }
  }

  testWidgets(
    'Compact water actions add, undo, custom entry, goal and log remain reachable',
    (tester) async {
      final l = await openWater(
        tester,
        size: const Size(320, 667),
        locale: const Locale('zh', 'TW'),
        panel: 1,
        total: 0,
      );
      final state = tester.state(find.byType(WaterPage)) as dynamic;
      expect(state.debugTotalMl, 0);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      try {
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('water-add-cup')))
              .getSemanticsData()
              .flagsCollection
              .isButton,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
      await tester.tap(find.byKey(const ValueKey('water-add-cup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(state.debugTotalMl, 250);
      await tester.tap(find.byKey(const ValueKey('water-remove-cup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(state.debugTotalMl, 0);
      for (final id in ['water-custom-action', 'water-records-action']) {
        await tester.tap(find.byKey(ValueKey(id)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(l.waterSheetTitle), findsOneWidget);
        Navigator.of(tester.element(find.text(l.waterSheetTitle))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byKey(const ValueKey('water-goal-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l.waterSettingsTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 12));
    },
  );
}
