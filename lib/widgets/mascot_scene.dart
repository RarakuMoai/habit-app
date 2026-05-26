// 兔咪場景共用元件：把首頁那組「兔咪 + 對話框 + 互動動畫」抽成可共用 widget，
// 讓其他頁面（番茄鐘、喝水、體重、家庭）能套用同樣的呈現。
//
// 主要對外 API：
//   - [MascotScene]：兔咪 + 對話框組合，直接餵給 [MascotPageShell] 的 scene。
//   - [MascotStage]：純兔咪 widget（含 idle 呼吸、tap reaction 動畫）。
//   - [MascotSpeechBubble]：對話框 widget。
//
// 內部維持原本動作參數表（_motionForAsset）與星星 reaction painter
// （_MascotSparklePainter）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

class MascotScene extends StatelessWidget {
  /// 兔咪 PNG 路徑（一般用 [MascotEmotion.assetPath]）。
  final String asset;

  /// 主色，影響對話框邊框與點擊時星星顏色。
  final Color accent;

  /// 要顯示的台詞。
  final String speech;

  /// 每次 +1 觸發一次「驚喜」反應動畫（往上跳 + 星星）。
  /// 不需要的話傳 0 即可。
  final int reactionTick;

  /// 點擊兔咪的 callback；不需互動可省略。
  final VoidCallback? onTap;

  const MascotScene({
    super.key,
    required this.asset,
    required this.accent,
    required this.speech,
    this.reactionTick = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 30,
          left: 28,
          right: 28,
          child: MascotSpeechBubble(text: speech, accent: accent),
        ),
        Align(
          alignment: const Alignment(0, 0.84),
          child: MascotStage(
            asset: asset,
            accent: accent,
            reactionTick: reactionTick,
            onTap: onTap ?? () {},
          ),
        ),
      ],
    );
  }
}

class MascotSpeechBubble extends StatelessWidget {
  final String text;
  final Color accent;

