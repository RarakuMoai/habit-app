import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/widgets/mascot_app_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CoinService.notifier.value = 0;
    CoinService.presentationBalance.value = null;
  });

  testWidgets('足跡幣鈕超過 999 顯示 999+', (tester) async {
    CoinService.notifier.value = 999;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CoinPill())),
      ),
    );

    final coinImage = tester.widget<Image>(find.byType(Image));
    expect(
      (coinImage.image as AssetImage).assetName,
      'assets/icon/ui/paw_footprint_coin_round.png',
    );
    expect(find.text('999'), findsOneWidget);
    expect(find.text('999+'), findsNothing);

    CoinService.notifier.value = 1000;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('999'), findsNothing);
    expect(find.text('999+'), findsOneWidget);
  });

  testWidgets('獎勵演出期間顯示暫存餘額', (tester) async {
    CoinService.notifier.value = 108;
    CoinService.presentationBalance.value = 100;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: CoinPill()))),
    );

    expect(find.text('100'), findsOneWidget);
    expect(find.text('108'), findsNothing);

    CoinService.presentationBalance.value = null;
    await tester.pump();
    expect(find.text('108'), findsOneWidget);
  });

  testWidgets('單雙位數比三位數稍高，符合掌墊視覺重心', (tester) async {
    CoinService.notifier.value = 1;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: CoinPill()))),
    );
    final oneY = tester.getCenter(find.text('1')).dy;

    CoinService.notifier.value = 10;
    await tester.pumpAndSettle();
    final tenY = tester.getCenter(find.text('10')).dy;

    CoinService.notifier.value = 100;
    await tester.pumpAndSettle();
    final hundredY = tester.getCenter(find.text('100')).dy;

    expect(oneY, lessThan(hundredY));
    expect(tenY, lessThan(hundredY));
  });
}
