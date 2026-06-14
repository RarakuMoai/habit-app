import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 計時圓環畫法（專注／運動共用）：柔和內盤 + 12 刻度 + 進度弧 + 弧端旋鈕。
/// 兩頁外觀一致，只差傳入的 [color]（專注番茄色、運動各子模式主色）。
class TimerRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const TimerRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(8.0, shortest * 0.048);
    final radius = shortest / 2 - stroke * 0.8;
    final bodyRadius = radius - stroke * 1.05;

    final bodyRect = Rect.fromCircle(center: center, radius: bodyRadius);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.34, -0.42),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.96),
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0.16),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, bodyRadius, bodyPaint);

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.50)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-bodyRadius * 0.34, -bodyRadius * 0.30),
        width: bodyRadius * 0.38,
        height: bodyRadius * 0.18,
      ),
      highlight,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, stroke * 0.16)
      ..color = color.withValues(alpha: 0.16);
    for (var i = 0; i < 12; i++) {
      final a = -math.pi / 2 + i * math.pi / 6;
      final outer = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
      final inner =
          center +
          Offset(
            math.cos(a) * (radius - stroke * (i % 3 == 0 ? 1.18 : 0.82)),
            math.sin(a) * (radius - stroke * (i % 3 == 0 ? 1.18 : 0.82)),
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
    canvas.drawCircle(
      knob,
      stroke * 0.72,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
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
