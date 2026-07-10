// 桌遊計時器設定面板（展開狀態）冒煙測試：
// 分區齊全、chip 即改即存、倒數提醒選項遵守 warn < turn 夾限。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_setup_panel.dart';
import 'package:habit_app/pages/timer/game/table_store.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> pumpPanel(
  WidgetTester tester, {
  void Function(TableTimerConfig)? onChanged,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // 拉高視窗讓整份設定不用捲動就看得到（ListView 懶建，摺疊區找不到）
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TableSetupPanel(
          prefs: prefs,
          onConfigChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('分區齊全：順位說明、倒數提醒、常用組合入口都在', (tester) async {
    await pumpPanel(tester);

    expect(find.text('出場順位'), findsOneWidget);
    expect(find.text('由上到下輪流出場，按住 ≡ 拖曳調整'), findsOneWidget);
    expect(find.text('本局摘要'), findsOneWidget);
    expect(find.text('4 人出場'), findsOneWidget);
    expect(find.text('每回合 1 分'), findsWidgets);
    expect(find.text('倒數提醒'), findsOneWidget);
    expect(find.text('常用組合'), findsOneWidget);
    expect(find.text('儲存目前設定'), findsOneWidget);
    // 預設 4 位玩家 + 順位徽章 1–4
    for (var i = 1; i <= 4; i++) {
      expect(find.text('玩家 $i'), findsOneWidget);
      expect(find.text('$i'), findsWidgets);
    }
  });

  testWidgets('點 chip 即改即存，並回報給入口卡', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(tester, onChanged: (c) => reported = c);

    await tester.tap(find.text('45 秒'));
    await tester.pumpAndSettle();

    expect(reported?.turnSeconds, 45);
    expect(TableStore.loadConfig(prefs).turnSeconds, 45);
  });

  testWidgets('倒數提醒遵守 warn < turn：turn 30 秒時沒有「剩 30 秒」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await TableStore.saveConfig(
      prefs,
      TableTimerConfig.fallback().copyWith(turnSeconds: 30),
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableSetupPanel(prefs: prefs, onConfigChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('剩 20 秒'), findsOneWidget);
    expect(find.text('剩 30 秒'), findsNothing); // cap = 29
  });

  testWidgets('對話框開著時面板被換掉，「新增」仍把常用玩家存進 prefs', (tester) async {
    // 迴歸：鍵盤彈出壓縮卡片 → 面板被換成縮小卡（state 銷毀）→
    // 對話框按確定後什麼都沒存（2026-07-10 修）。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final show = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, _) => v
                ? TableSetupPanel(prefs: prefs, onConfigChanged: (_) {})
                : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('＋ 新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '小兔');

    // 對話框還開著，把面板從樹上換掉（模擬縮小卡頂替）
    show.value = false;
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(TableStore.loadRoster(prefs), contains('小兔'));
  });

  testWidgets('自訂 sheet：步進調整每回合時間並即改即存', (tester) async {
    final prefs = await pumpPanel(tester);

    await tester.tap(find.text('自訂'));
    await tester.pumpAndSettle();
    expect(find.text('自訂每回合時間'), findsOneWidget);

    // 預設 60 秒，+5 → 65 秒；sheet 大字即時更新
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.add_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 分 5 秒'), findsWidgets);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(TableStore.loadConfig(prefs).turnSeconds, 65);
    // 值落在預設檔位外：自訂 chip 亮起並顯示目前值
    expect(find.text('自訂 1 分 5 秒'), findsOneWidget);
  });
}
