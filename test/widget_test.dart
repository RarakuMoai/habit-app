import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('跳過 onboarding 直接進主頁冒煙測試', (WidgetTester tester) async {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    SharedPreferences.setMockInitialValues({
      'last_open_date': '${now.year}-$m-$d',
    });
    // startAtHome: true 模擬已完成 onboarding 的狀態
    await tester.pumpWidget(const MyApp(startAtHome: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 主頁應顯示「新增習慣」按鈕（標題已改成兔咪場景，不再用文字標題）
    expect(find.text('新增習慣'), findsOneWidget);

    // BGM 服務的 engage-check 重試 timer 最長排到 9 秒；把假時間推過去
    // 讓所有一次性 timer 觸發完，避免 test binding 的 pending-timer 斷言
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('第一次啟動進入 onboarding 冒煙測試', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp(startAtHome: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 常駐動畫不會 settle；確認 onboarding 頁已進入即可。
    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
