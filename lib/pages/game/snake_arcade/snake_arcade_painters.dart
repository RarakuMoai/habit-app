// 菜園小蛇的畫家群：主視窗（大地圖裁切）、小地圖、像素窗簾。
//
// 視覺走「暖奶油菜園」：奶油底、柔綠田畦、暖棕籬笆；全部暖色系、
// 無冷灰純黑（對齊 visual_spec 與骰子彩蛋「回歸兔咪家視覺」的定案）。
// 鏡頭採安全區跟隨、在世界邊緣 clamp，並額外外擴 [cameraPadCells] 格，
// 讓籬笆在貼邊時仍完整可見，玩家不會誤判底牆。

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'snake_arcade_engine.dart';

/// 主視窗固定顯示 15 欄；列數依實際長方形高度動態增加。
const double kArcadeViewportColumns = 15;

/// 鏡頭在世界外圍多留的格數，保證邊線籬笆完整入鏡。
const double kArcadeCameraPadCells = 0.6;

abstract final class ArcadePalette {
  static const fieldA = Color(0xFFEDF2DF);
  static const fieldB = Color(0xFFE7EED3);
  static const outside = Color(0xFFF3ECDD);
  static const fence = Color(0xFF9A7A55);
  static const fenceLight = Color(0xFFB99A73);

  static const snakeBody = Color(0xFF4C8A75);
  static const snakeBodyAlt = Color(0xFF3F7868);
  static const snakeHead = Color(0xFF2E5F50);
  static const huntBody = Color(0xFFE0A63C);
  static const huntBodyAlt = Color(0xFFD29632);
  static const huntHead = Color(0xFFB97F1F);

  static const carrot = Color(0xFFE8813C);
  static const carrotDark = Color(0xFFD06F2C);
  static const leaf = Color(0xFF6FA34C);
  static const gold = Color(0xFFE3B23A);
  static const magnet = Color(0xFFB65D86);
  static const magnetGlow = Color(0xFFF2B7D0);
  static const laser = Color(0xFFFFF2A8);
  static const laserGlow = Color(0xFFE8B84E);

  static const mole = Color(0xFF7B5A46);
  static const moleLight = Color(0xFF9C7A64);
  static const mound = Color(0xFFC7AE8F);
  static const moundDark = Color(0xFFB09877);
  static const seed = Color(0xFF5E4633);

  static const arrow = Color(0xFFB9773B);
}

/// 鏡頭單軸左上角（世界座標，格為單位）的合法範圍夾取。
double clampArcadeCamera(double value, double viewportCells) {
  final minimum = -kArcadeCameraPadCells;
  final maximum = math.max(
    minimum,
    SnakeArcadeEngine.worldSize + kArcadeCameraPadCells - viewportCells,
  );
  return value.clamp(minimum, maximum).toDouble();
}

double _lerpCell(int from, int to, double progress) =>
    from + (to - from) * progress;

class SnakeArcadeBoardPainter extends CustomPainter {
  SnakeArcadeBoardPainter({
    required this.engine,
    required this.cameraX,
    required this.cameraY,
    required this.pulse,
  });

  final SnakeArcadeEngine engine;
  final double cameraX;
  final double cameraY;

