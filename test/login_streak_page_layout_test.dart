// 每日登入慶祝頁（足跡報到卡・蓋章版）：
// 1. SE 緊湊尺寸完整演出不破版：報到卡、墨印天數、腳印格、入帳與 CTA 都在。
// 2. Pro Max 里程碑日：7 格蓋滿、+20 加碼、總金額正確。
// 3. 寬限日台詞；點畫面快轉；CTA 關頁。
// 演出用真 Timer（fake async 下由 pump 推進），不 pumpAndSettle
//（環境光塵動畫永不停）。完整演出後頁面 semantics 可能整批合併成
// 一顆節點，label 一律用 RegExp 子字串比對。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/login_streak_page.dart';
import 'package:habit_app/utils/coin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 卡上蓋出來的金腳印（兔咪圖/CTA 都不是這個 asset，不會誤數）。
  Finder pawStamps() => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName ==
            'assets/icon/ui/paw_footprint_coin.png',
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required Size size,
    required int streak,
    required LoginReward reward,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: LoginStreakPage(streak: streak, reward: reward)),
    );
    // 演出時序最後一步在 2150ms；分段 pump 讓中間的隱式動畫有機會跑完。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('SE 緊湊尺寸完整演出不破版：報到卡各元素都在', (tester) async {
    await pumpPage(
      tester,
      size: const Size(320, 568),
      streak: 12,
      reward: const LoginReward(level: 6, amount: 10, graceUsed: false),
    );

    expect(find.text('兔咪報到卡'), findsOneWidget);
    expect(find.text('連續第 12 天'), findsOneWidget);
    expect(find.text('今日足跡幣 +10'), findsOneWidget);
    expect(find.text('開始吧'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'連續登入 12 天，今日足跡幣 \+10')),
      findsWidgets,
    );
    // 第 12 天 → 循環第 5 格：1~5 蓋上金腳印，第 7 格還是禮物。
    expect(pawStamps(), findsNWidgets(5));
    expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
    // 第二輪徽章要亮出來
    expect(find.text('第 2 輪'), findsOneWidget);
    // 滿級台詞
    expect(find.text('你一直有回來，兔咪都記得。'), findsOneWidget);
  });

  testWidgets('Pro Max 尺寸：里程碑日 7 格蓋滿並秀 +20 加碼', (tester) async {
    await pumpPage(
      tester,
      size: const Size(430, 932),
      streak: 7,
      reward: const LoginReward(
        level: 6,
        amount: 10,
        graceUsed: false,
        milestoneAmount: 20,
      ),
    );

    expect(pawStamps(), findsNWidgets(7));
    expect(find.byIcon(Icons.card_giftcard_rounded), findsNothing);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('今日足跡幣 +30'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'連續登入 7 天，今日足跡幣 \+30')),
      findsWidgets,
    );
    // 首輪（第 7 天）還不亮輪數徽章
    expect(find.textContaining('輪'), findsNothing);
    expect(find.text('一起走到第 7 天了，兔咪有點感動。'), findsOneWidget);
  });

  testWidgets('寬限日換台詞；點畫面快轉後 CTA 可關頁', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  LoginStreakPage.route(
                    streak: 5,
                    reward: const LoginReward(
                      level: 4,
                      amount: 8,
                      graceUsed: true,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 演出還沒走完就點畫面 → 一次亮完（Timer 全取消，今日腳印直接蓋上）。
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('昨天兔咪幫你看家，天數守住了。'), findsOneWidget);
    expect(pawStamps(), findsNWidgets(5));
    // 快轉後沒有殘留的演出 Timer，pump 大段時間也不再變化。
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('開始吧'), findsOneWidget);

    await tester.tap(find.text('開始吧'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LoginStreakPage), findsNothing);
  });
}
