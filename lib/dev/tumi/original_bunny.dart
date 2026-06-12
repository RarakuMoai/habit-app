import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 向量兔咪（最終實驗）：兔咪的實測幾何 × 無描邊可動架構。
///
/// 幾何座標來自參考圖逐像素校準（頭 squircle、眼 (412,399) 48×56、
/// 白臉帶 444-573、耳外緣 (218,402)(160,560)、身體手臂鼓起輪廓…），
/// 但以 lineless flat 渲染 — 沒有描邊就沒有線條脫隊，動畫天生順滑。
///
/// 參數：[breath] 呼吸、[earL]/[earR] 軟耳擺 -1..1、
/// [blink] 眨眼 0..1、[cheer] 開心 0..1（彎月眼＋腮紅加深）。
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

  // ---- 兔咪配色（實測自參考圖） ----
  static const _grey = Color(0xFFCBC5C5);
  static const _greyShade = Color(0xFFB9B1B2);
  static const _white = Color(0xFFFDF5F3);
  static const _pink = Color(0xFFFCBABB);
  static const _pinkDeep = Color(0xFFEFA3B0);
  static const _blush = Color(0xFFFBBECE);
  static const _blushDeep = Color(0xFFF5A4B8);
  static const _eye = Color(0xFF2A282C);
  static const _noseMouth = Color(0xFFD08C97);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1024.0;
    canvas.save();
    canvas.scale(s);

    final br = 1.0 + 0.014 * breath;
    canvas.translate(512, 900);
    canvas.scale(2 - br, br);
    canvas.translate(-512, -900);

    _body(canvas);
    _head(canvas);
    _face(canvas);
    _ear(canvas, mirror: false, amt: earL);
    _ear(canvas, mirror: true, amt: earR);

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

  // ---------------- 身體（實測輪廓：肩→手臂鼓起→腋凹→大腿→雙腿） ----------------
  void _body(Canvas canvas) {
    final body = _cubics(const Offset(400, 518), [
      [const Offset(362, 542), const Offset(326, 585), const Offset(310, 638)],
      [const Offset(304, 666), const Offset(310, 688), const Offset(330, 698)],
      [const Offset(346, 706), const Offset(358, 706), const Offset(364, 702)],
      [const Offset(348, 714), const Offset(339, 728), const Offset(338, 750)],
      [const Offset(339, 792), const Offset(350, 834), const Offset(362, 858)],
      [const Offset(368, 874), const Offset(376, 884), const Offset(384, 888)],
      [const Offset(400, 894), const Offset(430, 894), const Offset(452, 890)],
      [const Offset(462, 886), const Offset(468, 878), const Offset(470, 870)],
      [const Offset(478, 848), const Offset(490, 830), const Offset(502, 824)],
      [const Offset(507, 820), const Offset(517, 820), const Offset(522, 824)],
      [const Offset(534, 830), const Offset(546, 848), const Offset(554, 870)],
      [const Offset(556, 878), const Offset(562, 886), const Offset(572, 890)],
      [const Offset(594, 894), const Offset(624, 894), const Offset(640, 888)],
      [const Offset(648, 884), const Offset(656, 874), const Offset(662, 858)],
      [const Offset(674, 834), const Offset(685, 792), const Offset(686, 750)],
      [const Offset(685, 728), const Offset(676, 714), const Offset(660, 702)],
      [const Offset(666, 706), const Offset(678, 706), const Offset(694, 698)],
      [const Offset(714, 688), const Offset(720, 666), const Offset(714, 638)],
      [const Offset(698, 585), const Offset(662, 542), const Offset(624, 518)],
      [const Offset(580, 506), const Offset(444, 506), const Offset(400, 518)],
    ]);
    canvas.drawPath(body, _f(_grey));

    // 腿部接地陰影
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(512, 920), width: 560, height: 100),
        _f(_greyShade));

    // 白胸腹（頂端銜接下巴白，實測 411-610）
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(511, 666), width: 200, height: 222),
        _f(_white));

    // 白腳掌
    for (final mirror in [false, true]) {
      final c = _m(const Offset(438, 858), mirror);
      canvas.drawOval(
          Rect.fromCenter(center: c, width: 96, height: 72), _f(_white));
    }

    // 白掌尖（手臂末端，貼著輪廓內側）
    for (final mirror in [false, true]) {
      final c = _m(const Offset(348, 680), mirror);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(mirror ? -0.35 : 0.35);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 50, height: 38),
          _f(_white));
      canvas.restore();
    }
    canvas.restore();
  }

  // ---------------- 頭（實測 squircle：嬰兒肥臉頰） ----------------
  void _head(Canvas canvas) {
    final head = _cubics(const Offset(513, 160), [
      [const Offset(420, 162), const Offset(345, 188), const Offset(312, 256)],
      [const Offset(290, 310), const Offset(286, 392), const Offset(300, 452)],
      [const Offset(312, 502), const Offset(338, 536), const Offset(378, 550)],
      [const Offset(418, 562), const Offset(462, 566), const Offset(513, 566)],
      [const Offset(564, 566), const Offset(606, 562), const Offset(646, 550)],
      [const Offset(686, 536), const Offset(712, 502), const Offset(724, 452)],
      [const Offset(738, 392), const Offset(734, 310), const Offset(712, 256)],
      [const Offset(679, 188), const Offset(606, 162), const Offset(513, 160)],
    ]);
    canvas.drawPath(head, _f(_grey));

    // 呆毛：白色尖瓣束（無描邊直接疊，與臉帶同色自然相連）
    final tuft = Path()..moveTo(436, 190);
    const spikes = [
      [Offset(441, 148), Offset(461, 168)],
      [Offset(466, 132), Offset(485, 158)],
      [Offset(491, 122), Offset(508, 154)],
      [Offset(515, 119), Offset(532, 154)],
      [Offset(540, 126), Offset(556, 160)],
      [Offset(564, 138), Offset(577, 167)],
      [Offset(583, 154), Offset(590, 192)],
    ];
    for (final s in spikes) {
      final tip = s[0], notch = s[1];
      tuft.cubicTo(
          tip.dx - 13, tip.dy + 24, tip.dx - 7, tip.dy + 3, tip.dx, tip.dy);
      tuft.cubicTo(tip.dx + 7, tip.dy + 3, tip.dx + 13, tip.dy + 24, notch.dx,
          notch.dy);
    }
    tuft.quadraticBezierTo(515, 215, 436, 190);
    tuft.close();
    canvas.drawPath(tuft, _f(_white));

    canvas.save();
    canvas.clipPath(head);
    // 白臉帶（實測 444-573，上接呆毛）
    final band = _cubics(const Offset(440, 130), [
      [const Offset(441, 240), const Offset(443, 330), const Offset(446, 420)],
      [const Offset(468, 434), const Offset(556, 434), const Offset(577, 420)],
      [const Offset(580, 330), const Offset(582, 240), const Offset(583, 130)],
    ]);
    canvas.drawPath(band, _f(_white));
    // 口鼻白區（實測喇叭形：眼下凹弧、寬 392-628、底 544）
    final muzzle = _cubics(const Offset(446, 422), [
      [const Offset(430, 448), const Offset(412, 455), const Offset(398, 472)],
      [const Offset(391, 488), const Offset(391, 505), const Offset(398, 518)],
      [const Offset(408, 535), const Offset(440, 543), const Offset(510, 544)],
      [const Offset(580, 543), const Offset(612, 535), const Offset(622, 518)],
      [const Offset(629, 505), const Offset(629, 488), const Offset(622, 472)],
      [const Offset(608, 455), const Offset(590, 448), const Offset(574, 422)],
      [const Offset(530, 418), const Offset(490, 418), const Offset(446, 422)],
    ]);
    canvas.drawPath(muzzle, _f(_white));
    canvas.restore();

    // 下巴→胸口白色銜接（參考圖的白是連續的，蓋掉頸部灰帶）
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(510, 556), width: 168, height: 52),
        _f(_white));
  }

  // ---------------- 臉（實測五官座標） ----------------
  void _face(Canvas canvas) {
    for (final mirror in [false, true]) {
      final c = _m(const Offset(412, 399), mirror);

      if (cheer > 0.5) {
        final happy = Path()
          ..moveTo(c.dx - 28, c.dy + 8)
          ..quadraticBezierTo(c.dx, c.dy - 30, c.dx + 28, c.dy + 8);
        canvas.drawPath(
            happy,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 12
              ..strokeCap = StrokeCap.round
              ..color = _eye);
      } else {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(1, (1 - 0.92 * blink).clamp(0.08, 1.0));
        canvas.translate(-c.dx, -c.dy);
        canvas.drawOval(
            Rect.fromCenter(center: c, width: 53, height: 61), _f(_eye));
        // 高光：內上大點＋外下小點（實測方位）
        canvas.drawCircle(
            c + Offset(mirror ? -5 : 5, -10), 9, _f(Colors.white));
        canvas.drawCircle(c + Offset(mirror ? 9 : -9, 11), 4,
            _f(Colors.white.withValues(alpha: 0.8)));
        canvas.restore();
      }

      // 腮紅（實測 (374,460)，開心加深）
      canvas.drawOval(
          Rect.fromCenter(
              center: _m(const Offset(374, 460), mirror),
              width: 56,
              height: 40),
          _f(Color.lerp(_blush, _blushDeep, cheer) ?? _blush));
    }

    // × 型嘴（固定不變）
    final x = Path()
      ..moveTo(497, 448)
      ..quadraticBezierTo(509, 461, 521, 472)
      ..moveTo(521, 448)
      ..quadraticBezierTo(509, 461, 497, 472);
    canvas.drawPath(
        x,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..color = _noseMouth);
  }

  // ---------------- 耳朵（最前層大垂耳，實測曲線，逐頂點軟彎曲） ----------------
  void _ear(Canvas canvas, {required bool mirror, required double amt}) {
    Offset m(double x, double y) => _m(Offset(x, y), mirror);
    final pivot = m(370, 230);

    Offset warp(Offset o) {
      final w = ((o.dy - 240) / 450).clamp(0.0, 1.0);
      final th = (mirror ? -amt : amt) * 0.085 * w * w;
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

    // 耳灰（實測外緣 (218,402)(160,560)、尾端內勾、與臉頰留縫）
    final ear = wp(m(400, 195), [
      [m(370, 180), m(338, 200), m(315, 248)],
      [m(288, 295), m(243, 350), m(218, 402)],
      [m(190, 455), m(170, 505), m(160, 560)],
      [m(153, 605), m(155, 640), m(170, 665)],
      [m(182, 684), m(204, 695), m(222, 693)],
      [m(244, 688), m(262, 672), m(271, 651)],
      [m(290, 625), m(310, 590), m(325, 545)],
      [m(332, 515), m(330, 480), m(322, 445)],
      [m(316, 400), m(316, 350), m(330, 295)],
      [m(340, 250), m(360, 215), m(400, 195)],
    ]);
    canvas.drawPath(ear, _f(_grey));

    // 內耳粉（逐列校準的窄長水滴）
    final pink = wp(m(304, 408), [
      [m(288, 424), m(270, 462), m(250, 495)],
      [m(232, 525), m(216, 558), m(206, 585)],
      [m(199, 605), m(195, 625), m(200, 640)],
      [m(205, 650), m(213, 652), m(222, 646)],
      [m(244, 636), m(258, 618), m(272, 601)],
      [m(285, 575), m(296, 548), m(302, 520)],
      [m(309, 495), m(312, 470), m(311, 448)],
      [m(310, 430), m(307, 415), m(304, 408)],
    ]);
    canvas.drawPath(pink, _f(_pink));

    // 耳粉深色芯（層次）
    final core = wp(m(280, 470), [
      [m(258, 490), m(240, 530), m(230, 568)],
      [m(222, 600), m(224, 624), m(232, 634)],
      [m(242, 644), m(254, 638), m(262, 620)],
      [m(274, 588), m(284, 548), m(288, 516)],
      [m(290, 492), m(288, 472), m(280, 470)],
    ]);
    canvas.drawPath(core, _f(_pinkDeep));
  }

  @override
  bool shouldRepaint(covariant OriginalBunnyPainter old) =>
      old.breath != breath ||
      old.earL != earL ||
      old.earR != earR ||
      old.blink != blink ||
      old.cheer != cheer;
}
