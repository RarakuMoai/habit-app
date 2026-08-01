// 兔咪身上「打卡演出」那幾個動作參數的實際位移。
//
// home_completion_test 守的是「首頁在第幾毫秒送出哪一拍」；這裡守的是
// 「送出去之後兔咪真的動了、而且動的幅度是克制的、撤銷得掉」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home/completion_presentation_controller.dart';
import 'package:habit_app/pages/home/completion_timing.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/mascot_scene.dart';

const String _asset = 'assets/mascot/core/tumi_neutral_front.png';
const String _asset2 = 'assets/mascot/core/tumi_expect.png';

Future<void> _pumpStage(
  WidgetTester tester, {
  String asset = _asset,
  int reactionTick = 0,
  int noticeTick = 0,
  double reactionStrength = 1.0,
  int reactionCancelUpTo = -1,
  MascotPoseTransition poseTransition = MascotPoseTransition.crossFade,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MascotStage(
            asset: asset,
            poseTransition: poseTransition,
            reduceMotion: reduceMotion,
            accent: Colors.orange,
            reactionTick: reactionTick,
            noticeTick: noticeTick,
            reactionStrength: reactionStrength,
            reactionCancelUpTo: reactionCancelUpTo,
            onTap: () {},
            // 凍結呼吸/眨眼：留下來的縱向位移就只會來自打卡演出本身。
            paused: true,
          ),
        ),
      ),
    ),
  );
}

/// 兔咪本體目前在畫面上的縱向位置（越小＝越高）。
double _bodyTop(WidgetTester tester, [String asset = _asset]) =>
    tester.getTopLeft(find.byKey(ValueKey(asset))).dy;

