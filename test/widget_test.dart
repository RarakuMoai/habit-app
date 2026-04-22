import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';

void main() {
  testWidgets('跳過 onboarding 直接進主頁冒煙測試', (WidgetTester tester) async {
    // startAtHome: true 模擬已完成 onboarding 的狀態
    await tester.pumpWidget(const MyApp(startAtHome: true));
    await tester.pumpAndSettle();

    // 主頁應顯示「我的習慣」AppBar 標題
    expect(find.text('我的習慣'), findsOneWidget);
  });

  testWidgets('第一次啟動進入 onboarding 冒煙測試', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(startAtHome: false));
    await tester.pumpAndSettle();

    // Onboarding 第一頁顯示吉祥物 emoji
    expect(find.text('🐰'), findsWidgets);
  });
}
