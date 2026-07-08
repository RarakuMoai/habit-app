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
}
