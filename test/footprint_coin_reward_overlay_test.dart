import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/widgets/footprint_coin_reward_overlay.dart';

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
    await tester.pump(const Duration(milliseconds: 900));
    expect(CoinService.visibleBalance, inInclusiveRange(100, 108));

    await tester.pump(const Duration(milliseconds: 1000));
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
}
