// 每日登入慶祝頁：兔咪站上暖金放射光舞台，報告連續登入天數。
//
// 呈現節奏：光芒舞台淡入 → 兔咪浮現 → 大數字彈出 → 7 天進度格逐格亮
// → 今日格打勾（里程碑日兔咪歡呼＋禮物格 +20）→ 台詞與 CTA 亮起。
// 點畫面任意處可一次亮完（不強迫等演出）。
//
// 誰來開這一頁：MainPage 的 _claimDailyLoginReward 領到獎勵後 push；
// pop 之後才輪到金幣飛行吸入 AppBar（幣從本頁 CTA 的位置爆出，接得上）。
// 開發者頁的「預覽」直接 push、不動任何狀態。
//
// 兔咪圖暫用歡呼姿 tumi_streak.png；「抱大足跡幣」差分生好後換 _mascotAsset。
// 光芒/光塵全在 Flutter 端畫（CG 只畫純角色，特效重用）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/sfx_service.dart';

class LoginStreakPage extends StatefulWidget {
  /// 領取後的連續登入天數（coinLoginStreak）。
  final int streak;
  final LoginReward reward;

  const LoginStreakPage({
    super.key,
    required this.streak,
    required this.reward,
  });

  /// 全螢幕淡入路線（同揭曉頁：像燈光慢慢亮起，不用平台推頁動畫）。
  static Route<void> route({required int streak, required LoginReward reward}) {
    return PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => LoginStreakPage(streak: streak, reward: reward),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  State<LoginStreakPage> createState() => _LoginStreakPageState();
}

// 舞台色票：足跡幣的暖金家族（同 footprint overlay 的金框/棕影）。
const _kStageBase = Color(0xFFFFF7E8);
const _kRayGold = Color(0xFFF5C96B);
const _kDeepGold = Color(0xFF9A641B);
const _kNumberInk = Color(0xFF7A4A17);
const _kSlotGold = Color(0xFFEDAD3F);
const _kCtaGold = Color(0xFFEFB44F);
const _kCtaInk = Color(0xFF4A3312);

class _LoginStreakPageState extends State<LoginStreakPage>
    with SingleTickerProviderStateMixin {
  static const _mascotAsset = 'assets/mascot/core/tumi_streak.png';

  // 光芒旋轉／光塵／提示呼吸共用的環境時鐘（0→1 循環）。
  late final AnimationController _ambient;

  // 演出階段：0 無 → 1 兔咪 → 2 數字 → 3 進度卡 → 4 今日格打勾 → 5 全亮。
  int _step = 0;
  final List<Timer> _timers = [];
  bool _todayCheckPlayed = false;

  bool get _isMilestoneDay => widget.reward.milestoneAmount > 0;

  /// 進度格語義走「里程碑 7 天循環」而非日曆週：第 7 格是 +20 禮物格，
  /// 亮格數與實際發幣完全一致（同 review_page 的 cycle 計算）。
  int get _cycleDay {
    if (widget.streak <= 0) return 0;
    final m = CoinConfig.loginStreakMilestone;
    final d = widget.streak % m;
    return d == 0 ? m : d;
  }

  bool get _reduceMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations == true || mq?.accessibleNavigation == true;
  }

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    playFeedback(SfxCue.unlock, haptic: HapticLevel.light);
    _startShow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion && _step < 5) {
      _cancelTimers();
      _ambient.stop();
      _step = 5;
      _todayCheckPlayed = true; // 靜態呈現：不補打勾音效
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    _ambient.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _startShow() {
    const steps = [120, 480, 820, 1120, 1420];
    for (var i = 0; i < steps.length; i++) {
      _timers.add(
        Timer(Duration(milliseconds: steps[i]), () {
          if (mounted) setState(() => _advanceTo(i + 1));
        }),
      );
    }
  }

  void _advanceTo(int step) {
    _step = step;
    if (step >= 4 && !_todayCheckPlayed) {
      _todayCheckPlayed = true;
      playFeedback(SfxCue.success, haptic: HapticLevel.light);
      // 里程碑日是大事件：疊兔咪歡呼。
      if (_isMilestoneDay) playFeedback(SfxCue.tumiCheer);
    }
  }

  /// 點畫面任意處：一次亮完，不強迫等演出。
  void _fastForward() {
    if (_step >= 5) return;
    _cancelTimers();
    setState(() => _advanceTo(5));
    playHaptic(HapticLevel.selection);
  }

  void _dismiss() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.light);
    Navigator.of(context).pop();
  }

  String get _caption {
    final r = widget.reward;
    if (r.graceUsed) return '昨天兔咪幫你看家，天數守住了。';
    if (_isMilestoneDay) {
      return '一起走到第 ${widget.streak} 天了，兔咪有點感動。';
    }
    if (widget.streak <= 1) return '第一天。兔咪會陪著你，慢慢來。';
    if (r.level >= CoinConfig.loginMaxLevel) return '你一直有回來，兔咪都記得。';
    return '你今天也來了，兔咪有看到。';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 640;
    return Scaffold(
      backgroundColor: _kStageBase,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _fastForward,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 放射光舞台＋金色光塵（緩慢旋轉/上飄；減少動態時停在定格）。
            AnimatedBuilder(
              animation: _ambient,
              builder: (_, _) => CustomPaint(
                painter: _SunburstPainter(
                  t: _reduceMotion ? 0 : _ambient.value,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _ambient,
              builder: (_, _) => CustomPaint(
                painter: _GoldMotesPainter(
                  t: _reduceMotion ? 0.35 : _ambient.value,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, compact ? 6 : 14, 24, 16),
                child: Column(
                  children: [
                    Expanded(child: _buildMascot(compact)),
                    _buildStreakNumber(compact),
                    SizedBox(height: compact ? 12 : 20),
                    _buildCycleCard(compact),
                    SizedBox(height: compact ? 10 : 16),
                    _buildCaption(),
                    SizedBox(height: compact ? 10 : 16),
                    _buildCta(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMascot(bool compact) {
    final shown = _step >= 1;
    return AnimatedScale(
      scale: shown ? 1 : 0.82,
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: const Duration(milliseconds: 520),
        child: AnimatedBuilder(
          animation: _ambient,
          builder: (_, child) {
            // 待機輕飄（約 2.4 秒一輪）；減少動態時定住。
            final bob = _reduceMotion
                ? 0.0
                : 4 * math.sin(_ambient.value * 2 * math.pi * 10);
            return Transform.translate(offset: Offset(0, bob), child: child);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 兔咪身後的暖光暈，把角色從光芒中托出來。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xB3FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
                child: SizedBox.expand(),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 4 : 10),
                child: Image.asset(
                  _mascotAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakNumber(bool compact) {
    final shown = _step >= 2;
    return Semantics(
      label: '連續登入 ${widget.streak} 天，今日足跡幣 +${widget.reward.totalAmount}',
      child: AnimatedScale(
        scale: shown ? 1 : 0.55,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 380),
          child: Column(
            children: [
              Text(
                '${widget.streak}',
                style: AppType.digits(
                  fontSize: compact ? 62 : 78,
                  fontWeight: FontWeight.w800,
                  color: _kNumberInk,
                ).copyWith(
                  shadows: const [
                    Shadow(color: Colors.white, blurRadius: 18),
                    Shadow(
                      color: Color(0x338B5D3C),
                      blurRadius: 2,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Text(
                '天連續報到',
                style: TextStyle(
                  color: _kDeepGold.withValues(alpha: 0.92),
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCycleCard(bool compact) {
    final shown = _step >= 3;
    final milestone = CoinConfig.loginStreakMilestone;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.12),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kRayGold.withValues(alpha: 0.55)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              for (var day = 1; day <= milestone; day++) ...[
                if (day > 1) const SizedBox(width: 6),
                Expanded(child: _buildDaySlot(day, compact)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaySlot(int day, bool compact) {
    final milestone = CoinConfig.loginStreakMilestone;
    final isToday = day == _cycleDay;
    final filled = isToday ? _step >= 4 : day < _cycleDay;
    final isGift = day == milestone;
    final slotSize = compact ? 30.0 : 36.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$day',
          style: AppType.digits(
            fontWeight: FontWeight.w800,
            color: isToday ? _kDeepGold : AppInk.faint,
          ),
        ),
        const SizedBox(height: 5),
        AnimatedScale(
          // 今日格用彈跳感打勾；其他格跟卡片一起出現不再彈。
          scale: isToday && !filled ? 0.4 : 1,
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          child: Container(
            width: slotSize,
            height: slotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: filled
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF6C75E), _kSlotGold],
                    )
                  : null,
              color: filled ? null : const Color(0xFFF3E9D8),
              border: isToday && filled
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: _kDeepGold.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isGift && !filled
                  ? Icons.card_giftcard_rounded
                  : filled
                  ? Icons.check_rounded
                  : null,
              size: slotSize * 0.58,
              color: filled ? Colors.white : const Color(0xFFC99B4C),
            ),
          ),
        ),
        // 里程碑加碼徽章：佔位固定高度，出現時不推擠版面。
        SizedBox(
          height: 16,
          child: isGift
              ? AnimatedScale(
                  scale: _isMilestoneDay && _step >= 4 ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: Text(
                    '+${widget.reward.milestoneAmount}',
                    style: AppType.digits(
                      fontWeight: FontWeight.w800,
                      color: _kDeepGold,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildCaption() {
    final shown = _step >= 5;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 460),
      child: Column(
        children: [
          Text(
            _caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppInk.soft,
              fontSize: 14.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // 與金幣飛行時的入帳膠囊同款式，pop 後演出接得上。
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFF0C75E)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Text(
                '今日足跡幣 +${widget.reward.totalAmount}',
                style: AppType.digits(
                  color: _kNumberInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCta() {
    final shown = _step >= 5;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 460),
      child: IgnorePointer(
        ignoring: !shown,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kCtaGold,
              foregroundColor: _kCtaInk,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            onPressed: _dismiss,
            child: const Text('開始吧'),
          ),
        ),
      ),
    );
  }
}

/// 放射光舞台：以兔咪身後為圓心的暖金光芒緩慢旋轉，
/// 亮度由圓心向外淡出（radial shader），像聚光燈灑在舞台上。
class _SunburstPainter extends CustomPainter {
  final double t; // 0→1 循環

  const _SunburstPainter({required this.t});

  static const _rays = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.32);
    final radius = size.longestSide * 1.1;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          _kRayGold.withValues(alpha: 0.30),
          _kRayGold.withValues(alpha: 0.05),
          _kRayGold.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 0.9],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final rotation = t * 2 * math.pi / _rays; // 一輪剛好轉過一格，接縫無感
    const span = 2 * math.pi / _rays;
    for (var i = 0; i < _rays; i++) {
      final start = rotation + i * span;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          start,
          span * 0.5, // 亮暗各半的光芒條
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter old) => old.t != t;
}

/// 金色光塵：緩慢上飄＋呼吸閃爍（同揭曉頁作法，換暖金色票）。
class _GoldMotesPainter extends CustomPainter {
  final double t; // 0→1 循環

  const _GoldMotesPainter({required this.t});

  static const _count = 14;

  double _rand(int i, int salt) {
    final v = math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _count; i++) {
      final baseX = _rand(i, 1);
      final baseY = _rand(i, 2);
      final speed = 0.35 + 0.5 * _rand(i, 3);
      final radius = 1.6 + 2.6 * _rand(i, 4);
      final phase = _rand(i, 5) * 2 * math.pi;
      final sway = 0.012 * math.sin(t * 2 * math.pi * 2 + phase);

      final y = (baseY - t * speed) % 1.0;
      final x = (baseX + sway) % 1.0;
      final twinkle =
          0.5 + 0.5 * math.sin(t * 2 * math.pi * (6 + 4 * _rand(i, 6)) + phase);
      final edgeFade = math.min(1.0, math.min(y, 1 - y) * 6).clamp(0.0, 1.0);
      final alpha = (0.10 + 0.24 * twinkle) * edgeFade;

      final paint = Paint()
        ..color = Color.lerp(
          _kSlotGold,
          const Color(0xFFFFE9C8),
          0.35 + 0.5 * _rand(i, 7),
        )!.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.9);
      canvas.drawCircle(Offset(x * size.width, y * size.height), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldMotesPainter old) => old.t != t;
}
