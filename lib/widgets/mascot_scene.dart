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

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/mascot.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';

class MascotIdleScope extends InheritedWidget {
  final bool paused;

  const MascotIdleScope({
    super.key,
    required this.paused,
    required super.child,
  });

  static bool pausedOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MascotIdleScope>()
            ?.paused ??
        false;
  }

  @override
  bool updateShouldNotify(covariant MascotIdleScope oldWidget) =>
      oldWidget.paused != paused;
}

/// 從 [MascotPersona.current] 自動讀情緒 + 台詞 的場景；
/// 切頁不會重建兔咪狀態，只有互動會推新狀態。
class PersonaScene extends StatelessWidget {
  final Color accent;
  final int reactionTick;
  final VoidCallback? onTap;
  final VoidCallback? onHeadPet;

  /// 閒置凍結：true 時兔咪暫停呼吸與眨眼，讓畫面完全靜止省電；
  /// 一有互動由上層轉回 false 即恢復。
  final bool paused;

  const PersonaScene({
    super.key,
    required this.accent,
    this.reactionTick = 0,
    this.onTap,
    this.onHeadPet,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePaused = paused || MascotIdleScope.pausedOf(context);

    void handleHeadPet() {
      final callback = onHeadPet;
      if (callback != null) {
        callback();
      } else {
        MascotPersona.interact(MascotContext.headPet);
      }
    }

    return ValueListenableBuilder<MascotState>(
      valueListenable: MascotPersona.current,
      builder: (_, state, _) => ValueListenableBuilder<String>(
        valueListenable: WardrobeStore.selectedOutfit,
        builder: (_, outfitId, _) => MascotScene(
          // 依目前造型把 core 兔咪換成對應皮膚版本；原始造型為 identity。
          asset: skinnedMascotAsset(
            state.assetPath,
            outfitById(outfitId).skinKey,
          ),
          accent: accent,
          speech: state.speech,
          bubble: state.bubble,
          bubbleTick: state.bubbleTick,
          reactionTick: reactionTick,
          onTap: onTap,
          onHeadPet: handleHeadPet,
          paused: effectivePaused,
        ),
      ),
    );
  }
}

class MascotScene extends StatelessWidget {
  /// 兔咪 PNG 路徑（一般用 [MascotEmotion.assetPath]）。
  final String asset;

  /// 主色，影響對話框邊框與點擊時星星顏色。
  final Color accent;

  /// 要顯示的台詞；null / 空字串 = 這次不冒文字泡泡（只留頭頂符號）。
  final String? speech;

  /// 頭頂情緒泡泡；null = 這次不冒。換成新值（或非 null）時冒一下後淡出。
  final EmotionBubble? bubble;

  /// 泡泡事件序號；同一種泡泡連續觸發時也用它重播動畫。
  final int bubbleTick;

  /// 每次 +1 觸發一次「驚喜」反應動畫（往上跳 + 星星）。
  /// 不需要的話傳 0 即可。
  final int reactionTick;

  /// 點擊兔咪的 callback；不需互動可省略。
  final VoidCallback? onTap;

  /// 摸到兔咪頭時的 callback；不需特殊副作用可省略。
  final VoidCallback? onHeadPet;

  /// 閒置凍結：暫停兔咪呼吸與眨眼（見 [PersonaScene.paused]）。
  final bool paused;

