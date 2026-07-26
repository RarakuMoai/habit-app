// 遊戲入口從準備畫面開啟底部設定選單；鍵盤與視窗尺寸改變時選單仍保留。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_store.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';
import 'package:habit_app/pages/timer/game/table_timer_theme.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  test('直向家庭遊戲桌背景已收入 asset bundle', () async {
    final data = await rootBundle.load(TableTheme.tableAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    addTearDown(() {
      frame.image.dispose();
      codec.dispose();
    });

    expect(frame.image.width, 1320);
    expect(frame.image.height, 2731);
  });

  testWidgets('遊戲設定由下方彈出，高度與鍵盤改變都不會退出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final height = ValueNotifier<double>(500);
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, h, _) => Center(
              child: SizedBox(height: h, width: 400, child: const GameTimer()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 預設是一致的準備畫面，不會因為高度夠大就直接顯示整份設定。
    expect(find.text('完成'), findsNothing);
    expect(find.text('準備開局'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timer-settings-action')));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('遊戲桌')),
      findsOneWidget,
    );
    expect(find.text('只骰骰子'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('game-settings-header'))).height,
      lessThanOrEqualTo(96),
    );
    final close = find.byTooltip('關閉');
    expect(close, findsOneWidget);
    expect(
      tester.getCenter(close).dx,
      greaterThan(tester.getCenter(find.byType(BottomSheet)).dx),
    );

    // 鍵盤彈出：高度被壓到 200，仍是同一個設定頁。
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    height.value = 200;
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);

    // 鍵盤收起並恢復高度，設定狀態不變。
    tester.view.viewInsets = FakeViewPadding.zero;
    height.value = 500;
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);

    // 沒有鍵盤、高度真的只剩 200，也不會用尺寸猜測使用者意圖。
    height.value = 200;
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.text('完成').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(find.text('準備開局'), findsOneWidget);
  });

  testWidgets('玩法膠囊即點即換、玩家鈕快調人數並即改即存', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: Center(
            child: SizedBox(height: 560, width: 400, child: GameTimer()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('遊戲桌'), findsOneWidget);
    expect(find.text('4 位玩家'), findsOneWidget);

    // 快切玩法：二人棋鐘固定前兩位上場，玩家快調鈕停用。
    await tester.tap(find.text('二人棋鐘'));
    await tester.pumpAndSettle();
    expect(find.text('2 位玩家'), findsOneWidget);
    await tester.tap(
      find.byIcon(Icons.groups_rounded).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('今天幾位上桌？'), findsNothing);

    // 切回多人桌遊：原本 4 位玩家還在，人數快調可用。
    await tester.tap(find.text('多人桌遊'));
    await tester.pumpAndSettle();
    expect(find.text('4 位玩家'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.groups_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('今天幾位上桌？'), findsOneWidget);
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    expect(find.text('今天幾位上桌？'), findsNothing);
    expect(find.text('6 位玩家'), findsOneWidget);

    // 即改即存：重載 prefs 的設定要看到 6 位玩家與多人玩法。
    final prefs = await SharedPreferences.getInstance();
    final saved = TableStore.loadConfig(prefs);
    expect(saved.players.length, 6);
    expect(saved.mode, TableGameMode.party);
  });
}
