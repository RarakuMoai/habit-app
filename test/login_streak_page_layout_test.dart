import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/login_streak_page.dart';
import 'package:habit_app/utils/coin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // 演出時序最後一步在 1420ms，pump 過去讓所有 Timer 收掉。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
  }

  testWidgets('SE 緊湊尺寸不破版：天數、進度格、入帳與 CTA 都在', (tester) async {
    await pumpPage(
      tester,
      size: const Size(320, 568),
      streak: 12,
      reward: const LoginReward(level: 6, amount: 10, graceUsed: false),
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('天連續報到'), findsOneWidget);
    expect(find.text('今日足跡幣 +10'), findsOneWidget);
    expect(find.text('開始吧'), findsOneWidget);
    // 第 12 天 → 循環第 5 格：1~5 打勾，第 7 格還是禮物。
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
    expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
    // 滿級台詞
    expect(find.text('你一直有回來，兔咪都記得。'), findsOneWidget);
  });

  testWidgets('Pro Max 尺寸：里程碑日 7 格全亮並秀 +20 加碼', (tester) async {
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

    expect(find.text('7'), findsWidgets); // 大數字＋第 7 格標籤
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(7));
    expect(find.byIcon(Icons.card_giftcard_rounded), findsNothing);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('今日足跡幣 +30'), findsOneWidget);
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

    // 演出還沒走完就點畫面 → 一次亮完（Timer 全取消）。
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('昨天兔咪幫你看家，天數守住了。'), findsOneWidget);

    await tester.tap(find.text('開始吧'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LoginStreakPage), findsNothing);
  });
}
