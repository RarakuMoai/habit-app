// 兔咪頭頂情緒泡泡 — 渲染層。
//
// 資料層（[EmotionBubble] enum、情境→泡泡對應）在 `utils/mascot.dart`；
// 這裡負責「每種泡泡長什麼樣、怎麼動」，全部宣告在 [_specs] 註冊表，
// 由 [MascotStage] 的 [MascotEmotionBubblePainter] 統一繪製。
//
// ── 新增一種泡泡的步驟 ──
// 1. `utils/mascot.dart`：`EmotionBubble` 加一個值，`forContext` 決定
//    哪些情境冒它。
// 2. 本檔 [_specs] 註冊一筆 [BubbleSpec]：
//    - `tint`：語意色（固定色或用頁面 accent 調和）。
//    - `motion`：從 [BubbleMotion] 的參數組合動態個性
//      （上浮 / 搖擺 / 抖動 / 脈動 / 下滑 / 入場旋轉 / 拉長）。
//    - `glyph`：主符號幾何（[BubbleGlyph] 實作，可重用；null = 只有衛星）。
//    - `satellites`：伴隨小符號（延遲冒出、各自漂移搖擺）。
// 不需要動 painter 本體。
//
// 動畫時間軸（主進度 t ∈ 0..1，時長由 spec.duration 決定）：
//   彈出 [0, appearEnd] → 停留 [appearEnd, exitStart] → 上浮淡出 [exitStart, 1]
// 停留期的個性（搖擺/抖動/脈動/下滑）都以停留段的正規化時間 h 計算，
// 進出場則吃整段 t，兩者疊加。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/mascot.dart';

/// 某個瞬間主符號的姿態：位移 / 旋轉 / 縮放 / 透明度。
class BubblePose {
  final Offset offset;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double opacity;

  const BubblePose({
    required this.offset,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.opacity,
  });
}

/// 參數化動態包絡：每種泡泡用參數組合出自己的個性，不用各寫一條動畫。
class BubbleMotion {
  /// 彈出段結束點（0..1），easeOutBack 縮放入場。
  final double appearEnd;

  /// 淡出段起點（0..1），之後線性淡出＋持續上浮。
  final double exitStart;

  /// 全程上浮量 px（easeOut 前重後輕）。
  final double rise;

  /// 停留期下滑量 px（easeIn 越滑越快；汗滴用）。
  final double slideY;

  /// 停留期左右搖擺幅度 rad ＋ 次數（音符節拍 / 問號歪頭用）。
  final double swayAngle;
  final double swayCycles;

  /// 停留期高頻水平抖動 px ＋ 次數（隨停留進度衰減；驚嘆號用）。
  final double shakeAmp;
  final double shakeCycles;

  /// 停留期縮放脈動幅度 ＋ 次數（心跳 / 星星閃爍用）。
  final double pulseAmp;
  final double pulseCycles;

  /// 入場旋轉起始角 rad，彈出段內收斂到 0（星星旋入用）。
  final double spinIn;

  /// 停留期縱向拉長比例（配 slideY 做「滴下來」的形變）。
  final double stretch;

  const BubbleMotion({
    this.appearEnd = 0.14,
    this.exitStart = 0.68,
    this.rise = 16,
    this.slideY = 0,
    this.swayAngle = 0,
    this.swayCycles = 1,
    this.shakeAmp = 0,
    this.shakeCycles = 3,
    this.pulseAmp = 0,
    this.pulseCycles = 2,
    this.spinIn = 0,
    this.stretch = 0,
  });

