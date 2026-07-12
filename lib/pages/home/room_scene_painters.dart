// 首頁場景 painter：背景上方的互動效果層。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/scene_time.dart';
import 'room_ambient_overlay.dart' show sceneHourNow, ThrottledSceneTicker;
import 'room_metrics.dart';

/// 首頁互動效果層（地板光池 / 檯燈氛圍 / 完成光暈）。
/// 與 [WindowBackdrop]/[RoomAmbientOverlay] 同模式：30fps 節流 ticker +
/// RepaintBoundary，只重繪自己；外層用 TickerMode(enabled: !idle) 凍結省電。
/// 之前這層用 full-rate AnimationController 直驅、又沒包 RepaintBoundary，
/// 是全頁唯一漏掉節流的動態層（每幀全螢幕跑數個 MaskFilter.blur ＝ 發熱大戶）。
class RoomSceneEffects extends StatefulWidget {
  final Color accent;
  final double progress;
  final bool allDone;

  /// 共享場景時鐘（見 [SceneAnimationClock]）；null = 自建 30fps ticker。
  final ValueNotifier<double>? clock;

  const RoomSceneEffects({
    super.key,
    required this.accent,
    required this.progress,
    required this.allDone,
    this.clock,
  });

  @override
  State<RoomSceneEffects> createState() => _RoomSceneEffectsState();
}

class _RoomSceneEffectsState extends State<RoomSceneEffects>
    with SingleTickerProviderStateMixin, ThrottledSceneTicker {
  @override
  ValueNotifier<double>? get externalClock => widget.clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          size: Size.infinite,
          painter: RoomSceneEffectsPainter(
            accent: widget.accent,
            progress: widget.progress,
            allDone: widget.allDone,
            time: sceneTime,
          ),
        ),
      ),
    );
  }
}

// ── 生成背景上方的互動效果層：保留狀態回饋，不再重畫整個房間 ──
class RoomSceneEffectsPainter extends CustomPainter {
  final Color accent;
  final double progress;
  final bool allDone;

  /// 開場至今秒數（無界）；12 秒一圈換算成 phase。節流由 [RoomSceneEffects] 的
  /// ticker 負責，這裡只負責把秒數映射成相位。
  final ValueNotifier<double> time;

  RoomSceneEffectsPainter({
    required this.accent,
    required this.progress,
    required this.allDone,
    required this.time,
  }) : super(
         // 合併分鐘級時段更新：ticker 凍結時跨交界仍會單次 repaint。
         repaint: Listenable.merge([time, SceneTimeController.instance]),
       );

  @override
  void paint(Canvas canvas, Size size) {
    final phase = time.value * (math.pi / 6.0); // 2π / 12s
    // 場景高吃螢幕寬等比（與背景圖 cover-by-width 同參考系），14PM 時 == 舊 height×0.56。
    final sceneH = roomEffectsSceneHeight(size.width);
    final floorY = sceneH * 0.82;
    final hour = sceneHourNow();

    _paintSoftRoomDepth(canvas, size, sceneH, hour);
    _paintSunlitFloor(canvas, size, sceneH, hour, phase);
    _paintLampAtmosphere(canvas, size, sceneH, hour, phase);

    if (allDone) {
      _paintCompletionAura(canvas, size, sceneH, phase);
      _paintCompletionSparkles(canvas, size, floorY, phase);
    }
  }

  double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double _daylight(double hour) {
    if (hour < 6 || hour >= 16) return 0;
    if (hour <= 12) return _smooth(6.0, 12.0, hour);
    return 1 - _smooth(12.0, 16.0, hour);
  }

  // 黃昏地板光池／檯燈氛圍：時間窗與 RoomAmbientOverlay companionTiming
  // 一致（黃昏核心全程都在、暮→夜交接收掉；燈 16:48 起漸亮）。
  double _dusk(double hour) =>
      _smooth(16.0, 16.8, hour) * (1 - _smooth(18.3, 19.2, hour));

  double _lamp(double hour) =>
      hour >= 12 ? _smooth(16.8, 18.0, hour) : (1 - _smooth(5.4, 6.4, hour));

