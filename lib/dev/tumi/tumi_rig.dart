import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tumi_traced_data.dart';

/// 兔咪動畫骨架：把描圖色塊按部位分組，各自掛變換。
///
/// 分組（描圖數據的座標特徵分類）：
/// - earL / earR：耳灰、耳粉、耳粉陰影（質心 x 偏左/右側）
/// - eyeL / eyeR：黑眼珠＋高光（眨眼時垂直壓扁）
/// - head：頭灰、白臉帶、腮紅、鼻嘴記號
/// - body：身體灰、肚白、腳掌、手掌尖
///
/// 呼吸（整體縮放）由外層 widget 做，這裡只管部位變換。
class TumiRigPainter extends CustomPainter {
  /// 耳朵擺角（-1..1，實際角度 ×0.06 rad）
  final double earL;
  final double earR;

  /// 眨眼（0 全開 → 1 全閉）
  final double blink;

  const TumiRigPainter({this.earL = 0, this.earR = 0, this.blink = 0});

  static const _earPivotL = Offset(350, 235);
  static const _earPivotR = Offset(674, 235);

  static _Groups? _cache;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _cache ??= _classify();
    final s = size.shortestSide / 1024.0;
    canvas.save();
    canvas.scale(s);

    _drawGroup(canvas, g.body);

    _drawGroup(canvas, g.head);

    // 眼睛：眨眼時繞各自中心垂直壓扁
    for (final eye in [g.eyeL, g.eyeR]) {
      canvas.save();
      final c = eye.center;
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, 1 - 0.92 * blink);
      canvas.translate(-c.dx, -c.dy);
      _drawGroup(canvas, eye);
      canvas.restore();
    }

    // 耳朵：逐頂點彎曲 — 耳根不動、越往耳尖擺幅越大（軟耳感，根部不裂縫）
    _drawWarpedGroup(canvas, g.earL, earL, _earPivotL);
    _drawWarpedGroup(canvas, g.earR, earR, _earPivotR);

    canvas.restore();
  }

  void _drawWarpedGroup(Canvas canvas, _Group g, double amt, Offset pivot) {
    Offset warp(double x, double y) {
      // 權重：耳根(y≈240)為 0，耳尖(y≈690)為 1，平方讓根部更僵
      final w = ((y - 240) / 450).clamp(0.0, 1.0);
      final th = amt * 0.085 * w * w;
      final c = math.cos(th), s = math.sin(th);
      final dx = x - pivot.dx, dy = y - pivot.dy;
      return Offset(pivot.dx + dx * c - dy * s, pivot.dy + dx * s + dy * c);
    }

    Path warped(List<double> pts, {required bool close}) {
      final p0 = warp(pts[0], pts[1]);
      final p = Path()..moveTo(p0.dx, p0.dy);
      for (var i = 2; i < pts.length; i += 2) {
        final q = warp(pts[i], pts[i + 1]);
        p.lineTo(q.dx, q.dy);
      }
      if (close) p.close();
      return p;
    }

    for (final sh in g.shapes) {
      canvas.drawPath(
        warped(sh.pts, close: true),
        Paint()..color = Color(sh.color),
      );
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF6F6C70);
    for (final pts in g.strokes) {
      canvas.drawPath(warped(pts, close: false), stroke);
    }
  }

  void _drawGroup(Canvas canvas, _Group g) {
    for (final sh in g.shapes) {
      canvas.drawPath(
        _poly(sh.pts, close: true),
        Paint()..color = Color(sh.color),
      );
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF6F6C70);
    for (final pts in g.strokes) {
      canvas.drawPath(_poly(pts, close: false), stroke);
    }
  }

  Path _poly(List<double> pts, {required bool close}) {
    final p = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i], pts[i + 1]);
    }
    if (close) p.close();
    return p;
  }

  // ---------------- 分組 ----------------
  static _Groups _classify() {
    final g = _Groups();
    for (final sh in tumiTracedShapes) {
      final c = _centroid(sh.pts);
      switch (sh.color) {
        case 0xFF26242A: // 眼珠
          (c.dx < 512 ? g.eyeL : g.eyeR).add(sh);
        case 0xFFFCBABB: // 耳粉
          (c.dx < 512 ? g.earL : g.earR).add(sh);
        case 0xFFD08C97: // 深粉：耳內陰影（外側）或鼻嘴記號（中央）
          if (c.dx < 400) {
            g.earL.add(sh);
          } else if (c.dx > 624) {
            g.earR.add(sh);
          } else {
            g.head.add(sh);
          }
        case 0xFFFBBECE: // 腮紅
          g.head.add(sh);
        case 0xFFCBC5C5: // 灰
          if (c.dx < 345) {
            g.earL.add(sh);
          } else if (c.dx > 679) {
            g.earR.add(sh);
          } else if (c.dy < 545) {
            g.head.add(sh);
          } else {
            g.body.add(sh);
          }
        case 0xFFFDF5F3: // 白
          final box = _bbox(sh.pts);
          if (box.width * box.height < 3000 && c.dy < 450) {
            (c.dx < 512 ? g.eyeL : g.eyeR).add(sh); // 眼高光
          } else if (c.dy < 545) {
            g.head.add(sh); // 臉帶＋口鼻
          } else {
            g.body.add(sh); // 肚白/腳掌/手掌尖
          }
        default:
          g.head.add(sh);
      }
    }
    for (final pts in tumiTracedStrokes) {
      final c = _centroidLine(pts);
      if (c.dx < 345) {
        g.earL.strokes.add(pts);
      } else if (c.dx > 679) {
        g.earR.strokes.add(pts);
      } else if (c.dy < 545) {
        g.head.strokes.add(pts);
      } else {
        g.body.strokes.add(pts);
      }
    }
    return g;
  }

  static Offset _centroid(List<double> pts) {
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < pts.length; i += 2) {
      sx += pts[i];
      sy += pts[i + 1];
    }
    final n = pts.length / 2;
    return Offset(sx / n, sy / n);
  }

  static Offset _centroidLine(List<double> pts) => _centroid(pts);

  static Rect _bbox(List<double> pts) {
    var x0 = pts[0], x1 = pts[0], y0 = pts[1], y1 = pts[1];
    for (var i = 2; i < pts.length; i += 2) {
      if (pts[i] < x0) x0 = pts[i];
      if (pts[i] > x1) x1 = pts[i];
      if (pts[i + 1] < y0) y0 = pts[i + 1];
      if (pts[i + 1] > y1) y1 = pts[i + 1];
    }
    return Rect.fromLTRB(x0, y0, x1, y1);
  }

  @override
  bool shouldRepaint(covariant TumiRigPainter old) =>
      old.earL != earL || old.earR != earR || old.blink != blink;
}

class _Group {
  final List<TracedShape> shapes = [];
  final List<List<double>> strokes = [];

  void add(TracedShape s) => shapes.add(s);

  Offset get center {
    if (shapes.isEmpty) return Offset.zero;
    var r = TumiRigPainter._bbox(shapes.first.pts);
    for (final s in shapes.skip(1)) {
      r = r.expandToInclude(TumiRigPainter._bbox(s.pts));
    }
    return r.center;
  }
}

class _Groups {
  final body = _Group();
  final head = _Group();
  final earL = _Group();
  final earR = _Group();
  final eyeL = _Group();
  final eyeR = _Group();
}
