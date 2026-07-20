// 桌遊計時器設定面板（展開狀態）冒煙測試：
// 分區齊全、chip 即改即存、倒數提醒選項遵守 warn < turn 夾限、
// 出場順位排序模式（⋯ > 移動、長按拖曳、完成排序、棋鐘候補）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_setup_panel.dart';
import 'package:habit_app/pages/timer/game/table_store.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/reorder_jiggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> pumpPanel(
  WidgetTester tester, {
  void Function(TableTimerConfig)? onChanged,
  TableTimerConfig? initial,
  List<String>? roster,
  Size size = const Size(800, 2600),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (initial != null) await TableStore.saveConfig(prefs, initial);
  if (roster != null) await TableStore.saveRoster(prefs, roster);
  // 拉高視窗讓整份設定不用捲動就看得到（ListView 懶建，摺疊區找不到）
  tester.view.physicalSize = size;
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

/// 玩家列的 ⋯ 選單鈕（第 [i] 位）。用 tooltip 定位，
/// 避免誤中常用組合卡上同圖示的 ⋯。
Finder playerMenuButton(int i) => find.byTooltip('改名、移動或移除').at(i);

/// 排序模式中抖動動畫永遠在跑，pumpAndSettle 會逾時——
/// 一律用固定時長 pump 前進。
Future<void> pumpJiggling(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 走 ⋯ > 移動 進入排序模式。
Future<void> enterSortMode(WidgetTester tester, {int via = 0}) async {
  await tester.tap(playerMenuButton(via));
  await tester.pumpAndSettle();
  await tester.tap(find.text('移動'));
  await pumpJiggling(tester);
}

List<String> savedNames(SharedPreferences prefs) => [
  for (final p in TableStore.loadConfig(prefs).players) p.name,
];

void main() {
  testWidgets('第一層整合時間提醒，常用內容改為同尺寸彈窗入口', (tester) async {
    await pumpPanel(tester);

    // 頁首合併卡：兔咪＋一行本局摘要（舊三格摘要卡已收掉）
    expect(find.text('遊戲桌'), findsOneWidget);
    expect(find.text('多人桌遊 · 4 人 · 每回合 1 分'), findsOneWidget);
    expect(find.text('只骰骰子'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('game-settings-header'))).height,
      lessThanOrEqualTo(96),
    );
    expect(find.text('本局摘要'), findsNothing);

    expect(find.text('玩法'), findsOneWidget);
    expect(find.text('出場順位'), findsOneWidget);
    expect(find.text('按住蓄色後拖曳調整'), findsOneWidget);
    expect(find.text('每回合時間'), findsOneWidget);

    // 提醒與回合時間住同一卡片，不再多一層收合。
    expect(find.text('更多計時設定'), findsNothing);
    expect(find.text('倒數提醒（秒）'), findsOneWidget);
    expect(find.text('超時自動換下一位'), findsOneWidget);
    expect(find.text('常用設定'), findsOneWidget);
    expect(find.text('常用玩家'), findsOneWidget);
    expect(find.text('常用組合'), findsOneWidget);
    expect(find.text('儲存目前設定'), findsNothing);

    // 預設 4 位玩家 + 順位徽章 1–4，每列一個 ⋯ 選單
    for (var i = 1; i <= 4; i++) {
      expect(find.text('玩家 $i'), findsOneWidget);
      expect(find.text('$i'), findsWidgets);
    }
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.edit_rounded), findsNWidgets(4));
  });

  testWidgets('超時換人直接顯示並即時更新', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('自由輪流沒有可調提醒：整個「更多計時設定」不出現', (tester) async {
    await pumpPanel(
      tester,
      initial: TableTimerConfig.fallback().copyWith(mode: TableGameMode.free),
    );

    expect(find.text('更多計時設定'), findsNothing);
    expect(find.text('每回合時間'), findsNothing);
    expect(find.text('常用設定'), findsOneWidget);
  });

  testWidgets('空清單從「常用組合」彈窗存出第一組', (tester) async {
    final prefs = await pumpPanel(tester);

    await tester.tap(find.text('常用組合'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存目前設定'));
    await tester.pumpAndSettle();
    expect(find.text('儲存常用組合'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(TableStore.loadPresets(prefs).length, 1);
    expect(find.text('常用組合'), findsOneWidget);
    expect(find.text('1 組'), findsOneWidget);
  });

  group('出場順位排序模式', () {
    testWidgets('名字與鉛筆都能改名；中間空白無效；按住會出現蓄色', (tester) async {
      await pumpPanel(tester);

      final middle = tester.getRect(
        find.byKey(const ValueKey('player-row-middle-0')),
      );
      await tester.tapAt(Offset(middle.right - 12, middle.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('玩家名字'), findsNothing);
      expect(find.text('移除玩家'), findsNothing);

      await tester.tap(find.text('玩家 1'));
      await tester.pumpAndSettle();
      expect(find.text('玩家名字'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('編輯 玩家 1'));
      await tester.pumpAndSettle();
      expect(find.text('玩家名字'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('玩家 1')),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_PlayerHoldPainter',
        ),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('同時存入常用玩家會記住上次勾選', (tester) async {
      final prefs = await pumpPanel(tester);

      await tester.tap(find.byTooltip('編輯 玩家 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同時存入常用玩家'));
      await tester.enterText(find.byType(TextField), '阿兔');
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(prefs.getBool(PrefsKeys.gameTableRememberAddToRoster), isTrue);
      await tester.tap(find.byTooltip('編輯 阿兔'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    });

    testWidgets('⋯ > 移動 進入排序模式，完成排序退出', (tester) async {
      await pumpPanel(tester);

      await tester.tap(playerMenuButton(0));
      await tester.pumpAndSettle();
      expect(find.text('改名'), findsOneWidget);
      expect(find.text('移動'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await tester.tap(find.text('移動'));
      await pumpJiggling(tester);
      expect(find.text('完成排序'), findsOneWidget);
      expect(find.text('拖曳玩家調整出場順位'), findsOneWidget);
      // 排序模式中維持原本 ⋯ 圖示，不切換成另一種符號。
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(4));
      expect(find.text('新增玩家'), findsNothing);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);

      // 點完成排序後抖動停止，才能 pumpAndSettle
      await tester.tap(find.text('完成排序'));
      await tester.pumpAndSettle();
      expect(find.text('完成排序'), findsNothing);
      expect(find.text('按住蓄色後拖曳調整'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(4));
      expect(find.text('新增玩家'), findsOneWidget);
    });

    testWidgets('排序模式中拖曳整列，順位即改即存', (tester) async {
      final prefs = await pumpPanel(tester);
      await enterSortMode(tester);

      // 玩家 1 往下拖過一列（列高約 54）：即按即拖也要逐步移動＋pump，
      // 一次到位的合成手勢不會觸發 reorder 的位移追蹤
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('玩家 1')),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await pumpJiggling(tester);

      expect(savedNames(prefs), ['玩家 2', '玩家 1', '玩家 3', '玩家 4']);
    });

    testWidgets('一般狀態長按整列直接拖曳，並自動進入排序模式', (tester) async {
      final prefs = await pumpPanel(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('玩家 2')),
      );
      // 長按門檻後同一手勢直接拖
      await tester.pump(kReorderHoldDelay + const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await pumpJiggling(tester);

      expect(savedNames(prefs), ['玩家 1', '玩家 3', '玩家 2', '玩家 4']);
      expect(find.text('完成排序'), findsOneWidget);
    });

    testWidgets('棋鐘模式：前兩位標上場、其餘輪空，輪空玩家仍可從 ⋯ 改名', (tester) async {
      final prefs = await pumpPanel(
        tester,
        initial: TableTimerConfig.fallback().copyWith(
          mode: TableGameMode.chess,
        ),
      );

      expect(find.text('上場'), findsNWidgets(2));
      expect(find.text('本局輪空'), findsNWidgets(2));

      await tester.tap(playerMenuButton(2)); // 第 3 位＝輪空
      await tester.pumpAndSettle();
      await tester.tap(find.text('改名'));
      await tester.pumpAndSettle();
      expect(find.text('玩家名字'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '阿公');
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(savedNames(prefs)[2], '阿公');
    });

    testWidgets('只剩 2 人時 ⋯ 選單沒有「移除」', (tester) async {
      await pumpPanel(
        tester,
        initial: TableTimerConfig.fallback().copyWith(
          players: const [
            TablePlayer(name: '小明', colorIndex: 0),
            TablePlayer(name: '小美', colorIndex: 1),
          ],
        ),
      );

      await tester.tap(playerMenuButton(0));
      await tester.pumpAndSettle();
      expect(find.text('改名'), findsOneWidget);
      expect(find.text('移動'), findsOneWidget);
      expect(find.text('移除'), findsNothing);
    });

    testWidgets('套用常用組合會退出排序模式（名單整包換掉）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TableStore.savePresets(prefs, [
        TablePreset(name: '快速局', config: TableTimerConfig.fallback()),
      ]);
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

      await enterSortMode(tester);
      expect(find.text('完成排序'), findsOneWidget);

      await tester.tap(find.text('常用組合'));
      await pumpJiggling(tester);
      await tester.tap(find.text('快速局'));
      await pumpJiggling(tester);
      expect(find.text('完成排序'), findsOneWidget);
      await tester.tap(find.text('確認套用'));
      await tester.pumpAndSettle();
      expect(find.text('完成排序'), findsNothing);
    });
  });

  testWidgets('常用玩家以選取狀態加入本局，並可獨立刪除名單', (tester) async {
    final prefs = await pumpPanel(tester, roster: ['小兔']);

    await tester.tap(find.text('常用玩家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小兔'));
    await tester.pumpAndSettle();
    expect(savedNames(prefs), isNot(contains('小兔')));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.tap(find.text('確認加入（1 位）'));
    await tester.pumpAndSettle();
    expect(savedNames(prefs), contains('小兔'));

    await tester.tap(find.text('常用玩家'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除 小兔'));
    await tester.pumpAndSettle();
    expect(TableStore.loadRoster(prefs), isEmpty);
  });

  testWidgets('常用內容面板貼齊螢幕底部，短畫面仍可捲到最後一項', (tester) async {
    await pumpPanel(
      tester,
      size: const Size(800, 700),
      roster: ['玩家甲', '玩家乙', '玩家丙', '玩家丁', '玩家戊', '玩家己'],
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('常用玩家'));
    await tester.pumpAndSettle();

    expect(tester.getBottomRight(find.byType(BottomSheet)).dy, 700);
    await tester.scrollUntilVisible(
      find.text('新增常用玩家'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('新增常用玩家'), findsOneWidget);
  });

  testWidgets('點 chip 即改即存，並回報給入口卡', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(tester, onChanged: (c) => reported = c);

    await tester.tap(find.text('2 分'));
    await tester.pumpAndSettle();

    expect(reported?.turnSeconds, 120);
    expect(TableStore.loadConfig(prefs).turnSeconds, 120);
  });

  testWidgets('倒數提醒預設只留 5、10 秒', (tester) async {
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

    expect(find.text('剩 5 秒'), findsOneWidget);
    expect(find.text('剩 10 秒'), findsOneWidget);
    expect(find.text('剩 15 秒'), findsNothing);
    expect(find.text('剩 20 秒'), findsNothing);
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

    await tester.tap(find.text('常用玩家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增常用玩家'));
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

    await tester.tap(find.text('自訂').first);
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

    // 加減與手動分秒輸入可並存。
    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.enterText(find.byType(TextFormField).at(1), '15');

    // 秒數只接受 0–59；輸入 60 會保留上一個合法值。
    await tester.enterText(find.byType(TextFormField).at(1), '60');
    final secondsState = tester.state<FormFieldState<String>>(
      find.byType(TextFormField).at(1),
    );
    expect(secondsState.value, '15');

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(TableStore.loadConfig(prefs).turnSeconds, 135);
    expect(prefs.getInt(PrefsKeys.gameTableCustomTurnSeconds), 135);
    expect(find.text('自訂 2 分 15 秒'), findsOneWidget);

    // 切到預設值後，自訂 chip 仍記得 2:15；再點自訂即可取回。
    await tester.tap(find.text('1 分').first);
    await tester.pumpAndSettle();
    expect(find.text('自訂 2 分 15 秒'), findsOneWidget);
    await tester.tap(find.text('自訂 2 分 15 秒'));
    await tester.pumpAndSettle();
    expect(TableStore.loadConfig(prefs).turnSeconds, 135);
  });

  testWidgets('倒數提醒自訂固定在第二排並只輸入秒', (tester) async {
    final prefs = await pumpPanel(tester);

    // 第一顆自訂是每回合時間，第二顆是倒數提醒。
    await tester.tap(find.text('自訂').at(1));
    await tester.pumpAndSettle();
    expect(find.text('自訂倒數提醒'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('提前幾秒提醒'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '7');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(TableStore.loadConfig(prefs).warnSeconds, 7);
    expect(find.text('自訂 7 秒'), findsOneWidget);
  });
}
