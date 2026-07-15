// 四時段背景的「空氣層」：讓完整 CG 背景多一口呼吸，不重畫任何光影。
//
// 只做兩件事，且都錨定在背景圖已經畫好的位置上（幾何由 [SceneAirSpec]
// 逐房間設定，註冊表見 widgets/scene_rooms.dart）：
//   1. 塵埃微粒：沿清晨圖窗光光束的方向緩慢漂浮（清晨最明顯、白天餘韻、
//      黃昏夜晚沒有）。光束本身是圖畫的，塵埃只是「浮在光裡」。
//   2. 星光眨眼：夜圖窗內星星的精確座標上，疊極小的閃爍亮點，
//      各自相位、慢速呼吸。月亮與天空不動。
//
// 原則（計劃書）：背景已畫得自然的部分不重複堆效果——所以沒有光束、
// 沒有燈暈、沒有色罩，只有這兩種「圖畫不出來的微動態」。
//
// 效能：單一 CustomPaint、無 blur、≤18 個小圓點。時鐘可外接（首頁的
// 20fps SceneAnimationClock）或自建（ThrottledSceneTicker，30fps），
// 外層 TickerMode 凍結時一起停；時段權重讓沒東西可畫的時段零繪製。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/scene_time.dart';
import 'scene_clock.dart';

/// 一個房間的空氣層幾何與強度（座標一律圖比例：x = 寬比例、
/// y = 顯示圖高比例；顯示圖高 = 寬 / 0.8，同背景 cover-by-width）。
@immutable
class SceneAirSpec {
  /// 塵埃光束起點（清晨圖窗光的中段）。
  final Offset beamStart;

  /// 塵埃可視強度（各時段權重混合；0 = 該時段不畫塵埃）。
  final double dustMorning, dustDay, dustDusk, dustNight;

  /// 夜圖窗內星星座標＋各自閃爍相位：(x, y, phase)。空列表 = 不畫星光。
  final List<(double, double, double)> stars;

  const SceneAirSpec({
    required this.beamStart,
    this.dustMorning = 1.0,
    this.dustDay = 0.30,
    this.dustDusk = 0.0,
    this.dustNight = 0.0,
    required this.stars,
  });
}

class SceneAirLayer extends StatefulWidget {
  /// 共享場景時鐘（SceneAnimationClock.time）；null = 自建 30fps ticker。
  final ValueNotifier<double>? clock;

  final SceneAirSpec spec;

  const SceneAirLayer({super.key, this.clock, required this.spec});

  @override
  State<SceneAirLayer> createState() => _SceneAirLayerState();
}

class _SceneAirLayerState extends State<SceneAirLayer>
    with SingleTickerProviderStateMixin, ThrottledSceneTicker {
  @override
  ValueNotifier<double>? get externalClock => widget.clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SceneAirPainter(time: sceneTime, spec: widget.spec),
        ),
      ),
    );
  }
}

class _SceneAirPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final SceneAirSpec spec;

  _SceneAirPainter({required this.time, required this.spec})
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

  @override
  void paint(Canvas canvas, Size size) {
    final s = SceneTimeController.instance.state;
    final t = time.value;
    final w = size.width;
    final imgH = w / 0.8; // 背景 cover-by-width + topCenter 的顯示高度

    // ── 塵埃：浮在清晨圖畫好的窗光光束裡 ──
    final dust = s.blendValue(
      morning: spec.dustMorning,
      day: spec.dustDay,
      dusk: spec.dustDusk,
      night: spec.dustNight,
    );
    if (dust > 0.02) {
      // 光束幾何對齊清晨圖：起點在窗中段、朝右下（與圖中光斑走向一致）。
      final start = Offset(w * spec.beamStart.dx, imgH * spec.beamStart.dy);
      final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
      final perp = Offset(-dir.dy, dir.dx);
      final len = w * 0.8;
      final motePaint = Paint()..blendMode = BlendMode.plus;
      const warm = Color(0xFFFFEFCF);
      for (final m in _motes) {
        final along = (m.s + t * 0.008) % 1.0;
        final wobble =
            perp * (m.off * w * 0.055 + w * 0.010 * math.sin(t * 0.14 + m.p2));
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
    if (night > 0.02 && spec.stars.isNotEmpty) {
      final starPaint = Paint()..blendMode = BlendMode.plus;
      const glow = Color(0xFFFFF8E8);
      for (final (sx, sy, phase) in spec.stars) {
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
  bool shouldRepaint(covariant _SceneAirPainter old) => old.spec != spec;
  // 動態重繪由 super(repaint:) 的 clock/分鐘級時段合併 listenable 驅動。
}
