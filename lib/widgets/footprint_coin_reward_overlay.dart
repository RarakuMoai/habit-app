import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import '../utils/sfx_service.dart';
import 'reward_animation_anchor.dart';

/// 每日登入足跡幣演出：兔咪手前聚光、足跡幣向四周灑開，再依序吸入
/// AppBar 餘額——接在 LoginStreakPage pop 之後演。
class FootprintCoinRewardOverlay extends StatefulWidget {
  const FootprintCoinRewardOverlay({
    super.key,
    required this.amount,
    required this.startBalance,
    required this.targetBalance,
    required this.onFinished,
  });

  final int amount;
  final int startBalance;
  final int targetBalance;
  final VoidCallback onFinished;

  @override
  State<FootprintCoinRewardOverlay> createState() =>
      _FootprintCoinRewardOverlayState();
}

class _FootprintCoinRewardOverlayState extends State<FootprintCoinRewardOverlay>
    with SingleTickerProviderStateMixin {
  static const _maxCoinCount = 9;
  // 三段節奏：灑開約 0.8 秒 → 展示停留約 0.35 秒 → 依序吸入。
  // 讓使用者看清楚錢確實從兔咪身上散出，又不會拖成等待畫面；提示仍可點擊略過。
  static const _animationDuration = Duration(milliseconds: 2600);
  static const _scatterOffsets = <Offset>[
    Offset(-82, -10),
    Offset(-70, -50),
    Offset(-48, -82),
    Offset(-16, -100),
    Offset(20, -96),
    Offset(52, -76),
    Offset(76, -42),
    Offset(86, -5),
    Offset(62, 36),
  ];

  late final AnimationController _controller;
  bool _started = false;
  bool _landed = false;
  bool _finished = false;
  int _arrivedCoins = 0;
  Timer? _reducedMotionTimer;
  Timer? _absorbSoundTimer;
  Offset? _origin;
  Offset? _target;

  /// 一般登入獎勵 5～10 枚會依實際數量呈現與發聲；里程碑的 25～30 枚
  /// 壓縮成九枚，保留「很多錢」的密度但不連響三十次。
  int get _coinCount => widget.amount.clamp(1, _maxCoinCount).toInt();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _animationDuration)
      ..addListener(_onTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  bool get _reduceMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations == true || mq?.accessibleNavigation == true;
  }

  void _start() {
    if (!mounted || _started) return;
    _started = true;
    _resolveAnchors();
    if (_reduceMotion) {
      CoinService.presentationBalance.value = widget.targetBalance;
      _playLanding();
      _reducedMotionTimer = Timer(const Duration(milliseconds: 700), _finish);
      setState(() {});
      return;
    }
    // 第一枚幣冒出時就開始灑錢聲；以 0.68 倍速把原檔延長到約 1.47 秒，
    // 尾韻在第一枚入袋前收掉，保留「散出很多錢」的份量又不蓋住逐枚入袋。
    _absorbSoundTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted && !_finished) {
        unawaited(
          SfxService.instance.play(SfxCue.footprintCoinAbsorb, speed: 0.68),
        );
      }
    });
    _controller.forward();
  }

  void _resolveAnchors() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final mascotGlobal = RewardAnimationAnchors.globalPoint(
      RewardAnimationAnchorKind.mascot,
    );
    final coinGlobal = RewardAnimationAnchors.globalPoint(
      RewardAnimationAnchorKind.coinBalance,
    );
    final origin = mascotGlobal == null
        ? null
        : renderObject.globalToLocal(mascotGlobal);
    final target = coinGlobal == null
        ? null
        : renderObject.globalToLocal(coinGlobal);
    if (origin != _origin || target != _target) {
      setState(() {
        _origin = origin;
        _target = target;
      });
    }
  }

  double _coinLandAt(int index) {
    if (_coinCount == 1) return 0.86;
    return 0.70 + index * (0.24 / (_coinCount - 1));
  }

  void _onTick() {
    final arrived = List.generate(
      _coinCount,
      (index) => _controller.value >= _coinLandAt(index),
    ).where((value) => value).length;
    if (arrived > _arrivedCoins) {
      for (var index = _arrivedCoins; index < arrived; index++) {
        final progress = _coinCount == 1 ? 0.5 : index / (_coinCount - 1);
        unawaited(
          SfxService.instance.playPolyphonic(
            SfxCue.footprintCoinTick,
            volumeScale: 0.80 + progress * 0.14,
            pitch: 0.94 + progress * 0.14,
          ),
        );
      }
      _arrivedCoins = arrived;
    }
    final shown =
        widget.startBalance + (widget.amount * arrived / _coinCount).round();
    if (CoinService.presentationBalance.value != shown) {
      CoinService.presentationBalance.value = shown;
    }
    if (!_landed && arrived == _coinCount) _playLanding();
  }

  void _playLanding() {
    if (_landed) return;
    _landed = true;
    CoinService.presentationBalance.value = widget.targetBalance;
    CoinService.pulseRewardIcon();
    // 正常流程的最後一枚已在 _onTick 發聲，不再疊另一種結算音色。
    // 減少動態或點擊略過沒有逐枚落點時，至少保留一聲入袋提示。
    if (_arrivedCoins == 0) {
      unawaited(SfxService.instance.playPolyphonic(SfxCue.footprintCoinTick));
    }
    playHaptic(HapticLevel.light);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _reducedMotionTimer?.cancel();
    _absorbSoundTimer?.cancel();
    CoinService.presentationBalance.value = null;
    widget.onFinished();
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _absorbSoundTimer?.cancel();
    _controller
      ..removeListener(_onTick)
      ..dispose();
    if (!_finished) CoinService.presentationBalance.value = null;
    super.dispose();
  }

  void _skip() {
    _started = true;
    _absorbSoundTimer?.cancel();
    _controller.stop();
    unawaited(SfxService.instance.stop(SfxCue.footprintCoinAbsorb));
    _playLanding();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final origin = _origin ?? Offset(size.width * 0.5, size.height * 0.43);
    final target =
        _target ?? Offset(size.width - 134, safeTop + kToolbarHeight / 2);
    final labelTop = (origin.dy + 92).clamp(
      safeTop + kToolbarHeight + 24,
      size.height - 150,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                children: [
                  if (!_reduceMotion) ...[
                    _buildOriginGlow(origin),
                    for (var i = 0; i < _coinCount; i++)
                      _buildCoin(i, origin: origin, target: target),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: labelTop,
          child: Center(child: _buildRewardLabel()),
        ),
      ],
    );
  }

  Widget _buildRewardLabel() {
    final t = _reduceMotion ? 1.0 : _controller.value;
    final opacity = t < 0.12
        ? (t / 0.12).clamp(0.0, 1.0)
        : ((1 - t) / 0.10).clamp(0.0, 1.0);
    return Semantics(
      liveRegion: true,
      label: '今日獲得 ${widget.amount} 枚足跡幣',
      child: GestureDetector(
        onTap: _skip,
        child: Opacity(
          opacity: _reduceMotion ? 1 : opacity,
          child: Transform.scale(
            scale: _reduceMotion ? 1 : 0.92 + 0.08 * opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFF0C75E)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9A641B).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                child: Text(
                  '今日足跡幣 +${widget.amount}',
                  style: AppType.digits(
                    color: const Color(0xFF7A4A17),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOriginGlow(Offset origin) {
    final t = _controller.value;
    final emerge = const Interval(
      0,
      0.15,
      curve: Curves.easeOutBack,
    ).transform(t);
    final fade =
        1 - const Interval(0.20, 0.46, curve: Curves.easeOut).transform(t);
    const glowSize = 104.0;
    return Positioned(
      key: const ValueKey('footprint-coin-origin-glow'),
      left: origin.dx - glowSize / 2,
      top: origin.dy - glowSize / 2,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.35 + emerge * 0.65,
          child: SizedBox.square(
            dimension: glowSize,
            child: CustomPaint(painter: _RewardOriginGlowPainter(progress: t)),
          ),
        ),
      ),
    );
  }

  Widget _buildCoin(
    int index, {
    required Offset origin,
    required Offset target,
  }) {
    final startAt = 0.055 + index * 0.015;
    final scatterEnd = 0.28 + index * 0.007;
    final gatherStart = 0.43 + index * 0.008;
    final landAt = _coinLandAt(index);
    final scatter = Interval(
      startAt,
      scatterEnd,
      curve: Curves.easeOutCubic,
    ).transform(_controller.value);
    final gather = Interval(
      gatherStart,
      landAt,
      curve: Curves.easeInOutCubic,
    ).transform(_controller.value);
    final scatterPoint = origin + _scatterOffsetAt(index);
    final control = Offset(
      scatterPoint.dx + (target.dx - scatterPoint.dx) * (0.30 + index * 0.025),
      math.min(scatterPoint.dy, target.dy) - 34 - index * 3,
    );
    final point = _controller.value <= scatterEnd
        ? Offset.lerp(origin, scatterPoint, scatter)!
        : _quadraticPoint(scatterPoint, control, target, gather);
    final appear = Interval(
      startAt,
      startAt + 0.045,
      curve: Curves.easeOut,
    ).transform(_controller.value);
    final disappear = Interval(
      landAt - 0.045,
      landAt,
      curve: Curves.easeIn,
    ).transform(_controller.value);
    final opacity = (appear * (1 - disappear)).clamp(0.0, 1.0);
    final coinSize = 24.0 + (index % 3) * 3;
    return Positioned(
      key: ValueKey('footprint-coin-$index'),
      left: point.dx - coinSize / 2,
      top: point.dy - coinSize / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle:
              (index.isEven ? 1 : -1) *
              (scatter * 0.45 + gather * 1.15) *
              math.pi,
          child: Transform.scale(
            scale: 0.58 + appear * 0.42 - disappear * 0.28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD66B).withValues(alpha: 0.42),
                    blurRadius: 9,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/icon/ui/paw_footprint_coin_round.png',
                width: coinSize,
                height: coinSize,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _scatterOffsetAt(int index) {
    if (_coinCount == 1) return _scatterOffsets[4];
    final mapped = (index * (_scatterOffsets.length - 1) / (_coinCount - 1))
        .round();
    return _scatterOffsets[mapped];
  }

  Offset _quadraticPoint(Offset start, Offset control, Offset end, double t) {
    final oneMinus = 1 - t;
    return Offset(
      oneMinus * oneMinus * start.dx +
          2 * oneMinus * t * control.dx +
          t * t * end.dx,
      oneMinus * oneMinus * start.dy +
          2 * oneMinus * t * control.dy +
          t * t * end.dy,
    );
  }
}

class _RewardOriginGlowPainter extends CustomPainter {
  const _RewardOriginGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Offset.zero & size;
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xE6FFF8D9), Color(0x99FFD05A), Color(0x00F2A51D)],
        stops: [0, 0.38, 1],
      ).createShader(rect);
    canvas.drawCircle(center, size.shortestSide * 0.48, glow);

    final ringProgress = Curves.easeOut.transform(
      (progress / 0.32).clamp(0.0, 1.0),
    );
    final ring = Paint()
      ..color = const Color(
        0xFFFFCC4D,
      ).withValues(alpha: (1 - ringProgress) * 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, 12 + 34 * ringProgress, ring);

    final sparkle = Paint()
      ..color = const Color(0xFFFFE59A).withValues(alpha: 0.90)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + progress * 0.7;
      final inner = 29.0 + (i.isEven ? 3 : 0);
      final outer = inner + 6.0 + (i % 3) * 2;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        sparkle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RewardOriginGlowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
