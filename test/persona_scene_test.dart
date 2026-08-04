import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/mascot_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void resetPersona() {
    MascotPersona.debugResetVoiceCooldowns();
    // 收尾要的是「乾淨的中性待機」，不是模擬一次冷啟動——resetToOpening 會抽
    // 一句問候並排回神計時器，測試樹拆掉後那個 timer 會變成 pending。
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = true;
  }

  setUp(resetPersona);
  tearDown(() {
    MascotPersona.debugResetVoiceCooldowns();
    // 收尾要的是「乾淨的中性待機」，不是模擬一次冷啟動——resetToOpening 會抽
    // 一句問候並排回神計時器，測試樹拆掉後那個 timer 會變成 pending。
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = false;
  });

  // 實際使用時 PersonaScene 永遠在 MascotPageShell 的場景區裡（14PM：
  // 430 寬 × ~323 高，mascotStageScale == 1）。測試面 800×600 直接鋪滿
  // 會觸發寬度縮放、tap 座標跟著變換，所以用真實區域尺寸包起來。
  Widget sceneHarness(Widget scene) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 430, height: 323, child: scene)),
    ),
  );

  testWidgets('PersonaScene 未傳 onTap 時使用共用兔咪點擊反應', (tester) async {
    await tester.pumpWidget(
      sceneHarness(const PersonaScene(accent: Colors.orange, paused: true)),
    );

    final topLeft = tester.getTopLeft(find.byType(MascotStage));
    await tester.tapAt(topLeft + const Offset(126, 126));
    await tester.pump();

    expect(MascotPersona.current.value.bubble, EmotionBubble.question);
    MascotPersona.resetToIdle();
  });

  testWidgets('PersonaScene 有自訂 onTap 時不重複套用預設反應', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      sceneHarness(
        PersonaScene(
          accent: Colors.orange,
          onTap: () => tapped++,
          paused: true,
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(MascotStage));
    await tester.tapAt(topLeft + const Offset(126, 126));
    await tester.pump();

    expect(tapped, 1);
    expect(MascotPersona.current.value.bubble, isNull);
  });
}
