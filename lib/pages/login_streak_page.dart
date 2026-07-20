// 每日登入慶祝頁：兔咪在「足跡報到卡」上蓋章報到。
//
// 敘事＝蓋章打卡（足跡幣本來就是腳印，蓋腳印章是這個 app 自己的隱喻）：
// 「連續第 N 天」以全螢幕大墨印重擊畫面中央 → 定住半拍
// → 縮小飛回報到卡上方落款，同時兔咪浮現、報到卡滑入
// → 木柄印章懸停在今日格上方 → 「啪」蓋下（震動＋漣漪＋金腳印現身；
//   里程碑日兔咪歡呼＋整卡發光）→ 印章抬離
// → 台詞與 CTA 亮起。點畫面任意處可一次亮完（不強迫等演出）。
//
// 誰來開這一頁：MainPage 的 _claimDailyLoginReward 領到獎勵後 push；
// pop 之後才輪到金幣飛行吸入 AppBar（幣從本頁 CTA 的位置爆出，接得上）。
// 開發者頁的「預覽」直接 push、不動任何狀態。
//
// 兔咪圖暫用歡呼姿 tumi_streak.png；「兔咪拿印章」差分生好後換 _mascotAsset，
// 印章道具屆時可改與角色合體。光芒/光塵/印章/墨印全在 Flutter 端畫
//（CG 只畫純角色，特效重用）。

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
// 印章道具：木柄＋深棕章座＋沾金印泥（插畫慣例的簡潔向量質感）。
const _kStampWoodLight = Color(0xFFC89158);
const _kStampWoodDark = Color(0xFF96652F);
const _kStampBaseTop = Color(0xFF8A5A2B);
const _kStampBaseBottom = Color(0xFF6E4A1F);
const _kStampInkGold = Color(0xFFD79A2F);
// 報到卡空格：虛線圈（等著被蓋滿）。
const _kSlotDash = Color(0xFFD9BE93);
const _kSlotEmptyFill = Color(0xFFF9F0DD);