  BubblePose poseAt(double t) {
    final appear = (t / appearEnd).clamp(0.0, 1.0);
    final hold = ((t - appearEnd) / (exitStart - appearEnd)).clamp(0.0, 1.0);
    final exit = t < exitStart
        ? 0.0
        : ((t - exitStart) / (1 - exitStart)).clamp(0.0, 1.0);

    final entranceScale = Curves.easeOutBack.transform(appear);
    final opacity = Curves.easeOut.transform(appear) * (1 - exit);

    // 停留期個性（h = 停留段正規化時間）
    final pulse = pulseAmp == 0
        ? 1.0
        : 1 + pulseAmp * 0.5 * (1 - math.cos(2 * math.pi * pulseCycles * hold));
    final sway = swayAngle == 0
        ? 0.0
        : swayAngle * math.sin(2 * math.pi * swayCycles * hold);
    final shake = shakeAmp == 0
        ? 0.0
        : shakeAmp * math.sin(2 * math.pi * shakeCycles * hold) * (1 - hold);
    final spin = spinIn == 0 ? 0.0 : spinIn * (1 - Curves.easeOutCubic.transform(appear));

    final dy = -rise * Curves.easeOut.transform(t) +
        slideY * Curves.easeIn.transform(hold);
    final stretchY = 1 + stretch * Curves.easeIn.transform(hold);

    return BubblePose(
      offset: Offset(shake, dy),
      rotation: sway + spin,
      scaleX: entranceScale * pulse,
      scaleY: entranceScale * pulse * stretchY,
      opacity: opacity,
    );
  }
}

/// 純幾何符號：在原點畫一個基準大小 s 的符號（含白色 halo 描邊慣例，
/// 提升在場景背景上的可讀性）。新符號實作這個介面即可被主體/衛星重用。
abstract class BubbleGlyph {
  const BubbleGlyph();

  void paint(Canvas c, double s, Color tint, double opacity);

  // 白色描邊當 halo ＋ 彩色實心（沿用 sparkle / pet 那套視覺語彙）。
  static void fillWithHalo(Canvas c, Path path, Color tint, double opacity) {
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.92 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4);
    c.drawPath(path, halo);
    c.drawPath(path, Paint()..color = tint.withValues(alpha: opacity));
  }
}

class HeartGlyph extends BubbleGlyph {
  const HeartGlyph();

  @override
  void paint(Canvas c, double s, Color tint, double opacity) {
    final path = Path()
      ..moveTo(0, s * 0.85)
      ..cubicTo(-s * 1.5, -s * 0.1, -s * 0.65, -s * 1.15, 0, -s * 0.35)
      ..cubicTo(s * 0.65, -s * 1.15, s * 1.5, -s * 0.1, 0, s * 0.85)
      ..close();
    BubbleGlyph.fillWithHalo(c, path, tint, opacity);
  }
}

class StarGlyph extends BubbleGlyph {
  const StarGlyph();

  @override
  void paint(Canvas c, double s, Color tint, double opacity) {
    final path = Path();
    const spikes = 4;
    for (var i = 0; i < spikes * 2; i++) {
      final r = i.isEven ? s : s * 0.38;
      final a = -math.pi / 2 + i * math.pi / spikes;
      final pt = Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    BubbleGlyph.fillWithHalo(c, path, tint, opacity);
  }
}

class DropGlyph extends BubbleGlyph {
  const DropGlyph();

  @override
  void paint(Canvas c, double s, Color tint, double opacity) {
    final path = Path()
      ..moveTo(0, -s * 1.05)
      ..cubicTo(s * 0.95, -s * 0.05, s * 0.78, s * 0.95, 0, s * 0.95)
      ..cubicTo(-s * 0.78, s * 0.95, -s * 0.95, -s * 0.05, 0, -s * 1.05)
      ..close();
    BubbleGlyph.fillWithHalo(c, path, tint, opacity);
  }
}

class NoteGlyph extends BubbleGlyph {
  const NoteGlyph();

  @override
  void paint(Canvas c, double s, Color tint, double opacity) {
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.92 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4);
    final solid = Paint()..color = tint.withValues(alpha: opacity);
    final stem = Paint()
      ..color = tint.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.3
      ..strokeCap = StrokeCap.round;

    final stemTop = Offset(s * 0.55, -s * 1.0);
    final stemBottom = Offset(s * 0.05, s * 0.55);
    final headCenter = Offset(-s * 0.45, s * 0.75);
    final flag = Path()
      ..moveTo(stemTop.dx, stemTop.dy)
      ..quadraticBezierTo(
        stemTop.dx + s * 0.75,
        stemTop.dy + s * 0.3,
        stemTop.dx + s * 0.2,
        stemTop.dy + s * 0.95,
      );

