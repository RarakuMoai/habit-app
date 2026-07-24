// 兔咪檔案頁與設定頁名片：
// 1. 名片顯示名字／相識天數／足跡幣，點擊觸發 onTap。
// 2. 檔案頁 SE 尺寸不破版：名字、相識落款、報到卡進度、統計卡、敘述句都在。
// 3. streak 0 的空狀態提示；編輯鈕能進編輯基本資料頁。
// 立繪待機呼吸動畫永不停，一律用固定 pump，不 pumpAndSettle。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/mascot_profile_page.dart';
import 'package:habit_app/pages/profile_edit_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 金腳印幣圖（報到卡蓋章格與足跡幣統計卡共用同一張 asset）。
  Finder pawImages() => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName ==
            'assets/icon/ui/paw_footprint_coin.png',
  );

  Future<void> pumpProfile(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      const MaterialApp(home: MascotProfilePage()),
    );
    // 等 prefs / 金幣 / 回憶本非同步載完（呼吸動畫不停，不能 settle）。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('名片：名字、相識天數、足跡幣都在，點擊觸發 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: MascotCallingCard(
              name: '小白',
              companionDays: 128,
              coinBalance: 86,
              onTap: () => tapped++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('小白'), findsOneWidget);
    expect(find.text('相識第 128 天', findRichText: true), findsOneWidget);
    expect(find.text('86'), findsOneWidget);

    await tester.tap(find.byType(MascotCallingCard));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('檔案頁 SE 尺寸：落款、報到卡進度、統計卡、敘述句不破版', (tester) async {
    final onboarding = DateTime.now().subtract(const Duration(days: 9));
    SharedPreferences.setMockInitialValues({
      'mascot_name': '小白',
      'onboarding_date': onboarding.toIso8601String(),
      'coin_login_streak': 12,
      'coin_balance': 86,
    });
    await pumpProfile(tester, size: const Size(320, 568));

    expect(find.text('小白'), findsOneWidget);
    expect(find.text('相識第 10 天', findRichText: true), findsOneWidget);
    // 第 12 天 → 循環第 5 格；加上足跡幣統計卡那枚 = 6 張腳印幣圖。
    expect(pawImages(), findsNWidgets(6));
    expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
    expect(find.text('連續 12 天'), findsOneWidget);
    expect(find.text('第 2 輪'), findsOneWidget);
    // SE 上統計卡與敘述句在摺疊線以下，捲到底驗證（同時證明捲得到）。
    await tester.scrollUntilVisible(
      find.text('走過的每一天，都有留下足跡。'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('足跡幣'), findsOneWidget);
    expect(find.text('回憶本'), findsOneWidget);
    expect(find.text('0 冊'), findsOneWidget);
    expect(find.text('走過的每一天，都有留下足跡。'), findsOneWidget);
  });

  testWidgets('還沒開始報到：空格全虛線＋開始提示', (tester) async {
    SharedPreferences.setMockInitialValues({'mascot_name': '兔咪'});
    await pumpProfile(tester, size: const Size(390, 844));

    // 只剩足跡幣統計卡那一枚腳印幣圖，報到卡 7 格全空。
    expect(pawImages(), findsOneWidget);
    expect(find.text('連續 0 天'), findsOneWidget);
    expect(find.text('第一個腳印，今天打開就能蓋。'), findsOneWidget);
    expect(find.textContaining('輪'), findsNothing);
  });

  testWidgets('編輯鈕開啟編輯基本資料頁', (tester) async {
    SharedPreferences.setMockInitialValues({'mascot_name': '兔咪'});
    await pumpProfile(tester, size: const Size(390, 844));

    await tester.tap(find.byTooltip('改名字'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(ProfileEditPage), findsOneWidget);
  });
}