  const MascotScene({
    super.key,
    required this.asset,
    required this.accent,
    required this.speech,
    this.bubble,
    this.bubbleTick = 0,
    this.reactionTick = 0,
    this.onTap,
    this.onHeadPet,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (speech != null && speech!.isNotEmpty)
          Positioned(
            top: 50,
            left: 28,
            right: 28,
            child: MascotSpeechBubble(text: speech!, accent: accent),
          ),
        Align(
          alignment: const Alignment(0, 0.92),
          child: MascotStage(
            asset: asset,
            accent: accent,
            bubble: bubble,
            bubbleTick: bubbleTick,
            reactionTick: reactionTick,
            onTap: onTap ?? () {},
            onHeadPet: onHeadPet,
            paused: paused,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppInk.strong,
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

  /// 頭頂情緒泡泡；變化（或從 null 變成非 null）時冒一下後淡出。
  final EmotionBubble? bubble;
  final int bubbleTick;
  final int reactionTick;
  final VoidCallback onTap;
  final VoidCallback? onHeadPet;

  /// 閒置凍結：暫停呼吸與眨眼（見 [PersonaScene.paused]）。
  final bool paused;

  const MascotStage({
    super.key,
    required this.asset,
    required this.accent,
    this.bubble,
    this.bubbleTick = 0,
    required this.reactionTick,
    required this.onTap,
    this.onHeadPet,
    this.paused = false,
  });

  @override
  State<MascotStage> createState() => _MascotStageState();
}

class _MascotStageState extends State<MascotStage>
    with TickerProviderStateMixin {
  late final AnimationController _reactionCtrl;
  late final Animation<double> _reactionScale;
  late final Animation<double> _reactionLift;
  late final AnimationController _petCtrl;
  late final AnimationController _breathCtrl;
  late final Animation<double> _breath;

  // 頭頂情緒泡泡：彈出 → 停留 → 上浮淡出的一次性動畫。
  // 觸發見 didUpdateWidget；繪製見 _MascotEmotionBubblePainter。
  late final AnimationController _bubbleCtrl;
  EmotionBubble? _bubbleShown; // 動畫期間正在畫的泡泡（即使 widget 換新值也畫到淡出）

  // 眨眼：閉眼差分換圖。只有 MascotEmotion.blinkAssetForPath 有對應圖的
  // 情緒會眨；其他情緒 timer 照走但跳過，等換回有差分的圖自然恢復。
  final math.Random _rng = math.Random();
  Timer? _blinkTimer;
  bool _eyesClosed = false;
  bool _isPetting = false;
  double _petDrag = 0;

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

    _petCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );

    // idle 呼吸：以腳底為錨點的細微縱向縮放，一吸一吐 ~2.6 秒
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    if (!widget.paused) _breathCtrl.repeat(reverse: true);
    _breath = CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut);

    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    // 進場若已帶泡泡（例如直接落在某情緒），冒一次。
    _bubbleShown = widget.bubble;
    if (widget.bubble != null) _bubbleCtrl.forward(from: 0);

    _scheduleNextBlink();
  }

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    if (widget.paused) return; // 閒置凍結時不排下一次眨眼
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
    // 情緒事件帶了泡泡，且（事件序號、泡泡或立繪改變）就重冒一次。
    // 同情境連點會被 MascotPersona 的 holdDuration 擋掉，不會狂閃。
    if (widget.bubble != null &&
        (oldWidget.bubbleTick != widget.bubbleTick ||
            oldWidget.bubble != widget.bubble ||
            oldWidget.asset != widget.asset)) {
      _bubbleShown = widget.bubble;
      _bubbleCtrl.forward(from: 0);
    }
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        // 閒置凍結：停呼吸、取消眨眼，畫面靜止省電。
        _breathCtrl.stop();
        _blinkTimer?.cancel();
        _eyesClosed = false; // 不要定格在閉眼；隨即重建會套用
      } else {
        // 恢復：重新開始呼吸與眨眼。
        if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
        _scheduleNextBlink();
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _petCtrl.dispose();
    _breathCtrl.dispose();
    _reactionCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  bool _isHeadHit(Offset position, {bool relaxed = false}) {
    const center = Offset(126, 88);
    final radiusX = relaxed ? 116.0 : 94.0;
    final radiusY = relaxed ? 88.0 : 70.0;
    final dx = (position.dx - center.dx) / radiusX;
    final dy = (position.dy - center.dy) / radiusY;
    return dx * dx + dy * dy <= 1;
  }

  double _headDragAmount(Offset position) =>
      ((position.dx - 126) / 94).clamp(-1.0, 1.0).toDouble();

  void _triggerTapReaction() {
    _reactionCtrl.forward(from: 0);
    widget.onTap();
  }

  void _triggerHeadPet({required bool held}) {
    _petDrag = 0;
    playHaptic(HapticLevel.selection);
    widget.onHeadPet?.call();
    if (held) {
      _isPetting = true;
      _petCtrl.repeat();
    } else {
      _isPetting = false;
      _petCtrl.forward(from: 0);
    }
  }

  void _updateHeadPet(Offset position) {
    if (!_isPetting) return;
    if (!_isHeadHit(position, relaxed: true)) {
      _endHeadPet();
      return;
    }
    _petDrag = _headDragAmount(position);
  }

  void _endHeadPet() {
    if (!_isPetting) return;
    _isPetting = false;
    _petDrag = 0;
    _petCtrl.animateTo(
      1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
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
      onTapUp: (details) {
        if (_isHeadHit(details.localPosition)) {
          _triggerHeadPet(held: false);
        } else {
          // 按到就自動彈一下（每頁都有反應），再交給外面的 onTap 處理其他副作用
          _triggerTapReaction();
        }
      },
      onPanStart: (details) {
        if (_isHeadHit(details.localPosition)) {
          _triggerHeadPet(held: true);
        }
      },
      onPanUpdate: (details) {
        _updateHeadPet(details.localPosition);
      },
      onPanEnd: (_) => _endHeadPet(),
      onPanCancel: _endHeadPet,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 252,
        height: 252,
        child: AnimatedBuilder(
          animation: Listenable.merge([_reactionCtrl, _petCtrl, _bubbleCtrl]),
          builder: (context, child) {
            // 地面陰影：依 _reactionLift 同步縮小變淡 → 「離開地面」的感覺
            // 位置 bottom 要對到兔咪 CG 圖裡腳的位置（1024×1024 畫布，腳在 ~80%）
            final lift = _reactionLift.value; // 0 ~ -6
            final liftProgress = (-lift / 6).clamp(0.0, 1.0);
            final pet = _petCtrl.value;
            final petPress = math.sin(math.pi * pet).clamp(0.0, 1.0).toDouble();
            final petRub = math.sin(math.pi * 2 * pet);
            final petScaleX = 1 + 0.012 * petPress;
            final petScaleY = 1 - 0.018 * petPress;
            final petOffsetX = (petRub * 1.9 + _petDrag * 2.4) * petPress;
            final petOffsetY = 1.4 * petPress;
            final petTilt = (petRub * 0.014 + _petDrag * 0.012) * petPress;
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _MascotSparklePainter(
                            progress: _reactionCtrl.value,
                            color: widget.accent,
                          ),
                        ),
                        CustomPaint(
                          painter: _MascotPetPainter(
                            progress: pet,
                            color: widget.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(petOffsetX, _reactionLift.value + petOffsetY),
                  child: Transform.rotate(
                    angle: petTilt,
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scaleX: _reactionScale.value * petScaleX,
                      scaleY: _reactionScale.value * petScaleY,
                      child: child,
                    ),
                  ),
                ),
                // 頭頂情緒泡泡：畫在最上層（蓋住頭頂前方），不吃點擊。
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MascotEmotionBubblePainter(
                        progress: _bubbleCtrl.value,
                        bubble: _bubbleShown,
                        color: widget.accent,
                      ),
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
    final cx = size.width / 2;
    // 三層（由淡到深）：ambient 大暈 → 中層 pool → 雙腳 contact kiss。
    // 視角是斜俯視，暈的重心放在畫布下半（往觀者方向 pool）；
    // kiss 貼在畫布上緣附近 = 兔咪腳底正下方，蓋掉 CG 腳掌白邊
    // 與陰影之間的亮縫，才有「體重壓在地上」的感覺。

    final ambient = Paint()
      ..color = color.withValues(alpha: opacity * 0.34)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 11);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.58),
        width: size.width * 0.96,
        height: size.height * 0.62,
      ),
      ambient,
    );

