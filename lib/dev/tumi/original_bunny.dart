import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 原創向量兔（一次性實驗）：無參考圖、自由設計。
///
/// 設計原則：
/// - 無描邊扁平向量（lineless flat）— 色塊＋柔和雙色調陰影，
///   向量的原生美學，動畫時不存在線條脫隊問題。
/// - 所有部件語意化＋參數化，天生可動：
///   [breath] 呼吸 0..1、[earL]/[earR] 耳擺 -1..1、[blink] 眨眼 0..1、
///   [cheer] 開心程度 0..1（眼睛變彎月＋腮紅加深）。
/// - 1024 設計網格，等比縮放。
class OriginalBunnyPainter extends CustomPainter {
  final double breath;
  final double earL;
  final double earR;
  final double blink;
  final double cheer;

  const OriginalBunnyPainter({
    this.breath = 0,
    this.earL = 0,
    this.earR = 0,
    this.blink = 0,
    this.cheer = 0,
  });

  // ---- 配色：奶油兔 × 玫瑰粉 ----
  static const _cream = Color(0xFFFBF2E9); // 本體
  static const _creamShade = Color(0xFFEEDFD2); // 陰影色調
  static const _earBack = Color(0xFFF3E6DA); // 耳背（比本體深半階）
  static const _pinkInner = Color(0xFFF6BFC8); // 耳內粉
  static const _pinkDeep = Color(0xFFEFA3B0); // 耳內深粉
  static const _eye = Color(0xFF3A3336); // 暖黑
  static const _noseMouth = Color(0xFFE2939F);
  static const _blush = Color(0xFFF6C3C9);
  static const _blushDeep = Color(0xFFF2ABB6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1024.0;
    canvas.save();
    canvas.scale(s);

    // 呼吸：整體以腳底為錨輕微縱向縮放
    final br = 1.0 + 0.014 * breath;
    canvas.translate(512, 950);
    canvas.scale(2 - br, br);
    canvas.translate(-512, -950);

    _ear(canvas, mirror: false, amt: earL);
    _ear(canvas, mirror: true, amt: earR);
    _body(canvas);
    _head(canvas);
    _face(canvas);

    canvas.restore();
  }

  Paint _f(Color c) => Paint()..color = c;

  Offset _m(Offset o, bool mirror) => mirror ? Offset(1024 - o.dx, o.dy) : o;

  Path _cubics(Offset start, List<List<Offset>> segs) {
    final p = Path()..moveTo(start.dx, start.dy);
    for (final s in segs) {
      p.cubicTo(s[0].dx, s[0].dy, s[1].dx, s[1].dy, s[2].dx, s[2].dy);
    }
    return p..close();
  }

  // ---------------- 耳朵（頭後方的長垂耳，逐頂點軟彎曲） ----------------
  void _ear(Canvas canvas, {required bool mirror, required double amt}) {
    Offset m(double x, double y) => _m(Offset(x, y), mirror);
    final pivot = m(400, 220);

    Offset warp(Offset o) {
      final w = ((o.dy - 210) / 420).clamp(0.0, 1.0);
      final th = (mirror ? -amt : amt) * 0.10 * w * w;
      final c = math.cos(th), s = math.sin(th);
      final dx = o.dx - pivot.dx, dy = o.dy - pivot.dy;
      return Offset(pivot.dx + dx * c - dy * s, pivot.dy + dx * s + dy * c);
    }

    Path wp(Offset start, List<List<Offset>> segs) {
      final p = Path();
      final s0 = warp(start);
      p.moveTo(s0.dx, s0.dy);
      for (final s in segs) {
        final a = warp(s[0]), b = warp(s[1]), e = warp(s[2]);
        p.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
      }
      return p..close();
    }

    // 耳背：明顯垂在頭外側的長水滴（垂耳是兔子的靈魂）
    final back = wp(m(400, 230), [
      [m(305, 130), m(185, 165), m(165, 320)],
      [m(150, 450), m(185, 590), m(255, 668)],
      [m(298, 715), m(362, 700), m(382, 625)],
      [m(404, 520), m(412, 380), m(408, 295)],
      [m(406, 248), m(403, 222), m(400, 230)],
    ]);
    canvas.drawPath(back, _f(_earBack));

    // 耳內粉：同形內縮
    final inner = wp(m(370, 290), [
      [m(295, 230), m(225, 270), m(218, 380)],
      [m(212, 480), m(242, 580), m(295, 638)],
      [m(326, 670), m(366, 652), m(376, 590)],
      [m(388, 500), m(388, 390), m(382, 335)],
      [m(378, 300), m(374, 284), m(370, 290)],
    ]);
    canvas.drawPath(inner, _f(_pinkInner));

    // 耳內深粉芯
    final core = wp(m(345, 380), [
      [m(295, 345), m(258, 390), m(258, 460)],
      [m(258, 530), m(282, 590), m(318, 618)],
      [m(342, 636), m(366, 616), m(368, 565)],
      [m(372, 500), m(366, 430), m(358, 400)],
      [m(353, 380), m(348, 372), m(345, 380)],
    ]);
    canvas.drawPath(core, _f(_pinkDeep));
  }

