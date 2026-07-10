import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_setup_panel.dart';
import 'package:habit_app/pages/timer/game/table_store.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> pumpPanel(
  WidgetTester tester, {
  TableTimerConfig? config,
  ValueChanged<TableTimerConfig>? onChanged,
  Size size = const Size(800, 2600),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (config != null) await TableStore.saveConfig(prefs, config);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
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
  setUp(() => AudioSettingsService.sfxMuted.value = true);
  tearDown(() => AudioSettingsService.sfxMuted.value = false);

  testWidgets('三步文案與預設玩家都完整呈現', (tester) async {
    await pumpPanel(tester);

    expect(find.text('兔咪遊戲桌'), findsOneWidget);
    expect(find.text('選玩法、人數和時間，準備好就一起玩！'), findsOneWidget);
    expect(find.text('今天怎麼玩？'), findsOneWidget);
    expect(find.text('今天有幾位玩家？'), findsOneWidget);
    expect(find.text('想留多少時間？'), findsOneWidget);

    for (var i = 1; i <= 4; i++) {
      expect(find.text('玩家 $i'), findsOneWidget);
    }
  });

  testWidgets('模式切換會更新次步驟並即時持久化', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(tester, onChanged: (c) => reported = c);

    await tester.tap(find.text('雙人對弈'));
    await tester.pumpAndSettle();

    expect(reported?.mode, TableGameMode.chess);
    expect(TableStore.loadConfig(prefs).mode, TableGameMode.chess);
    expect(find.text('哪兩位對弈？'), findsOneWidget);
    expect(find.text('棋鐘固定兩位，點名字可以修改'), findsOneWidget);
    expect(find.text('每人總時間'), findsOneWidget);

    await tester.tap(find.text('輕鬆輪流'));
    await tester.pumpAndSettle();

    expect(reported?.mode, TableGameMode.free);
    expect(TableStore.loadConfig(prefs).mode, TableGameMode.free);
    expect(find.text('不用趕，慢慢玩'), findsOneWidget);
    expect(find.text('只記錄每個人想了多久，不會倒數'), findsOneWidget);
  });

  testWidgets('玩家加減會立即更新畫面、回報設定並寫入 prefs', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(tester, onChanged: (c) => reported = c);

    await tester.tap(find.byTooltip('增加一位玩家'));
    await tester.pumpAndSettle();

    expect(find.text('5 位玩家'), findsOneWidget);
    expect(find.text('玩家 5'), findsOneWidget);
    expect(reported?.players.length, 5);
    expect(TableStore.loadConfig(prefs).players.length, 5);

    await tester.tap(find.byTooltip('減少一位玩家'));
    await tester.pumpAndSettle();

    expect(find.text('4 位玩家'), findsOneWidget);
    expect(find.text('玩家 5'), findsNothing);
    expect(reported?.players.length, 4);
    expect(TableStore.loadConfig(prefs).players.length, 4);
  });

  testWidgets('時間卡點一下就改即存並回報入口', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(tester, onChanged: (c) => reported = c);

    await tester.tap(find.text('1 分 30 秒'));
    await tester.pumpAndSettle();

    expect(reported?.turnSeconds, 90);
    expect(TableStore.loadConfig(prefs).turnSeconds, 90);
  });

  testWidgets('縮短回合時維持 warn 嚴格小於 turn', (tester) async {
    TableTimerConfig? reported;
    final prefs = await pumpPanel(
      tester,
      config: TableTimerConfig.fallback().copyWith(
        turnSeconds: 60,
        warnSeconds: 30,
      ),
      onChanged: (c) => reported = c,
    );

    await tester.tap(find.text('更多設定'));
    await tester.pumpAndSettle();
    expect(find.text('剩 30 秒'), findsOneWidget);
    await tester.tap(find.text('30 秒'));
    await tester.pumpAndSettle();

    expect(reported?.turnSeconds, 30);
    expect(reported?.warnSeconds, 29);
    final saved = TableStore.loadConfig(prefs);
    expect(saved.turnSeconds, 30);
    expect(saved.warnSeconds, 29);
    expect(saved.warnSeconds, lessThan(saved.turnSeconds));
    expect(find.text('剩 30 秒'), findsNothing);
    final selectedWarn = find.ancestor(
      of: find.text('剩 29 秒'),
      matching: find.byType(ChoiceChip),
    );
    expect(selectedWarn, findsOneWidget);
    expect(tester.widget<ChoiceChip>(selectedWarn).selected, isTrue);
  });

  testWidgets('390×844 放大字體切棋鐘後，計時制與進階設定皆可捲動', (tester) async {
    final prefs = await pumpPanel(
      tester,
      size: const Size(390, 844),
      textScale: 1.3,
    );
    final setupList = find.byType(Scrollable).first;

    await tester.tap(find.text('雙人對弈'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('每人總時間'),
      280,
      scrollable: setupList,
    );
    await tester.pumpAndSettle();
    expect(find.text('每回合'), findsOneWidget);
    expect(find.text('每人總時間'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('每人總時間'));
    await tester.pumpAndSettle();
    expect(TableStore.loadConfig(prefs).usesBank, isTrue);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('更多設定'),
      280,
      scrollable: setupList,
    );
    await tester.tap(find.text('更多設定'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('走完一手加秒'),
      220,
      scrollable: setupList,
    );
    await tester.pumpAndSettle();

    expect(find.text('走完一手加秒'), findsOneWidget);
    expect(find.text('＋2 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390×844 且文字 1.3 倍，從頂到底都不 overflow', (tester) async {
    await pumpPanel(tester, size: const Size(390, 844), textScale: 1.3);

    expect(tester.takeException(), isNull);
    final list = find.byType(ListView).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('收藏這組玩法'), findsOneWidget);
  });

  testWidgets('核心控制都有給孩子與長輩可理解的 Semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpPanel(tester);
      await tester.tap(find.text('更多設定'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('兔咪遊戲桌，三步就能開始')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('大家輪流，桌遊、牌卡、說故事')), findsWidgets);
      expect(find.bySemanticsLabel('增加一位玩家'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('第 1 位，玩家 1')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('修改 玩家 1 的名字')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('1 分鐘')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('時間到自動換下一位')), findsWidgets);
      expect(find.bySemanticsLabel('收藏目前的玩法設定'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });
}
