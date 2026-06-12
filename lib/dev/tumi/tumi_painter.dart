import 'package:flutter/material.dart';

/// 兔咪向量重繪 — 扁平風。
///
/// 幾何與配色全部實測自 assets/mascot/ref/tumi_neutral_front.JPG
///（1254px 原圖換算到 1024 設計網格）。結構要點：
/// - 耳朵在最前層（蓋住臉頰與身體側緣），不是頭後。
/// - 白臉帶寬 ~130（x 444-573），眼睛在帶外的灰色區。
/// - 下巴白與胸腹白相連（脖子處收腰），中央下巴不描邊。
/// - 手臂是細長條（寬 ~28）掛在白胸前。
/// - 雙腿在 y~805 以下分開，中間是拱形鏤空。
class TumiPainter extends CustomPainter {
  const TumiPainter();

  // ---- 實測配色 ----
  static const _grey = Color(0xFFCBC5C5);
  static const _white = Color(0xFFFDF5F3);
  static const _pinkEar = Color(0xFFFCBABB);
  static const _blush = Color(0xFFFBBECE);
  static const _eyeBlack = Color(0xFF2A282C);
  static const _nosePink = Color(0xFFD58F9B);
  static const _mouthLine = Color(0xFFC28990);
  static const _outline = Color(0xFF7B787D);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1024.0;
    canvas.save();
    canvas.scale(s);

    _drawBody(canvas);
    _drawHead(canvas);
    _drawFace(canvas);
    _drawEar(canvas, mirror: false);
    _drawEar(canvas, mirror: true);

