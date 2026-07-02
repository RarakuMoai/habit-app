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

    // 空狀態不再縮小場景（舊 0.40 特例已移除）：卡片線與其他分頁統一
    // （寬度錨點 + kSceneRegionMaxFraction 護欄），所以只驗證邀請卡整張
    // （含「新增小孩」按鈕）留在 800×600 測試面內、沒有被場景推出畫面。
    final cardTop = tester.getTopLeft(find.text('先新增一位小孩')).dy;
    expect(cardTop, lessThan(500));
    final addButtonBottom = tester.getBottomLeft(find.text('新增小孩')).dy;
    expect(addButtonBottom, lessThanOrEqualTo(600));
  });
}
