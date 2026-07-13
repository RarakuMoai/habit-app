import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/scene_time.dart';
import 'package:habit_app/widgets/four_period_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SceneTimeController? controller;

  Future<void> pumpAt(WidgetTester tester, DateTime now) async {
    controller = SceneTimeController(clock: () => now);
    SceneTimeController.debugInstance = controller;
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 390,
          height: 488,
          child: FourPeriodBackground(assets: kHomePeriodAssets),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() {
    controller?.dispose();
    controller = null;
    SceneTimeController.debugInstance = null;
  });

  List<String> assetNames(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => (image.image as AssetImage).assetName)
      .toList();

  test('首頁四時段資產命名完整且互不重複', () {
    expect(ScenePeriod.values.map(kHomePeriodAssets.of), <String>{
      'assets/scenes/home/home_morning.webp',
      'assets/scenes/home/home_day.webp',
      'assets/scenes/home/home_dusk.webp',
      'assets/scenes/home/home_night.webp',
    });
  });

  testWidgets('純白天顯示白天底圖並預載下一張黃昏圖', (tester) async {
    await pumpAt(tester, DateTime(2026, 7, 13, 13));

    expect(assetNames(tester), [kHomePeriodAssets.day, kHomePeriodAssets.dusk]);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
  });

  testWidgets('白天至黃昏交界以相鄰兩張圖平滑交疊', (tester) async {
    await pumpAt(tester, DateTime(2026, 7, 13, 17, 22, 30));

    expect(assetNames(tester), [kHomePeriodAssets.day, kHomePeriodAssets.dusk]);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(0.5, 1e-9),
    );
  });

  testWidgets('跨序夜晚至清晨交界仍使用相鄰圖層', (tester) async {
    await pumpAt(tester, DateTime(2026, 7, 13, 5, 22, 30));

    expect(assetNames(tester), [
      kHomePeriodAssets.night,
      kHomePeriodAssets.morning,
    ]);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(0.5, 1e-9),
    );
  });
}
