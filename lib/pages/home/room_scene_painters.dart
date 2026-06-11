// 首頁場景 painter：背景上方的互動效果層。
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── 生成背景上方的互動效果層：保留狀態回饋，不再重畫整個房間 ──
class RoomSceneEffectsPainter extends CustomPainter {
  final Color accent;
  final double progress;
  final bool allDone;
  final int streak;

  RoomSceneEffectsPainter({
    required this.accent,
    required this.progress,
    required this.allDone,
    required this.streak,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final floorY = size.height * 0.52;
    if (streak >= 3) {
      _paintTrophy(canvas, Offset(size.width - 60, 202));
    }
    if (allDone) {
      _paintCompletionSparkles(canvas, size, floorY);
    }
  }

  void _paintTrophy(Canvas canvas, Offset base) {
    final gold = Paint()
      ..color = const Color(0xFFFFC857).withValues(alpha: 0.86);
    final darkGold = Paint()
      ..color = const Color(0xFFE0A928).withValues(alpha: 0.82);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(base.dx, base.dy - 17),
          width: 22,
          height: 20,
        ),
        const Radius.circular(4),
      ),
      gold,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(base.dx - 13, base.dy - 18),
        width: 16,
        height: 14,
      ),
      math.pi / 2,
      math.pi,
      false,
      darkGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(base.dx + 13, base.dy - 18),
        width: 16,
        height: 14,
      ),
      -math.pi / 2,
      math.pi,
      false,
      darkGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - 2),
        width: 5,
        height: 12,
      ),
      darkGold..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(base.dx, base.dy + 6),
          width: 26,
          height: 7,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF8D6E63).withValues(alpha: 0.64),
    );
  }

  void _paintCompletionSparkles(Canvas canvas, Size size, double floorY) {
    final sparklePaint = Paint()
      ..color = const Color(
        0xFFFFD54F,
      ).withValues(alpha: 0.48 + progress * 0.22)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final points = [
      Offset(size.width * 0.22, floorY - 84),
      Offset(size.width * 0.39, floorY - 132),
      Offset(size.width * 0.62, floorY - 116),
      Offset(size.width * 0.78, floorY - 74),
      Offset(size.width * 0.52, floorY - 46),
    ];
    for (var i = 0; i < points.length; i++) {
      _drawTinySparkle(canvas, points[i], 4.0 + i % 2 * 1.5, sparklePaint);
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
      old.allDone != allDone ||
      old.streak != streak;
}
