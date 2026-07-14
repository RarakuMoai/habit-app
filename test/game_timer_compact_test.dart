// 遊戲入口卡的縮小門檻：鍵盤彈出（原始 viewInsets 墊高）時不准把
// 完整設定頁換成縮小卡——否則設定頁 state 連同輸入對話框的存檔一起
// 被銷毀（常用玩家/組合存不進去、改名無效、畫面捲回頂部）。
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

  testWidgets('鍵盤彈出壓縮高度時，完整設定頁不換成縮小卡', (tester) async {
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
    // 500 高 ≥ 門檻：完整設定頁（底部只有開始對局，沒有多餘完成鈕）
    expect(find.text('完成'), findsNothing);
    expect(find.text('兔咪遊戲桌'), findsOneWidget);

    // 鍵盤彈出：高度被壓到 200、原始 viewInsets 同步墊高 → 仍是設定頁
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    height.value = 200;
    await tester.pumpAndSettle();
    expect(find.text('兔咪遊戲桌'), findsOneWidget);

    // 鍵盤收起：Scaffold 會把高度還回來（實機上兩者永遠一起變）
    tester.view.viewInsets = FakeViewPadding.zero;
    height.value = 500;
    await tester.pumpAndSettle();
    expect(find.text('兔咪遊戲桌'), findsOneWidget);

    // 沒有鍵盤、高度真的只剩 200（兔咪面板展開）：才換成縮小卡
    height.value = 200;
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(find.text('設定'), findsOneWidget);
  });
}
