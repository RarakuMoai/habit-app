// 首頁臥室背景的動態光影層：疊在 home_bg.png + 時段色罩之上，
// 讓靜態 CG 房間「活起來」。原圖完全不動，質感零損失。
//
//   - 晨/晝：窗光斜射光束（晨間金黃最強、白天轉奶油色變柔）、
//     光束內塵埃微粒漂浮、地板光池。
//   - 暮/夜：床頭檯燈暖光暈（緩慢呼吸）；深夜另有一道極淡的
//     冷色月光從窗斜入。
//   - 所有強度都用連續 hour 的 smoothstep 開關，時段交界不跳變。
//
// 幾何錨點對齊 home_bg.png 的內容（BoxFit.cover + topCenter，
// 圖檔長寬比 0.8 → 顯示高度 = 寬度 / 0.8）：窗在左上、檯燈在中右、
// 地毯在中下。座標一律用 (寬度比例, 顯示圖高比例) 表達。
//
// 效能：單 Ticker 節流 ~30fps + RepaintBoundary，只重繪本層。
//
// 截圖驗證用 debug 覆寫：kDebugMode 下從 prefs 讀
// PrefsKeys.debugSceneHour（HomeSceneDebug），release 完全不讀。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/prefs_keys.dart';

/// debug 覆寫（截圖驗證時段用）。release 一律走真實時間。
abstract final class HomeSceneDebug {
  static double? hourOverride;

  static void loadFromPrefs(SharedPreferences prefs) {
    if (!kDebugMode) return;
    hourOverride = prefs.getDouble(PrefsKeys.debugSceneHour);
  }
}

/// 目前場景小時（0~24 連續值）。首頁 _sceneColors/_sceneTint 也用它，
/// 確保光影層跟色罩/accent 在 debug 覆寫下一致。
double sceneHourNow() {
  final override = HomeSceneDebug.hourOverride;
  if (override != null) return override % 24;
  final now = DateTime.now();
  return now.hour + now.minute / 60 + now.second / 3600;
}

class RoomAmbientOverlay extends StatefulWidget {
  const RoomAmbientOverlay({super.key});

  @override
  State<RoomAmbientOverlay> createState() => _RoomAmbientOverlayState();
}

