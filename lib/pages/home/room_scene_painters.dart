// 首頁場景 painter：背景上方的「全完成」慶祝效果層。
//
// 2026-07 四時段完整背景（four_period_background.dart）上線後，本層
// 原本的房間深度/地板光池/檯燈氛圍全部由背景圖承擔而移除；只保留
// 與時間無關的狀態回饋（完成光暈＋星光），並且只在全完成時掛載。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/scene_clock.dart' show ThrottledSceneTicker;
import 'room_metrics.dart';

/// 首頁「全完成」慶祝層（光暈＋星光）。
/// 與其他場景層同模式：共享 20fps 場景時鐘 + RepaintBoundary，
/// 外層用 TickerMode(enabled: !idle) 凍結省電；只在全完成時掛載。
class RoomSceneEffects extends StatefulWidget {
  final Color accent;
  final double progress;

  /// 共享場景時鐘（見 SceneAnimationClock）；null = 自建 30fps ticker。
  final ValueNotifier<double>? clock;

  const RoomSceneEffects({
    super.key,
    required this.accent,
    required this.progress,
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
            time: sceneTime,
          ),
        ),
      ),
    );
  }
}

class RoomSceneEffectsPainter extends CustomPainter {
  @visibleForTesting
  static const completionAuraStops = <double>[0.0, 0.5, 1.0];

  final Color accent;
  final double progress;

  /// 開場至今秒數（無界）；12 秒一圈換算成 phase。節流由 [RoomSceneEffects]
  /// 的 ticker 負責，這裡只負責把秒數映射成相位。
  final ValueNotifier<double> time;

  RoomSceneEffectsPainter({
    required this.accent,
    required this.progress,
    required this.time,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = time.value * (math.pi / 6.0); // 2π / 12s
    final sceneH = roomEffectsSceneHeight(size.width);
    final floorY = sceneH * 0.82;
    _paintCompletionAura(canvas, size, sceneH, phase);
    _paintCompletionSparkles(canvas, size, floorY, phase);
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
        ], completionAuraStops),
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
      old.accent != accent || old.progress != progress;
  // time 由 super(repaint: time) 驅動每幀重繪，不必列入 shouldRepaint。
}
