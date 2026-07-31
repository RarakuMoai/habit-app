// 喝水水瓶：波浪／泡泡／光帶的繪圖與動畫。
//
// 這是純展示元件——只吃 progress / reached 等參數，不碰 prefs、不知道資料
// 從哪來。原本住在 water_page.dart，家庭模式的小孩喝水面板也要用同一個
// 水瓶，所以搬出來共用（純搬移，行為未改）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class BottleGeometry {
  static const double imageAspectRatio = 1024 / 1536;
  static const double bodyLeft = 195 / 1024;
  static const double bodyTop = 468 / 1536;
  static const double bodyWidth = 595 / 1024;
  static const double bodyHeight = 860 / 1536;

  static Rect bodyRectIn(Size size) => Rect.fromLTWH(
    size.width * bodyLeft,
    size.height * bodyTop,
    size.width * bodyWidth,
    size.height * bodyHeight,
  );

  static Path clipPathIn(Size size) {
    final r = bodyRectIn(size);
    final w = r.width;
    final h = r.height;
    return Path()
      ..moveTo(r.left + w * 0.24, r.top)
      ..lineTo(r.right - w * 0.24, r.top)
      ..cubicTo(
        r.right - w * 0.08,
        r.top + h * 0.03,
        r.right + w * 0.01,
        r.top + h * 0.18,
        r.right - w * 0.01,
        r.top + h * 0.34,
      )
      ..lineTo(r.right - w * 0.02, r.top + h * 0.72)
      ..cubicTo(
        r.right - w * 0.02,
        r.top + h * 0.90,
        r.right - w * 0.10,
        r.bottom - h * 0.02,
        r.right - w * 0.30,
        r.bottom,
      )
      ..lineTo(r.left + w * 0.30, r.bottom)
      ..cubicTo(
        r.left + w * 0.10,
        r.bottom - h * 0.02,
        r.left + w * 0.02,
        r.top + h * 0.90,
        r.left + w * 0.02,
        r.top + h * 0.72,
      )
      ..lineTo(r.left + w * 0.01, r.top + h * 0.34)
      ..cubicTo(
        r.left - w * 0.01,
        r.top + h * 0.18,
        r.left + w * 0.08,
        r.top + h * 0.03,
        r.left + w * 0.24,
        r.top,
      )
      ..close();
  }
}

class WaterBottle extends StatefulWidget {
  final double progress;
  final bool reached;
  // bumpKey changes (e.g. cup count) trigger a brief scale bounce.
  final int bumpKey;
  final double panelOpenValue;
  final bool paused;

  const WaterBottle({
    super.key,
    required this.progress,
    required this.reached,
    required this.bumpKey,
    required this.panelOpenValue,
    required this.paused,
  });

  @override
  State<WaterBottle> createState() => WaterBottleState();
}

