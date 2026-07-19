import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/dev_test_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await tester.pumpWidget(const MaterialApp(home: DevTestPage()));
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
}
