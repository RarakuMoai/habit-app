import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 計時圓環畫法（專注／運動共用）：暖白面盤 + 48 細刻度 + 纖細進度弧 + 弧端定位點。
/// 兩頁外觀一致，只差傳入的 [color]（專注暖橘、運動各子模式主色）。
class TimerRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const TimerRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(5.0, shortest * 0.028);
    final radius = shortest / 2 - stroke * 1.2;
    final bodyRadius = radius - stroke * 1.05;

    // 單層暖白面盤與細刻度，避免環內卡片、陰影和高光反覆疊出厚塑膠感。
    canvas.drawCircle(center, bodyRadius, Paint()..color = AppSurfaces.card);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius, track);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, stroke * 0.14)
      ..color = color.withValues(alpha: 0.16);
    for (var i = 0; i < 48; i++) {
      final a = -math.pi / 2 + i * math.pi / 24;
      final outer =
          center +
          Offset(
            math.cos(a) * (radius - stroke * 2.3),
            math.sin(a) * (radius - stroke * 2.3),
          );
      final inner =
          center +
          Offset(
            math.cos(a) * (radius - stroke * (i % 4 == 0 ? 3.5 : 2.9)),
            math.sin(a) * (radius - stroke * (i % 4 == 0 ? 3.5 : 2.9)),
          );
      canvas.drawLine(inner, outer, tickPaint);
    }

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
        colors: [color.withValues(alpha: 0.7), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      arc,
    );

    final angle = -math.pi / 2 + 2 * math.pi * p;
    final knob =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    canvas.drawCircle(knob, stroke * 0.56, Paint()..color = Colors.white);
    canvas.drawCircle(
      knob,
      stroke * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(TimerRingPainter old) =>
      old.progress != progress || old.color != color;
}