  /// 0→1 循環的呼吸值：土丘預告、金蘿蔔光暈、狩獵倒數閃爍共用。
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kArcadeViewportColumns;
    final viewportRows = size.height / cell;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = ArcadePalette.outside);

    Offset toScreen(double worldX, double worldY) =>
        Offset((worldX - cameraX) * cell, (worldY - cameraY) * cell);

    // ── 田畦棋盤格 ──
    const world = SnakeArcadeEngine.worldSize;
    final firstX = math.max(0, cameraX.floor());
    final firstY = math.max(0, cameraY.floor());
    final lastX = math.min(
      world - 1,
      (cameraX + kArcadeViewportColumns).ceil(),
    );
    final lastY = math.min(world - 1, (cameraY + viewportRows).ceil());
    final fieldPaint = Paint();
    for (var y = firstY; y <= lastY; y++) {
      for (var x = firstX; x <= lastX; x++) {
        fieldPaint.color = (x + y).isEven
            ? ArcadePalette.fieldA
            : ArcadePalette.fieldB;
        canvas.drawRect(
          Rect.fromPoints(
            toScreen(x.toDouble(), y.toDouble()),
            toScreen(x + 1.0, y + 1.0),
          ),
          fieldPaint,
        );
      }
    }

    // ── 籬笆（世界界線外側 0.55 格厚的暖棕木欄）──
    final fenceThickness = cell * 0.55;
    final worldRect = Rect.fromPoints(
      toScreen(0, 0),
      toScreen(world.toDouble(), world.toDouble()),
    );
    final fenceRect = worldRect.inflate(fenceThickness);
    final fencePaint = Paint()
      ..color = ArcadePalette.fence
      ..style = PaintingStyle.stroke
      ..strokeWidth = fenceThickness;
    canvas.drawRect(worldRect.inflate(fenceThickness / 2), fencePaint);
    // 籬笆上的亮色橫紋，加強「木欄」辨識。
    final slat = Paint()
      ..color = ArcadePalette.fenceLight
      ..strokeWidth = math.max(1.5, cell * 0.10);
    const slatGapCells = 2.5;
    for (var wx = 0.0; wx <= world; wx += slatGapCells) {
      final top = toScreen(wx, 0);
      final bottom = toScreen(wx, world.toDouble());
      canvas.drawLine(
        Offset(top.dx, top.dy - fenceThickness * 0.75),
        Offset(top.dx, top.dy - fenceThickness * 0.25),
        slat,
      );
      canvas.drawLine(
        Offset(bottom.dx, bottom.dy + fenceThickness * 0.25),
        Offset(bottom.dx, bottom.dy + fenceThickness * 0.75),
        slat,
      );
    }
    for (var wy = 0.0; wy <= world; wy += slatGapCells) {
      final left = toScreen(0, wy);
      final right = toScreen(world.toDouble(), wy);
      canvas.drawLine(
        Offset(left.dx - fenceThickness * 0.75, left.dy),
        Offset(left.dx - fenceThickness * 0.25, left.dy),
        slat,
      );
      canvas.drawLine(
        Offset(right.dx + fenceThickness * 0.25, right.dy),
        Offset(right.dx + fenceThickness * 0.75, right.dy),
        slat,
      );
    }
    canvas.save();
    canvas.clipRect(fenceRect);

    Rect worldCellRect(double x, double y, {double inset = 0}) =>
        Rect.fromPoints(
          toScreen(x + inset, y + inset),
          toScreen(x + 1.0 - inset, y + 1.0 - inset),
        );

    Rect cellRect(ArcadePoint p, {double inset = 0}) =>
        worldCellRect(p.x.toDouble(), p.y.toDouble(), inset: inset);

    bool visibleAt(double x, double y) =>
        x + 1 > cameraX - 1 &&
        x < cameraX + kArcadeViewportColumns + 1 &&
        y + 1 > cameraY - 1 &&
        y < cameraY + viewportRows + 1;

    bool visible(ArcadePoint p) => visibleAt(p.x.toDouble(), p.y.toDouble());

    // ── 收集物 ──
    for (final item in engine.collectibles) {
      if (!visible(item.cell)) continue;
      final rect = cellRect(item.cell, inset: 0.12);
      switch (item.type) {
        case ArcadeCollectibleType.carrot:
          _paintCarrot(canvas, rect, cell);
        case ArcadeCollectibleType.gold:
          _paintGoldCarrot(canvas, rect, cell);
        case ArcadeCollectibleType.magnetFruit:
          final center = rect.center;
          canvas.drawCircle(
            center,
            rect.width * (0.48 + pulse * 0.05),
            Paint()..color = ArcadePalette.magnetGlow.withValues(alpha: 0.42),
          );
          canvas.drawCircle(
            center,
            rect.width * 0.34,
            Paint()..color = ArcadePalette.magnet,
          );
          canvas.drawCircle(
            center.translate(-rect.width * 0.09, -rect.height * 0.09),
            rect.width * 0.07,
            Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.82),
          );
      }
    }

    // ── 鼴鼠與土丘預告 ──
    for (final mole in engine.moles) {
      final progress = mole.state == ArcadeMoleState.active
          ? engine.moleRenderProgress
          : 1.0;
      final x = _lerpCell(mole.previousCell.x, mole.cell.x, progress);
      final y = _lerpCell(mole.previousCell.y, mole.cell.y, progress);
      if (!visibleAt(x, y)) continue;
      final rect = worldCellRect(x, y, inset: 0.10);
      if (mole.state == ArcadeMoleState.telegraph) {
        _paintMound(canvas, rect);
      } else {
        _paintMole(canvas, rect, mole.facing);
      }
    }

    // ── 種子 ──
    final seedPaint = Paint()..color = ArcadePalette.seed;
    for (final bullet in engine.bullets) {
      final x = _lerpCell(
        bullet.previousCell.x,
        bullet.cell.x,
        engine.bulletRenderProgress,
      );
      final y = _lerpCell(
        bullet.previousCell.y,
        bullet.cell.y,
        engine.bulletRenderProgress,
      );
      if (!visibleAt(x, y)) continue;
      final rect = worldCellRect(x, y, inset: 0.34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.45)),
        seedPaint,
      );
    }

    // ── 三排雷射（140ms 短閃；三條路徑直接把能力範圍說清楚）──
    if (engine.laserFlashMsLeft > 0) {
      final alpha =
          engine.laserFlashMsLeft / SnakeArcadeEngine.laserFlashDurationMs;
      final (dx, dy) = switch (engine.direction) {
        ArcadeDirection.up => (0, -1),
        ArcadeDirection.down => (0, 1),
        ArcadeDirection.left => (-1, 0),
        ArcadeDirection.right => (1, 0),
      };
      final (px, py) = (-dy, dx);
      for (var lane = -1; lane <= 1; lane++) {
        final startX = engine.head.x + 0.5 + px * lane;
        final startY = engine.head.y + 0.5 + py * lane;
        if (startX < 0 || startX >= world || startY < 0 || startY >= world) {
          continue;
        }
        final endX = (startX + dx * SnakeArcadeEngine.laserRange).clamp(
          0.5,
          world - 0.5,
        );
        final endY = (startY + dy * SnakeArcadeEngine.laserRange).clamp(
          0.5,
          world - 0.5,
        );
        final start = toScreen(startX, startY);
        final end = toScreen(endX, endY);
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = ArcadePalette.laserGlow.withValues(alpha: alpha * 0.42)
            ..strokeWidth = cell * 0.76
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = ArcadePalette.laser.withValues(alpha: alpha * 0.92)
            ..strokeWidth = cell * 0.22
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // ── 蛇（尾到頭，讓頭壓在最上面）──
    final hunt = engine.huntActive;
    // 狩獵最後 3 秒金色→原色閃爍警告。
    final huntFlash = hunt && engine.huntMsLeft <= 3000 && pulse > 0.5;
    final bodyColor = hunt && !huntFlash
        ? ArcadePalette.huntBody
        : ArcadePalette.snakeBody;
    final bodyAlt = hunt && !huntFlash
        ? ArcadePalette.huntBodyAlt
        : ArcadePalette.snakeBodyAlt;
    final headColor = hunt && !huntFlash
        ? ArcadePalette.huntHead
        : ArcadePalette.snakeHead;
    final body = engine.body;
    final segmentPaint = Paint();
    for (var i = body.length - 1; i >= 1; i--) {
      if (!visible(body[i])) continue;
      segmentPaint.color = i.isEven ? bodyColor : bodyAlt;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect(body[i], inset: 0.06),
          Radius.circular(cell * 0.22),
        ),
        segmentPaint,
      );
    }
    final headX = engine.head.x.toDouble();
    final headY = engine.head.y.toDouble();
    final headRect = cellRect(engine.head, inset: 0.02);
    _paintHead(canvas, headRect, cell, headColor);

    // 五倍待發：頭頂星光。
    if (engine.fiveFoldArmed) {
      _paintSparkle(
        canvas,
        headRect.center.translate(cell * 0.42, -cell * 0.42),
        cell * (0.22 + 0.08 * pulse),
      );
    }

    canvas.restore();

    // ── 目標方向箭頭：視窗內沒有任何收集物時指向最近的一個 ──
    _paintTargetArrow(canvas, size, cell, toScreen, headX, headY);
  }

  void _paintCarrot(Canvas canvas, Rect rect, double cell) {
    final root = Path()
      ..moveTo(rect.left + rect.width * 0.22, rect.top + rect.height * 0.34)
      ..lineTo(rect.right - rect.width * 0.10, rect.top + rect.height * 0.22)
      ..lineTo(rect.center.dx + rect.width * 0.06, rect.bottom)
      ..close();
    canvas.drawPath(root, Paint()..color = ArcadePalette.carrot);
    canvas.drawLine(
      Offset(rect.center.dx - rect.width * 0.02, rect.center.dy),
      Offset(
        rect.center.dx + rect.width * 0.16,
        rect.center.dy - rect.height * 0.06,
      ),
      Paint()
        ..color = ArcadePalette.carrotDark
        ..strokeWidth = math.max(1, cell * 0.05),
    );
    final leaf = Paint()..color = ArcadePalette.leaf;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          rect.right - rect.width * 0.12,
          rect.top + rect.height * 0.12,
        ),
        width: rect.width * 0.30,
        height: rect.height * 0.18,
      ),
      leaf,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          rect.right - rect.width * 0.26,
          rect.top + rect.height * 0.06,
        ),
        width: rect.width * 0.18,
        height: rect.height * 0.26,
      ),
      leaf,
    );
  }

  void _paintGoldCarrot(Canvas canvas, Rect rect, double cell) {
    canvas.drawCircle(
      rect.center,
      rect.width * (0.58 + 0.10 * pulse),
      Paint()..color = ArcadePalette.gold.withValues(alpha: 0.30),
    );
    final root = Path()
      ..moveTo(rect.left + rect.width * 0.20, rect.top + rect.height * 0.30)
      ..lineTo(rect.right - rect.width * 0.08, rect.top + rect.height * 0.20)
      ..lineTo(rect.center.dx + rect.width * 0.08, rect.bottom)
      ..close();
    canvas.drawPath(root, Paint()..color = ArcadePalette.gold);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          rect.right - rect.width * 0.14,
          rect.top + rect.height * 0.10,
        ),
        width: rect.width * 0.28,
        height: rect.height * 0.18,
      ),
      Paint()..color = ArcadePalette.leaf,
    );
    _paintSparkle(
      canvas,
      rect.topLeft.translate(rect.width * 0.16, rect.height * 0.10),
      rect.width * 0.14,
    );
  }

  void _paintSparkle(Canvas canvas, Offset center, double radius) {
    final paint = Paint()..color = const Color(0xFFFFF6DE);
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.32, center.dy - radius * 0.32)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx + radius * 0.32, center.dy + radius * 0.32)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.32, center.dy + radius * 0.32)
      ..lineTo(center.dx - radius, center.dy)
      ..lineTo(center.dx - radius * 0.32, center.dy - radius * 0.32)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _paintMound(Canvas canvas, Rect rect) {
    // 預告呼吸：小土丘微微起伏＋三點土屑。
    final lift = rect.height * 0.06 * pulse;
    final mound = Rect.fromLTRB(
      rect.left,
      rect.top + rect.height * 0.38 - lift,
      rect.right,
      rect.bottom,
    );
    canvas.drawArc(
      mound,
      math.pi,
      math.pi,
      true,
      Paint()..color = ArcadePalette.mound,
    );
    final dot = Paint()..color = ArcadePalette.moundDark;
    for (final dx in const [0.28, 0.52, 0.74]) {
      canvas.drawCircle(
        Offset(
          rect.left + rect.width * dx,
          rect.top + rect.height * (0.30 - 0.10 * pulse),
        ),
        rect.width * 0.05,
        dot,
      );
    }
  }

  void _paintMole(Canvas canvas, Rect rect, ArcadeDirection facing) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.38)),
      Paint()..color = ArcadePalette.mole,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: rect.center.translate(0, rect.height * 0.14),
        width: rect.width * 0.62,
        height: rect.height * 0.48,
      ),
      Paint()..color = ArcadePalette.moleLight,
    );
    // 面向側的鼻頭與眼睛。
    final forward = Offset(facing.dx.toDouble(), facing.dy.toDouble());
    final nose = rect.center + forward * rect.width * 0.30;
    canvas.drawCircle(
      nose,
      rect.width * 0.11,
      Paint()..color = ArcadePalette.carrotDark,
    );
    final side = Offset(-forward.dy, forward.dx);
    final eyePaint = Paint()..color = const Color(0xFF3E2C21);
    for (final sign in const [1.0, -1.0]) {
      canvas.drawCircle(
        rect.center +
            forward * rect.width * 0.10 +
            side * rect.width * 0.16 * sign,
        rect.width * 0.06,
        eyePaint,
      );
    }
  }

  void _paintHead(Canvas canvas, Rect rect, double cell, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.30)),
      Paint()..color = color,
    );
    final angle = switch (engine.direction) {
      ArcadeDirection.right => 0.0,
      ArcadeDirection.down => math.pi / 2,
      ArcadeDirection.left => math.pi,
      ArcadeDirection.up => -math.pi / 2,
    };
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    final white = Paint()..color = const Color(0xFFFFFDF6);
    final pupil = Paint()..color = const Color(0xFF243B31);
    for (final y in [-cell * 0.17, cell * 0.17]) {
      final eye = Offset(cell * 0.16, y);
      canvas.drawCircle(eye, cell * 0.10, white);
      canvas.drawCircle(eye.translate(cell * 0.03, 0), cell * 0.05, pupil);
    }
    canvas.restore();
  }

  void _paintTargetArrow(
    Canvas canvas,
    Size size,
    double cell,
    Offset Function(double, double) toScreen,
    double headX,
    double headY,
  ) {
    if (engine.collectibles.isEmpty) return;
    final headScreen = toScreen(headX + 0.5, headY + 0.5);
    ArcadeCollectible? nearest;
    var nearestDistance = 1 << 30;
    var anyVisible = false;
    final viewRect = Offset.zero & size;
    for (final item in engine.collectibles) {
      final screen = toScreen(item.cell.x + 0.5, item.cell.y + 0.5);
      if (viewRect.contains(screen)) {
        anyVisible = true;
        break;
      }
      final distance = engine.head.chebyshev(item.cell);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = item;
      }
    }
    if (anyVisible || nearest == null) return;

    final target = toScreen(nearest.cell.x + 0.5, nearest.cell.y + 0.5);
    final delta = target - headScreen;
    if (delta.distance < 1) return;
    final direction = delta / delta.distance;
    final margin = cell * 0.55;
    // 沿「畫面中心→目標」方向推到視窗邊緣內縮 margin 的位置。
    final center = Offset(size.width / 2, size.height / 2);
    var t = double.infinity;
    if (direction.dx.abs() > 1e-6) {
      t = math.min(
        t,
        ((direction.dx > 0 ? size.width - margin : margin) - center.dx) /
            direction.dx,
      );
    }
    if (direction.dy.abs() > 1e-6) {
      t = math.min(
        t,
        ((direction.dy > 0 ? size.height - margin : margin) - center.dy) /
            direction.dy,
      );
    }
    if (!t.isFinite) return;
    final tip = center + direction * t;
    final angle = math.atan2(direction.dy, direction.dx);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    final arrow = Path()
      ..moveTo(cell * 0.30, 0)
      ..lineTo(-cell * 0.16, -cell * 0.22)
      ..lineTo(-cell * 0.06, 0)
      ..lineTo(-cell * 0.16, cell * 0.22)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = ArcadePalette.arrow.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SnakeArcadeBoardPainter oldDelegate) => true;
}