class _RoomAmbientOverlayState extends State<RoomAmbientOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  // painter 的 repaint listenable：值 = 開場至今秒數（無界）
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t - _lastNotified < 1 / 30) return; // 節流 ~30fps
    _lastNotified = t;
    _time.value = t;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          size: Size.infinite,
          painter: _RoomAmbientPainter(time: _time),
        ),
      ),
    );
  }
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class _RoomAmbientPainter extends CustomPainter {
  final ValueNotifier<double> time;

  _RoomAmbientPainter({required this.time}) : super(repaint: time);

  // 塵埃微粒：固定 seed，沿光束軸向參數化（s = 0~1 位置、off = 垂直偏移）
  static final List<({double s, double off, double r, double p1, double p2})>
  _motes = () {
    final rng = math.Random(5);
    return List.generate(16, (_) {
      return (
        s: rng.nextDouble(),
        off: (rng.nextDouble() - 0.5) * 2,
        r: 0.8 + rng.nextDouble() * 1.2,
        p1: rng.nextDouble() * math.pi * 2,
        p2: rng.nextDouble() * math.pi * 2,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final h = sceneHourNow();
    final w = size.width;
    final imgH = w / 0.8; // home_bg.png cover + topCenter 的顯示高度

    // ── 時段強度曲線（連續、平滑）──
    // 窗光：5:30 亮起、晨間最強、白天轉柔、16~19 收掉
    final shaft = _smooth(5.5, 7.5, h) * (1 - _smooth(16.0, 18.8, h));
    final dayness = _smooth(7.5, 11.0, h); // 0 = 晨金, 1 = 晝奶油
    final shaftStrength = shaft * (1.0 - 0.42 * dayness);
    // 檯燈：傍晚 16:30 漸亮、清晨 5~6:30 漸滅（跨日分段）
    final lamp = h >= 12 ? _smooth(16.5, 18.0, h) : (1 - _smooth(5.0, 6.5, h));
    // 月光：22 點後 / 清晨 5 點前的極淡冷色窗光
    final moon = h >= 12 ? _smooth(21.0, 22.8, h) : (1 - _smooth(4.0, 5.5, h));

    if (shaftStrength > 0.01) {
      _paintSunShafts(canvas, w, imgH, t, shaftStrength, dayness);
    }
    if (moon > 0.01) {
      _paintMoonShaft(canvas, w, imgH, moon);
    }
    if (lamp > 0.01) {
      _paintLampGlow(canvas, w, imgH, t, lamp);
    }
  }

  // ── 窗光光束 + 地板光池 + 塵埃 ──────────────────────────────
  void _paintSunShafts(
    Canvas canvas,
    double w,
    double imgH,
    double t,
    double strength,
    double dayness,
  ) {
    final color = Color.lerp(
      const Color(0xFFFFC388), // 晨金
      const Color(0xFFFFEFCF), // 晝奶油
      dayness,
    )!;
    final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
    final perp = Offset(-dir.dy, dir.dx);
    final len = w * 0.95;

    // 三道光束沿窗格錯開，亮度微微呼吸（極慢，幾乎察覺不到才高級）
    final beams = <({Offset start, double halfW, double alpha})>[
      (start: Offset(w * 0.07, imgH * 0.09), halfW: w * 0.030, alpha: 0.18),
      (start: Offset(w * 0.12, imgH * 0.16), halfW: w * 0.042, alpha: 0.22),
      (start: Offset(w * 0.17, imgH * 0.24), halfW: w * 0.034, alpha: 0.16),
    ];
    final breath = 0.9 + 0.1 * math.sin(t * 0.35);
    final blur = Paint()
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9)
      ..blendMode = BlendMode.plus;

    for (final b in beams) {
      final end = b.start + dir * len;
      final path = Path()
        ..moveTo(
          b.start.dx + perp.dx * b.halfW,
          b.start.dy + perp.dy * b.halfW,
        )
        ..lineTo(
          b.start.dx - perp.dx * b.halfW,
          b.start.dy - perp.dy * b.halfW,
        )
        // 尾端略張開，像真的光錐
        ..lineTo(end.dx - perp.dx * b.halfW * 1.6, end.dy - perp.dy * b.halfW * 1.6)
        ..lineTo(end.dx + perp.dx * b.halfW * 1.6, end.dy + perp.dy * b.halfW * 1.6)
        ..close();
      blur.shader = ui.Gradient.linear(b.start, end, [
        color.withValues(alpha: b.alpha * strength * breath),
        color.withValues(alpha: 0),
      ]);
      canvas.drawPath(path, blur);
    }

    // 地板光池（光束落點，地毯偏左）
    final pool = Offset(w * 0.40, imgH * 0.78);
    canvas.drawOval(
      Rect.fromCenter(
        center: pool,
        width: w * 0.46,
        height: imgH * 0.10,
      ),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(pool, w * 0.24, [
          color.withValues(alpha: 0.13 * strength * breath),
          color.withValues(alpha: 0),
        ]),
    );

    // 塵埃微粒：沿中央光束緩慢漂移 + 各自閃爍
    final mid = beams[1];
    final motePaint = Paint()..blendMode = BlendMode.plus;
    for (final m in _motes) {
      final s = (m.s + t * 0.009) % 1.0;
      final wobble = perp * (m.off * mid.halfW * 2.2 +
          w * 0.012 * math.sin(t * 0.13 + m.p2));
      final pos = mid.start +
          dir * (s * len * 0.92 + w * 0.015 * math.sin(t * 0.09 + m.p1)) +
          wobble;
      final twinkle = 0.5 + 0.5 * math.sin(t * (0.6 + m.p1 * 0.2) + m.p2);
      // 沿光束尾端淡出，跟光束的衰減一致
      final fade = (1 - s) * strength * twinkle;
      motePaint.color = color.withValues(alpha: 0.38 * fade);
      canvas.drawCircle(pos, m.r, motePaint);
    }
  }

  // ── 深夜月光：一道極淡的冷色斜光 ────────────────────────────
  void _paintMoonShaft(Canvas canvas, double w, double imgH, double moon) {
    const color = Color(0xFFBFC9EE);
    final dir = Offset(1, 0.9) / Offset(1, 0.9).distance;
    final perp = Offset(-dir.dy, dir.dx);
    final start = Offset(w * 0.11, imgH * 0.14);
    final end = start + dir * (w * 0.9);
    final halfW = w * 0.055;
    final path = Path()
      ..moveTo(start.dx + perp.dx * halfW, start.dy + perp.dy * halfW)
      ..lineTo(start.dx - perp.dx * halfW, start.dy - perp.dy * halfW)
      ..lineTo(end.dx - perp.dx * halfW * 1.5, end.dy - perp.dy * halfW * 1.5)
      ..lineTo(end.dx + perp.dx * halfW * 1.5, end.dy + perp.dy * halfW * 1.5)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 11)
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(start, end, [
          color.withValues(alpha: 0.07 * moon),
          color.withValues(alpha: 0),
        ]),
    );
  }

  // ── 床頭檯燈暖光暈（呼吸）────────────────────────────────────
  void _paintLampGlow(
    Canvas canvas,
    double w,
    double imgH,
    double t,
    double lamp,
  ) {
    final c = Offset(w * 0.645, imgH * 0.41);
    final breath = 0.86 + 0.14 * math.sin(t * 0.8);
    const warm = Color(0xFFFFC98A);
    // 外暈大而淡、內暈小而暖，疊出柔和的燈光層次
    canvas.drawCircle(
      c,
      w * 0.30,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, w * 0.30, [
          warm.withValues(alpha: 0.16 * lamp * breath),
          warm.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(
      c,
      w * 0.12,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, w * 0.12, [
          const Color(0xFFFFE0B0).withValues(alpha: 0.22 * lamp * breath),
          const Color(0xFFFFE0B0).withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomAmbientPainter old) => false;
}
