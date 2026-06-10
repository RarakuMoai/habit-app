// 首頁場景 painter：互動效果層與（備用的）完整房間場景。
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

// ── 兔咪場景背景 painter（窗戶、地板線、植物） ──
// ── 兔咪的家：完整房間場景 painter ──
// 目前未使用（背景已改用 home_bg.png CG 圖），保留備用。
// 包含：窗戶（避開頂部日期 pill）、畫框、書架、植物、地板分隔、坐墊
class RoomScenePainter extends CustomPainter {
  final Color accent;
  final bool isNight;
  final double progress;
  final bool allDone;
  final int streak;
  RoomScenePainter({
    required this.accent,
    required this.isNight,
    required this.progress,
    required this.allDone,
    required this.streak,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 場景區域大約佔上半部 ~55%（下方被白色習慣卡覆蓋）
    final floorY = h * 0.52;

    _paintWallTexture(canvas, size, floorY);

    // 1. 地板顏色帶（淡淡的木頭色調）
    final floorPaint = Paint()
      ..color = isNight
          ? const Color(0xFF6D4C41).withValues(alpha: 0.10)
          : const Color(0xFFBCAAA4).withValues(alpha: 0.18);
    canvas.drawRect(Rect.fromLTWH(0, floorY, w, h - floorY), floorPaint);
    _paintFloorBoards(canvas, size, floorY);
    _paintRug(
      canvas,
      Rect.fromCenter(
        center: Offset(w / 2, floorY + 42),
        width: math.min(260, w * 0.68),
        height: 74,
      ),
    );

    // 地板與牆的分隔線
    final lineP = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, floorY), Offset(w, floorY), lineP);

    // 2. 窗戶（右側，避開左邊的日期 pill）
    final windowRect = Rect.fromLTWH(w - 96, 112, 78, 68);
    _paintWindowGlow(canvas, windowRect);
    _paintWindow(canvas, windowRect);

    // 3. 牆上畫框（左側，明確在日期 pill 下方）
    _paintPictureFrame(canvas, Rect.fromLTWH(28, 168, 52, 44));

    // 4. 書架（右側，畫框對應位置）
    _paintShelf(canvas, Rect.fromLTWH(w - 88, 208, 66, 18));

    if (streak >= 3) {
      _paintTrophy(canvas, Offset(w - 60, 202));
    }

    // 5. 兔咪坐墊已移至前景兔咪 SizedBox 內（_CushionPainter），確保與兔咪連動

    // 6. 盆栽（左下角地板）
    _paintPlant(canvas, Offset(34, floorY - 8));

    // 7. 小檯燈（右下角地板）
    _paintLamp(canvas, Offset(w - 38, floorY - 22));

