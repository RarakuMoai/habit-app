import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/dev_test_page.dart';
import 'package:habit_app/utils/coin_config.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SceneTimeController sceneTime;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sceneTime = SceneTimeController(clock: () => DateTime(2026, 7, 13, 13));
    SceneTimeController.debugInstance = sceneTime;
  });

  tearDown(() {
    sceneTime.dispose();
    SceneTimeController.debugInstance = null;
  });

  testWidgets('場景預覽使用正式四時段與 50/50 交界，原始統計不再佔據頁首', (tester) async {
    await tester.pumpWidget(l10nTestApp(home: const DevTestPage()));
    await tester.pumpAndSettle();

    expect(find.text('使用統計（本機匿名）'), findsNothing);
    expect(find.text('足跡幣（測試）'), findsOneWidget);
    for (final amount in [1, 5, 10, 100]) {
      expect(find.text('+$amount'), findsOneWidget);
    }
    expect(find.text('+50'), findsNothing);

    final list = find.byType(ListView);
    for (var i = 0; i < 5 && find.text('場景時段').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    expect(find.text('場景時段'), findsOneWidget);
    expect(find.text('清晨 06:30'), findsOneWidget);
    expect(find.text('白天 13:00'), findsOneWidget);
    expect(find.text('黃昏 17:30'), findsOneWidget);
    expect(find.text('夜晚 23:00'), findsOneWidget);
    expect(find.text('晝→暮 16:30:00'), findsOneWidget);

    await tester.tap(find.text('晝→暮 16:30:00'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PrefsKeys.debugSceneHour), 16.5);
    expect(find.text('16:30'), findsOneWidget);
  });

  testWidgets('快轉日子會重開當日登入獎勵並可再觸發報到', (tester) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.coinLastLoginDate: today,
      PrefsKeys.coinLoginLevel: 2,
      PrefsKeys.coinLoginStreak: 2,
      PrefsKeys.coinClaim(CoinSource.dailyLogin.name, today): true,
      PrefsKeys.coinClaim(CoinSource.weeklyStreak.name, today): true,
    });

    await tester.pumpWidget(l10nTestApp(home: const DevTestPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('快轉一天'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('快轉一天'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(PrefsKeys.coinClaim(CoinSource.dailyLogin.name, today)),
      isNull,
    );
    expect(
      prefs.getBool(PrefsKeys.coinClaim(CoinSource.weeklyStreak.name, today)),
      isNull,
    );
    final reward = await CoinService.claimDailyLogin(now: now);
    expect(reward, isNotNull);
    expect(reward!.level, 3);
  });
}
