// 首頁臥室背景的動態層，分上下兩塊：
//
//   [WindowBackdrop]（墊在背景圖之下）
//     窗外景。背景圖用 home_bg_glassless.png（窗玻璃已挖透明、窗框窗櫺
//     原圖像素全保留），這層只畫「洞後面的世界」：時段天空、日月、
//     星星、雲、灌木剪影。畫的範圍略大於玻璃開口，其餘被原圖蓋住，
//     所以完全不存在補畫窗櫺 / 對齊的問題。
//
//   [RoomAmbientOverlay]（疊在背景圖 + 時段色罩之上）
//     室內光影。晨/晝窗光斜射光束 + 塵埃微粒 + 地板光池；
//     暮/夜床頭檯燈暖光暈（呼吸）；深夜極淡冷色月光。
//
// 所有強度都用連續 hour 的 smoothstep 開關，時段交界不跳變。
// 幾何錨點對齊 home_bg 內容（BoxFit.cover + topCenter，圖檔長寬比 0.8
// → 顯示高度 = 寬度 / 0.8）；座標一律用 (寬度比例, 顯示圖高比例) 表達。
//
// 效能：兩層各自單 Ticker 節流 ~30fps + RepaintBoundary，只重繪自己。
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
    // 只有 prefs 真的有值才覆蓋，避免把程式裡手動寫死的預覽值洗掉
    final v = prefs.getDouble(PrefsKeys.debugSceneHour);
    if (v != null) hourOverride = v;
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

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 30fps Ticker + ValueNotifier 的共用底座（兩個動態層都用這個模式）。
mixin _ThrottledTicker<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker;
  // painter 的 repaint listenable：值 = 開場至今秒數（無界）
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  double _lastNotified = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      if (t - _lastNotified < 1 / 30) return; // 節流 ~30fps
      _lastNotified = t;
      _time.value = t;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════
// 窗外景（墊在背景圖之下）
// ════════════════════════════════════════════════════════════════

class WindowBackdrop extends StatefulWidget {
  const WindowBackdrop({super.key});

  @override
  State<WindowBackdrop> createState() => _WindowBackdropState();
}

class _WindowBackdropState extends State<WindowBackdrop>
    with SingleTickerProviderStateMixin, _ThrottledTicker {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          size: Size.infinite,
          painter: _WindowBackdropPainter(time: _time),
        ),
      ),
    );
  }
}

class _WindowBackdropPainter extends CustomPainter {
  final ValueNotifier<double> time;

  _WindowBackdropPainter({required this.time}) : super(repaint: time);

  // 夜空星點（窗區座標：x = 區寬比例、y = 區高比例的上半）
  static const _stars = <(double, double, double)>[
    (0.16, 0.10, 1.1), (0.36, 0.05, 0.9), (0.55, 0.14, 1.3),
    (0.74, 0.08, 0.9), (0.88, 0.18, 1.1), (0.27, 0.24, 0.8),
    (0.64, 0.30, 1.0), (0.45, 0.38, 0.8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final h = sceneHourNow();
    final w = size.width;
    final imgH = w / 0.8;
    final pal = _windowPalette(h);

    // 窗區（比玻璃開口略大，邊緣被上層原圖蓋掉）
    final region = Rect.fromLTRB(0, imgH * 0.040, w * 0.21, imgH * 0.345);
    final xL = region.left;
    final xR = region.right;
    final winW = region.width;
    final top = region.top;
    final bottom = region.bottom;

    canvas.save();
    canvas.clipRect(region);

    // 1. 天空
    canvas.drawRect(
      region,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, bottom),
          [pal.top, pal.bot],
        ),
    );

