// 推頁轉場：iOS 的邊緣滑回手勢不能被自訂轉場弄丟。
//
// 裸 `PageRouteBuilder` + 自訂 transitionsBuilder 看起來跟系統轉場很像，但它
// **不走 theme 的 pageTransitionsTheme**，所以連帶拿掉滑回手勢與舊頁視差。
// 設定頁與足跡頁曾經因此滑不回去。這組測試守住「推頁一律走平台路由」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pushWith(
    WidgetTester tester,
    Route<void> Function() route,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        // 用 ThemeData.platform 指定 iOS，而不是動 debugDefaultTargetPlatform
        // 全域變數——那個在測試 body 結束時就會被檢查，tearDown 還原來不及。
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(route()),
                child: const Text('push'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('inner'), findsOneWidget);
  }

  const inner = Scaffold(body: Center(child: Text('inner')));

  testWidgets('MaterialPageRoute 在 iOS 上可以從左緣滑回', (tester) async {
    await pushWith(
      tester,
      () => MaterialPageRoute<void>(builder: (_) => inner),
    );

    // 從左緣往右拖 = iOS 返回手勢。
    await tester.dragFrom(const Offset(2, 300), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('inner'), findsNothing, reason: '滑回應該把頁面收掉');
    expect(find.text('push'), findsOneWidget);
  });

  testWidgets('裸 PageRouteBuilder 滑不回去——這就是不能用它推頁的原因', (tester) async {
    await pushWith(
      tester,
      () => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => inner,
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
    );

    await tester.dragFrom(const Offset(2, 300), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('inner'), findsOneWidget, reason: '對照組：自訂轉場沒有滑回手勢，頁面留在原地');
  });
}
