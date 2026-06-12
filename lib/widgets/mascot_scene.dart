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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/mascot.dart';

/// 從 [MascotPersona.current] 自動讀情緒 + 台詞 的場景；
/// 切頁不會重建兔咪狀態，只有互動會推新狀態。
class PersonaScene extends StatelessWidget {
  final Color accent;
  final int reactionTick;
  final VoidCallback? onTap;

  const PersonaScene({
    super.key,
    required this.accent,
    this.reactionTick = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MascotState>(
      valueListenable: MascotPersona.current,
      builder: (_, state, _) => MascotScene(
        asset: state.assetPath,
        accent: accent,
        speech: state.speech,
        reactionTick: reactionTick,
        onTap: onTap,
      ),
    );
  }
}

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
          top: 50,
          left: 28,
          right: 28,
          child: MascotSpeechBubble(text: speech, accent: accent),
        ),
        Align(
          alignment: const Alignment(0, 0.92),
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

class MascotSpeechBubble extends StatefulWidget {
  final String text;
  final Color accent;

  /// 顯示多久後開始淡出（換新台詞會重新計時）
  final Duration visibleDuration;

  /// 淡出動畫長度
  final Duration fadeDuration;

  const MascotSpeechBubble({
    super.key,
    required this.text,
    required this.accent,
    this.visibleDuration = const Duration(seconds: 7),
    this.fadeDuration = const Duration(milliseconds: 600),
  });

  @override
  State<MascotSpeechBubble> createState() => _MascotSpeechBubbleState();
}

class _MascotSpeechBubbleState extends State<MascotSpeechBubble> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant MascotSpeechBubble old) {
    super.didUpdateWidget(old);
    // 換新台詞 → 立刻可見 + 重新計時
    if (old.text != widget.text) {
      setState(() => _visible = true);
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.visibleDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: widget.fadeDuration,
        curve: Curves.easeOut,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: CustomPaint(
              painter: _SpeechBubblePainter(
                color: Colors.white,
                borderColor: widget.accent.withValues(alpha: 0.25),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    widget.text,
                    key: ValueKey(widget.text),
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
  late final AnimationController _reactionCtrl;
  late final Animation<double> _reactionScale;
  late final Animation<double> _reactionLift;
  late final AnimationController _breathCtrl;
  late final Animation<double> _breath;

  // 眨眼：閉眼差分換圖。只有 MascotEmotion.blinkAssetForPath 有對應圖的
  // 情緒會眨；其他情緒 timer 照走但跳過，等換回有差分的圖自然恢復。
  final math.Random _rng = math.Random();
  Timer? _blinkTimer;
  bool _eyesClosed = false;

  @override
  void initState() {
    super.initState();
    _reactionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    final curved = CurvedAnimation(
      parent: _reactionCtrl,
      curve: Curves.easeOutCubic,
    );
    _reactionScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.98), weight: 16),
      TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.05), weight: 34),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 50),
    ]).animate(curved);
    _reactionLift = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 38),
      TweenSequenceItem(tween: Tween(begin: -6, end: 0), weight: 62),
    ]).animate(curved);

    // idle 呼吸：以腳底為錨點的細微縱向縮放，一吸一吐 ~2.6 秒
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _breath = CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut);

    _scheduleNextBlink();
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    // 人類眨眼間隔大約 2~6 秒，取隨機避免機械感
    _blinkTimer = Timer(
      Duration(milliseconds: 2400 + _rng.nextInt(3200)),
      () async {
        if (!mounted) return;
        if (MascotEmotion.blinkAssetForPath(widget.asset) != null) {
          await _blinkOnce();
          // 偶爾連眨兩下，更像活的
          if (mounted && _rng.nextDouble() < 0.22) {
            await Future<void>.delayed(const Duration(milliseconds: 140));
            if (mounted) await _blinkOnce();
          }
        }
        if (mounted) _scheduleNextBlink();
      },
    );
  }

  Future<void> _blinkOnce() async {
    setState(() => _eyesClosed = true);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    if (mounted) setState(() => _eyesClosed = false);
  }

  @override
  void didUpdateWidget(covariant MascotStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reactionTick != widget.reactionTick) {
      _reactionCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _breathCtrl.dispose();
    _reactionCtrl.dispose();
    super.dispose();
  }

  /// 兔咪本體。有閉眼差分時把兩張圖都放進樹裡（用 opacity 切換），
  /// 讓差分圖保持解碼狀態，第一次眨眼才不會閃白。
  Widget _buildBunnyImage() {
    final blinkAsset = MascotEmotion.blinkAssetForPath(widget.asset);
    if (blinkAsset == null) {
      return Image.asset(widget.asset, fit: BoxFit.contain);
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Opacity(
          opacity: _eyesClosed ? 0 : 1,
          child: Image.asset(widget.asset, fit: BoxFit.contain),
        ),
        Opacity(
          opacity: _eyesClosed ? 1 : 0,
          child: Image.asset(blinkAsset, fit: BoxFit.contain),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 按到就自動彈一下（每頁都有反應），再交給外面的 onTap 處理其他副作用
        _reactionCtrl.forward(from: 0);
        widget.onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 252,
        height: 252,
        child: AnimatedBuilder(
          animation: _reactionCtrl,
          builder: (context, child) {
            // 地面陰影：依 _reactionLift 同步縮小變淡 → 「離開地面」的感覺
            // 位置 bottom 要對到兔咪 CG 圖裡腳的位置（1024×1024 畫布，腳在 ~80%）
            final lift = _reactionLift.value; // 0 ~ -6
            final liftProgress = (-lift / 6).clamp(0.0, 1.0);
            final shadowScale = ui.lerpDouble(1, 0.88, liftProgress)!;
            final shadowOpacity = ui.lerpDouble(0.24, 0.13, liftProgress)!;
            final shadowColor = Color.lerp(
              const Color(0xFF5B4436),
              widget.accent,
              0.12,
            )!;
            return Stack(
              alignment: Alignment.center,
              children: [
                // 腳下橢圓陰影（在 sparkle 跟兔咪本體下方）
                Positioned(
                  // 對齊兔咪 CG 的腳底：shadow painter 的接觸影中心約落在 stage y=216。
                  bottom: 22,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.scale(
                      scaleX: shadowScale,
                      child: SizedBox(
                        width: 158,
                        height: 38,
                        child: CustomPaint(
                          painter: _MascotGroundShadowPainter(
                            color: shadowColor,
                            opacity: shadowOpacity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
                  offset: Offset(0, _reactionLift.value),
                  child: Transform.scale(
                    scaleX: _reactionScale.value,
                    scaleY: _reactionScale.value,
                    child: child,
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
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, bunny) => Transform.scale(
                  scaleY: 1 + 0.013 * _breath.value,
                  scaleX: 1 - 0.005 * _breath.value,
                  alignment: Alignment.bottomCenter,
                  child: bunny,
                ),
                child: _buildBunnyImage(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotGroundShadowPainter extends CustomPainter {
  final Color color;
  final double opacity;

  const _MascotGroundShadowPainter({
    required this.color,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.56);

    final ambientPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.38)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: size.width * 0.96,
        height: size.height * 0.72,
      ),
      ambientPaint,
    );

    final contactPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, size.height * 0.08),
        width: size.width * 0.66,
        height: size.height * 0.34,
      ),
      contactPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotGroundShadowPainter old) =>
      old.color != color || old.opacity != opacity;
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
