import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('沒有小孩時顯示暖色邀請入口', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: FamilyPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('先新增一位小孩'), findsOneWidget);
    expect(find.text('兔咪會幫你們記小任務和積分。'), findsOneWidget);
    expect(find.text('新增小孩'), findsOneWidget);

    final cardTop = tester.getTopLeft(find.text('先新增一位小孩')).dy;
    expect(cardTop, lessThan(360));
  });
}
