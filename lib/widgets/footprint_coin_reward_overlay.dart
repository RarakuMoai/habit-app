import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import '../utils/sfx_service.dart';

/// 每日登入足跡幣演出：幣從畫面中段散開，再沿弧線吸入 AppBar 餘額。
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
  static const _coinCount = 7;
  late final AnimationController _controller;
  bool _started = false;
  bool _landed = false;
  bool _finished = false;
  Timer? _reducedMotionTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addListener(_onTick);
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
    if (_reduceMotion) {
      CoinService.presentationBalance.value = widget.targetBalance;
      _playLanding();
      _reducedMotionTimer = Timer(const Duration(milliseconds: 700), _finish);
      setState(() {});
      return;
    }
    unawaited(SfxService.instance.play(SfxCue.footprintCoinAbsorb));
    _controller.forward();
  }

  void _onTick() {
    final progress = const Interval(
      0.20,
      0.82,
      curve: Curves.easeInOutCubic,
    ).transform(_controller.value);
    final shown = widget.startBalance + (widget.amount * progress).round();
    if (CoinService.presentationBalance.value != shown) {
      CoinService.presentationBalance.value = shown;
    }
    if (!_landed && _controller.value >= 0.82) _playLanding();
  }

  void _playLanding() {
    if (_landed) return;
    _landed = true;
    CoinService.presentationBalance.value = widget.targetBalance;
    CoinService.pulseRewardIcon();
    unawaited(SfxService.instance.play(SfxCue.footprintCoinLandSoft));
    playHaptic(HapticLevel.light);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _reducedMotionTimer?.cancel();
    CoinService.presentationBalance.value = null;
    widget.onFinished();
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller
      ..removeListener(_onTick)
      ..dispose();
    if (!_finished) CoinService.presentationBalance.value = null;
    super.dispose();
  }

  void _skip() {
    _started = true;
    _controller.stop();
    _playLanding();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                children: [
                  if (!_reduceMotion)
                    for (var i = 0; i < _coinCount; i++) _buildCoin(context, i),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.sizeOf(context).height * 0.43,
          child: Center(child: _buildRewardLabel()),
        ),
      ],
    );
  }

  Widget _buildRewardLabel() {
    final t = _reduceMotion ? 1.0 : _controller.value;
    final opacity = t < 0.12
        ? (t / 0.12).clamp(0.0, 1.0)
        : ((1 - t) / 0.18).clamp(0.0, 1.0);
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

  Widget _buildCoin(BuildContext context, int index) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final startAt = 0.08 + index * 0.035;
    final endAt = startAt + 0.52;
    final flight = Interval(
      startAt,
      endAt,
      curve: Curves.easeInCubic,
    ).transform(_controller.value);
    final start = Offset(
      size.width * (0.19 + index * 0.103),
      size.height * (0.53 + (index.isEven ? -0.035 : 0.035)),
    );
    final target = Offset(size.width - 134, safeTop + kToolbarHeight / 2);
    final control = Offset(
      start.dx + (target.dx - start.dx) * (0.35 + index * 0.025),
      math.min(start.dy, target.dy) - 70 - index * 7,
    );
    final oneMinus = 1 - flight;
    final point = Offset(
      oneMinus * oneMinus * start.dx +
          2 * oneMinus * flight * control.dx +
          flight * flight * target.dx,
      oneMinus * oneMinus * start.dy +
          2 * oneMinus * flight * control.dy +
          flight * flight * target.dy,
    );
    final opacity = flight >= 0.96
        ? ((1 - flight) / 0.04).clamp(0.0, 1.0)
        : (flight / 0.08).clamp(0.0, 1.0);
    final coinSize = 24.0 + (index % 3) * 3;
    return Positioned(
      left: point.dx - coinSize / 2,
      top: point.dy - coinSize / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: (index.isEven ? 1 : -1) * flight * math.pi * 1.4,
          child: Transform.scale(
            scale: 0.78 + 0.22 * math.sin(flight * math.pi),
            child: Image.asset(
              'assets/icon/ui/paw_footprint_coin_round.png',
              width: coinSize,
              height: coinSize,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
