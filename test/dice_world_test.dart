// 骰盤物理公平性：蒙地卡羅模擬 + 卡方檢定。
//
// 點數由物理決定（不是亂數），所以「夠不夠隨機」要用統計驗證：
// - 擲骰鈕：隨機方向/力道/自旋 → 六面應接近均勻（卡方檢定）。
// - 對抗性手甩：固定起始姿態、同方向同力道、不碰牆的直線輕甩——
//   沒有離手隨機自旋/滾動微擾時只會在 4 個面循環甚至可瞄面，
//   補強後六面都要出得來且無法穩定預測。
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/dice_world.dart';

const _dt = 1.0 / 60;

/// 空指針陣列 step 到 settled，回傳用掉的步數。
int _runUntilSettled(DiceWorld w, {int maxSteps = 3000}) {
  for (var i = 0; i < maxSteps; i++) {
    w.step(_dt, const []);
    if (w.settled) return i;
  }
  fail('骰子 $maxSteps 步沒停（物理停定壞了）');
}

/// 卡方統計量（對均勻分布，df = 5）。
double _chiSquare(List<int> counts) {
  final total = counts.reduce((a, b) => a + b);
  final expected = total / counts.length;
  var chi = 0.0;
  for (final c in counts) {
    chi += (c - expected) * (c - expected) / expected;
  }
  return chi;
}

void main() {
  test('擲骰鈕單顆：六面分布通過卡方檢定', () {
    final w = DiceWorld(rng: math.Random(42));
    w.setBounds(const Rect.fromLTRB(0, 62, 390, 676), 92);
    w.spawn(1);

    const trials = 1500;
    final counts = List.filled(6, 0);
    for (var t = 0; t < trials; t++) {
      w.throwAll();
      _runUntilSettled(w);
      counts[w.dice[0].value - 1]++;
    }

    final chi = _chiSquare(counts);
    // ignore: avoid_print
    print('擲骰鈕單顆 counts=$counts chi2=${chi.toStringAsFixed(2)}');
    // df=5、α=0.001 的臨界值 20.5；物理骰允許輕微偏差，門檻放 25
    expect(chi, lessThan(25), reason: '單顆分布偏離均勻：$counts');
    for (final c in counts) {
      expect(c, greaterThan(trials ~/ 6 ~/ 2), reason: '有面明顯出不來：$counts');
    }
  });

  test('擲骰鈕雙顆（含互撞路徑）：六面分布通過卡方檢定', () {
    final w = DiceWorld(rng: math.Random(7));
    w.setBounds(const Rect.fromLTRB(0, 62, 390, 676), 92);
    w.spawn(2);

    const trials = 700;
    final counts = List.filled(6, 0);
    for (var t = 0; t < trials; t++) {
      w.throwAll();
      _runUntilSettled(w);
      for (final d in w.dice) {
        counts[d.value - 1]++;
      }
    }

    final chi = _chiSquare(counts);
    // ignore: avoid_print
    print('擲骰鈕雙顆 counts=$counts chi2=${chi.toStringAsFixed(2)}');
    expect(chi, lessThan(25), reason: '雙顆分布偏離均勻：$counts');
  });

  test('對抗性直線輕甩（固定姿態/方向/力道、不碰牆）：無法控骰', () {
    final w = DiceWorld(rng: math.Random(1234));
    // 超大場地：這種輕甩滑行 ~300px，永遠碰不到牆——最有利於控骰的情境
    w.setBounds(const Rect.fromLTRB(0, 0, 2400, 1600), 92);
    w.spawn(1);

    const trials = 900;
    final counts = List.filled(6, 0);
    for (var t = 0; t < trials; t++) {
      final d = w.dice[0];
      w.wake();
      d.pos = const Offset(400, 800);
      d.q = DiceQuat.identity(); // 每次都從「1 朝上」開始
      d.vel = const Offset(320, 0); // 同方向同力道
      d.wx = 0;
      d.wy = 0;
      d.wz = 0;
      d.tiltT = 0;
      d.popT = 0;
      w.releaseBurst();
      _runUntilSettled(w);
      counts[d.value - 1]++;
    }

    // ignore: avoid_print
    print(
      '對抗性直線甩 counts=$counts chi2=${_chiSquare(counts).toStringAsFixed(2)}',
    );
    // 重點不是完美均勻（同一動作重複本來就有慣性），是「六面都出得來、
    // 沒有一面可以穩定押注」：每面至少 5%、最大面不超過 40%
    for (var v = 0; v < 6; v++) {
      expect(
        counts[v],
        greaterThan((trials * 0.05).round()),
        reason: '第 ${v + 1} 面幾乎出不來（可被排除下注）：$counts',
      );
    }
    expect(
      counts.reduce(math.max),
      lessThan((trials * 0.40).round()),
      reason: '有面出現率過高（可穩定押注）：$counts',
    );
  });
}
