import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/home/habit_card.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/pages/timer_page.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MascotPersona.voiceMuted = true;
    MascotPanelPrefs.openValue.value = 0;
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    StoryStore.pendingReveal.value = [];
    // The journal/navigation harness excludes milestone reveal routes.
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
      for (final populated in [false, true]) {
        testWidgets(
          '正式首頁 ${size.width} ${locale.languageCode} populated=$populated 大字低動態',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
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
              PrefsKeys.waterEnabled: populated,
              PrefsKeys.timerEnabled: true,
              PrefsKeys.weightTrackingEnabled: populated,
              PrefsKeys.familyEnabled: true,
              PrefsKeys.habits: jsonEncode([
                if (populated) ...[
                  {
                    'id': 'walk',
                    'name': 'Walk after lunch',
                    'frequency': 'daily',
                    'done': false,
                    'createdAt': today,
                  },
                  {
                    'id': 'water',
                    'name': '喝足夠的水',
                    'frequency': 'daily',
                    'done': false,
                    'createdAt': today,
                  },
                  {
                    'id': 'read',
                    'name': 'Read for a quiet moment',
                    'frequency': 'weekly',
                    'done': false,
                    'createdAt': today,
                    'weeklyTarget': 3,
                    'weeklyDates': <String>[],
                  },
                ],
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
            expect(find.byType(HomePage), findsOneWidget);
            expect(tester.takeException(), isNull);
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
            for (final label in [
              l10n.tabHabits,
              l10n.tabTimer,
              if (populated) l10n.tabWater,
              if (populated) l10n.tabWeight,
              l10n.tabFamily,
              l10n.tabWardrobe,
            ]) {
              final item = navItem(label);
              expect(item.hitTestable(), findsOneWidget);
              final target = tester.getSize(item);
              expect(target.width, greaterThanOrEqualTo(44));
              expect(target.height, greaterThanOrEqualTo(44));
            }
            if (populated) {
              final weekly = find.byWidgetPredicate(
                (widget) => widget is HabitCard && widget.isWeekly,
              );
              await tester.scrollUntilVisible(
                weekly,
                180,
                scrollable: find
                    .descendant(
                      of: find.byType(HomePage),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              expect(weekly.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            } else {
              expect(find.text(l10n.hpEmptyTitle), findsOneWidget);
            }
            final targetLabel = populated ? l10n.tabWater : l10n.tabTimer;
            await tester.tap(navItem(targetLabel));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(
              find.byType(populated ? WaterPage : TimerPage),
              findsOneWidget,
            );
            expect(
              tester.widget<AppPressable>(navItem(targetLabel)).selected,
              isTrue,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(navItem(l10n.tabHabits));
            await tester.pump();
            expect(
              tester.widget<AppPressable>(navItem(l10n.tabHabits)).selected,
              isTrue,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 12));
          },
        );
      }
    }
  }

  testWidgets('按壓途中打開降低動態會回到原尺寸，取消手勢不送出操作', (tester) async {
    var taps = 0;
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ValueListenableBuilder<bool>(
          valueListenable: reduced,
          builder: (context, value, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: value),
            child: Scaffold(
              body: Center(
                child: AppPressable(
                  onPressed: () => taps++,
                  child: const SizedBox(
                    width: 180,
                    height: 56,
                    child: Text('Record'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final target = find.byType(AppPressable);
    final initial = tester.getRect(target);
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(target), initial);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    reduced.value = true;
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.cancel();
    await tester.pump();
    expect(taps, 0);
  });
}