  const MascotSpeechBubble({
    super.key,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: CustomPaint(
          painter: _SpeechBubblePainter(
            color: Colors.white,
            borderColor: accent.withValues(alpha: 0.25),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                text,
                key: ValueKey(text),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MascotStage extends StatefulWidget {
  final String asset;
  final Color accent;
  final int reactionTick;
  final VoidCallback onTap;

  const MascotStage({
    super.key,
    required this.asset,
    required this.accent,
    required this.reactionTick,
    required this.onTap,
  });

  @override
  State<MascotStage> createState() => _MascotStageState();
}

class _MascotStageState extends State<MascotStage>
    with TickerProviderStateMixin {
  late final AnimationController _idleCtrl;
  late final AnimationController _reactionCtrl;
  late final Animation<double> _reactionScale;
  late final Animation<double> _reactionLift;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: _motionForAsset(widget.asset).duration,
    )..repeat(reverse: true);
    _reactionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    final curved = CurvedAnimation(
      parent: _reactionCtrl,
      curve: Curves.easeOutCubic,
    );
    _reactionScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.96), weight: 16),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.12), weight: 34),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 50),
    ]).animate(curved);
    _reactionLift = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -18), weight: 38),
      TweenSequenceItem(tween: Tween(begin: -18, end: 0), weight: 62),
    ]).animate(curved);
  }

  @override
  void didUpdateWidget(covariant MascotStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _idleCtrl
        ..duration = _motionForAsset(widget.asset).duration
        ..repeat(reverse: true);
    }
    if (oldWidget.reactionTick != widget.reactionTick) {
      _reactionCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    _reactionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 252,
        height: 252,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idleCtrl, _reactionCtrl]),
          builder: (context, child) {
            final motion = _motionForAsset(widget.asset);
            final idle = Curves.easeInOut.transform(_idleCtrl.value);
            final breathe = motion.baseScale + idle * motion.breathe;
            final sway = (idle - 0.5) * motion.sway;
            final lift = motion.baseLift - motion.lift * idle;

            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MascotSparklePainter(
                        progress: _reactionCtrl.value,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, lift + _reactionLift.value),
                  child: Transform.rotate(
                    angle: sway,
                    child: Transform.scale(
                      scaleX: _reactionScale.value,
                      scaleY: breathe * _reactionScale.value,
                      child: child,
                    ),
                  ),
                ),
              ],
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(widget.asset),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Image.asset(widget.asset, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotMotion {
  final Duration duration;
  final double baseScale;
  final double baseLift;
  final double breathe;
  final double sway;
  final double lift;

  const _MascotMotion({
    required this.duration,
    required this.baseScale,
    required this.baseLift,
    required this.breathe,
    required this.sway,
    required this.lift,
  });
}

String _moodForAsset(String asset) {
  if (asset.contains('sleep')) return 'sleep';
  if (asset.contains('night')) return 'night';
  if (asset.contains('expect')) return 'expect';
  if (asset.contains('sad')) return 'sad';
  if (asset.contains('streak')) return 'streak';
  if (asset.contains('happy')) return 'happy';
  if (asset.contains('smile')) return 'smile';
  return 'neutral';
}

_MascotMotion _motionForAsset(String asset) {
  switch (_moodForAsset(asset)) {
    case 'sleep':
      return const _MascotMotion(
        duration: Duration(milliseconds: 4200),
        baseScale: 0.99,
        baseLift: 4,
        breathe: 0.010,
        sway: 0.016,
        lift: 5.5,
      );
    case 'night':
      return const _MascotMotion(
        duration: Duration(milliseconds: 4600),
        baseScale: 0.99,
        baseLift: 3,
        breathe: 0.008,
        sway: 0.012,
        lift: 3.5,
      );
    case 'expect':
      return const _MascotMotion(
        duration: Duration(milliseconds: 2200),
        baseScale: 1.0,
        baseLift: -1,
        breathe: 0.016,
        sway: 0.030,
        lift: 3.8,
      );
    case 'sad':
      return const _MascotMotion(
        duration: Duration(milliseconds: 3600),
        baseScale: 0.975,
        baseLift: 5,
        breathe: 0.006,
        sway: 0.008,
        lift: 1.8,
      );
    case 'happy':
      return const _MascotMotion(
        duration: Duration(milliseconds: 2100),
        baseScale: 1.01,
        baseLift: -2,
        breathe: 0.020,
        sway: 0.038,
        lift: 4.5,
      );
    case 'streak':
      return const _MascotMotion(
        duration: Duration(milliseconds: 1800),
        baseScale: 1.015,
        baseLift: -3,
        breathe: 0.022,
        sway: 0.048,
        lift: 5.0,
      );
    default:
      return const _MascotMotion(
        duration: Duration(milliseconds: 3000),
        baseScale: 1.0,
        baseLift: 0,
        breathe: 0.014,
        sway: 0.022,
        lift: 2.8,
      );
  }
}

class _MascotSparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  _MascotSparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final opacity = (progress < 0.5 ? progress * 2 : (1 - progress) * 2).clamp(
      0.0,
      1.0,
    );
    final center = Offset(size.width / 2, size.height / 2 - 20);
    final specs = <({double angle, double distance, double size})>[
      (angle: -2.35, distance: 86, size: 7),
      (angle: -1.75, distance: 100, size: 5),
      (angle: -0.92, distance: 92, size: 8),
      (angle: -0.18, distance: 76, size: 5),
      (angle: 0.62, distance: 95, size: 7),
      (angle: 2.65, distance: 78, size: 5),
    ];
    for (final spec in specs) {
      final distance = spec.distance * Curves.easeOut.transform(progress);
      final offset = Offset(
        center.dx + distance * math.cos(spec.angle),
        center.dy + distance * math.sin(spec.angle),
      );
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55 * opacity)
        ..style = PaintingStyle.fill;
      _drawStar(canvas, offset, spec.size * (0.7 + progress * 0.3), paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : radius * 0.42;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final p = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MascotSparklePainter old) =>
      old.progress != progress || old.color != color;
}

class _SpeechBubblePainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  _SpeechBubblePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 8),
      const Radius.circular(16),
    );
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawRRect(bodyRect.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawRRect(bodyRect, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(bodyRect, borderPaint);

    final tailPath = Path()
      ..moveTo(size.width / 2 - 8, size.height - 8)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 8, size.height - 8)
      ..close();
    canvas.drawPath(tailPath, fillPaint);
    canvas.drawPath(tailPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter old) =>
      old.color != color || old.borderColor != borderColor;
}
