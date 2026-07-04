import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 遊戲計時器（2026-07-04 體驗重做版）的行為契約：
// 卡片＝入口卡；全螢幕＝環桌對戰面（上排旋轉 180°、每人一格），
// 像實體棋鐘——待機點誰的區誰先走、進行中點自己的區換手。
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

  Future<void> enterArena(WidgetTester tester) async {
    await tester.tap(find.text('進入對戰'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> tapZone(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('game_zone_$i')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder inZone(int i, String text) => find.descendant(
    of: find.byKey(ValueKey('game_zone_$i')),
    matching: find.text(text),
  );

  testWidgets('入口卡進入對戰＝環桌待機，每格都能當開局鈕', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);

    // 入口卡：門面資訊＋大鈕，沒有操作面。
    expect(find.text('遊戲計時器'), findsOneWidget);
    expect(find.text('每回合 30 秒 · 2 人'), findsOneWidget);
    expect(find.text('進入對戰'), findsOneWidget);

    await enterArena(tester);

    // 環桌待機：兩格都在、每格都提示「點一下由你開始」。
    expect(find.byKey(const ValueKey('game_zone_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_zone_1')), findsOneWidget);
    expect(find.text('點一下由你開始'), findsNWidgets(2));
  });

  testWidgets('待機點玩家2 的區＝玩家2 先走（先手步驟消失）', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);

    await tapZone(tester, 1);
    expect(inZone(1, '點一下換手'), findsOneWidget);
    expect(inZone(0, '點一下換手'), findsNothing);
  });

  testWidgets('進行中點自己的區換手、點對面無效、上一位可還原', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);

    await tapZone(tester, 0); // 玩家1 先走
    expect(inZone(0, '點一下換手'), findsOneWidget);

    await tapZone(tester, 0); // 換手 → 玩家2
    expect(inZone(1, '點一下換手'), findsOneWidget);

    await tapZone(tester, 0); // 誤點對面 → 不換手
    expect(inZone(1, '點一下換手'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(0, '點一下換手'), findsOneWidget);
  });

  testWidgets('中線暫停顯示繼續提示，點任一格即繼續', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);
    await tapZone(tester, 0);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inZone(0, '點一下繼續'), findsOneWidget);

    await tapZone(tester, 1); // 暫停中點任何區都是繼續（不換手）
    expect(inZone(0, '點一下換手'), findsOneWidget);
  });

  testWidgets('每回合超時：格內紅色正計時；退回入口卡顯示超時實況', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 5,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);
    await tapZone(tester, 0);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('+0:0'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('超時'), findsWidgets);
    expect(find.text('回到對戰'), findsOneWidget);
    expect(find.text('重設對局'), findsOneWidget);
  });

  testWidgets('三人環桌：上排 1 格（旋轉）＋下排 2 格', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerPlayerCount: 3,
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);

    expect(find.byKey(const ValueKey('game_zone_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_zone_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_zone_2')), findsOneWidget);
    expect(find.text('點一下由你開始'), findsNWidgets(3));

    // 換手沿座位順序：1 → 2 → 3。
    await tapZone(tester, 0);
    await tapZone(tester, 0);
    expect(inZone(1, '點一下換手'), findsOneWidget);
    await tapZone(tester, 1);
    expect(inZone(2, '點一下換手'), findsOneWidget);
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

  testWidgets('設定：時間快選 chips 一點即存', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('1 分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 分'));
    await tester.pump(const Duration(milliseconds: 250));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.gameTimerTurnSeconds), 60);
  });

  testWidgets('設定玩家排序使用 ReorderableListView 並持久化順序', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerPlayerCount: 3,
      PrefsKeys.gameTimerNames: ['甲', '乙', '丙'],
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await enterArena(tester);
    await tester.tap(find.byIcon(Icons.tune_rounded));
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