  // ---------------- 身體 ----------------
  void _body(Canvas canvas) {
    // 圓潤水滴身體
    final body = _cubics(const Offset(512, 560), [
      [const Offset(420, 562), const Offset(346, 620), const Offset(340, 730)],
      [const Offset(336, 822), const Offset(408, 880), const Offset(512, 880)],
      [const Offset(616, 880), const Offset(688, 822), const Offset(684, 730)],
      [const Offset(678, 620), const Offset(604, 562), const Offset(512, 560)],
    ]);
    canvas.drawPath(body, _f(_cream));

    // 身體下緣陰影（雙色調）
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(512, 905), width: 560, height: 180),
        _f(_creamShade));
    canvas.restore();

    // 白肚毛色塊（亮一階）
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(512, 740), width: 250, height: 230),
        _f(const Color(0xFFFFFAF3)));
    canvas.restore();

    // 手：奶油色小圓臂搭在白肚邊上（靠色差自然顯形，不畫分界線）
    for (final mirror in [false, true]) {
      Offset m(double x, double y) => _m(Offset(x, y), mirror);
      final arm = _cubics(m(404, 618), [
        [m(364, 624), m(342, 662), m(350, 704)],
        [m(357, 740), m(390, 754), m(416, 740)],
        [m(436, 726), m(442, 690), m(434, 658)],
        [m(428, 632), m(420, 614), m(404, 618)],
      ]);
      canvas.drawPath(arm, _f(_cream));
      // 掌端小肉色點
      canvas.drawOval(
          Rect.fromCenter(center: m(390, 728), width: 40, height: 26),
          _f(_pinkInner.withValues(alpha: 0.55)));
    }

    // 腳：前方兩枚圓掌
    for (final mirror in [false, true]) {
      Offset m(double x, double y) => _m(Offset(x, y), mirror);
      final foot = Rect.fromCenter(center: m(437, 858), width: 130, height: 92);
      canvas.drawOval(foot, _f(_cream));
      // 粉色掌心肉球
      canvas.drawOval(
          Rect.fromCenter(center: m(437, 868), width: 64, height: 40),
          _f(_pinkInner));
    }
  }

  // ---------------- 頭 ----------------
  void _head(Canvas canvas) {
    // 寬扁的超橢圓感大頭：左右臉頰飽滿
    final head = _cubics(const Offset(512, 168), [
      [const Offset(372, 168), const Offset(268, 232), const Offset(258, 374)],
      [const Offset(250, 492), const Offset(346, 580), const Offset(512, 580)],
      [const Offset(678, 580), const Offset(774, 492), const Offset(766, 374)],
      [const Offset(756, 232), const Offset(652, 168), const Offset(512, 168)],
    ]);
    canvas.drawPath(head, _f(_cream));

    // 下巴接地陰影（窄而低調）
    canvas.save();
    canvas.clipPath(head);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(512, 604), width: 300, height: 64),
        _f(_creamShade));
    canvas.restore();

    // 頭頂呆毛：兩片柔軟葉瓣
    final tuft = Path()
      ..moveTo(470, 180)
      ..cubicTo(452, 140, 466, 102, 498, 96)
      ..cubicTo(516, 93, 528, 106, 526, 126)
      ..cubicTo(540, 108, 562, 112, 566, 134)
      ..cubicTo(570, 158, 552, 178, 528, 186)
      ..cubicTo(506, 192, 482, 190, 470, 180)
      ..close();
    canvas.drawPath(tuft, _f(_cream));
    // 呆毛內側陰影瓣（增加層次）
    final tuftShade = Path()
      ..moveTo(524, 130)
      ..cubicTo(534, 116, 552, 118, 555, 136)
      ..cubicTo(557, 152, 546, 168, 528, 174)
      ..cubicTo(520, 160, 518, 144, 524, 130)
      ..close();
    canvas.drawPath(tuftShade, _f(_earBack));
  }

  // ---------------- 臉 ----------------
  void _face(Canvas canvas) {
    for (final mirror in [false, true]) {
      Offset m(double x, double y) => _m(Offset(x, y), mirror);
      final c = m(404, 408);

      if (cheer > 0.5) {
        // 開心彎月眼（^ ^）
        final happy = Path()
          ..moveTo(c.dx - 34, c.dy + 10)
          ..quadraticBezierTo(c.dx, c.dy - 34, c.dx + 34, c.dy + 10);
        canvas.drawPath(
            happy,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 13
              ..strokeCap = StrokeCap.round
              ..color = _eye);
      } else {
        // 圓亮眼＋眨眼壓扁
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(1, (1 - 0.92 * blink).clamp(0.08, 1.0));
        canvas.translate(-c.dx, -c.dy);
        canvas.drawCircle(c, 37, _f(_eye));
        canvas.drawCircle(c + const Offset(-12, -13), 12, _f(Colors.white));
        canvas.drawCircle(c + const Offset(13, 12), 5.5,
            _f(Colors.white.withValues(alpha: 0.8)));
        canvas.restore();
      }

      // 腮紅（開心時加深）
      final blushColor =
          Color.lerp(_blush, _blushDeep, cheer) ?? _blush;
      canvas.drawOval(
          Rect.fromCenter(center: m(368, 480), width: 74, height: 40),
          _f(blushColor));
    }

    // 鼻＋嘴（固定不變）：小三角鼻＋ω嘴
    final nose = Path()
      ..moveTo(496, 466)
      ..quadraticBezierTo(512, 458, 528, 466)
      ..quadraticBezierTo(521, 482, 512, 484)
      ..quadraticBezierTo(503, 482, 496, 466)
      ..close();
    canvas.drawPath(nose, _f(_noseMouth));
    final mouth = Path()
      ..moveTo(512, 484)
      ..lineTo(512, 498)
      ..moveTo(512, 498)
      ..quadraticBezierTo(500, 510, 488, 500)
      ..moveTo(512, 498)
      ..quadraticBezierTo(524, 510, 536, 500);
    canvas.drawPath(
        mouth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = _noseMouth);
  }

  @override
  bool shouldRepaint(covariant OriginalBunnyPainter old) =>
      old.breath != breath ||
      old.earL != earL ||
      old.earR != earR ||
      old.blink != blink ||
      old.cheer != cheer;
}