  void _paintSoftRoomDepth(
    Canvas canvas,
    Size size,
    double sceneH,
    double hour,
  ) {
    final w = size.width;
    final night = hour >= 12
        ? _smooth(20.0, 22.5, hour)
        : (1 - _smooth(4.8, 6.3, hour));
    final progressLift = 0.65 + progress * 0.35;

    final floorShadow = Rect.fromCenter(
      center: Offset(w * 0.52, sceneH * 0.80),
      width: w * 0.74,
      height: sceneH * 0.18,
    );
    canvas.drawOval(
      floorShadow,
      Paint()
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18)
        ..color = Color.lerp(
          const Color(0xFF7B5B46),
          const Color(0xFF6D625B),
          night,
        )!.withValues(alpha: 0.085 * progressLift),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, sceneH),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.50, sceneH * 0.40),
          w * 0.82,
          [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.024 + 0.012 * night),
          ],
          const [0.62, 1.0],
        ),
    );
  }

  void _paintSunlitFloor(
    Canvas canvas,
    Size size,
    double sceneH,
    double hour,
    double phase,
  ) {
    final sun = _daylight(hour);
    final dusk = _dusk(hour);
    final light = math.max(sun, dusk * 0.46);
    if (light <= 0.01) return;

    final w = size.width;
    final noonWarmth = Color.lerp(
      const Color(0xFFFFC782),
      const Color(0xFFFFF3D6),
      _smooth(6.0, 12.0, hour),
    )!;
    final warmth = dusk > sun
        ? Color.lerp(const Color(0xFFFFD19A), const Color(0xFFFFA866), dusk)!
        : noonWarmth;
    final breathe = 0.92 + 0.08 * math.sin(phase * 0.42);
    final alpha = (0.025 + 0.075 * light) * breathe;

    final patches = <Path>[
      Path()
        ..moveTo(w * 0.13, sceneH * 0.40)
        ..lineTo(w * 0.35, sceneH * 0.44)
        ..lineTo(w * 0.61, sceneH * 0.59)
        ..lineTo(w * 0.31, sceneH * 0.55)
        ..close(),
      Path()
        ..moveTo(w * 0.26, sceneH * 0.34)
        ..lineTo(w * 0.42, sceneH * 0.38)
        ..lineTo(w * 0.76, sceneH * 0.56)
        ..lineTo(w * 0.56, sceneH * 0.53)
        ..close(),
    ];

    for (var i = 0; i < patches.length; i++) {
      final path = patches[i];
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9)
          ..shader = ui.Gradient.linear(
            Offset(w * 0.14, sceneH * 0.36),
            Offset(w * 0.72, sceneH * 0.59),
            [
              warmth.withValues(alpha: alpha * (i == 0 ? 1.0 : 0.72)),
              warmth.withValues(alpha: 0),
            ],
          ),
      );

      canvas.save();
      canvas.clipPath(path);
      final stripePaint = Paint()
        ..blendMode = BlendMode.plus
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFF9EA).withValues(alpha: alpha * 0.72);
      for (var s = 0; s < 3; s++) {
        final x = w * (0.22 + s * 0.11 + 0.008 * math.sin(phase + s));
        canvas.drawLine(
          Offset(x, sceneH * 0.34),
          Offset(x + w * 0.31, sceneH * 0.59),
          stripePaint,
        );
      }
      canvas.restore();
    }
  }

  void _paintLampAtmosphere(
    Canvas canvas,
    Size size,
    double sceneH,
    double hour,
    double phase,
  ) {
    final lamp = _lamp(hour);
    if (lamp <= 0.01) return;

    final w = size.width;
    final imgH = w / 0.8;
    final center = Offset(w * 0.645, imgH * 0.41);
    if (center.dy > sceneH) return;

    final breath = 0.88 + 0.12 * math.sin(phase * 0.74);
    const warm = Color(0xFFFFC27A);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.59, imgH * 0.54),
        width: w * 0.36,
        height: imgH * 0.12,
      ),
      Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 16)
        ..shader = ui.Gradient.radial(Offset(w * 0.59, imgH * 0.54), w * 0.28, [
          warm.withValues(alpha: 0.075 * lamp * breath),
          warm.withValues(alpha: 0),
        ]),
    );

    final motePaint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 7; i++) {
      final orbit = phase * (0.12 + i * 0.018) + i * 1.37;
      final r = w * (0.035 + i * 0.009);
      final pos = center.translate(
        math.cos(orbit) * r,
        math.sin(orbit * 1.4) * r * 0.48 + math.sin(phase + i) * 1.6,
      );
      final twinkle = 0.55 + 0.45 * math.sin(phase * (0.8 + i * 0.07) + i);
      motePaint.color = const Color(
        0xFFFFF0C8,
      ).withValues(alpha: 0.15 * lamp * twinkle);
      canvas.drawCircle(pos, 0.9 + (i % 3) * 0.45, motePaint);
    }
  }

  void _paintCompletionAura(
    Canvas canvas,
    Size size,
    double sceneH,
    double phase,
  ) {
    final w = size.width;
    final pulse = 0.88 + 0.12 * math.sin(phase);
    final center = Offset(w * 0.50, sceneH * 0.62);
    canvas.drawCircle(
      center,
      w * 0.34 * pulse,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(center, w * 0.34 * pulse, [
          accent.withValues(alpha: 0.06),
          const Color(0xFFFFF1A8).withValues(alpha: 0.035),
          Colors.transparent,
        ]),
    );
  }

  void _paintCompletionSparkles(
    Canvas canvas,
    Size size,
    double floorY,
    double phase,
  ) {
    final sparklePaint = Paint()
      ..color = const Color(
        0xFFFFD54F,
      ).withValues(alpha: 0.42 + progress * 0.24)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final points = [
      Offset(size.width * 0.22, floorY - 84),
      Offset(size.width * 0.39, floorY - 132),
      Offset(size.width * 0.62, floorY - 116),
      Offset(size.width * 0.78, floorY - 74),
      Offset(size.width * 0.52, floorY - 46),
      Offset(size.width * 0.31, floorY - 32),
      Offset(size.width * 0.69, floorY - 38),
    ];
    for (var i = 0; i < points.length; i++) {
      final twinkle = 0.58 + 0.42 * math.sin(phase * (0.9 + i * 0.05) + i);
      sparklePaint.color = Color.lerp(
        const Color(0xFFFFD54F),
        accent,
        0.28,
      )!.withValues(alpha: (0.30 + progress * 0.30) * twinkle);
      _drawTinySparkle(canvas, points[i], 4.0 + i % 2 * 1.6, sparklePaint);
    }
  }

  void _drawTinySparkle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant RoomSceneEffectsPainter old) =>
      old.accent != accent ||
      old.progress != progress ||
      old.allDone != allDone;
  // time 由 super(repaint: time) 驅動每幀重繪，不必列入 shouldRepaint。
}