    final pool = Paint()
      ..color = color.withValues(alpha: opacity * 0.70)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.52),
        width: size.width * 0.62,
        height: size.height * 0.40,
      ),
      pool,
    );

    // 左右腳各一個小接觸影（CG 站姿雙腳中心約在 ±12% 畫布寬），
    // 比 base opacity 再深一階，蓋掉腳掌白邊下的亮縫
    final kiss = Paint()
      ..color = color.withValues(alpha: (opacity * 1.3).clamp(0.0, 1.0))
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5);
    for (final dx in [-size.width * 0.12, size.width * 0.12]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx, size.height * 0.27),
          width: size.width * 0.26,
          height: size.height * 0.26,
        ),
        kiss,
      );
    }
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

class _MascotPetPainter extends CustomPainter {
  final double progress;
  final Color color;

  _MascotPetPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final opacity = math.sin(math.pi * progress).clamp(0.0, 1.0).toDouble();
    if (opacity <= 0) return;

    final rub = math.sin(math.pi * 2 * progress);
    final petColor = Color.lerp(color, const Color(0xFFEFA1A8), 0.7)!;
    final center = Offset(size.width / 2 + rub * 4, size.height * 0.23);
    final stroke = Paint()
      ..color = petColor.withValues(alpha: 0.50 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.3;

    for (var i = 0; i < 3; i++) {
      final arcCenter = center + Offset((i - 1) * 18, i.isEven ? 0 : -3);
      final rect = Rect.fromCenter(
        center: arcCenter,
        width: 26 + i * 4,
        height: 15 + i * 2,
      );
      canvas.drawArc(rect, math.pi * 1.08, math.pi * 0.84, false, stroke);
    }

    final dotPaint = Paint()
      ..color = petColor.withValues(alpha: 0.34 * opacity);
    canvas.drawCircle(center + Offset(-48, 14 - opacity * 4), 2.1, dotPaint);
    canvas.drawCircle(center + Offset(47, 10 - opacity * 3), 1.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _MascotPetPainter old) =>
      old.progress != progress || old.color != color;
}

/// 頭頂情緒泡泡：在兔咪頭頂右上方冒一顆漫畫符號，彈出→停留→上浮淡出。
/// 符號全用 Path / 文字幾何畫（同 sparkle／pet 那套），可隨頁面主色上色。
class _MascotEmotionBubblePainter extends CustomPainter {
  // DEBUG: true 時一次畫出全部泡泡（截圖檢查符號用），驗證後改回 false。
  static const bool _kDebugBubbleStrip = false;

