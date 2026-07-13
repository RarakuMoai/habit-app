// 足跡頁冒煙測試：週/月統計與獨立的補習慣入口。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/review_page.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('空資料：顯示足跡標題、分段、溫柔的空摘要', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    expect(find.text('足跡'), findsOneWidget);
    expect(find.text('忘了打勾？補上最近的習慣'), findsOneWidget);
    expect(find.text('週'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('每日足跡'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('每日足跡'), findsOneWidget);
    // 沒有習慣紀錄時是陪伴語氣，不是 0 分審判
    expect(find.textContaining('還沒有習慣紀錄'), findsOneWidget);
  });

  testWidgets('足跡錢包顯示在分段切換上方', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    final walletTop = tester.getTopLeft(find.text('足跡錢包')).dy;
    final backfillTop = tester.getTopLeft(find.text('忘了打勾？補上最近的習慣')).dy;
    final segmentTop = tester.getTopLeft(find.text('週')).dy;
    expect(walletTop, lessThan(backfillTop));
    expect(backfillTop, lessThan(segmentTop));
  });

  testWidgets('透明 AppBar 使用深色狀態列與返回圖示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.systemOverlayStyle, SystemUiOverlayStyle.dark);
    expect(appBar.iconTheme?.color, AppInk.strong);
    expect(appBar.actionsIconTheme?.color, AppInk.strong);
  });

  testWidgets('點「補習慣」會進入獨立補登頁', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('忘了打勾？補上最近的習慣'));
    await tester.pumpAndSettle();

    expect(find.text('補上之前的足跡'), findsOneWidget);
    expect(find.textContaining('可補昨天起往前 7 天'), findsOneWidget);
  });

  testWidgets('切到「月」仍正常渲染', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();

    expect(find.textContaining('年'), findsWidgets); // 月標題含「YYYY 年 M 月」
  });
}