    void oval(Paint paint) {
      c.save();
      c.translate(headCenter.dx, headCenter.dy);
      c.rotate(-0.35);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: s * 1.15, height: s * 0.85),
        paint,
      );
      c.restore();
    }

    c.drawLine(stemBottom, stemTop, halo);
    c.drawPath(flag, halo);
    oval(halo);
    c.drawLine(stemBottom, stemTop, stem);
    c.drawPath(flag, stem);
    oval(solid);
  }
}

/// 文字型符號（!、?、Z）：字重 w900、白色雙層 shadow 當 halo。
/// 字級 = s * 2.2（與圖形符號的視覺份量對齊）。
class TextGlyph extends BubbleGlyph {
  final String text;

  const TextGlyph(this.text);

  @override
  void paint(Canvas c, double s, Color tint, double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: s * 2.2,
          fontWeight: FontWeight.w900,
          height: 1.0,
          color: tint.withValues(alpha: opacity),
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.95 * opacity),
              blurRadius: 3.5,
            ),
            Shadow(
              color: Colors.white.withValues(alpha: 0.95 * opacity),
              blurRadius: 1.5,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
  }
}

/// 伴隨小符號：在主進度的 [delay, delay+span] 窗口內活著，
/// 從 from 漂到 from+drift（單位＝主符號基準 s），自帶淡入淡出與微搖擺。
class BubbleSatellite {
  final BubbleGlyph glyph;

  /// 主進度 0..1 中的出生點與存活長度。
  final double delay;
  final double span;

  /// 相對錨點的起點與整段漂移量（單位：主符號基準 s）。
  final Offset from;
  final Offset drift;

  /// 相對主符號的大小。
  final double scale;

  /// 存活期間的正弦搖擺幅度 rad ＋ 次數。
  final double sway;
  final double swayCycles;

  const BubbleSatellite({
    required this.glyph,
    required this.delay,
    required this.span,
    required this.from,
    required this.drift,
    required this.scale,
    this.sway = 0,
    this.swayCycles = 1,
  });
}

/// 一種泡泡的完整規格。
class BubbleSpec {
  final Duration duration;

  /// 語意色；吃頁面主色的用 accent 調和，其他固定色。
  final Color Function(Color accent) tint;

  final BubbleMotion motion;

  /// 主符號；null = 只有衛星（如 Zzz 三個 Z 依序飄）。
  final BubbleGlyph? glyph;

  /// 主符號基準大小。
  final double size;

  final List<BubbleSatellite> satellites;

  const BubbleSpec({
    required this.duration,
    required this.tint,
    required this.motion,
    required this.glyph,
    this.size = 13.0,
    this.satellites = const [],
  });
}

