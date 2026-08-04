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

  test('每日登入短樂句、蓋章、吸入與逐枚入袋音已收入 asset bundle', () async {
    for (final cue in [
      SfxCue.loginStreakIntro,
      SfxCue.footprintStamp,
      SfxCue.footprintCoinAbsorb,
      SfxCue.footprintCoinTick,
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

  // 閒置凍結是省電決定，不會改；但停在一雙睜著不眨的眼睛會讀成畫面當掉。
  // 先慢慢闔上眼再靜止，靜止就變成「牠等著等著睡著了」。
  group('閒置凍結前先打瞌睡', () {
    // 閉眼差分那一層現在的不透明度；找不到回 -1。
    double closedEyeOpacity(WidgetTester tester, String basePath) {
      final blink = MascotEmotion.blinkAssetForPath(basePath)!;
      for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
        final child = o.child;
        if (child is Image) {
          final img = child.image;
          if (img is AssetImage && img.assetName == blink) return o.opacity;
        }
      }
      return -1;
    }

    Future<void> pumpPaused(WidgetTester tester, {required bool paused}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MascotStage(
                // neutralFront 是目前唯一有閉眼差分的立繪。
                asset: MascotEmotion.neutralFront.assetPath,
                accent: Colors.orange,
                reactionTick: 0,
                onTap: () {},
                paused: paused,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('凍結時眼睛慢慢闔上，回來時再睜開', (tester) async {
      final base = MascotEmotion.neutralFront.assetPath;

      await pumpPaused(tester, paused: false);
      expect(closedEyeOpacity(tester, base), 0, reason: '醒著時眼睛是睜的');

      await pumpPaused(tester, paused: true);
      // 淡入途中：已經在闔，但還沒闔滿——證明是漸變不是瞬間跳圖。
      await tester.pump(const Duration(milliseconds: 200));
      final mid = closedEyeOpacity(tester, base);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pump(const Duration(milliseconds: 400));
      expect(closedEyeOpacity(tester, base), 1, reason: '凍結時停在闔眼');

      await pumpPaused(tester, paused: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(closedEyeOpacity(tester, base), 0, reason: '一有互動就睜開');
      await pumpPaused(tester, paused: true);
    });

    testWidgets('一開始就是凍結狀態：直接落在闔眼，不補播淡入', (tester) async {
      await pumpPaused(tester, paused: true);
      expect(
        closedEyeOpacity(tester, MascotEmotion.neutralFront.assetPath),
        1,
      );
    });
  });

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

  // ── 換立繪過場 × 分頁切換 ──
  // 七個兔咪頁常駐 IndexedStack，沒被選到的由 TickerMode 靜音；靜音的 ticker
  // 不推進動畫，換立繪的交叉淡入若照跑就會凍在「舊立繪不透明、新立繪全透明」，
  // 切回那一頁的第一幀先閃出上一個動作（多半是預設站姿）。
  Future<void> pumpTabbedStage(
    WidgetTester tester, {
    required bool visible,
    required String asset,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TickerMode(
              enabled: visible, // false = 這一頁被收在 IndexedStack 裡
              child: MascotStage(
                asset: asset,
                accent: Colors.orange,
                reactionTick: 0,
                onTap: () {},
                paused: true, // 凍結呼吸/眨眼，避免測試殘留 pending timer
              ),
            ),
          ),
        ),
      ),
    );
  }

  final neutralAsset = MascotEmotion.neutralFront.assetPath;
  final sleepAsset = MascotEmotion.sleep.assetPath;

  testWidgets('在別的分頁時換立繪：切回來的第一幀就是新立繪', (tester) async {
    await pumpTabbedStage(tester, visible: false, asset: neutralAsset);
    await pumpTabbedStage(tester, visible: false, asset: sleepAsset);
    await tester.pump();
    expect(
      find.image(AssetImage(neutralAsset)),
      findsNothing,
      reason: '靜音時換圖不該把舊立繪凍在樹上',
    );

    // 切回這一頁：第一幀（還沒 pump 動畫）就該是新立繪
    await pumpTabbedStage(tester, visible: true, asset: sleepAsset);
    expect(find.image(AssetImage(sleepAsset)), findsOneWidget);
    expect(find.image(AssetImage(neutralAsset)), findsNothing);
  });

  testWidgets('過場跑到一半切走分頁：切回來不留舊立繪殘影', (tester) async {
    await pumpTabbedStage(tester, visible: true, asset: neutralAsset);
    await pumpTabbedStage(tester, visible: true, asset: sleepAsset);
    await tester.pump(const Duration(milliseconds: 100)); // 交叉淡入跑到一半
    expect(find.image(AssetImage(neutralAsset)), findsOneWidget);

    await pumpTabbedStage(tester, visible: false, asset: sleepAsset); // 切走
    await tester.pump();
    await pumpTabbedStage(tester, visible: true, asset: sleepAsset); // 切回
    expect(find.image(AssetImage(neutralAsset)), findsNothing);
  });

  testWidgets('分頁在前景時換立繪仍走交叉淡入', (tester) async {
    await pumpTabbedStage(tester, visible: true, asset: neutralAsset);
    await pumpTabbedStage(tester, visible: true, asset: sleepAsset);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.image(AssetImage(neutralAsset)),
      findsOneWidget,
      reason: '看得見的時候舊立繪要淡出，不是硬切',
    );

    await tester.pumpAndSettle();
    expect(find.image(AssetImage(neutralAsset)), findsNothing);
    expect(find.image(AssetImage(sleepAsset)), findsOneWidget);
  });
}
