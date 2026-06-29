// 足跡頁冒煙測試：會建、空資料給溫柔語氣、日/週/月可切換。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/review_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('空資料：顯示足跡標題、分段、溫柔的空摘要', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    expect(find.text('足跡'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('週'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    // 沒有習慣紀錄時是陪伴語氣，不是 0 分審判
    expect(find.textContaining('還沒有習慣紀錄'), findsOneWidget);
  });

  testWidgets('切到「日」會顯示補登視圖', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();

    // BackfillDayView 的底部說明
    expect(find.textContaining('不影響金幣與連勝'), findsOneWidget);
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