    // 2. 星星（夜間，各自相位眨眼）
    if (pal.star > 0.01) {
      final starPaint = Paint();
      for (var i = 0; i < _stars.length; i++) {
        final (sx, sy, sr) = _stars[i];
        final tw = 0.55 + 0.45 * math.sin(t * (1.3 + i * 0.31) + i * 2.1);
        starPaint.color = const Color(0xFFFFF6DE)
            .withValues(alpha: (pal.star * tw).clamp(0.0, 1.0));
        canvas.drawCircle(
          Offset(xL + winW * sx, top + region.height * sy),
          sr,
          starPaint,
        );
      }
    }

    // 3. 太陽（6~19）/ 月亮（19~6）沿窗內小弧移動
    _paintCelestial(canvas, xL, xR, top, bottom, h);

    // 4. 兩朵小雲慢慢飄過（夜裡淡到幾乎看不見）
    final cloudPaint = Paint()
      ..color = pal.cloud.withValues(alpha: 1.0 - pal.nightness * 0.55);
    for (final (x0, cy, s, sp) in <(double, double, double, double)>[
      (0.15, 0.30, 1.0, 0.011),
      (0.65, 0.16, 0.72, 0.017),
    ]) {
      final fx = (x0 + t * sp) % 1.3 - 0.15;
      final c = Offset(xL + winW * fx, top + region.height * cy);
      canvas.drawOval(
        Rect.fromCenter(
            center: c, width: winW * 0.34 * s, height: winW * 0.13 * s),
        cloudPaint,
      );
      canvas.drawCircle(c.translate(-winW * 0.07 * s, -winW * 0.045 * s),
          winW * 0.075 * s, cloudPaint);
      canvas.drawCircle(c.translate(winW * 0.05 * s, -winW * 0.035 * s),
          winW * 0.06 * s, cloudPaint);
    }

    // 5. 遠/近兩層灌木剪影帶（顏色隨時段入夜變深）
    final far = Color.lerp(
        const Color(0xFFA7CF8B), const Color(0xFF46566E), pal.nightness)!;
    final near = Color.lerp(
        const Color(0xFF86BB68), const Color(0xFF38485C), pal.nightness)!;
    _paintBushBand(canvas, region, 0.60, 14, 16, 2.1, 0, far);
    _paintBushBand(canvas, region, 0.76, 10, 14, 1.7, 1, near);

    canvas.restore();
  }

  void _paintBushBand(Canvas canvas, Rect region, double topFrac,
      double stagger, double arc, double seed, int phase, Color color) {
    final bandTop = region.top + region.height * topFrac;
    const bumps = 4;
    final path = Path()
      ..moveTo(region.left, region.bottom)
      ..lineTo(region.left, bandTop + 8);
    for (var i = 0; i <= bumps; i++) {
      final bx = region.left + region.width * (i / bumps);
      final wave = (i % 2 == phase) ? 0.0 : stagger;
      final by = bandTop + wave + 4 * math.sin(i * seed + phase);
      if (i == 0) {
        path.lineTo(bx, by);
      } else {
        path.quadraticBezierTo(
            bx - region.width / bumps / 2, by - arc, bx, by);
      }
    }
    path
      ..lineTo(region.right, region.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintCelestial(
    Canvas canvas,
    double xL,
    double xR,
    double top,
    double bottom,
    double h,
  ) {
    final winW = xR - xL;
    final isMoon = !(h >= 6 && h < 19);
    final tArc = isMoon ? ((h - 19) % 24) / 11 : (h - 6) / 13;
    final lift = math.sin(math.pi * tArc.clamp(0.0, 1.0));
    final c = Offset(
      xL + winW * ui.lerpDouble(0.18, 0.82, tArc)!,
      ui.lerpDouble(bottom - (bottom - top) * 0.32,
          top + (bottom - top) * 0.14, lift)!,
    );
    if (!isMoon) {
      final disc =
          Color.lerp(const Color(0xFFFFB36B), const Color(0xFFFFE9A8), lift)!;
      canvas.drawCircle(
        c,
        winW * 0.30,
        Paint()
          ..shader = ui.Gradient.radial(c, winW * 0.30, [
            disc.withValues(alpha: 0.40),
            disc.withValues(alpha: 0),
          ]),
      );
      canvas.drawCircle(c, winW * 0.10, Paint()..color = disc);
    } else {
      const moon = Color(0xFFF6F1DE);
      canvas.drawCircle(
        c,
        winW * 0.24,
        Paint()
          ..shader = ui.Gradient.radial(c, winW * 0.24, [
            moon.withValues(alpha: 0.30),
            moon.withValues(alpha: 0),
          ]),
      );
      final r = winW * 0.085;
      final crescent = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
        Path()
          ..addOval(Rect.fromCircle(
              center: c.translate(r * 0.45, -r * 0.25), radius: r * 0.88)),
      );
      canvas.drawPath(crescent, Paint()..color = moon);
    }
  }

  @override
  bool shouldRepaint(covariant _WindowBackdropPainter old) => false;
}