/// 泡泡註冊表：一種泡泡一筆，全部個性都宣告在這。
final Map<EmotionBubble, BubbleSpec> _specs = {
  // 愛心（摸頭）：心跳脈動＋兩顆小愛心錯開往上飄。
  EmotionBubble.heart: BubbleSpec(
    duration: const Duration(milliseconds: 2400),
    tint: (_) => const Color(0xFFF26B82),
    motion: const BubbleMotion(rise: 18, pulseAmp: 0.12),
    glyph: const HeartGlyph(),
    satellites: const [
      BubbleSatellite(
        glyph: HeartGlyph(),
        delay: 0.18,
        span: 0.55,
        from: Offset(-1.6, 0.2),
        drift: Offset(-0.5, -1.8),
        scale: 0.45,
        sway: 0.10,
      ),
      BubbleSatellite(
        glyph: HeartGlyph(),
        delay: 0.34,
        span: 0.50,
        from: Offset(1.7, -0.3),
        drift: Offset(0.4, -1.6),
        scale: 0.38,
        sway: 0.08,
      ),
    ],
  ),

  // 音符（完成、進度在動）：跟節拍左右搖擺＋一顆小音符伴飛。
  EmotionBubble.note: BubbleSpec(
    duration: const Duration(milliseconds: 2200),
    tint: (accent) => Color.lerp(accent, const Color(0xFF3B3B4E), 0.2)!,
    motion: const BubbleMotion(
      appearEnd: 0.13,
      exitStart: 0.66,
      swayAngle: 0.14,
      swayCycles: 2,
    ),
    glyph: const NoteGlyph(),
    satellites: const [
      BubbleSatellite(
        glyph: NoteGlyph(),
        delay: 0.30,
        span: 0.50,
        from: Offset(1.5, 0.6),
        drift: Offset(0.8, -1.4),
        scale: 0.5,
        sway: 0.12,
        swayCycles: 1.5,
      ),
    ],
  ),

  // 星星（全完成、連勝）：旋轉入場＋閃爍脈動＋兩顆小星交錯眨。
  EmotionBubble.star: BubbleSpec(
    duration: const Duration(milliseconds: 2400),
    tint: (_) => const Color(0xFFFFB938),
    motion: const BubbleMotion(
      appearEnd: 0.13,
      exitStart: 0.70,
      rise: 14,
      spinIn: -0.6,
      pulseAmp: 0.14,
    ),
    glyph: const StarGlyph(),
    satellites: const [
      BubbleSatellite(
        glyph: StarGlyph(),
        delay: 0.20,
        span: 0.45,
        from: Offset(-1.8, -0.6),
        drift: Offset(-0.3, -0.9),
        scale: 0.42,
      ),
      BubbleSatellite(
        glyph: StarGlyph(),
        delay: 0.45,
        span: 0.45,
        from: Offset(1.6, 0.6),
        drift: Offset(0.3, -1.0),
        scale: 0.36,
      ),
    ],
  ),

  // 汗滴（撤銷、失落）：沿頭側下滑＋微拉長；低落情緒保持克制、不加衛星。
  EmotionBubble.sweat: BubbleSpec(
    duration: const Duration(milliseconds: 1900),
    tint: (_) => const Color(0xFF58B4E6),
    motion: const BubbleMotion(
      appearEnd: 0.16,
      exitStart: 0.60,
      rise: 0,
      slideY: 12,
      stretch: 0.16,
    ),
    glyph: const DropGlyph(),
  ),

  // Zzz（還沒開始、夜晚）：三個 Z 由小到大「依序」浮現、各自慢飄——
  // 睡意是慢的，整體時長也拉長。
  EmotionBubble.zzz: BubbleSpec(
    duration: const Duration(milliseconds: 2800),
    tint: (_) => const Color(0xFF93A4BC),
    motion: const BubbleMotion(appearEnd: 0.06, exitStart: 0.72, rise: 6),
    glyph: null,
    satellites: const [
      BubbleSatellite(
        glyph: TextGlyph('Z'),
        delay: 0.0,
        span: 0.72,
        from: Offset(-0.6, 0.5),
        drift: Offset(0.5, -1.0),
        scale: 0.48,
        sway: 0.05,
      ),
      BubbleSatellite(
        glyph: TextGlyph('Z'),
        delay: 0.15,
        span: 0.72,
        from: Offset(0.5, -0.4),
        drift: Offset(0.7, -1.3),
        scale: 0.68,
        sway: 0.05,
      ),
      BubbleSatellite(
        glyph: TextGlyph('Z'),
        delay: 0.30,
        span: 0.70,
        from: Offset(1.7, -1.5),
        drift: Offset(0.9, -1.6),
        scale: 0.91,
        sway: 0.05,
      ),
    ],
  ),

  // 驚嘆號（喝水過量提醒）：快速彈出＋急促左右抖動，主符號稍大。
  EmotionBubble.exclaim: BubbleSpec(
    duration: const Duration(milliseconds: 1800),
    tint: (_) => const Color(0xFFEF6B5A),
    motion: const BubbleMotion(
      appearEnd: 0.10,
      exitStart: 0.70,
      rise: 12,
      shakeAmp: 2.6,
    ),
    glyph: const TextGlyph('!'),
    size: 14.5,
  ),

  // 問號（點兔咪）：歪頭式慢速搖擺。
  EmotionBubble.question: BubbleSpec(
    duration: const Duration(milliseconds: 2100),
    tint: (accent) => Color.lerp(accent, const Color(0xFF3B3B4E), 0.1)!,
    motion: const BubbleMotion(
      rise: 14,
      swayAngle: 0.13,
      swayCycles: 1.5,
    ),
    glyph: const TextGlyph('?'),
  ),
};

