import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/family/parent_management_page.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:habit_app/widgets/app_pressable.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:habit_app/widgets/mascot_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('沒有小孩時顯示暖色邀請入口', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(l10nTestApp(home: const FamilyPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('先新增一位小孩'), findsOneWidget);
    expect(find.text('兔咪會幫你們記小任務和積分。'), findsOneWidget);
    expect(find.text('新增小孩'), findsOneWidget);

    // 邀請卡要緊接功能面板的把手，不可被 AnimatedSwitcher 垂直置中。
    final cardTop = tester.getTopLeft(find.text('先新增一位小孩')).dy;
    final panelHandleBottom = tester
        .getBottomLeft(find.byType(MascotToggleBar))
        .dy;
    expect(cardTop - panelHandleBottom, lessThan(40));

    // 整張卡片（含按鈕）仍要留在畫面內。
    final addButtonBottom = tester.getBottomLeft(find.text('新增小孩')).dy;
    expect(addButtonBottom, lessThanOrEqualTo(600));
  });

  testWidgets('收合名冊與固定管理操作列避開真實 MainPage 雙排底欄', (tester) async {
    tester.view.physicalSize = const Size(320, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 20);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    MascotPersona.voiceMuted = true;
    MascotPanelPrefs.openValue.value = 1;
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    StoryEvents.debugCatalog = const [];
    addTearDown(() {
      MascotPersona.resetToIdle();
      MascotPersona.voiceMuted = false;
      MascotPanelPrefs.openValue.value = 0;
      LogicalDayCoordinator.debugInstance = null;
      StoryStore.pendingReveal.value = [];
      StoryEvents.debugCatalog = null;
    });
    final now = DateTime.now();
    final today = LogicalDate.stringFor(now, LogicalDate.defaultHour);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: today,
      PrefsKeys.coinLastLoginDate: now.toIso8601String().split('T').first,
      PrefsKeys.onboardingDone: true,
      // 真正開啟六個分頁，讓 MainPage 在320pt寬度使用雙排導覽。
      PrefsKeys.waterEnabled: true,
      PrefsKeys.timerEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.familyEnabled: true,
      PrefsKeys.children: jsonEncode([
        {'id': 'child-1', 'name': '小兔', 'avatar': '🐰', 'points': 28},
        {'id': 'child-2', 'name': '小熊', 'avatar': '🐻', 'points': 16},
      ]),
    });
    await LogicalDayCoordinator.instance.start();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
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
    final l10n = AppLocalizations.of(tester.element(find.byType(MainPage)));
    final nav = find.byKey(const ValueKey('main_navigation'));
    final navItems = find.descendant(
      of: nav,
      matching: find.byType(AppPressable),
    );
    expect(navItems, findsNWidgets(6));
    final navRowTops = {
      for (var i = 0; i < 6; i++) tester.getTopLeft(navItems.at(i)).dy,
    };
    expect(navRowTops, hasLength(2), reason: '此案例必須真正覆蓋雙排導覽');
    final familyTab = find.descendant(
      of: nav,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AppPressable && widget.semanticsLabel == l10n.tabFamily,
      ),
    );
    await tester.tap(familyTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final dock = find.byKey(const ValueKey('family-roster-actions'));
    final shellFinder = find.ancestor(
      of: dock,
      matching: find.byType(MascotPageShell),
    );
    expect(shellFinder, findsOneWidget);
    final shell = tester.widget<MascotPageShell>(shellFinder);
    final panelRect = tester.getRect(find.byWidget(shell.child));
    final dockRect = tester.getRect(dock);
    final navRect = tester.getRect(nav);
    final manage = find.descendant(
      of: dock,
      matching: find.widgetWithText(FilledButton, l10n.famParentManage),
    );
    final add = find.descendant(
      of: dock,
      matching: find.widgetWithText(TextButton, l10n.famAddChild),
    );
    for (final action in [manage, add]) {
      expect(action.hitTestable(), findsOneWidget);
      final rect = tester.getRect(action);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.top, greaterThanOrEqualTo(panelRect.top));
      expect(rect.bottom, lessThanOrEqualTo(panelRect.bottom));
      expect(
        rect.bottom,
        lessThanOrEqualTo(navRect.top),
        reason: '完整觸控區必須位於導覽上方',
      );
    }
    expect(dockRect.bottom, lessThanOrEqualTo(navRect.top));
    final firstChild = find.byKey(const ValueKey('family-child-child-1'));
    expect(firstChild.hitTestable(), findsOneWidget);
    final childRect = tester.getRect(firstChild);
    expect(childRect.top, greaterThanOrEqualTo(panelRect.top));
    expect(
      childRect.bottom,
      lessThanOrEqualTo(dockRect.top),
      reason: '第一位孩子的完整名冊列不能被管理操作列遮住',
    );
    expect(tester.takeException(), isNull);

    // 除幾何位置以外，實際點擊仍須進入原有家長管理流程。
    await tester.tap(manage);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ParentManagementPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });
}
