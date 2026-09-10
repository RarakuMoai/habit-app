import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/pages/weight_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/utils/wardrobe_catalog.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Production ships these fonts. Loading them keeps numeric and English line
  // measurements faithful instead of substituting square Ahem glyphs.
  setUpAll(() async {
    final nunito = FontLoader('Nunito');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
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
    MascotPanelPrefs.openValue.value = 0;
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

  for (final size in [const Size(320, 667), const Size(430, 932)]) {
    for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
      for (final openValue in [0.0, 1.0]) {
        testWidgets(
          '真實 MainPage 四頁 ${size.width} ${locale.languageCode} panel=$openValue 大字低動態',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = size.width == 430
                ? const FakeViewPadding(top: 59, bottom: 34)
                : const FakeViewPadding(top: 20);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final now = DateTime.now();
            final today = LogicalDate.stringFor(now, LogicalDate.defaultHour);
            final yesterday = LogicalDate.stringFor(
              now.subtract(const Duration(days: 1)),
              LogicalDate.defaultHour,
            );
            final calendar =
                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            SharedPreferences.setMockInitialValues({
              PrefsKeys.lastOpenDate: today,
              PrefsKeys.coinLastLoginDate: calendar,
              PrefsKeys.onboardingDone: true,
              PrefsKeys.waterEnabled: true,
              PrefsKeys.timerEnabled: true,
              PrefsKeys.weightTrackingEnabled: true,
              PrefsKeys.familyEnabled: true,
              PrefsKeys.waterGoalSuggestionDismissed: true,
              PrefsKeys.waterGoalSuggestionBaseline: 2000,
              PrefsKeys.waterCupMl: 250,
              PrefsKeys.waterGoalMl: 2000,
              PrefsKeys.waterDay(today): 3,
              PrefsKeys.unitSystem: 'metric',
              PrefsKeys.weightRecords: jsonEncode([
                {
                  'date': today,
                  'time': '08:20',
                  'weight': 68.4,
                  'body_fat': 21.4,
                },
                {
                  'date': yesterday,
                  'time': '08:10',
                  'weight': 68.7,
                  'body_fat': 21.6,
                },
              ]),
              PrefsKeys.userHeight: 165.0,
              PrefsKeys.userGender: '女',
              PrefsKeys.userBirthday: '1992-05-20',
              PrefsKeys.userActivityLevel: '輕度',
              PrefsKeys.targetWeight: 65.0,
              PrefsKeys.children: jsonEncode([
                {
                  'id': 'child-1',
                  'name': locale.languageCode == 'en' ? 'Mia' : '小葵',
                  'avatar': '🐼',
                  'points': 28,
                },
                {
                  'id': 'child-2',
                  'name': locale.languageCode == 'en' ? 'Leo' : '小宇',
                  'avatar': '🐨',
                  'points': 16,
                },
              ]),
              PrefsKeys.habits: jsonEncode([
                {
                  'id': 'walk',
                  'name': 'Walk after lunch',
                  'frequency': 'daily',
                  'done': false,
                  'createdAt': today,
                },
              ]),
            });
            await LogicalDayCoordinator.instance.start();
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
            final l10n = AppLocalizations.of(
              tester.element(find.byType(MainPage)),
            );
            final nav = find.byKey(const ValueKey('main_navigation'));
            Finder navItem(String label) => find.descendant(
              of: nav,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is AppPressable && widget.semanticsLabel == label,
              ),
            );
            MascotPanelPrefs.openValue.value = openValue;
            await tester.pump();
            for (final page in [
              (l10n.tabWater, WaterPage, 'water-today-card'),
              (l10n.tabWeight, WeightPage, 'today-weight-card'),
              (l10n.tabFamily, FamilyPage, 'family-child-child-1'),
              (l10n.tabWardrobe, WardrobePage, 'wardrobe-outfit-tumi_original'),
            ]) {
              await tester.tap(navItem(page.$1));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
              expect(tester.takeException(), isNull, reason: page.$1);
              final pageFinder = find.byType(page.$2);
              final shellFinder = find.descendant(
                of: pageFinder,
                matching: find.byType(MascotPageShell),
              );
              final shell = tester.widget<MascotPageShell>(shellFinder);
              final panelRect = tester.getRect(find.byWidget(shell.child));
              final card = find.byKey(ValueKey(page.$3));
              final cardRect = tester.getRect(card);
              expect(
                cardRect.top,
                greaterThanOrEqualTo(panelRect.top),
                reason: '${page.$1} card top',
              );
              expect(
                cardRect.bottom,
                lessThanOrEqualTo(panelRect.bottom),
                reason:
                    '${page.$1} complete first card $cardRect in $panelRect',
              );
              if (page.$2 == WaterPage) {
                final controls = panelRect.height < 400 || size.width < 360
                    ? find.byKey(const ValueKey('water-compact-actions'))
                    : find.text(l10n.waterCupDrank);
                expect(controls.hitTestable(), findsOneWidget);
                expect(
                  cardRect.bottom,
                  lessThanOrEqualTo(tester.getRect(controls).top),
                  reason: 'Water data must end above the action dock',
                );
                expect(
                  find.byTooltip(l10n.waterAdjustGoal).hitTestable(),
                  findsOneWidget,
                );
              } else if (page.$2 == WeightPage) {
                final action = find.byKey(
                  const ValueKey('weight-primary-action'),
                );
                expect(action.hitTestable(), findsOneWidget);
                expect(
                  cardRect.bottom,
                  lessThanOrEqualTo(tester.getRect(action).top),
                  reason: 'Weight data must end above the action dock',
                );
              } else if (page.$2 == FamilyPage) {
                expect(
                  find.text(l10n.famParentManage).hitTestable(),
                  findsOneWidget,
                );
                expect(
                  find.text(l10n.famAddChild).hitTestable(),
                  findsOneWidget,
                );
                final action = find.byKey(
                  const ValueKey('family-roster-actions'),
                );
                expect(
                  cardRect.bottom,
                  lessThanOrEqualTo(tester.getRect(action).top),
                  reason: 'Roster must not be covered by management',
                );
              } else {
                expect(
                  find
                      .text(outfitName(l10n, defaultOutfit))
                      .first
                      .hitTestable(),
                  findsOneWidget,
                );
                expect(find.text(l10n.wdApplied).hitTestable(), findsOneWidget);
                for (final label in [
                  l10n.wdTabOutfits,
                  l10n.wdTabMusic,
                  l10n.wdTabMemories,
                ]) {
                  final tab = find.descendant(
                    of: pageFinder,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is AppPressable &&
                          widget.semanticsLabel == label,
                    ),
                  );
                  expect(tab.hitTestable(), findsOneWidget);
                  expect(tester.getSize(tab).height, greaterThanOrEqualTo(44));
                }
              }
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 12));
          },
        );
      }
    }
  }
}