    canvas.restore();
  }

  Paint _fill(Color c) => Paint()..color = c;

  Paint _stroke({double width = 4, Color? color}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color ?? _outline;

  Offset _mx(Offset o, bool mirror) =>
      mirror ? Offset(1024 - o.dx, o.dy) : o;

  /// 從起點＋一串三次貝茲段建 path（每段 [c1, c2, end]）。
  Path _pathFrom(Offset start, List<List<Offset>> cubics) {
    final p = Path()..moveTo(start.dx, start.dy);
    for (final seg in cubics) {
      p.cubicTo(seg[0].dx, seg[0].dy, seg[1].dx, seg[1].dy, seg[2].dx, seg[2].dy);
    }
    return p..close();
  }

  // ---------------- 身體 ----------------
  // 剪影一筆成形：肩 → 手臂鼓起（手臂外緣＝剪影）→ 腋下凹 →
  // 大腿鼓起 → 腿 → 腳底 → 腿內緣上行 → 腿間三角拱 → 鏡像。
  // 手臂只用一條內側弧線跟肚子分開；白腳套包住腿底。
  void _drawBody(Canvas canvas) {
    final body = _pathFrom(const Offset(400, 518), [
      // 左肩 → 手臂外鼓（最寬 ~306 at g650-670）
      [const Offset(362, 542), const Offset(326, 585), const Offset(310, 638)],
      [const Offset(300, 678), const Offset(308, 702), const Offset(330, 712)],
      // 手掌圓底 → 與大腿交會的腋下凹
      [const Offset(346, 718), const Offset(358, 717), const Offset(365, 712)],
      // 凹點 → 大腿外鼓（haunch 337@g740）
      [const Offset(349, 716), const Offset(340, 730), const Offset(338, 750)],
      // 大腿 → 腿外緣下行（底部外角放寬、整體上提）
      [const Offset(339, 788), const Offset(350, 826), const Offset(360, 848)],
      [const Offset(366, 864), const Offset(372, 874), const Offset(380, 878)],
      // 左腳底
      [const Offset(398, 884), const Offset(430, 884), const Offset(452, 880)],
      [const Offset(462, 876), const Offset(468, 870), const Offset(470, 862)],
      // 腿內緣上行 → 腿間拱頂（縫變窄、apex ~(512,822)）
      [const Offset(478, 842), const Offset(490, 828), const Offset(502, 824)],
      [const Offset(507, 820), const Offset(517, 820), const Offset(522, 824)],
      // 右腿內緣下行（鏡像）
      [const Offset(534, 828), const Offset(546, 842), const Offset(554, 862)],
      [const Offset(556, 870), const Offset(562, 876), const Offset(572, 880)],
      [const Offset(594, 884), const Offset(626, 884), const Offset(644, 878)],
      [const Offset(652, 874), const Offset(658, 864), const Offset(664, 848)],
      [const Offset(674, 826), const Offset(685, 788), const Offset(686, 748)],
      [const Offset(684, 730), const Offset(675, 722), const Offset(659, 712)],
      [const Offset(666, 717), const Offset(678, 718), const Offset(694, 712)],
      [const Offset(716, 702), const Offset(724, 678), const Offset(714, 638)],
      [const Offset(698, 585), const Offset(662, 542), const Offset(624, 518)],
      [const Offset(580, 504), const Offset(444, 504), const Offset(400, 518)],
    ]);
    canvas.drawPath(body, _fill(_grey));

    // 白胸腹（硬邊大蛋形，頂端與下巴白相連）
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(511, 666), width: 200, height: 222),
        _fill(_white));
    canvas.restore();

    // 腳套：白色包住腿底（微外八），描邊後讓身體輪廓壓在上面
    for (final mirror in [false, true]) {
      Offset m(double x, double y) => _mx(Offset(x, y), mirror);
      canvas.save();
      canvas.clipPath(body);
      final c = m(420, 858);
      canvas.translate(c.dx, c.dy);
      canvas.rotate((mirror ? 1 : -1) * 0.10);
      final paw = Path()
        ..addOval(Rect.fromCenter(
            center: Offset.zero, width: 118, height: 94));
      canvas.drawPath(paw, _fill(_white));
      canvas.drawPath(paw, _stroke(width: 3.5));
      canvas.restore();
      // 腳趾縫（從底緣往上）
      for (final dx in [-20.0, 14.0]) {
        final t = m(420 + dx, 0);
        final cleft = Path()
          ..moveTo(t.dx, 880)
          ..quadraticBezierTo(t.dx + (mirror ? -3 : 3), 862, t.dx, 846);
        canvas.drawPath(cleft, _stroke(width: 3));
      }
    }

    canvas.drawPath(body, _stroke());

    // 手臂：外緣已是剪影，掌尖白先畫，再用一條內側弧線分開手臂與肚子
    for (final mirror in [false, true]) {
      Offset m(double x, double y) => _mx(Offset(x, y), mirror);
      canvas.save();
      canvas.clipPath(body);
      final h = m(350, 688);
      canvas.translate(h.dx, h.dy);
      canvas.rotate((mirror ? -1 : 1) * 0.35);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 54, height: 40),
          _fill(_white));
      canvas.restore();
      final innerArm = Path()
        ..moveTo(m(428, 548).dx, 548)
        ..cubicTo(m(415, 580).dx, 580, m(405, 615).dx, 615, m(400, 645).dx,
            645)
        ..cubicTo(m(396, 668).dx, 668, m(388, 685).dx, 685, m(372, 697).dx,
            697)
        ..cubicTo(m(362, 704).dx, 704, m(350, 706).dx, 706, m(342, 702).dx,
            702);
      canvas.drawPath(innerArm, _stroke(width: 3.5));
    }
  }

  // ---------------- 頭＋呆毛 ----------------
  // 實測：頭頂 y≈160、g237 寬 326-700、下顎 g532 寬 ~390-636。
  // 不是橢圓 — 下半鼓起的嬰兒肥圓臉（squircle）。
  Path get _headPath => _pathFrom(const Offset(513, 160), [
        // 左上四分之一（過 (326,237)）
        [const Offset(420, 162), const Offset(345, 188), const Offset(312, 256)],
        // 左側最寬（藏在耳後）→ 飽滿臉頰
        [const Offset(290, 310), const Offset(286, 392), const Offset(300, 452)],
        // 左下顎（更寬更低的嬰兒肥）
        [const Offset(312, 502), const Offset(338, 536), const Offset(378, 550)],
        // 下巴
        [const Offset(418, 554), const Offset(462, 558), const Offset(513, 558)],
        // 右半鏡像
        [const Offset(564, 558), const Offset(608, 554), const Offset(648, 550)],
        [const Offset(688, 536), const Offset(714, 502), const Offset(726, 452)],
        [const Offset(740, 392), const Offset(736, 310), const Offset(714, 256)],
        [const Offset(681, 188), const Offset(606, 162), const Offset(513, 160)],
      ]);

  Path _tuftPath() {
    const spikes = [
      // [尖端, 瓣間凹口]
      [Offset(432, 150), Offset(452, 166)],
      [Offset(458, 134), Offset(476, 158)],
      [Offset(482, 124), Offset(500, 152)],
      [Offset(507, 120), Offset(524, 152)],
      [Offset(530, 126), Offset(547, 156)],
      [Offset(553, 136), Offset(568, 162)],
      [Offset(574, 148), Offset(585, 170)],
      [Offset(590, 162), Offset(596, 192)],
    ];
    final p = Path()..moveTo(424, 184);
    for (final s in spikes) {
      final tip = s[0], notch = s[1];
      p.cubicTo(tip.dx - 14, tip.dy + 22, tip.dx - 7, tip.dy + 3,
          tip.dx, tip.dy);
      p.cubicTo(tip.dx + 7, tip.dy + 3, tip.dx + 14, tip.dy + 22,
          notch.dx, notch.dy);
    }
    p.quadraticBezierTo(515, 212, 444, 186);
    return p..close();
  }

  void _drawHead(Canvas canvas) {
    final headAndTuft =
        Path.combine(PathOperation.union, _headPath, _tuftPath());
    canvas.drawPath(headAndTuft, _fill(_grey));

    // 白臉帶（實測 x 437-582 → 444-573）＋ 口鼻白區（394-627）
    final band = _pathFrom(const Offset(437, 125), [
      [const Offset(439, 240), const Offset(442, 330), const Offset(446, 420)],
      [const Offset(468, 436), const Offset(556, 436), const Offset(578, 420)],
      [const Offset(582, 330), const Offset(585, 240), const Offset(587, 125)],
    ]);
    // 口鼻白區：上緣從臉帶喇叭狀外擴（眼下凹弧），
    // 最寬 392-628@y490，下緣（下巴）~y544
    final muzzle = _pathFrom(const Offset(446, 422), [
      [const Offset(430, 448), const Offset(412, 455), const Offset(398, 472)],
      [const Offset(391, 488), const Offset(391, 505), const Offset(398, 518)],
      [const Offset(408, 535), const Offset(440, 543), const Offset(510, 544)],
      [const Offset(580, 543), const Offset(612, 535), const Offset(622, 518)],
      [const Offset(629, 505), const Offset(629, 488), const Offset(622, 472)],
      [const Offset(608, 455), const Offset(590, 448), const Offset(574, 422)],
      [const Offset(530, 418), const Offset(490, 418), const Offset(446, 422)],
    ]);
    final blaze = Path.combine(PathOperation.union, band, muzzle);
    canvas.save();
    canvas.clipPath(headAndTuft);
    canvas.drawPath(blaze, _fill(_white));
    canvas.restore();

    canvas.drawPath(headAndTuft, _stroke());

    // 下巴是淡灰軟邊界（實測 #E4DCDA），不是硬描邊也不是無縫
    final chinSoft = Path()
      ..moveTo(452, 554)
      ..cubicTo(478, 558, 548, 558, 574, 554);
    canvas.drawPath(chinSoft, _stroke(width: 8, color: const Color(0xFFE4DCDA)));
  }

  // ---------------- 臉 ----------------
  void _drawFace(Canvas canvas) {
    // 眼睛：實測中心 (412,399)/(608,399)，48×56，高光在內上側
    for (final mirror in [false, true]) {
      final c = _mx(const Offset(412, 399), mirror);
      canvas.drawOval(
          Rect.fromCenter(center: c, width: 53, height: 61), _fill(_eyeBlack));
      canvas.drawCircle(
          c + Offset(mirror ? -5 : 5, -10), 9.5, _fill(Colors.white));
    }

    // 腮紅：實測中心 (375,459)，52×38
    for (final mirror in [false, true]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: _mx(const Offset(374, 460), mirror),
              width: 58,
              height: 43),
          _fill(_blush));
    }

    // 鼻（小）＋人中＋小八字嘴（嘴型固定不變）
    final nose = Path()
      ..moveTo(498, 446)
      ..quadraticBezierTo(508, 441, 518, 446)
      ..quadraticBezierTo(514, 457, 508, 459)
      ..quadraticBezierTo(502, 457, 498, 446)
      ..close();
    canvas.drawPath(nose, _fill(_nosePink));
    final mouth = Path()
      ..moveTo(508, 459)
      ..lineTo(508, 474)
      ..moveTo(508, 474)
      ..quadraticBezierTo(503, 481, 496, 482)
      ..moveTo(508, 474)
      ..quadraticBezierTo(513, 481, 520, 482);
    canvas.drawPath(
        mouth,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _mouthLine);
  }

  // ---------------- 耳朵（最前層大垂耳）----------------
  void _drawEar(Canvas canvas, {required bool mirror}) {
    Offset m(double x, double y) => _mx(Offset(x, y), mirror);

    // 外緣實測：g261:306 g343:257 g457:187 g539:159 g604:155 g670:177
    // 內緣實測：g392:310 g506:330 g572:312 g637:280
    // 筆直下垂的長水滴：外緣一條長順滑曲線、內緣近直線、圓底，
    // 不要香蕉彎也不要尾端內勾
    // 邊緣實測：外緣過 (283,300)(218,400)(168,500)(155,600)，
    // 內緣過 (313,457)(331,506)(303,600)(271,650)，底端 ~y692 結束
    final ear = _pathFrom(m(400, 195), [
      [m(370, 180), m(338, 200), m(315, 248)], // 根部圓肩
      [m(288, 295), m(243, 350), m(218, 402)], // 外緣上段
      [m(190, 455), m(170, 505), m(160, 560)], // 外緣最寬段
      [m(153, 605), m(155, 640), m(170, 665)], // 外緣下段
      [m(182, 684), m(204, 695), m(222, 693)], // 圓底（y~692 收尾）
      [m(244, 688), m(262, 672), m(271, 651)], // 底轉內緣
      [m(290, 625), m(310, 590), m(325, 545)], // 內緣下段
      [m(332, 515), m(330, 480), m(322, 445)], // 內緣鼓起（331@506）
      [m(316, 400), m(316, 350), m(330, 295)],
      [m(340, 250), m(360, 215), m(400, 195)],
    ]);
    canvas.drawPath(ear, _fill(_grey));

    // 內耳粉：逐列校準 — 外緣過 (280,450)(240,510)(210,570)(197,630)，
    // 內緣過 (309,450)(308,510)(289,570)(255,630)，頂 (304,408) 底 ~y648
    final pink = _pathFrom(m(304, 408), [
      [m(288, 424), m(270, 462), m(250, 495)],
      [m(232, 525), m(216, 558), m(206, 585)],
      [m(199, 605), m(195, 625), m(200, 640)],
      [m(205, 650), m(213, 652), m(222, 646)],
      [m(244, 636), m(258, 618), m(272, 601)],
      [m(285, 575), m(296, 548), m(302, 520)],
      [m(309, 495), m(312, 470), m(311, 448)],
      [m(310, 430), m(307, 415), m(304, 408)],
    ]);
    canvas.drawPath(pink, _fill(_pinkEar));

    canvas.drawPath(ear, _stroke());
  }

  @override
  bool shouldRepaint(covariant TumiPainter oldDelegate) => false;
}