// 漏註冊時的保底規格（debug 會 assert 提醒，release 不至於 crash）。
final BubbleSpec _fallbackSpec = BubbleSpec(
  duration: const Duration(milliseconds: 2100),
  tint: (accent) => Color.lerp(accent, const Color(0xFF3B3B4E), 0.1)!,
  motion: const BubbleMotion(),
  glyph: const TextGlyph('!'),
);

BubbleSpec bubbleSpecFor(EmotionBubble b) {
  final spec = _specs[b];
  assert(spec != null, 'EmotionBubble.$b 尚未在 mascot_bubbles.dart 的 _specs 註冊');
  return spec ?? _fallbackSpec;
}

/// 頭頂情緒泡泡 painter：在兔咪頭頂右上方依 [BubbleSpec] 演出。
/// 疊在 [MascotStage] 最上層、不吃點擊；progress 由 stage 的
/// AnimationController 驅動（時長 = spec.duration）。
class MascotEmotionBubblePainter extends CustomPainter {
  // DEBUG: true 時把全部泡泡攤開畫在一排（截圖檢查符號用），驗證後改回 false。
  static const bool kDebugBubbleStrip = false;

  final double progress; // 0..1；0 或 1 不畫
  final EmotionBubble? bubble;
  final Color accent; // 頁面主色（部分符號用固定語意色，不吃 accent）

  MascotEmotionBubblePainter({
    required this.progress,
    required this.bubble,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final anchorY = size.height * 0.17;

    // DEBUG: 一次畫出全部泡泡的停留期姿態，方便截圖檢查。
    if (kDebugBubbleStrip) {
      final all = EmotionBubble.values;
      for (var i = 0; i < all.length; i++) {
        final anchor = Offset(
          size.width * (0.13 + 0.74 * i / (all.length - 1)),
          size.height * 0.14,
        );
        _paintOne(canvas, all[i], anchor, 0.5);
      }
      return;
    }

    final b = bubble;
    if (b == null || progress <= 0 || progress >= 1) return;
    _paintOne(canvas, b, Offset(size.width * 0.655, anchorY), progress);
  }

  void _paintOne(Canvas canvas, EmotionBubble b, Offset anchor, double t) {
    final spec = bubbleSpecFor(b);
    final tint = spec.tint(accent);
    final pose = spec.motion.poseAt(t);

    // 衛星先畫（墊在主符號後面）。
    for (final sat in spec.satellites) {
      final lt = (t - sat.delay) / sat.span;
      if (lt <= 0 || lt >= 1) continue;
      final fadeIn = (lt / 0.25).clamp(0.0, 1.0);
      final fadeOut = ((1 - lt) / 0.30).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut * pose.opacity;
      if (opacity <= 0) continue;
      final pop = Curves.easeOutBack.transform((lt / 0.3).clamp(0.0, 1.0));
      final pos = anchor +
          (sat.from + sat.drift * Curves.easeOut.transform(lt)) * spec.size;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      if (sat.sway != 0) {
        canvas.rotate(
          sat.sway * math.sin(2 * math.pi * sat.swayCycles * lt),
        );
      }
      sat.glyph.paint(canvas, spec.size * sat.scale * pop, tint, opacity);
      canvas.restore();
    }

    final glyph = spec.glyph;
    if (glyph == null ||
        pose.opacity <= 0 ||
        pose.scaleX <= 0 ||
        pose.scaleY <= 0) {
      return;
    }
    canvas.save();
    canvas.translate(anchor.dx + pose.offset.dx, anchor.dy + pose.offset.dy);
    canvas.rotate(pose.rotation);
    canvas.scale(pose.scaleX, pose.scaleY);
    glyph.paint(canvas, spec.size, tint, pose.opacity);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MascotEmotionBubblePainter old) =>
      old.progress != progress || old.bubble != bubble || old.accent != accent;
}
