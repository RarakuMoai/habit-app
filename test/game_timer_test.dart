import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 遊戲計時器 UI（2026-07-04 重做版）的行為契約：
// 卡片＝對局大廳；全螢幕 2 人＝棋鐘分半（點自己那半換手）、3 人以上＝大舞台。
// 純邏輯（換手/棋鐘/undo/事件）另在 game_clock_controller_test.dart。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AudioSettingsService.sfxMuted.value = true;
  });

  Future<void> pumpGameTimer(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 390, height: 620, child: GameTimer()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> startMatch(WidgetTester tester) async {
    await tester.tap(find.text('開始對局'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Finder inZone(int i, String text) => find.descendant(
    of: find.byKey(ValueKey('game_zone_$i')),
    matching: find.text(text),
  );

  testWidgets('大廳顯示摘要與席次，開始對局自動進全螢幕（2 人＝上下分半）', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);

    // 大廳：摘要卡 + 先手提示 + 開始鈕（不再有圓環）。
    expect(find.text('每回合計時'), findsOneWidget);
    expect(find.text('點選玩家可指定先手'), findsOneWidget);
    expect(find.text('開始對局'), findsOneWidget);

    await startMatch(tester);

    // 全螢幕分半：兩個半場都在，輪到玩家1（換手提示只在他那半）。
    expect(find.byKey(const ValueKey('game_zone_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_zone_1')), findsOneWidget);
    expect(inZone(0, '點一下換手'), findsOneWidget);
    expect(inZone(1, '點一下換手'), findsNothing);
  });

  testWidgets('點自己的半邊換手；點對面沒反應；上一位可還原', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await startMatch(tester);

    // 玩家1 點自己的半場 → 輪到玩家2。
    await tester.tap(find.byKey(const ValueKey('game_zone_0')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(1, '點一下換手'), findsOneWidget);

    // 誤點對面（非目前玩家）的半場 → 不換手。
    await tester.tap(find.byKey(const ValueKey('game_zone_0')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(1, '點一下換手'), findsOneWidget);

    // 上一位 → 回到玩家1。
    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(0, '點一下換手'), findsOneWidget);
  });

  testWidgets('中線暫停後顯示繼續提示，點半場即繼續', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await startMatch(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(0, '點一下繼續'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game_zone_0')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(0, '點一下換手'), findsOneWidget);
  });

  testWidgets('每回合倒數歸零標示超時（半場紅色正計時；退回卡片顯示超時字樣）', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 5,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await startMatch(tester);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 350));

    // 超時往上數：時間字前面帶 +。
    expect(find.textContaining('+0:0'), findsWidgets);

    // 退出全螢幕 → 卡片實況標示超時。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('超時'), findsWidgets);
    expect(find.text('重設'), findsOneWidget);
    expect(find.text('下一位'), findsOneWidget);
    expect(find.text('全螢幕'), findsOneWidget);
  });

  testWidgets('三人以上用大舞台：點畫面換手', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerPlayerCount: 3,
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await startMatch(tester);

    expect(find.byKey(const ValueKey('game_stage')), findsOneWidget);
    // 開局：玩家2 只出現在座位列。
    expect(find.text('玩家2'), findsOneWidget);

    // 點舞台換手 → 玩家2 同時出現在舞台標題與座位列。
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('game_stage'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('玩家2'), findsNWidgets(2));
  });

  testWidgets('展開使用走 MascotToggleBar 同一套面板收合流程', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.sfxMuted: true});
    MascotPanelPrefs.openValue.value = 1;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 620,
            child: MascotPageShell(
              accent: kGameAccent,
              scene: SizedBox.shrink(),
              child: GameTimer(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('展開使用'), findsOneWidget);

    await tester.tap(find.text('展開使用'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(MascotPanelPrefs.openValue.value, closeTo(0, 0.01));
    expect(find.text('展開使用'), findsNothing);
  });

  testWidgets('設定玩家排序使用 ReorderableListView 並持久化順序', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerPlayerCount: 3,
      PrefsKeys.gameTimerNames: ['甲', '乙', '丙'],
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await tester.tap(find.text('遊戲設定'));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.tap(find.byTooltip('移動').first);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('完成排序'), findsOneWidget);

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorder(0, 3);
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.text('完成排序'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PrefsKeys.gameTimerNames)?.take(3).toList(), [
      '乙',
      '丙',
      '甲',
    ]);
  });
}