class WaterBottleState extends State<WaterBottle>
    with TickerProviderStateMixin {
  // 主時鐘：60 秒一圈、循環播放。波浪/泡泡/光帶/星光的相位一律取
  // 「整數圈 × clock」，value 從 1 跳回 0 時相位剛好接上，循環不會跳針
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  // 晃動包絡：加減水時 forward(from: 0)，painter 端用指數衰減收斂；
  // idle 停在 1（殘餘振幅 ~3%，視覺上等於靜止的微波）
  late final AnimationController _slosh = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: 1.0,
  );
  // 這次晃動是不是「加水」：加水才畫漣漪跟跳起的水珠，減水只搖晃
  bool _sloshIsAdd = true;

  late final AnimationController _bumpCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _bump = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_bumpCtl);

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  // 空瓶或頁面閒置時畫面上沒有必要持續動，停掉主時鐘省電；有水且未閒置才轉。
  void _syncClock() {
    final needsTick = !widget.paused && (widget.progress > 0 || widget.reached);
    if (needsTick && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!needsTick && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void didUpdateWidget(WaterBottle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bumpKey != widget.bumpKey) {
      _sloshIsAdd = widget.progress >= oldWidget.progress;
      _bumpCtl.forward(from: 0);
      _slosh.forward(from: 0);
    }
    _syncClock();
  }

  @override
  void dispose() {
    _clock.dispose();
    _slosh.dispose();
    _bumpCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.progress),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, level, _) {
        final compactProgress = widget.reached
            ? ((widget.panelOpenValue - 0.55) / 0.45).clamp(0.0, 1.0)
            : 0.0;
        final bottleOpacity = widget.reached ? 1.0 - compactProgress : 1.0;
        return ScaleTransition(
          scale: _bump,
          child: AspectRatio(
            aspectRatio: BottleGeometry.imageAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: bottleOpacity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // soft halo behind the bottle (purely decorative,
                      // sits outside the bottle interior).
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 28, 0, 32),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.cyan.withValues(alpha: 0.16),
                                Colors.cyan.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Image.asset(
                        'assets/scenes/water/bottle_back.png',
                        fit: BoxFit.contain,
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([_clock, _slosh]),
                        builder: (_, _) => CustomPaint(
                          painter: WaterPainter(
                            level: level,
                            clock: _clock.value,
                            slosh: _slosh.value,
                            sloshIsAdd: _sloshIsAdd,
                            reached: widget.reached,
                          ),
                        ),
                      ),
                      Image.asset(
                        'assets/scenes/water/bottle_front.png',
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                if (widget.reached)
                  BottleGoalBadge(compactProgress: compactProgress),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BottleGoalBadge extends StatelessWidget {
  final double compactProgress;

  const BottleGoalBadge({super.key, required this.compactProgress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final smallSize = (constraints.maxWidth * 0.20).clamp(14.0, 36.0);
        final largeSize = constraints.maxWidth * 0.88;
        final badgeSize = ui.lerpDouble(smallSize, largeSize, compactProgress)!;
        final iconSize = ui.lerpDouble(
          smallSize * 0.64,
          largeSize * 0.66,
          compactProgress,
        )!;
        final blurRadius = ui.lerpDouble(
          smallSize * 0.20,
          largeSize * 0.16,
          compactProgress,
        )!;
        final alignment = Alignment.lerp(
          const Alignment(0.55, -0.72),
          Alignment.center,
          compactProgress,
        )!;

        return Align(
          alignment: alignment,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD54F).withValues(alpha: 0.35),
                  blurRadius: blurRadius,
                  spreadRadius: compactProgress * 2,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        );
      },
    );
  }
}

// 活水 painter：連續波浪（前後雙層、雙諧波）、上升氣泡、水中光帶、
// 加減水時的傾盪/漣漪/水珠、達標後的金色星光。
//
// 所有週期運動的相位都來自 60 秒主時鐘的「整數圈數」，循環接縫不跳動。
// 水體幾何依然完全以 BottleGeometry 為準——換瓶身素材只改那邊。
class WaterPainter extends CustomPainter {
  final double level; // 0..1 目前水位（外層已做補間）
  final double clock; // 0..1 主時鐘
  final double slosh; // 0..1 晃動進度（1 = 靜止）
  final bool sloshIsAdd;
  final bool reached;

  WaterPainter({
    required this.level,
    required this.clock,
    required this.slosh,
    required this.sloshIsAdd,
    required this.reached,
  });

  static const int _surfaceSteps = 28;
  static const double _tau = 2 * math.pi;

  // 確定性偽隨機：同一顆泡泡/星星每一幀都拿到一樣的參數
  double _hash(int i, int salt) {
    final v = math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Drop shadow beneath the bottle (purely decorative, drawn outside
    // the body rect so it doesn't interact with the water clip).
    final shadow = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.95),
        width: size.width * 0.55,
        height: 16,
      ),
      shadow,
    );

    if (level <= 0.002) return;

    final r = BottleGeometry.bodyRectIn(size);
    final w = r.width;
    final waterH = r.height * level;
    final waterTop = r.bottom - waterH;

    // 晃動包絡：指數衰減。tilt 讓水面左右傾盪、振幅放大讓波浪短暫變大
    final env = math.exp(-3.4 * slosh);
    final tilt = w * 0.05 * env * math.sin(_tau * 2.4 * slosh);
    // 水很淺時把波浪壓小，避免薄薄一層水卻掀大浪
    final shallow = (level / 0.06).clamp(0.0, 1.0);
    final ampBoost = (1 + 2.6 * env) * shallow;
    final a1 = w * 0.016 * ampBoost;
    final a2 = w * 0.007 * ampBoost;

    // 波面取樣：兩個不同波長/速度的諧波疊加，dir 控制行進方向
    // （前後層反向流動，水面才有立體感）
    double surfaceYAt(
      double f,
      double lift,
      double phaseOff,
      double ampMul,
      double dir,
    ) {
      return waterTop -
          lift +
          tilt * (f - 0.5) * 2 * ampMul +
          a1 *
              ampMul *
              math.sin(_tau * (f * 1.15 + dir * clock * 7 + phaseOff)) +
          a2 *
              ampMul *
              math.sin(_tau * (f * 2.45 - dir * clock * 11 + phaseOff * 1.7));
    }

    Path surfacePolyline(
      double lift,
      double phaseOff,
      double ampMul,
      double dir,
    ) {
      final p = Path();
      for (var i = 0; i <= _surfaceSteps; i++) {
        final f = i / _surfaceSteps;
        final x = r.left + w * f;
        final y = surfaceYAt(f, lift, phaseOff, ampMul, dir);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      return p;
    }

    Path bodyFrom(Path surface) => Path.from(surface)
      ..lineTo(r.right, r.bottom + 2)
      ..lineTo(r.left, r.bottom + 2)
      ..close();

    final clip = BottleGeometry.clipPathIn(size);
    canvas.save();
    canvas.clipPath(clip);

    // 後層波浪：比前層高出一點點、反向流動，營造水面厚度
    final backBody = bodyFrom(
      surfacePolyline(a1 * 1.5 + w * 0.012, 0.42, 0.7, -1),
    );
    canvas.drawPath(
      backBody,
      Paint()..color = const Color(0xFFAEEBFF).withValues(alpha: 0.6),
    );

    final frontSurface = surfacePolyline(0, 0, 1, 1);
    final frontBody = bodyFrom(frontSurface);
    canvas.drawPath(
      frontBody,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xCC86E8FF), Color(0xE03FC0E8), Color(0xF21895C8)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(r),
    );

    // 水裡的東西（光帶/泡泡/星光）都夾在水體內
    canvas.save();
    canvas.clipPath(frontBody);
    _paintCaustics(canvas, r, waterH);
    _paintBubbles(canvas, r, waterH);
    if (reached) _paintSparkles(canvas, r, waterTop, waterH);
    canvas.restore();

    // 水面高光線
    canvas.drawPath(
      frontSurface,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // 加水那一下：水面漣漪 + 跳起又落回的小水珠
    if (sloshIsAdd && slosh < 0.45) {
      _paintSplash(canvas, r, waterTop);
    }

    canvas.restore();
  }

  // 緩慢斜向飄移的光帶，模擬透進水裡的光（很淡，讓水「活」起來就好）
  void _paintCaustics(Canvas canvas, Rect r, double waterH) {
    final w = r.width;
    final drift = (clock * 2) % 1.0; // 2 圈 / 60s → 30 秒飄一輪
    for (var i = 0; i < 2; i++) {
      final f = (drift + i * 0.5) % 1.0;
      final cx = r.left + w * (f * 1.5 - 0.25);
      final band = Rect.fromCenter(
        center: Offset(cx, r.bottom - waterH / 2),
        width: w * 0.2,
        height: waterH + 60,
      );
      canvas.save();
      canvas.translate(band.center.dx, band.center.dy);
      canvas.rotate(-0.32);
      canvas.translate(-band.center.dx, -band.center.dy);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  void _paintBubbles(Canvas canvas, Rect r, double waterH) {
    final w = r.width;
    final rise = waterH - w * 0.12; // 從瓶底升到水面下一點點
    if (rise <= w * 0.04) return;
    final count = 3 + (level * 7).round();
    for (var i = 0; i < count; i++) {
      final h1 = _hash(i, 1);
      final h2 = _hash(i, 2);
      final h3 = _hash(i, 3);
      final h4 = _hash(i, 4);
      final cycles = 10 + (h1 * 14).floor(); // 整數圈 → 60s 接縫不跳
      final tt = (clock * cycles + h2) % 1.0;
      final x =
          r.left +
          w * (0.16 + 0.68 * h3) +
          math.sin(_tau * (tt * 2 + h4)) * w * 0.022;
      final y = r.bottom - w * 0.05 - rise * tt;
      final rad = w * (0.011 + 0.016 * h4) * (0.7 + 0.3 * tt);
      final alpha = math.sin(math.pi * tt); // 底部淡入、近水面淡出
      canvas.drawCircle(
        Offset(x, y),
        rad,
        Paint()..color = Colors.white.withValues(alpha: 0.42 * alpha),
      );
      // 小高光點，泡泡才有圓滾滾的感覺
      canvas.drawCircle(
        Offset(x - rad * 0.32, y - rad * 0.32),
        rad * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.65 * alpha),
      );
    }
  }

  // 達標後水裡的金色星光，呼應達標徽章的金色
  void _paintSparkles(Canvas canvas, Rect r, double waterTop, double waterH) {
    final w = r.width;
    for (var i = 0; i < 6; i++) {
      final hx = _hash(i, 11);
      final hy = _hash(i, 12);
      final hp = _hash(i, 13);
      final hs = _hash(i, 14);
      final cycles = 18 + (hs * 14).floor();
      final tw = 0.5 + 0.5 * math.sin(_tau * (clock * cycles + hp));
      final glow = tw * tw * tw;
      if (glow < 0.05) continue;
      final c = Offset(
        r.left + w * (0.2 + 0.6 * hx),
        waterTop + waterH * (0.18 + 0.65 * hy),
      );
      final s = w * (0.02 + 0.022 * hs) * (0.6 + 0.4 * glow);
      canvas.drawPath(
        _starPath(c, s),
        Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.85 * glow),
      );
      canvas.drawCircle(
        c,
        s * 0.22,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * glow),
      );
    }
  }

  Path _starPath(Offset c, double s) {
    return Path()
      ..moveTo(c.dx, c.dy - s)
      ..quadraticBezierTo(c.dx + s * 0.18, c.dy - s * 0.18, c.dx + s, c.dy)
      ..quadraticBezierTo(c.dx + s * 0.18, c.dy + s * 0.18, c.dx, c.dy + s)
      ..quadraticBezierTo(c.dx - s * 0.18, c.dy + s * 0.18, c.dx - s, c.dy)
      ..quadraticBezierTo(c.dx - s * 0.18, c.dy - s * 0.18, c.dx, c.dy - s)
      ..close();
  }

  // 加水瞬間：水面同心漣漪 + 幾滴跳起又落回的水珠
  void _paintSplash(Canvas canvas, Rect r, double waterTop) {
    final w = r.width;
    final t = (slosh / 0.45).clamp(0.0, 1.0);
    final cx = r.center.dx;

    final eased = Curves.easeOutCubic.transform(t);
    final rippleW = ui.lerpDouble(w * 0.16, w * 0.74, eased)!;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, waterTop),
        width: rippleW,
        height: rippleW * 0.18,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5 * (1 - t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + 1.6 * (1 - t),
    );

    final dropPaint = Paint()
      ..color = const Color(0xFF6BD6F2).withValues(alpha: 0.85 * (1 - t));
    for (var j = 0; j < 5; j++) {
      final ha = _hash(j, 31);
      final hb = _hash(j, 32);
      final dx = (ha - 0.5) * w * 0.7;
      final peak = w * (0.10 + 0.16 * hb);
      final x = cx + dx * t;
      final y = waterTop - peak * 4 * t * (1 - t);
      final rad = w * (0.010 + 0.012 * hb) * (1 - 0.4 * t);
      canvas.drawCircle(Offset(x, y), rad, dropPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WaterPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.clock != clock ||
      oldDelegate.slosh != slosh ||
      oldDelegate.sloshIsAdd != sloshIsAdd ||
      oldDelegate.reached != reached;
}