    if (allDone) {
      _paintCompletionSparkles(canvas, size, floorY);
    }
  }

  void _paintWallTexture(Canvas canvas, Size size, double floorY) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: isNight ? 0.12 : 0.22);
    for (var y = 88.0; y < floorY - 22; y += 34) {
      for (var x = 18.0; x < size.width; x += 42) {
        final offset = ((y / 34).round().isEven ? 0 : 18).toDouble();
        canvas.drawCircle(Offset(x + offset, y), 1.2, dotPaint);
      }
    }
  }

  void _paintFloorBoards(Canvas canvas, Size size, double floorY) {
    final boardPaint = Paint()
      ..color = Colors.white.withValues(alpha: isNight ? 0.10 : 0.18)
      ..strokeWidth = 1;
    for (var y = floorY + 24; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), boardPaint);
    }
    for (var x = 28.0; x < size.width; x += 76) {
      canvas.drawLine(
        Offset(x, floorY + 8),
        Offset(x + 22, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: isNight ? 0.05 : 0.10)
          ..strokeWidth = 0.8,
      );
    }
  }

  void _paintRug(Canvas canvas, Rect rect) {
    final base = Paint()
      ..color = accent.withValues(alpha: isNight ? 0.18 : 0.24);
    canvas.drawOval(rect, base);
    canvas.drawOval(
      rect.deflate(9),
      Paint()..color = Colors.white.withValues(alpha: isNight ? 0.11 : 0.20),
    );
    canvas.drawOval(
      rect.deflate(18),
      Paint()..color = accent.withValues(alpha: isNight ? 0.13 : 0.20),
    );
  }

  void _paintWindowGlow(Canvas canvas, Rect rect) {
    final glowRect = Rect.fromCenter(
      center: Offset(rect.center.dx - 20, rect.center.dy + 52),
      width: 170,
      height: 118,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..color = (isNight ? const Color(0xFFFFF3C4) : const Color(0xFFFFF8E1))
            .withValues(alpha: isNight ? 0.13 : 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _paintWindow(Canvas canvas, Rect rect) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // 窗框外緣
    canvas.drawRRect(
      r,
      Paint()..color = const Color(0xFF8D6E63).withValues(alpha: 0.55),
    );
    // 窗內天空
    final innerR = RRect.fromRectAndRadius(
      rect.deflate(3),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      innerR,
      Paint()
        ..color = isNight
            ? const Color(0xFF1A237E).withValues(alpha: 0.35)
            : const Color(0xFF81D4FA).withValues(alpha: 0.55),
    );
    // 窗格十字
    final cross = Paint()
      ..color = const Color(0xFF8D6E63).withValues(alpha: 0.6)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(rect.center.dx, rect.top + 3),
      Offset(rect.center.dx, rect.bottom - 3),
      cross,
    );
    canvas.drawLine(
      Offset(rect.left + 3, rect.center.dy),
      Offset(rect.right - 3, rect.center.dy),
      cross,
    );

    // 日/月
    final celestialCx = rect.center.dx - 12;
    final celestialCy = rect.center.dy - 10;
    if (isNight) {
      canvas.drawCircle(
        Offset(celestialCx, celestialCy),
        7,
        Paint()..color = const Color(0xFFFFD54F),
      );
      final star = Paint()..color = const Color(0xFFFFEB3B);
      canvas.drawCircle(Offset(rect.right - 10, rect.top + 10), 1.5, star);
      canvas.drawCircle(Offset(rect.left + 10, rect.bottom - 12), 1.5, star);
    } else {
      canvas.drawCircle(
        Offset(celestialCx, celestialCy),
        8,
        Paint()..color = const Color(0xFFFFB74D),
      );
    }

    // 窗簾（左右各一條，溫馨感）
    final curtain = Paint()
      ..color = const Color(0xFFEF9A9A).withValues(alpha: 0.55);
    final curtainW = 8.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left - 4, rect.top - 2, curtainW, rect.height + 4),
        const Radius.circular(3),
      ),
      curtain,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.right - 4, rect.top - 2, curtainW, rect.height + 4),
        const Radius.circular(3),
      ),
      curtain,
    );
  }

  void _paintPictureFrame(Canvas canvas, Rect rect) {
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(
      outer,
      Paint()..color = const Color(0xFF8D6E63).withValues(alpha: 0.6),
    );
    final inner = RRect.fromRectAndRadius(
      rect.deflate(3),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      inner,
      Paint()..color = const Color(0xFFFFE0B2).withValues(alpha: 0.85),
    );
    // 畫框內：愛心
    final heartCenter = rect.center;
    final heartPaint = Paint()
      ..color = const Color(0xFFE57373).withValues(alpha: 0.85);
    final r = 4.0;
    canvas.drawCircle(
      Offset(heartCenter.dx - r * 0.8, heartCenter.dy - 1),
      r,
      heartPaint,
    );
    canvas.drawCircle(
      Offset(heartCenter.dx + r * 0.8, heartCenter.dy - 1),
      r,
      heartPaint,
    );
    final path = Path()
      ..moveTo(heartCenter.dx - r * 1.6, heartCenter.dy + 1)
      ..lineTo(heartCenter.dx, heartCenter.dy + r * 1.8)
      ..lineTo(heartCenter.dx + r * 1.6, heartCenter.dy + 1)
      ..close();
    canvas.drawPath(path, heartPaint);
  }

  void _paintShelf(Canvas canvas, Rect rect) {
    // 木板
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF8D6E63).withValues(alpha: 0.55),
    );
    // 三本書
    final colors = [
      const Color(0xFFE57373),
      const Color(0xFF81D4FA),
      const Color(0xFFAED581),
    ];
    final bookW = rect.width / 4;
    for (var i = 0; i < 3; i++) {
      final bx = rect.left + 6 + i * (bookW + 1);
      final by = rect.top - 16;
      canvas.drawRect(
        Rect.fromLTWH(bx, by, bookW, 16),
        Paint()..color = colors[i].withValues(alpha: 0.85),
      );
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
      ).withValues(alpha: 0.48 + progress * 0.22);
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
      paint
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
  }

  void _paintPlant(Canvas canvas, Offset base) {
    // 花盆
    final potRect = Rect.fromCenter(
      center: Offset(base.dx, base.dy + 8),
      width: 26,
      height: 18,
    );
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        potRect.left,
        potRect.top,
        potRect.right,
        potRect.bottom,
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
        topLeft: const Radius.circular(1),
        topRight: const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFFA1887F).withValues(alpha: 0.85),
    );
    // 葉子（三片，由小到大）
    final leaf = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.78);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx - 8, base.dy - 4),
        width: 14,
        height: 18,
      ),
      leaf,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx + 8, base.dy - 4),
        width: 14,
        height: 18,
      ),
      leaf,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - 12),
        width: 16,
        height: 20,
      ),
      Paint()..color = const Color(0xFF81C784).withValues(alpha: 0.85),
    );
  }

  void _paintLamp(Canvas canvas, Offset base) {
    // 燈座
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy + 12),
        width: 16,
        height: 6,
      ),
      Paint()..color = const Color(0xFF6D4C41).withValues(alpha: 0.65),
    );
    // 燈柱
    canvas.drawRect(
      Rect.fromCenter(center: Offset(base.dx, base.dy), width: 2, height: 22),
      Paint()..color = const Color(0xFF6D4C41).withValues(alpha: 0.65),
    );
    // 燈罩（梯形樣）
    final shadePath = Path()
      ..moveTo(base.dx - 12, base.dy - 12)
      ..lineTo(base.dx + 12, base.dy - 12)
      ..lineTo(base.dx + 8, base.dy - 24)
      ..lineTo(base.dx - 8, base.dy - 24)
      ..close();
    canvas.drawPath(
      shadePath,
      Paint()
        ..color = isNight
            ? const Color(0xFFFFE082).withValues(alpha: 0.85)
            : const Color(0xFF90CAF9).withValues(alpha: 0.55),
    );
    // 燈光暈（夜間更明顯）
    if (isNight) {
      canvas.drawCircle(
        Offset(base.dx, base.dy - 18),
        18,
        Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RoomScenePainter old) =>
      old.accent != accent ||
      old.isNight != isNight ||
      old.progress != progress ||
      old.allDone != allDone ||
      old.streak != streak;
}
