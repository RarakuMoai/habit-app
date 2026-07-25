// onboarding 全流程 widget test：依頁面定義表逐頁前進到最後一頁。
// 目的：改動頁面順序/新增頁面時，確保換頁邊界、各頁渲染（含小螢幕能否
// 捲到底部按鈕）不被弄壞。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 點一個選項/按鈕並等換頁動畫（350ms）跑完。
  // 測試視窗較小，先捲到可見再點，避免畫面外 tap 落空。
  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // 相遇頁：等三句打字動畫自然播完（3 句 × 60ms/字 + 句間 900ms）
  Future<void> waitForTyping(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
  }

  // 音效/BGM 的一次性 timer 推完，避免 pending-timer 斷言
  Future<void> drainTimers(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 10));

  testWidgets('從相遇一路走到最後一頁', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));

    // 畫面1：相遇。打字期間顯示快轉提示，播完才換成「繼續」
    await tester.pump();
    expect(find.text('點一下繼續'), findsOneWidget);
    await waitForTyping(tester);
    expect(find.text('繼續'), findsOneWidget);
    await tapAndSettle(tester, '繼續');

    // 畫面2：互相認識。兔咪名字有預設值，暱稱必填才能前進
    expect(find.text('我的名字'), findsOneWidget);
    expect(find.text('你的名字'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '小測');
    await tester.pump();
    await tapAndSettle(tester, '下一步');

    // 畫面3：想一起做什麼。三張功能卡與習慣 chip 同頁
    expect(find.text('喝水提醒'), findsOneWidget);
    expect(find.text('專注計時'), findsOneWidget);
    expect(find.text('家庭模式'), findsOneWidget);
    // 喝水/計時預設開啟 → 按鈕是「下一步」而不是「略過」
    expect(find.text('下一步'), findsOneWidget);
    await tapAndSettle(tester, '下一步');

    // 畫面4：身體資訊（選填，直接跳過）
    expect(find.text('下次再說'), findsOneWidget);
    await tapAndSettle(tester, '下次再說');

    // 畫面5：收尾
    expect(find.text('開始'), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('點畫面可快轉打字，不用等完整動畫', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 點畫面左下角空白處（避開兔咪自己的點擊區與底部進度列）。
    // 三句 × 每句最多兩下（補完當前句 → 進下一句）
    final body = tester.getRect(find.byType(PageView));
    final blankSpot = Offset(body.left + 12, body.bottom - 24);
    for (var i = 0; i < 8 && find.text('繼續').evaluate().isEmpty; i++) {
      await tester.tapAt(blankSpot);
      await tester.pump();
    }
    expect(
      find.text('繼續'),
      findsOneWidget,
      reason: '點畫面應該能跳過打字動畫，不必乾等 6 秒',
    );

    await drainTimers(tester);
  });

  testWidgets('小螢幕（iPhone SE）第3頁全選後仍能前進', (tester) async {
    // 「想一起做什麼」頁是合併後內容最多的一頁：8 個習慣 chip 全選會
    // 展開頻率面板，加上三張功能卡。小螢幕上必須還能捲到底部按鈕。
    tester.view.physicalSize = const Size(750, 1334); // SE：375 × 667 @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));

    await waitForTyping(tester);
    await tapAndSettle(tester, '繼續');
    await tester.enterText(find.byType(TextField).at(1), '小測');
    await tester.pump();
    await tapAndSettle(tester, '下一步');

    // 全選習慣：可調頻率的那幾個會展開每日/每週面板，把頁面撐到最長
    for (final name in ['刷牙', '整理環境', '閱讀', '早起', '運動', '飲食控制', '冥想', '早睡']) {
      await tester.ensureVisible(find.textContaining(name));
      await tester.pump();
      await tester.tap(find.textContaining(name));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('想多久做一次？'), findsOneWidget);

    // 底部按鈕仍捲得到、按得動 → 會前進到身體資訊頁
    await tapAndSettle(tester, '下一步');
    expect(find.text('下次再說'), findsOneWidget);

    await drainTimers(tester);
  });
}
