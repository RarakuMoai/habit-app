import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/pages/weight_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/water_bottle.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget journalApp(Widget page, {Locale locale = const Locale('zh', 'TW')}) {
  return MaterialApp(
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
    home: Scaffold(
      extendBody: true,
      // Production keeps the page in an IndexedStack behind navigation.
      // Reserve the two-row navigation footprint used by short phones.
      bottomNavigationBar: const SizedBox(height: 112),
      body: IndexedStack(children: [page]),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.unitSystem: 'metric',
      PrefsKeys.waterGoalSuggestionDismissed: true,
      PrefsKeys.waterGoalSuggestionBaseline: 2000,
    });
    MascotPanelPrefs.openValue.value = 1;
  });

  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    testWidgets('補水在小螢幕、大字、${locale.languageCode} 保留主操作與可捲動輸入', (tester) async {
      tester.view.physicalSize = const Size(320, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(journalApp(const WaterPage(), locale: locale));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      final context = tester.element(find.byType(WaterPage));
      final l10n = AppLocalizations.of(context);
      final add = find.byKey(const ValueKey('water-add-cup'));
      expect(add.hitTestable(), findsOneWidget);
      expect(
        find.byTooltip(l10n.waterCustomAmount).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip(l10n.waterCustomAmount));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l10n.waterSheetTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      final history = find.text(l10n.waterTodayRecords).last;
      await tester.ensureVisible(history);
      await tester.pump();
      expect(history.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('體重空狀態在小螢幕大字可開啟輸入面板', (tester) async {
    tester.view.physicalSize = const Size(320, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(journalApp(const WeightPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final action = find.byKey(const ValueKey('weight-primary-action'));
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('新增體重紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('降低動態仍立即更新水位，省略水瓶位移與水位補間', (tester) async {
    Widget bottle(double progress, int bumpKey) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(
          child: SizedBox(
            width: 100,
            height: 150,
            child: WaterBottle(
              progress: progress,
              reached: progress >= 1,
              bumpKey: bumpKey,
              panelOpenValue: 0,
              paused: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(bottle(0.25, 1));
    await tester.pumpWidget(bottle(0.75, 2));
    await tester.pump();
    final progressAnimation = tester.widget<TweenAnimationBuilder<double>>(
      find.descendant(
        of: find.byType(WaterBottle),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
    );
    expect(progressAnimation.duration, Duration.zero);
    final waterPaint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(WaterBottle),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere((paint) => paint.painter is WaterPainter);
    expect((waterPaint.painter! as WaterPainter).level, 0.75);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
