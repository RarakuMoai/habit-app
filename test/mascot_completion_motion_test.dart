// 兔咪身上「打卡演出」那幾個動作參數的實際位移。
//
// home_completion_test 守的是「首頁在第幾毫秒送出哪一拍」；這裡守的是
// 「送出去之後兔咪真的動了、而且動的幅度是克制的、撤銷得掉」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/widgets/mascot_scene.dart';

const String _asset = 'assets/mascot/core/tumi_neutral_front.png';

Future<void> _pumpStage(
  WidgetTester tester, {
  int reactionTick = 0,
  int noticeTick = 0,
  double reactionStrength = 1.0,
  int reactionCancelTick = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MascotStage(
            asset: _asset,
            accent: Colors.orange,
            reactionTick: reactionTick,
            noticeTick: noticeTick,
            reactionStrength: reactionStrength,
            reactionCancelTick: reactionCancelTick,
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
double _bodyTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey(_asset))).dy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('察覺是往下沉一點點，而且很快回正', (tester) async {
    await _pumpStage(tester);
    final rest = _bodyTop(tester);

    await _pumpStage(tester, noticeTick: 1);
    await tester.pump(const Duration(milliseconds: 120));
    final sunk = _bodyTop(tester);

    expect(sunk, greaterThan(rest), reason: '察覺是「沉一下」不是彈起來');
    expect(
      sunk - rest,
      lessThan(4.0),
      reason: '只允許 2–3px 級別；再大就變成預備動作了',
    );

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
    expect(
      mutedLift,
      lessThan(fullLift),
      reason: '普通完成不該跟直接互動一樣大聲',
    );
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
      reactionCancelTick: 1,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      _bodyTop(tester),
      closeTo(rest, 0.5),
      reason: '撤銷後不該繼續完成過時的跳躍',
    );
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
}
