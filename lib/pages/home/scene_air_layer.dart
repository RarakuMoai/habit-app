// 首頁四時段背景的「空氣層」：讓完整 CG 背景多一口呼吸，不重畫任何光影。
//
// 只做兩件事，且都錨定在背景圖已經畫好的位置上：
//   1. 塵埃微粒：沿清晨圖窗光光束的方向緩慢漂浮（清晨最明顯、白天極淡、
//      黃昏夜晚沒有）。光束本身是圖畫的，塵埃只是「浮在光裡」。
//   2. 星光眨眼：夜圖窗內六顆星星的精確座標上，疊極小的閃爍亮點，
//      各自相位、慢速呼吸。月亮與天空不動。
//
// 原則（計劃書）：背景已畫得自然的部分不重複堆效果——所以沒有光束、
// 沒有燈暈、沒有色罩，只有這兩種「圖畫不出來的微動態」。
//
// 效能：單一 CustomPaint、無 blur、≤18 個小圓點；由首頁共享的
// SceneAnimationClock（20fps）驅動，閒置凍結時一起停；時段權重讓
// 純黃昏時整層什麼都不畫。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/scene_time.dart';

class SceneAirLayer extends StatelessWidget {
  /// 共享場景時鐘（SceneAnimationClock.time）。
  final ValueNotifier<double> clock;

  const SceneAirLayer({super.key, required this.clock});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SceneAirPainter(time: clock),
        ),
      ),
    );
  }
}

class _SceneAirPainter extends CustomPainter {
  final ValueNotifier<double> time;

  _SceneAirPainter({required this.time})
    : super(repaint: Listenable.merge([time, SceneTimeController.instance]));

  // 塵埃微粒：固定 seed 參數化（s = 光束軸向 0~1、off = 垂直偏移 -1~1）。
  static final List<({double s, double off, double r, double p1, double p2})>
  _motes = () {
    final rng = math.Random(11);
    return List.generate(12, (_) {
      return (
        s: rng.nextDouble(),
        off: (rng.nextDouble() - 0.5) * 2,
        r: 0.8 + rng.nextDouble() * 1.1,
        p1: rng.nextDouble() * math.pi * 2,
        p2: rng.nextDouble() * math.pi * 2,
      );
    });
  }();

  // 夜圖窗內星星的實際座標（圖比例：x = 寬比例、y = 顯示圖高比例；
  // 從 home_night 原圖亮點聚類量得），各自的閃爍速度/相位。
  static const _stars = <(double, double, double)>[
    // (x, y, phase)
    (0.1356, 0.0733, 0.0),
    (0.1680, 0.1163, 1.3),
    (0.0232, 0.1188, 2.4),
    (0.1573, 0.1644, 3.6),
    (0.0615, 0.0777, 4.4),
    (0.1310, 0.2489, 5.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = SceneTimeController.instance.state;
    final t = time.value;
    final w = size.width;
    final imgH = w / 0.8; // home_* cover-by-width + topCenter 的顯示高度

    // ── 塵埃：浮在清晨圖畫好的窗光光束裡 ──
    // 清晨滿量、白天餘韻（圖裡仍有柔窗光）、黃昏夜晚無。
    final dust = s.blendValue(morning: 1.0, day: 0.30, dusk: 0.0, night: 0.0);
    if (dust > 0.02) {
      // 光束幾何對齊清晨圖：起點在窗中段、朝右下（與圖中光斑走向一致）。
      final start = Offset(w * 0.13, imgH * 0.18);
      final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
      final perp = Offset(-dir.dy, dir.dx);
      final len = w * 0.8;
      final motePaint = Paint()..blendMode = BlendMode.plus;
      const warm = Color(0xFFFFEFCF);
      for (final m in _motes) {
        final along = (m.s + t * 0.008) % 1.0;
        final wobble =
            perp *
            (m.off * w * 0.055 + w * 0.010 * math.sin(t * 0.14 + m.p2));
        final pos =
            start +
            dir * (along * len + w * 0.012 * math.sin(t * 0.10 + m.p1)) +
            wobble;
        final twinkle = 0.5 + 0.5 * math.sin(t * (0.5 + m.p1 * 0.18) + m.p2);
        // 頭尾淡出：靠窗與落地處都不突兀
        final endFade = math.sin(math.pi * along);
        motePaint.color = warm.withValues(
          alpha: (0.32 * dust * twinkle * endFade).clamp(0.0, 1.0),
        );
        canvas.drawCircle(pos, m.r, motePaint);
      }
    }

    // ── 星光眨眼：只疊在夜圖畫好的星點上 ──
    final night = s.nightWeight;
    if (night > 0.02) {
      final starPaint = Paint()..blendMode = BlendMode.plus;
      const glow = Color(0xFFFFF8E8);
      for (final (sx, sy, phase) in _stars) {
        // 慢速呼吸＋各自相位；平方讓「暗的時間長、亮起來一瞬」更像星星
        final tw = 0.5 + 0.5 * math.sin(t * (0.55 + phase * 0.07) + phase);
        final a = tw * tw * 0.5 * night;
        if (a < 0.02) continue;
        starPaint.color = glow.withValues(alpha: a);
        canvas.drawCircle(Offset(w * sx, imgH * sy), w * 0.0035, starPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SceneAirPainter old) => false;
  // repaint 由 super(repaint:) 的 clock/分鐘級時段合併 listenable 驅動。
}