/// 小地圖：世界外框、蛇身淡跡、蛇頭、收集物、鼴鼠與目前視窗框。
class SnakeArcadeMinimapPainter extends CustomPainter {
  SnakeArcadeMinimapPainter({
    required this.engine,
    required this.cameraX,
    required this.cameraY,
    required this.viewportColumns,
    required this.viewportRows,
  });

  final SnakeArcadeEngine engine;
  final double cameraX;
  final double cameraY;
  final double viewportColumns;
  final double viewportRows;

  @override
  void paint(Canvas canvas, Size size) {
    const world = SnakeArcadeEngine.worldSize;
    final scale = size.width / world;
    final radius = Radius.circular(size.width * 0.08);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = ArcadePalette.fieldA,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()
        ..color = ArcadePalette.fence
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.03),
    );

    Offset dot(ArcadePoint p) =>
        Offset((p.x + 0.5) * scale, (p.y + 0.5) * scale);

    final trail = Paint()
      ..color = ArcadePalette.snakeBody.withValues(alpha: 0.45);
    for (final segment in engine.body) {
      canvas.drawCircle(dot(segment), scale * 0.7, trail);
    }

    final carrotPaint = Paint()..color = ArcadePalette.carrot;
    final goldPaint = Paint()..color = ArcadePalette.gold;
    final magnetPaint = Paint()..color = ArcadePalette.magnet;
    for (final item in engine.collectibles) {
      canvas.drawCircle(dot(item.cell), scale * 1.1, switch (item.type) {
        ArcadeCollectibleType.carrot => carrotPaint,
        ArcadeCollectibleType.gold => goldPaint,
        ArcadeCollectibleType.magnetFruit => magnetPaint,
      });
    }

    final molePaint = Paint()..color = ArcadePalette.mole;
    for (final mole in engine.moles) {
      if (mole.state != ArcadeMoleState.active) continue;
      canvas.drawCircle(dot(mole.cell), scale * 1.1, molePaint);
    }

    canvas.drawCircle(
      dot(engine.head),
      scale * 1.4,
      Paint()..color = ArcadePalette.snakeHead,
    );

    canvas.drawRect(
      Rect.fromLTWH(
        cameraX * scale,
        cameraY * scale,
        viewportColumns * scale,
        viewportRows * scale,
      ),
      Paint()
        ..color = ArcadePalette.arrow
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.02),
    );
  }

  @override
  bool shouldRepaint(SnakeArcadeMinimapPainter oldDelegate) => true;
}

/// 全螢幕像素窗簾：延續骰子彩蛋的復古儀式感，換成菜園色盤。
class ArcadePixelCurtainPainter extends CustomPainter {
  const ArcadePixelCurtainPainter(this.progress);

  final double progress;

  static const _palette = <Color>[
    Color(0xFFFFF8EC),
    Color(0xFFF3ECDD),
    Color(0xFFE7EED3),
    Color(0xFFD9E5C4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    final cell = (size.width / 22).clamp(14.0, 26.0);
    final columns = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final paint = Paint();
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final hash = ((column * 73856093) ^ (row * 19349663)) & 0x7fffffff;
        if ((hash % 997) / 997 >= progress) continue;
        paint.color = hash % 31 == 0
            ? ArcadePalette.carrot
            : _palette[hash % _palette.length];
        canvas.drawRect(
          Rect.fromLTWH(
            column * cell,
            row * cell,
            math.min(cell + 0.5, size.width - column * cell),
            math.min(cell + 0.5, size.height - row * cell),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ArcadePixelCurtainPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
