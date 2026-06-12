import 'package:flutter/material.dart';

import 'tumi_traced_data.dart';

/// 兔咪向量版 — 由 scripts/trace_tumi.py 自動描圖自參考圖
/// assets/mascot/ref/tumi_neutral_front.JPG。
///
/// 色塊（依面積大→小疊放）＋選擇性描邊線稿，1024 設計網格。
/// 之後做動畫時把這些 shape 依部位分組（耳/頭/身/手）各自 transform。
class TumiPainter extends CustomPainter {
  const TumiPainter();

  static const _outline = Color(0xFF6F6C70);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1024.0;
    canvas.save();
    canvas.scale(s);

    for (final shape in tumiTracedShapes) {
      final path = _poly(shape.pts, close: true);
      canvas.drawPath(path, Paint()..color = Color(shape.color));
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _outline;
    for (final pts in tumiTracedStrokes) {
      canvas.drawPath(_poly(pts, close: false), stroke);
    }

    canvas.restore();
  }

  Path _poly(List<double> pts, {required bool close}) {
    final p = Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i], pts[i + 1]);
    }
    if (close) p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant TumiPainter oldDelegate) => false;
}
