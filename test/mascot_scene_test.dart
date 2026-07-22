// 充電互動（長按蓄力放開）的手勢層測試：
// 驗證長按/放開/蓄滿自動爆發會觸發 onEnergize，且不搶原本的摸頭手勢。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/widgets/mascot_bubbles.dart';
import 'package:habit_app/widgets/mascot_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('摸頭主愛心比原版多停留 0.3 秒', () {
    expect(
      bubbleSpecFor(EmotionBubble.heart).duration,
      const Duration(milliseconds: 2400),
    );
  });

  test('搓動產生的小愛心延長約 0.3 秒', () {
    expect(mascotPetHeartLifetime, const Duration(milliseconds: 1130));
  });

  test('集氣、跳躍與摸頭動作音均已收入 asset bundle', () async {
    for (final cue in [SfxCue.tumiCharge, SfxCue.tumiJump, SfxCue.tumiPet]) {
      final data = await rootBundle.load(cue.assetPath);
      expect(data.lengthInBytes, greaterThan(1000), reason: cue.assetPath);
    }
  });

  test('足跡幣三段演出音已收入 asset bundle', () async {
    for (final cue in [
      SfxCue.footprintCoinScatter,
      SfxCue.footprintCoinAbsorb,
      SfxCue.footprintCoinReward,
    ]) {
      final data = await rootBundle.load(cue.assetPath);
      expect(data.lengthInBytes, greaterThan(1000), reason: cue.assetPath);
    }
  });

  Future<void> pumpStage(
    WidgetTester tester, {
    VoidCallback? onEnergize,
    VoidCallback? onHeadPet,
    MascotSceneLighting? lighting,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MascotStage(
              asset: MascotEmotion.neutralFront.assetPath,
              accent: Colors.orange,
              reactionTick: 0,
              onTap: () {},
              onHeadPet: onHeadPet,
              onEnergize: onEnergize,
              lighting: lighting,
              // 凍結呼吸/眨眼，避免測試殘留 pending timer
              paused: true,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('環境光參數只濾兔咪本體，中性路徑不增加濾鏡', (tester) async {
    await pumpStage(tester);
    expect(find.byType(ColorFiltered), findsNothing);

    await pumpStage(
      tester,
      lighting: const MascotSceneLighting(
        colorMatrix: <double>[
          1.02, 0, 0, 0, 5, //
          0, 0.96, 0, 0, 1, //
          0, 0, 0.90, 0, -4, //
          0, 0, 0, 1, 0,
        ],
        shadowColor: Color(0xFF6F4529),
        shadowOpacity: 0.25,
        shadowDx: -6,
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('長按蓄力後放開觸發一次 onEnergize', (tester) async {
    var energized = 0;
    await pumpStage(tester, onEnergize: () => energized++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MascotStage)),
    );
    await tester.pump(const Duration(milliseconds: 600)); // 過長按門檻
    await tester.pump(const Duration(milliseconds: 400)); // 蓄一點力
    expect(energized, 0, reason: '蓄力中還不該爆發');

    await gesture.up();
    await tester.pump();
    expect(energized, 1);

    await tester.pumpAndSettle(); // 跑完爆發動畫
  });

  testWidgets('蓄滿自動爆發，之後放開不會再觸發第二次', (tester) async {
    var energized = 0;
    await pumpStage(tester, onEnergize: () => energized++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MascotStage)),
    );
    await tester.pump(const Duration(milliseconds: 600)); // 過長按門檻
    await tester.pump(const Duration(milliseconds: 1300)); // 超過 1.1s 蓄滿
    expect(energized, 1, reason: '蓄滿應自動爆發');

    await gesture.up();
    await tester.pump();
    expect(energized, 1);

    await tester.pumpAndSettle();
  });

  testWidgets('快點頭部＝一般點擊反應，不算摸頭也不觸發充電', (tester) async {
    var energized = 0;
    var petted = 0;
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MascotStage(
              asset: MascotEmotion.neutralFront.assetPath,
              accent: Colors.orange,
              reactionTick: 0,
              onTap: () => tapped++,
              onHeadPet: () => petted++,
              onEnergize: () => energized++,
              paused: true,
            ),
          ),
        ),
      ),
    );

    // 頭部命中區中心（stage 內座標 126,88）快速點一下
    final topLeft = tester.getTopLeft(find.byType(MascotStage));
    await tester.tapAt(topLeft + const Offset(126, 88));
    await tester.pump();

    expect(tapped, 1);
    expect(petted, 0);
    expect(energized, 0);

    await tester.pumpAndSettle();
  });

  testWidgets('點 stage 角落空白處：點擊/充電都不反應', (tester) async {
    var energized = 0;
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MascotStage(
              asset: MascotEmotion.neutralFront.assetPath,
              accent: Colors.orange,
              reactionTick: 0,
              onTap: () => tapped++,
              onEnergize: () => energized++,
              paused: true,
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(MascotStage));
    // 左上角空白
    await tester.tapAt(topLeft + const Offset(12, 12));
    await tester.pump();
    expect(tapped, 0);

    // 空白處長按也不會開始蓄力
    final gesture = await tester.startGesture(topLeft + const Offset(12, 12));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump();
    expect(energized, 0);

    // 對照組：兔咪身上點一下有反應
    await tester.tapAt(topLeft + const Offset(126, 126));
    await tester.pump();
    expect(tapped, 1);

    await tester.pumpAndSettle();
  });

  testWidgets('頭上搓動＝摸頭，放開才通知一次', (tester) async {
    var petted = 0;
    var energized = 0;
    await pumpStage(
      tester,
      onHeadPet: () => petted++,
      onEnergize: () => energized++,
    );

    // 從頭部中心開始左右搓動（先超過 touch slop 讓 pan 成立）
    final topLeft = tester.getTopLeft(find.byType(MascotStage));
    final gesture = await tester.startGesture(topLeft + const Offset(126, 88));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(i.isEven ? -30 : 30, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(petted, 0, reason: '搓動途中不該提前通知');

    await gesture.up();
    await tester.pump();
    expect(petted, 1);
    expect(energized, 0);

    await tester.pumpAndSettle(); // 等愛心飄完、彈簧歸位、驅動器自停
  });
}