  final double progress; // 0..1；0 或 1 不畫
  final EmotionBubble? bubble;
  final Color color; // 頁面主色（部分符號用固定語意色，不吃 accent）

  _MascotEmotionBubblePainter({
    required this.progress,
    required this.bubble,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final b = bubble;
    if (!_kDebugBubbleStrip && (b == null || progress <= 0 || progress >= 1)) {
      return;
    }

    // 彈出(0~0.14) → 停留(~0.68) → 上浮淡出(0.68~1)
    final appear = (progress / 0.14).clamp(0.0, 1.0);
    final scale = Curves.easeOutBack.transform(appear);
    final fadeOut = progress < 0.68
        ? 1.0
        : (1 - (progress - 0.68) / 0.32).clamp(0.0, 1.0);
    final opacity = Curves.easeOut.transform(appear) * fadeOut;

    final rise = -16 * Curves.easeOut.transform(progress);
    final anchor = Offset(size.width * 0.655, size.height * 0.17 + rise);
    final s = 13.0 * scale;

    // DEBUG: 一次畫出全部泡泡，方便截圖檢查符號外觀（驗證後移除）。
    if (_kDebugBubbleStrip) {
      final all = EmotionBubble.values;
      for (var i = 0; i < all.length; i++) {
        canvas.save();
        canvas.translate(
          size.width * (0.13 + 0.74 * i / (all.length - 1)),
          size.height * 0.14,
        );
        _paintSymbol(canvas, all[i], 13.0, 1.0);
        canvas.restore();
      }
      return;
    }

    if (opacity <= 0 || scale <= 0) return;
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    _paintSymbol(canvas, b!, s, opacity);
    canvas.restore();
  }

  void _paintSymbol(Canvas canvas, EmotionBubble b, double s, double opacity) {
    final tint = _tintFor(b);
    switch (b) {
      case EmotionBubble.heart:
        _fillSymbol(canvas, _heartPath(s), tint, opacity);
      case EmotionBubble.star:
        _fillSymbol(canvas, _starPath(s), tint, opacity);
      case EmotionBubble.sweat:
        _fillSymbol(canvas, _dropPath(s), tint, opacity);
      case EmotionBubble.note:
        _drawNote(canvas, s, tint, opacity);
      case EmotionBubble.zzz:
        _drawZzz(canvas, s, tint, opacity);
      case EmotionBubble.exclaim:
        _paintGlyph(canvas, '!', s * 2.2, tint, opacity, Offset.zero);
      case EmotionBubble.question:
        _paintGlyph(canvas, '?', s * 2.2, tint, opacity, Offset.zero);
    }
  }

  Color _tintFor(EmotionBubble b) {
    switch (b) {
      case EmotionBubble.heart:
        return const Color(0xFFF26B82);
      case EmotionBubble.note:
        return Color.lerp(color, const Color(0xFF3B3B4E), 0.2)!;
      case EmotionBubble.star:
        return const Color(0xFFFFB938);
      case EmotionBubble.sweat:
        return const Color(0xFF58B4E6);
      case EmotionBubble.zzz:
        return const Color(0xFF93A4BC);
      case EmotionBubble.exclaim:
        return const Color(0xFFEF6B5A);
      case EmotionBubble.question:
        return Color.lerp(color, const Color(0xFF3B3B4E), 0.1)!;
    }
  }

  // 白色描邊當 halo（提升在場景背景上的可讀性）+ 彩色實心。
  void _fillSymbol(Canvas c, Path path, Color tint, double opacity) {
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.92 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4);
    c.drawPath(path, halo);
    c.drawPath(path, Paint()..color = tint.withValues(alpha: opacity));
  }