// 窗外景時段調色盤：keyframe 線性插值（與 _sceneTint 時段概念對齊）
({Color top, Color bot, Color cloud, double star, double nightness})
_windowPalette(double h) {
  const stops = <(double, (int, int, int, double, double))>[
    // (hour, (skyTop, skyBot, cloud, star, nightness))
    (0.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (5.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (6.6, (0xFFB8B5E0, 0xFFFFD9B3, 0xFFFFE7DC, 0.2, 0.15)),
    (8.5, (0xFF8FC9EC, 0xFFD6EFF7, 0xFFFFFFFF, 0.0, 0.0)),
    (16.8, (0xFF8FC9EC, 0xFFD6EFF7, 0xFFFFFFFF, 0.0, 0.0)),
    (18.6, (0xFF8F8BC9, 0xFFFFC08A, 0xFFF4CDC2, 0.1, 0.2)),
    (20.4, (0xFF5D5C96, 0xFFB98FB4, 0xFFB9AED6, 0.55, 0.55)),
    (22.4, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
    (24.0, (0xFF3D4673, 0xFF6E78AC, 0xFF9FA8CE, 1.0, 1.0)),
  ];
  for (var i = 0; i < stops.length - 1; i++) {
    final (h0, a) = stops[i];
    final (h1, b) = stops[i + 1];
    if (h >= h0 && h <= h1) {
      final t = (h - h0) / (h1 - h0);
      return (
        top: Color.lerp(Color(a.$1), Color(b.$1), t)!,
        bot: Color.lerp(Color(a.$2), Color(b.$2), t)!,
        cloud: Color.lerp(Color(a.$3), Color(b.$3), t)!,
        star: ui.lerpDouble(a.$4, b.$4, t)!,
        nightness: ui.lerpDouble(a.$5, b.$5, t)!,
      );
    }
  }
  return (
    top: const Color(0xFF3D4673),
    bot: const Color(0xFF6E78AC),
    cloud: const Color(0xFF9FA8CE),
    star: 1.0,
    nightness: 1.0,
  );
}

// ════════════════════════════════════════════════════════════════
// 室內光影（疊在背景圖 + 時段色罩之上）
// ════════════════════════════════════════════════════════════════

class RoomAmbientOverlay extends StatefulWidget {
  const RoomAmbientOverlay({super.key});

  @override
  State<RoomAmbientOverlay> createState() => _RoomAmbientOverlayState();
}

class _RoomAmbientOverlayState extends State<RoomAmbientOverlay>
    with SingleTickerProviderStateMixin, _ThrottledTicker {
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
    final imgH = w / 0.8; // home_bg cover + topCenter 的顯示高度

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
        ..lineTo(
            end.dx - perp.dx * b.halfW * 1.6, end.dy - perp.dy * b.halfW * 1.6)
        ..lineTo(
            end.dx + perp.dx * b.halfW * 1.6, end.dy + perp.dy * b.halfW * 1.6)
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
      final wobble = perp *
          (m.off * mid.halfW * 2.2 + w * 0.012 * math.sin(t * 0.13 + m.p2));
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
