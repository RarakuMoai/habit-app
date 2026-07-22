import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/widgets/footprint_coin_reward_overlay.dart';
import 'package:habit_app/widgets/reward_animation_anchor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CoinService.notifier.value = 0;
    CoinService.presentationBalance.value = null;
  });

  testWidgets('足跡幣吸入後顯示正確餘額並完成', (tester) async {
    var finished = false;
    CoinService.notifier.value = 108;
    CoinService.presentationBalance.value = 100;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FootprintCoinRewardOverlay(
            amount: 8,
            startBalance: 100,
            targetBalance: 108,
            onFinished: () => finished = true,
          ),
        ),
      ),
    );

    expect(find.text('今日足跡幣 +8'), findsOneWidget);
    expect(CoinService.visibleBalance, 100);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));
    expect(finished, isFalse);
    expect(CoinService.visibleBalance, 100, reason: '灑開並停留展示時不能急著把餘額跳完');

    await tester.pump(const Duration(milliseconds: 650));
    expect(CoinService.visibleBalance, inExclusiveRange(100, 108));

    await tester.pump(const Duration(milliseconds: 700));
    expect(finished, isTrue);
    expect(CoinService.presentationBalance.value, isNull);
    expect(CoinService.visibleBalance, 108);
  });

  testWidgets('點提示可略過且仍以正確餘額結束', (tester) async {
    var finished = false;
    CoinService.notifier.value = 25;
    CoinService.presentationBalance.value = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FootprintCoinRewardOverlay(
            amount: 25,
            startBalance: 0,
            targetBalance: 25,
            onFinished: () => finished = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('今日足跡幣 +25'));
    await tester.pump();

    expect(finished, isTrue);
    expect(CoinService.visibleBalance, 25);
  });

  testWidgets('足跡幣從兔咪錨點散開後飛向 AppBar 錨點', (tester) async {
    CoinService.notifier.value = 7;
    CoinService.presentationBalance.value = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned(
                left: 80,
                top: 300,
                width: 100,
                height: 100,
                child: RewardAnimationAnchor(
                  kind: RewardAnimationAnchorKind.mascot,
                  child: SizedBox.expand(),
                ),
              ),
              const Positioned(
                right: 20,
                top: 20,
                width: 48,
                height: 48,
                child: RewardAnimationAnchor(
                  kind: RewardAnimationAnchorKind.coinBalance,
                  child: SizedBox.expand(),
                ),
              ),
              // IndexedStack 會保留其他分頁的錨點；後註冊但不可見的錨點
              // 不得蓋掉目前分頁的實際座標。
              const Offstage(
                child: SizedBox.square(
                  dimension: 40,
                  child: RewardAnimationAnchor(
                    kind: RewardAnimationAnchorKind.mascot,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              const Offstage(
                child: SizedBox.square(
                  dimension: 40,
                  child: RewardAnimationAnchor(
                    kind: RewardAnimationAnchorKind.coinBalance,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              FootprintCoinRewardOverlay(
                amount: 7,
                startBalance: 0,
                targetBalance: 7,
                onFinished: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final glowCenter = tester.getCenter(
      find.byKey(const ValueKey('footprint-coin-origin-glow')),
    );
    expect(glowCenter, const Offset(130, 350));

    await tester.pump(const Duration(milliseconds: 850));
    final scattered = tester.getCenter(
      find.byKey(const ValueKey('footprint-coin-0')),
    );
    expect(scattered.dx, lessThan(glowCenter.dx - 40));

    await tester.pump(const Duration(milliseconds: 250));
    final held = tester.getCenter(
      find.byKey(const ValueKey('footprint-coin-0')),
    );
    expect(
      (held - scattered).distance,
      lessThan(1),
      reason: '錢灑開後應停留片刻，讓使用者看清楚再開始收集',
    );

    await tester.pump(const Duration(milliseconds: 530));
    final gathering = tester.getCenter(
      find.byKey(const ValueKey('footprint-coin-0')),
    );
    expect(gathering.dx, greaterThan(scattered.dx));
    expect(gathering.dy, lessThan(scattered.dy));
  });
}