  Path _heartPath(double s) => Path()
    ..moveTo(0, s * 0.85)
    ..cubicTo(-s * 1.5, -s * 0.1, -s * 0.65, -s * 1.15, 0, -s * 0.35)
    ..cubicTo(s * 0.65, -s * 1.15, s * 1.5, -s * 0.1, 0, s * 0.85)
    ..close();

  Path _dropPath(double s) => Path()
    ..moveTo(0, -s * 1.05)
    ..cubicTo(s * 0.95, -s * 0.05, s * 0.78, s * 0.95, 0, s * 0.95)
    ..cubicTo(-s * 0.78, s * 0.95, -s * 0.95, -s * 0.05, 0, -s * 1.05)
    ..close();

  Path _starPath(double s) {
    final p = Path();
    const spikes = 4;
    for (var i = 0; i < spikes * 2; i++) {
      final r = i.isEven ? s : s * 0.38;
      final a = -math.pi / 2 + i * math.pi / spikes;
      final pt = Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  void _drawNote(Canvas c, double s, Color tint, double opacity) {
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

  // Zzz：三個 Z 由小到大往右上斜飄。
  void _drawZzz(Canvas c, double s, Color tint, double opacity) {
    final specs = <({double size, Offset off})>[
      (size: s * 1.05, off: Offset(-s * 0.6, s * 0.5)),
      (size: s * 1.5, off: Offset(s * 0.5, -s * 0.4)),
      (size: s * 2.0, off: Offset(s * 1.7, -s * 1.5)),
    ];
    for (final spec in specs) {
      _paintGlyph(c, 'Z', spec.size, tint, opacity, spec.off);
    }
  }

  void _paintGlyph(
    Canvas c,
    String text,
    double fontSize,
    Color tint,
    double opacity,
    Offset off,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
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
    tp.paint(c, off - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MascotEmotionBubblePainter old) =>
      old.progress != progress || old.bubble != bubble || old.color != color;
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
