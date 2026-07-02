import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/widgets/mascot_app_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CoinService.notifier.value = 0;
  });

  testWidgets('足跡金幣鈕超過 999 顯示 999+', (tester) async {
    CoinService.notifier.value = 999;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CoinPill())),
      ),
    );

    expect(find.text('999'), findsOneWidget);
    expect(find.text('999+'), findsNothing);

    CoinService.notifier.value = 1000;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('999'), findsNothing);
    expect(find.text('999+'), findsOneWidget);
  });
}
