// onboarding 全流程 widget test：依頁面定義表逐頁前進到最後一頁。
// 目的：改動頁面順序/新增頁面時，確保換頁邊界、返回鍵的子步驟邏輯、
// 各頁渲染（含 overflow）不被弄壞。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

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

  testWidgets('點畫面可快轉打字，不用等完整動畫', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(l10nTestApp(home: const OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('點一下繼續'), findsOneWidget);

    // 點畫面左下角空白處（避開兔咪自己的點擊區與底部進度列）。
    // 四句 × 每句最多兩下（補完當前句 → 進下一句）
    final body = tester.getRect(find.byType(PageView));
    final blankSpot = Offset(body.left + 12, body.bottom - 24);
    for (var i = 0; i < 10 && find.text('繼續').evaluate().isEmpty; i++) {
      await tester.tapAt(blankSpot);
      await tester.pump();
    }
    expect(find.text('繼續'), findsOneWidget, reason: '點畫面應該能跳過打字動畫，不必乾等 6 秒');

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('從打字動畫一路走到最後一頁', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(l10nTestApp(home: const OnboardingPage()));

    // 畫面1：等打字動畫播完（4 句 × 60ms/字 + 句間 900ms），「繼續」浮現
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('繼續'), findsOneWidget);
    await tapAndSettle(tester, '繼續');

    // 畫面2：你想怎麼叫牠（預設兔咪，直接下一步）
    expect(find.text('幫我取個名字'), findsOneWidget);
    await tapAndSettle(tester, '下一步');

    // 畫面3：暱稱必填，填了才能下一步
    await tester.enterText(find.byType(TextField), '小測');
    await tester.pump();
    await tapAndSettle(tester, '下一步');

    // 畫面4（架子上放什麼）：不選任何習慣 → 按鈕顯示「略過」
    expect(find.text('略過'), findsOneWidget);
    await tapAndSettle(tester, '略過');

    // 畫面5（進門）：到達最後一頁
    expect(find.text('開始'), findsOneWidget);

    // 把 BGM/音效的一次性 timer 推完，避免 pending-timer 斷言
    await tester.pump(const Duration(seconds: 10));
  });
}
