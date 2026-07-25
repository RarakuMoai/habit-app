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
      MaterialApp(
        home: LoginStreakPage(streak: streak, reward: reward),
      ),
    );
    // 演出時序最後一步在 2880ms；分段 pump 讓中間的隱式動畫有機會跑完。
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

    expect(find.text('報到卡'), findsOneWidget);
    expect(find.text('兔咪報到卡'), findsNothing);
    expect(find.text('連續第 12 天'), findsOneWidget);
    expect(find.text('今日足跡幣 +10'), findsOneWidget);
    // 連續 12 天：零食升級成紅蘿蔔（第 7 天起）
    expect(find.text('拿紅蘿蔔給牠'), findsOneWidget);
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
    expect(find.text('你一直有回來，我都有記得。'), findsOneWidget);
  });

  testWidgets('先顯示連續天數，縮小時才浮出兔咪與報到卡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginStreakPage(
          streak: 1,
          reward: LoginReward(level: 1, amount: 5, graceUsed: false),
        ),
      ),
    );

    AnimatedOpacity opacity(String key) =>
        tester.widget<AnimatedOpacity>(find.byKey(ValueKey(key)));

    // 第一拍只有全螢幕連續天數墨印。
    await tester.pump(const Duration(milliseconds: 250));
    expect(opacity('login-streak-seal').opacity, 1);
    expect(opacity('login-streak-mascot').opacity, 0);
    expect(opacity('login-streak-card').opacity, 0);

    // 墨印縮回落款的同一拍，兔咪與報到卡才開始浮現。
    await tester.pump(const Duration(milliseconds: 700));
    expect(opacity('login-streak-mascot').opacity, 1);
    expect(opacity('login-streak-card').opacity, 1);
    expect(opacity('login-streak-stamp').opacity, 0);

    // 報到卡就位後，印章才進場準備蓋下。
    await tester.pump(const Duration(milliseconds: 450));
    expect(opacity('login-streak-stamp').opacity, 1);
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
    expect(find.bySemanticsLabel(RegExp(r'連續登入 7 天，今日足跡幣 \+30')), findsWidgets);
    // 首輪（第 7 天）還不亮輪數徽章
    expect(find.textContaining('輪'), findsNothing);
    expect(find.text('一起走到第 7 天了，我有點感動。'), findsOneWidget);
  });

  testWidgets('中斷回歸（等級>1、天數=1）：歡迎回來台詞、卡片只蓋第 1 格', (tester) async {
    await pumpPage(
      tester,
      size: const Size(390, 844),
      streak: 1,
      reward: const LoginReward(level: 4, amount: 8, graceUsed: false),
    );

    expect(find.text('歡迎回來。今天再一起慢慢開始。'), findsOneWidget);
    expect(pawStamps(), findsNWidgets(1));
    // 真・新用戶（等級 1）仍拿第一天台詞——這條保護兩句不互相蓋掉
  });

  testWidgets('真・第一天（等級 1）：新朋友台詞', (tester) async {
    await pumpPage(
      tester,
      size: const Size(390, 844),
      streak: 1,
      reward: const LoginReward(level: 1, amount: 5, graceUsed: false),
    );

    expect(find.text('第一天。以後也一起慢慢來。'), findsOneWidget);
  });

  testWidgets('零食隨連續天數升級：里程碑日給最好的', (tester) async {
    // 第 7 天＝里程碑（milestoneAmount > 0）：不管天數多少，里程碑優先
    await pumpPage(
      tester,
      size: const Size(390, 844),
      streak: 7,
      reward: const LoginReward(
        level: 5,
        amount: 9,
        milestoneAmount: 20,
        graceUsed: false,
      ),
    );
    expect(find.text('拿特別的點心給牠'), findsOneWidget);
    expect(find.text('拿紅蘿蔔給牠'), findsNothing);
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
    expect(find.text('昨天休息了一天，連續天數還留著。'), findsOneWidget);
    expect(pawStamps(), findsNWidgets(5));
    // 快轉後沒有殘留的演出 Timer，pump 大段時間也不再變化。
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('拿小餅乾給牠'), findsOneWidget);

    // 遞出零食：飛向兔咪（440ms）→ 牠收下彈一下 → 760ms 後才關頁，
    // 讓 main.dart 的足跡幣動畫接手。
    await tester.tap(find.text('拿小餅乾給牠'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(LoginStreakPage),
      findsOneWidget,
      reason: '零食還在飛，不該立刻關頁',
    );
    // 分段 pump 推完 760ms 的關頁 timer 與 380ms 的淡出轉場
    //（_ambient 是無限循環，不能用 pumpAndSettle）
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(LoginStreakPage), findsNothing);
  });
}