class _LoginStreakPageState extends State<LoginStreakPage>
    with SingleTickerProviderStateMixin {
  static const _mascotAsset = 'assets/mascot/core/tumi_streak.png';
  static const _coinAsset = 'assets/icon/ui/paw_footprint_coin.png';

  // 光芒旋轉／光塵／懸停呼吸共用的環境時鐘（0→1 循環）。
  late final AnimationController _ambient;

  // 演出階段：0 無 → 1 大墨印重擊 → 2 墨印縮小落款＋兔咪＋報到卡
  // → 3 印章懸停 → 4 印章壓下 → 5 印章抬離 → 6 演出定位 → 7 全亮。
  int _step = 0;

  // 大墨印飛行參數：post-frame 量出落款定位點 → 畫面中央的位移與倍率。
  // 量測時矩陣的平移為零、縮放/旋轉都以中心為軸，中心點不受影響。
  final GlobalKey _sealKey = GlobalKey();
  Offset _sealShift = Offset.zero;
  double _sealBigScale = 2.0;

  // 印章接觸瞬間（壓下後約 150ms）：腳印現身／漣漪／音效震動以此為準。
  bool _impact = false;
  bool _impactPlayed = false;
  final List<Timer> _timers = [];

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSealFlight());
  }

  /// 量出墨印落款的畫面位置，換算重擊階段的位移與放大倍率。
  void _measureSealFlight() {
    if (!mounted) return;
    final box = _sealKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final sealCenter = box.localToGlobal(box.size.center(Offset.zero));
    final size = MediaQuery.sizeOf(context);
    setState(() {
      // 重擊落點在偏上的視覺中心（兔咪胸前），不是幾何正中央。
      _sealShift = Offset(size.width / 2, size.height * 0.40) - sealCenter;
      _sealBigScale = ((size.width * 0.94) / box.size.width).clamp(1.5, 2.4);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion && _step < 7) {
      _cancelTimers();
      _ambient.stop();
      _step = 7;
      _impact = true;
      _impactPlayed = true; // 靜態呈現：不補蓋章音效
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
    const steps = [150, 880, 1320, 1740, 2180, 2480, 2880];
    for (var i = 0; i < steps.length; i++) {
      _timers.add(
        Timer(Duration(milliseconds: steps[i]), () {
          if (!mounted) return;
          setState(() => _step = i + 1);
          // 大墨印第一拍重擊畫面，先給一下輕震；
          // 之後印章真正接觸卡面時再由 _markImpact 給中震。
          if (i + 1 == 1) playHaptic(HapticLevel.light);
        }),
      );
    }
    // 壓下動畫約 150ms 後底面接觸卡面＝真正的「啪」。
    _timers.add(
      Timer(const Duration(milliseconds: 1890), () {
        if (mounted) setState(_markImpact);
      }),
    );
  }

  void _markImpact() {
    _impact = true;
    if (_impactPlayed) return;
    _impactPlayed = true;
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
    // 里程碑日是大事件：疊兔咪歡呼。
    if (_isMilestoneDay) playFeedback(SfxCue.tumiCheer);
  }

  /// 點畫面任意處：一次亮完，不強迫等演出。
  void _fastForward() {
    if (_step >= 7) return;
    _cancelTimers();
    setState(() {
      _step = 7;
      _markImpact();
    });
    playHaptic(HapticLevel.selection);
  }

  void _dismiss() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.light);
    Navigator.of(context).pop();
  }

  String get _caption {
    final r = widget.reward;
    if (r.graceUsed) return '昨天休息了一天，連續天數還留著。';
    if (_isMilestoneDay) {
      return '一起走到第 ${widget.streak} 天了，我有點感動。';
    }
    if (widget.streak <= 1) {
      // 等級 >1 但天數歸 1 ＝中斷後回歸的老朋友；不提中斷、不帶罪惡感
      //（兔咪語氣：不是評分，是看見）。等級被扣到 1 的舊識認不出來，
      // 會拿到新朋友台詞，可接受。
      if (r.level > 1) return '歡迎回來。今天再一起慢慢開始。';
      return '第一天。以後也一起慢慢來。';
    }
    if (r.level >= CoinConfig.loginMaxLevel) return '你一直有回來，我都有記得。';
    return '你今天也來了，我有看到。';
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
                    _buildStreakSeal(compact),
                    SizedBox(height: compact ? 10 : 16),
                    _buildStampCard(compact),
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
    final shown = _step >= 2;
    return AnimatedScale(
      scale: shown ? 1 : 0.82,
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        key: const ValueKey('login-streak-mascot'),
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

  /// 重擊／飛行階段的墨印矩陣：位移到畫面視覺中心＋額外傾斜＋放大。
  /// transformAlignment 是中心，縮放旋轉都繞著自身中心轉。
  Matrix4 _sealBigMatrix(double extraScale) {
    final s = _sealBigScale * extraScale;
    return Matrix4.translationValues(_sealShift.dx, _sealShift.dy, 0)
      ..rotateZ(-0.045)
      ..multiply(Matrix4.diagonal3Values(s, s, 1));
  }

  /// 「連續第 N 天」墨印落款：像蓋在紙上的橡皮章（微傾斜、粗框）。
  /// 先以全螢幕大墨印重擊畫面中央（現身時由更大壓到定格＝
  /// 印下來的力道），定住半拍再縮小飛回這裡落款。版面位置從頭到尾
  /// 佔著不動，重擊/飛行全靠 transform，不推擠其他元素。
  Widget _buildStreakSeal(bool compact) {
    final shown = _step >= 1;
    final landed = _step >= 2 || _reduceMotion;
    final matrix = landed
        ? Matrix4.identity()
        : _sealBigMatrix(shown ? 1 : 1.18);
    return Semantics(
      label: '連續登入 ${widget.streak} 天，今日足跡幣 +${widget.reward.totalAmount}',
      child: AnimatedOpacity(
        key: const ValueKey('login-streak-seal'),
        opacity: shown ? 1 : 0,
        // 重擊現身要快（力道）；快轉直達落款時稍緩。
        duration: Duration(milliseconds: shown && !landed ? 140 : 220),
        child: AnimatedContainer(
          duration: Duration(milliseconds: landed ? 460 : 190),
          curve: landed ? Curves.easeInOutCubic : Curves.easeOutCubic,
          transform: matrix,
          transformAlignment: Alignment.center,
          child: Transform.rotate(
            angle: -0.05,
            child: Container(
              key: _sealKey,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kNumberInk.withValues(alpha: 0.78),
                  width: 2.4,
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '連續第 '),
                    TextSpan(
                      text: '${widget.streak}',
                      style: AppType.digits(
                        fontSize: compact ? 26 : 31,
                        fontWeight: FontWeight.w800,
                        color: _kNumberInk,
                      ),
                    ),
                    const TextSpan(text: ' 天'),
                  ],
                ),
                style: TextStyle(
                  color: _kNumberInk,
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStampCard(bool compact) {
    final shown = _step >= 2;
    final milestone = CoinConfig.loginStreakMilestone;
    final round = (widget.streak - 1) ~/ milestone + 1;
    return AnimatedOpacity(
      key: const ValueKey('login-streak-card'),
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.14),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: _impactDip(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              14,
              compact ? 8 : 11,
              14,
              compact ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kRayGold.withValues(alpha: 0.55)),
              boxShadow: [
                ...AppShadows.card,
                // 里程碑日蓋滿整卡：暖金光暈慶祝。
                if (_impact && _isMilestoneDay)
                  BoxShadow(
                    color: _kSlotGold.withValues(alpha: 0.45),
                    blurRadius: 26,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '報到卡',
                      style: TextStyle(
                        color: _kDeepGold,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    // 走到第二輪以後亮出輪數：老朋友的小勳章。
                    if (round >= 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _kRayGold.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          '第 $round 輪',
                          style: AppType.digits(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _kDeepGold,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 7 : 9),
                // 旁白唸整體進度就好，格子裡的日數字/圖示不逐一唸。
                Semantics(
                  label: '本輪已報到 $_cycleDay 天，滿 $milestone 天有加碼',
                  child: ExcludeSemantics(
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 蓋章瞬間整張卡往下沉一點再回彈：印章真的壓在紙上。
  Widget _impactDip({required Widget child}) {
    if (!_impact || _reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      builder: (_, t, c) => Transform.translate(
        offset: Offset(0, 3.2 * math.sin(t * math.pi)),
        child: c,
      ),
      child: child,
    );
  }

  Widget _buildDaySlot(int day, bool compact) {
    final milestone = CoinConfig.loginStreakMilestone;
    final isToday = day == _cycleDay;
    // 今日格等印章接觸才蓋上；之前的日子跟卡片一起亮相。
    final stamped = isToday ? _impact : day < _cycleDay;
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
        SizedBox(
          width: slotSize,
          height: slotSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (!stamped) ...[
                CustomPaint(
                  size: Size.square(slotSize),
                  painter: const _DashedSlotPainter(),
                ),
                if (isGift)
                  Icon(
                    Icons.card_giftcard_rounded,
                    size: slotSize * 0.52,
                    color: const Color(0xFFC99B4C),
                  ),
              ] else if (isToday) ...[
                _buildMintedCoin(slotSize),
                if (!_reduceMotion) ...[
                  _buildStampRipple(slotSize),
                  _buildSpeckBurst(slotSize),
                ],
              ] else
                Image.asset(_coinAsset, width: slotSize, height: slotSize),
              if (isToday) _buildStamp(slotSize),
            ],
          ),
        ),
        // 里程碑加碼徽章：佔位固定高度，出現時不推擠版面。
        // 非里程碑日不建這個 Text（scale 0 藏起來仍會漏進 semantics）。
        SizedBox(
          height: 16,
          child: isGift && _isMilestoneDay
              ? AnimatedScale(
                  scale: _impact ? 1 : 0,
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

  /// 今日的金腳印：從印章底下「鑄」出來——由大縮小帶一點旋轉落定。
  Widget _buildMintedCoin(double slotSize) {
    final coin = Image.asset(_coinAsset, width: slotSize, height: slotSize);
    if (_reduceMotion) return coin;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: -0.16 * (1 - t),
          child: Transform.scale(scale: 1.45 - 0.45 * t, child: child),
        ),
      ),
      child: coin,
    );
  }

  Widget _buildStampRipple(double slotSize) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => Opacity(
          opacity: (1 - t) * 0.55,
          child: Container(
            width: slotSize * (0.9 + 1.1 * t),
            height: slotSize * (0.9 + 1.1 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _kSlotGold, width: 2.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeckBurst(double slotSize) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => CustomPaint(
          size: Size.square(slotSize * 2.4),
          painter: _SpeckBurstPainter(t: t, slotSize: slotSize),
        ),
      ),
    );
  }

  /// 木柄印章：懸停（呼吸浮動）→ 壓下 → 抬離淡出。只掛在今日格上，
  /// 位置全部相對格子算，不用量全域座標。
  Widget _buildStamp(double slotSize) {
    if (_reduceMotion || _step >= 6) return const SizedBox.shrink();
    final stampW = slotSize * 1.5;
    final stampH = slotSize * 1.7;
    final visible = _step >= 3 && _step < 5;
    final pressing = _step >= 4 && _step < 5;
    // 懸停：底面離格子一小段距離；壓下：底面貼住格子；抬離：拉高飛走。
    final top = _step >= 5
        ? -stampH - slotSize * 1.4
        : pressing
        ? -stampH + slotSize * 0.55
        : -stampH - slotSize * 0.65;
    return AnimatedPositioned(
      // 壓下要快（重量感）、抬離與懸停就位走緩出。
      duration: Duration(
        milliseconds: pressing ? 150 : (_step >= 5 ? 380 : 420),
      ),
      curve: pressing ? Curves.easeInCubic : Curves.easeOutCubic,
      top: top,
      left: (slotSize - stampW) / 2,
      child: IgnorePointer(
        child: AnimatedOpacity(
          key: const ValueKey('login-streak-stamp'),
          opacity: visible ? 1 : 0,
          duration: Duration(milliseconds: _step >= 5 ? 300 : 260),
          child: AnimatedBuilder(
            animation: _ambient,
            builder: (_, child) {
              // 懸停時輕輕呼吸（醞釀）；壓下瞬間定住。
              final bob = pressing || _step < 3
                  ? 0.0
                  : 3 * math.sin(_ambient.value * 2 * math.pi * 12);
              return Transform.translate(offset: Offset(0, bob), child: child);
            },
            child: AnimatedRotation(
              turns: pressing ? 0 : (_step >= 5 ? 0.01 : -0.016),
              duration: const Duration(milliseconds: 180),
              child: _squashOnImpact(
                child: CustomPaint(
                  size: Size(stampW, stampH),
                  painter: const _StampPainter(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 接觸瞬間的擠壓（縮 Y 再回彈）：橡皮章的彈性。
  Widget _squashOnImpact({required Widget child}) {
    if (!_impact) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (_, t, c) => Transform.scale(
        scaleY: 1 - 0.10 * math.sin(t * math.pi),
        alignment: Alignment.bottomCenter,
        child: c,
      ),
      child: child,
    );
  }

  Widget _buildCaption() {
    final shown = _step >= 7;
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
    final shown = _step >= 7;
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

/// 報到卡空格：虛線圓圈＋淡奶油底，等著被蓋滿。
class _DashedSlotPainter extends CustomPainter {
  const _DashedSlotPainter();

  static const _dashes = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    canvas.drawCircle(center, radius, Paint()..color = _kSlotEmptyFill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = _kSlotDash;
    const span = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * span,
        span * 0.55,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedSlotPainter old) => false;
}

/// 蓋章瞬間向四周迸出的小金屑（一次性，跟漣漪一起收掉）。
class _SpeckBurstPainter extends CustomPainter {
  final double t; // 0→1 一次性
  final double slotSize;

  const _SpeckBurstPainter({required this.t, required this.slotSize});

  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < _count; i++) {
      final angle = i * 2 * math.pi / _count + (i.isEven ? 0.22 : -0.12);
      final travel = slotSize * (0.5 + 0.85 * t);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * travel;
      final radius = (1 - t) * 2.4 + 0.5;
      final paint = Paint()
        ..color = Color.lerp(
          _kSlotGold,
          const Color(0xFFFFE9C8),
          i / _count,
        )!.withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeckBurstPainter old) => old.t != t;
}

/// 木柄印章道具：圓柄＋護環＋深棕章座＋沾金印泥底緣。
/// 純向量簡潔質感；之後若有「兔咪拿印章」CG 可整組替換。
class _StampPainter extends CustomPainter {
  const _StampPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 章座（底部胖圓角塊）
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.06, h * 0.66, w * 0.94, h * 0.95),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(
      baseRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kStampBaseTop, _kStampBaseBottom],
        ).createShader(baseRect.outerRect),
    );

    // 沾了金印泥的底緣
    final inkRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.10, h * 0.90, w * 0.90, h * 0.99),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(inkRect, Paint()..color = _kStampInkGold);

    // 木柄（直立圓柱）
    final handleRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.40, h * 0.04, w * 0.60, h * 0.62),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(
      handleRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [_kStampWoodLight, _kStampWoodDark],
        ).createShader(handleRect.outerRect),
    );

    // 柄座護環
    final collarRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.30, h * 0.58, w * 0.70, h * 0.68),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(collarRect, Paint()..color = _kStampWoodDark);

    // 柄上一道高光，立體感
    canvas.drawLine(
      Offset(w * 0.445, h * 0.10),
      Offset(w * 0.445, h * 0.54),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StampPainter old) => false;
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