/// 沒有任何一張立繪處於半透明（會透出背景＝雙影）。
void _expectNoTranslucentPose(WidgetTester tester) {
  final opacities = <double>[];
  for (final el
      in find
          .descendant(
            of: find.byType(MascotStage),
            matching: find.byType(Padding),
          )
          .evaluate()) {
    if ((el.widget as Padding).key is! ValueKey<String>) continue;
    var opacity = 1.0;
    el.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition) {
        opacity = widget.opacity.value;
        return false;
      }
      return widget is! MascotStage;
    });
    opacities.add(opacity);
  }
  expect(
    opacities.where((o) => o > 0.05 && o < 0.95),
    isEmpty,
    reason: '不得出現半透明立繪（實際：$opacities）',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('察覺是往下沉一點點，而且很快回正', (tester) async {
    await _pumpStage(tester);
    final rest = _bodyTop(tester);

    await _pumpStage(tester, noticeTick: 1);
    await tester.pump(const Duration(milliseconds: 120));
    final sunk = _bodyTop(tester);

    expect(sunk, greaterThan(rest), reason: '察覺是「沉一下」不是彈起來');
    expect(sunk - rest, lessThan(4.0), reason: '只允許 2–3px 級別；再大就變成預備動作了');

    await tester.pump(const Duration(milliseconds: 200));
    expect(_bodyTop(tester), closeTo(rest, 0.5), reason: '察覺跑完要回正');
  });

  testWidgets('打卡的小跳幅度比直接點兔咪克制', (tester) async {
    await _pumpStage(tester);
    final rest = _bodyTop(tester);

    await _pumpStage(tester, reactionTick: 1);
    await tester.pump(const Duration(milliseconds: 300));
    final fullLift = rest - _bodyTop(tester);
    await tester.pump(const Duration(milliseconds: 800));

    await _pumpStage(tester, reactionTick: 2, reactionStrength: 0.62);
    await tester.pump(const Duration(milliseconds: 300));
    final mutedLift = rest - _bodyTop(tester);
    await tester.pump(const Duration(milliseconds: 800));

    expect(fullLift, greaterThan(0), reason: '完整幅度真的會離地');
    expect(mutedLift, greaterThan(0), reason: '打卡仍然看得出動作');
    expect(mutedLift, lessThan(fullLift), reason: '普通完成不該跟直接互動一樣大聲');
  });

  testWidgets('幅度在觸發那一刻定住，中途改參數不會讓動作瞬間變大', (tester) async {
    await _pumpStage(tester);
    final rest = _bodyTop(tester);

    await _pumpStage(tester, reactionTick: 1, reactionStrength: 0.62);
    await tester.pump(const Duration(milliseconds: 300));
    final before = _bodyTop(tester);

    // 只改幅度、不換 tick：正在跑的動作不該被影響。
    await _pumpStage(tester, reactionTick: 1);
    expect(_bodyTop(tester), closeTo(before, 0.01));
    expect(rest - before, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('撤銷會把還在空中的小跳收回地面', (tester) async {
    await _pumpStage(tester);
    final rest = _bodyTop(tester);

    await _pumpStage(tester, reactionTick: 1, reactionStrength: 0.62);
    await tester.pump(const Duration(milliseconds: 260));
    expect(_bodyTop(tester), lessThan(rest), reason: '此刻應該在空中');

    await _pumpStage(
      tester,
      reactionTick: 1,
      reactionStrength: 0.62,
      reactionCancelUpTo: 1,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(_bodyTop(tester), closeTo(rest, 0.5), reason: '撤銷後不該繼續完成過時的跳躍');
  });

  test('局部粒子維持個位數，打卡版本更少', () {
    expect(mascotSparkleCountFor(1.0), 6);
    expect(mascotSparkleCountFor(0.62), 4);
    expect(mascotSparkleCountFor(0.62), lessThan(mascotSparkleCountFor(1.0)));
    for (final s in [0.0, 0.3, 0.62, 1.0]) {
      expect(
        mascotSparkleCountFor(s),
        lessThanOrEqualTo(8),
        reason: '局部特效上限 8 顆（§16）',
      );
    }
  });

  test('silent 的姿勢切換不冒泡泡、不出聲', () {
    final voices = <Object>[];
    MascotPersona.debugVoiceSink = voices.add;
    addTearDown(() => MascotPersona.debugVoiceSink = null);
    MascotPersona.resetToIdle();
    MascotPersona.debugResetVoiceCooldowns();

    MascotPersona.setForContext(
      MascotEmotion.expect.assetPath,
      MascotContext.completedOne,
      silent: true,
      force: true,
    );
    expect(MascotPersona.current.value.bubble, isNull);
    expect(MascotPersona.current.value.speech, isNull);
    expect(voices, isEmpty);

    // 同一個情境，這次要冒泡泡與出聲
    MascotPersona.setForContext(
      MascotEmotion.expect.assetPath,
      MascotContext.completedOne,
      force: true,
    );
    expect(MascotPersona.current.value.bubble, EmotionBubble.note);
    expect(voices, hasLength(1));
  });

  test('silent 也不會從台詞池自己補一句', () {
    MascotPersona.debugVoiceSink = (_) {};
    addTearDown(() => MascotPersona.debugVoiceSink = null);
    MascotPersona.resetToIdle();

    // notStarted 是「會講話」的情境；silent 時仍然要安靜。
    expect(MascotLines.speaksFor(MascotContext.notStarted), isTrue);
    MascotPersona.setForContext(
      MascotEmotion.sleep.assetPath,
      MascotContext.notStarted,
      silent: true,
      force: true,
    );
    expect(MascotPersona.current.value.speech, isNull);
    expect(MascotPersona.current.value.bubble, isNull);
  });

  // ── Blocker 6：換立繪的過場 ─────────────────────────────────

  group('打卡換立繪', () {
    testWidgets('cut 模式不會讓兩張完整立繪同時存在', (tester) async {
      await _pumpStage(tester, poseTransition: MascotPoseTransition.cut);
      expect(find.byKey(const ValueKey(_asset)), findsOneWidget);

      await _pumpStage(
        tester,
        asset: _asset2,
        poseTransition: MascotPoseTransition.cut,
      );
      expect(find.byKey(const ValueKey(_asset2)), findsOneWidget);
      // 第一幀允許舊立繪還在（完全不透明，用來蓋住新圖尚未解圖的那一格），
      // 但不能是半透明——半透明疊在一起才會透出背景變成鬼影。
      _expectNoTranslucentPose(tester);

      // 下一幀起就只剩一張，整段沉降期間都不再有第二張
      await tester.pump(const Duration(milliseconds: 20));
      for (final ms in [20, 60, 120, 200]) {
        expect(
          find.byKey(const ValueKey(_asset)),
          findsNothing,
          reason: '$ms ms 時仍不得有第二張',
        );
        _expectNoTranslucentPose(tester);
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    testWidgets('對照組：交叉淡入模式中段確實兩張並存', (tester) async {
      await _pumpStage(tester);
      await _pumpStage(tester, asset: _asset2);
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.byKey(const ValueKey(_asset)),
        findsOneWidget,
        reason: '這就是原本會出現雙影的預設行為（其他頁面維持不變）',
      );
      expect(find.byKey(const ValueKey(_asset2)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('cut 的沉降不 overshoot，腳也不跳位', (tester) async {
      await _pumpStage(tester, poseTransition: MascotPoseTransition.cut);
      final rest = _bodyTop(tester);

      await _pumpStage(
        tester,
        asset: _asset2,
        poseTransition: MascotPoseTransition.cut,
      );
      await tester.pump(const Duration(milliseconds: 20));
      final compressed = _bodyTop(tester, _asset2);
      expect(compressed, greaterThan(rest), reason: '沉降是往下壓一點點，不是彈起來');
      expect(compressed - rest, lessThan(6.0), reason: '幅度必須很小');

      // 全程不得超過原位（沒有 back curve、沒有 overshoot）
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          _bodyTop(tester, _asset2),
          greaterThanOrEqualTo(rest - 0.5),
          reason: 'Reduce Motion 也走這條，不允許 overshoot',
        );
      }
      expect(_bodyTop(tester, _asset2), closeTo(rest, 0.5));
    });

    testWidgets('Reduce Motion：換圖仍是離散的，但完全不沉降', (tester) async {
      await _pumpStage(
        tester,
        poseTransition: MascotPoseTransition.cut,
        reduceMotion: true,
      );
      final rest = _bodyTop(tester);

      await _pumpStage(
        tester,
        asset: _asset2,
        poseTransition: MascotPoseTransition.cut,
        reduceMotion: true,
      );
      expect(find.byKey(const ValueKey(_asset2)), findsOneWidget);
      _expectNoTranslucentPose(tester);

      // 整段期間縱向位置完全不動：沒有 scale、沒有 sink、沒有位移。
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          _bodyTop(tester, _asset2),
          closeTo(rest, 0.01),
          reason: 'Reduce Motion 下 completion 的 body 位移必須為零',
        );
      }
    });

    test('Reduce Motion 的衝擊點與縮短後的勾勾終點是同一個時間', () {
      expect(
        CompletionPresentationController.kReducedImpactDelay,
        kCheckDrawDurationReduced,
      );
      expect(CompletionPresentationController.kImpactDelay, kCheckDrawDuration);
    });

    test('沉降長度非零且不使用 back 曲線的 overshoot 範圍', () {
      expect(kMascotPoseCutSettle, greaterThan(Duration.zero));
      expect(kMascotPoseCutSettleScale, lessThan(1.0));
      expect(
        kMascotPoseCutSettleScale,
        greaterThan(0.95),
        reason: '只是很小的沉降，不是縮成一點',
      );
    });
  });
}
