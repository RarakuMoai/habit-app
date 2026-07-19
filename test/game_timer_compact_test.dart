// 遊戲入口以明確的「準備／設定」狀態切換，不再把設定生命週期綁在高度。
// 鍵盤、兔咪面板或視窗尺寸改變都不能銷毀正在編輯的設定頁。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_timer_theme.dart';
import 'package:habit_app/pages/timer/game_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('進入設定後，高度與鍵盤改變都不會退出設定頁', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final height = ValueNotifier<double>(500);
    await tester.pumpWidget(
      MaterialApp(
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

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('兔咪遊戲桌'), findsOneWidget);

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

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(find.text('準備開局'), findsOneWidget);
  });
}
