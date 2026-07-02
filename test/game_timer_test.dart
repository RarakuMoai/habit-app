import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('暫停後顯示繼續與暫停中，避免誤導成重新開始', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 5,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);

    expect(find.text('點一下開始'), findsOneWidget);

    await tester.tap(find.text('點一下開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 開新局會自動推進全螢幕面對面頁；退出回一般畫面才能繼續原本的斷言。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('點一下換手'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('點一下繼續'), findsOneWidget);
    expect(find.text('玩家1 暫停中'), findsOneWidget);
  });

  testWidgets('每回合倒數歸零後標示超時', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 5,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);

    await tester.tap(find.text('點一下開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 開新局會自動推進全螢幕面對面頁；退出回一般畫面才能繼續原本的斷言。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('超時'), findsWidgets);
    expect(find.text('點一下換手'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.replay_rounded));
    await tester.pump();
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

  testWidgets('開局自動進全螢幕：點畫面任一處換手、上一位可還原、退出回一般畫面', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.gameTimerTurnSeconds: 30,
      PrefsKeys.gameTimerPlayerCount: 2,
      PrefsKeys.sfxMuted: true,
    });

    await pumpGameTimer(tester);
    await tester.tap(find.text('點一下開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 全螢幕頁才有的退出鈕存在＝真的進了全螢幕（不是原本那個小卡片）。
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('玩家1'), findsWidgets);

    // 點畫面任一處＝換手：圓環本身的點擊被 IgnorePointer 蓋掉、改由外層
    // GestureDetector 接手，這裡故意點頂端留白（不是圓環、不是任何按鈕）驗證。
    final screenTopLeft = tester.getTopLeft(find.byType(Scaffold).last);
    await tester.tapAt(screenTopLeft + const Offset(300, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('玩家2'), findsWidgets);

    // 上一位：誤觸換手時可以退回，回到玩家1。
    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('玩家1'), findsWidgets);

    // 退出：回一般畫面（重設鈕重新可見）。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
  });
}
