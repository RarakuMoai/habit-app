// 兔咪檔案頁 + 設定頁頂部的「兔咪名片」。
//
// 名片（[MascotCallingCard]）放在設定頁最上方：暖金證件卡質感、圓框臉部
// 特寫、名字＋相識天數＋足跡幣。點進來是本頁——隨時可翻看的夥伴檔案，
// 把足跡元素（報到卡本輪進度、連續天數、足跡幣、回憶本）整合成靜態總覽。
//
// 與 login_streak_page（領獎慶祝演出）刻意分開：那頁的語境是「今天報到、
// 發幣、蓋章」，本頁是「檔案」，共用的是暖金家族色票與報到卡的視覺語言，
// 不共用頁面。名字改自編輯基本資料頁，返回即重讀刷新。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/prefs_keys.dart';
import '../utils/story_store.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import 'profile_edit_page.dart';

// ── 足跡家族色票（同 login_streak_page 的暖金舞台）──
const _kStageBase = Color(0xFFFFF7E8);
const _kRayGold = Color(0xFFF5C96B);
const _kDeepGold = Color(0xFF9A641B);
const _kNumberInk = Color(0xFF7A4A17);
const _kSlotDash = Color(0xFFD9BE93);
const _kSlotEmptyFill = Color(0xFFF9F0DD);

const _kCoinAsset = 'assets/icon/ui/paw_footprint_coin.png';
const _kMascotAsset = 'assets/mascot/core/tumi_smile.png';

/// 相識第 N 天（第 1 天＝onboarding 當天）。缺日期時當第 1 天、不落盤——
/// 首頁載入時本來就會補寫 onboardingDate。
int companionDays(SharedPreferences prefs, DateTime now) {
  final raw = prefs.getString(PrefsKeys.onboardingDate);
  final start = (raw == null ? null : DateTime.tryParse(raw)) ?? now;
  return DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(start.year, start.month, start.day)).inDays +
      1;
}

/// 目前造型對應的兔咪微笑立繪（衣櫃選了新造型，名片/檔案頁跟著換裝）。
String _skinnedSmileAsset(String outfitId) =>
    skinnedMascotAsset(_kMascotAsset, outfitById(outfitId).skinKey);

/// 設定頁頂部的兔咪名片：暖金證件卡。
/// 資料由呼叫端載好傳入（名字、相識天數、足跡幣），本身不碰 prefs。
class MascotCallingCard extends StatelessWidget {
  final String name;
  final int companionDays;
  final int coinBalance;
  final VoidCallback onTap;

  const MascotCallingCard({
    super.key,
    required this.name,
    required this.companionDays,
    required this.coinBalance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name 的名片，相識第 $companionDays 天，足跡幣 $coinBalance，查看檔案',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFBF0), Color(0xFFFFF3DC)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kRayGold.withValues(alpha: 0.65)),
            boxShadow: AppShadows.card,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              splashColor: _kRayGold.withValues(alpha: 0.30),
              highlightColor: _kRayGold.withValues(alpha: 0.12),
              onTap: () {
                playHaptic(HapticLevel.selection);
                onTap();
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    // 右下角淡淡的腳印幣浮水印，一眼認出這張卡的世界觀。
                    Positioned(
                      right: -8,
                      bottom: -12,
                      child: Transform.rotate(
                        angle: -0.28,
                        child: Opacity(
                          opacity: 0.10,
                          child: Image.asset(_kCoinAsset, width: 68),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                      child: Row(
                        children: [
                          const _FaceAvatar(diameter: 58),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppInk.strong,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          const TextSpan(text: '相識第 '),
                                          TextSpan(
                                            text: '$companionDays',
                                            style: AppType.digits(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: _kNumberInk,
                                            ),
                                          ),
                                          const TextSpan(text: ' 天'),
                                        ],
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: _kNumberInk,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Image.asset(_kCoinAsset, width: 16),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$coinBalance',
                                      style: AppType.digits(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _kNumberInk,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _kDeepGold.withValues(alpha: 0.65),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圓框臉部特寫：全身立繪放大裁到臉（大頭貼感），金環描邊。
/// 縮放/對位參數是對著 tumi 全身圖（臉約在畫面上緣 4 成處）調的。
class _FaceAvatar extends StatelessWidget {
  final double diameter;

  const _FaceAvatar({required this.diameter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _kRayGold, width: 2),
        boxShadow: AppShadows.flat,
      ),
      child: ClipOval(
        child: Transform.scale(
          scale: 1.65,
          alignment: const Alignment(0, -0.52),
          child: ValueListenableBuilder<String>(
            valueListenable: WardrobeStore.selectedOutfit,
            builder: (_, outfitId, _) => Image.asset(
              _skinnedSmileAsset(outfitId),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

/// 兔咪檔案頁本體。
class MascotProfilePage extends StatefulWidget {
  const MascotProfilePage({super.key});

  @override
  State<MascotProfilePage> createState() => _MascotProfilePageState();
}

class _MascotProfilePageState extends State<MascotProfilePage>
    with SingleTickerProviderStateMixin {
  bool _loaded = false;
  String _name = '兔咪';
  int _days = 1;
  int _streak = 0;
  int _coins = 0;
  int _stories = 0;

  // 立繪待機輕飄（呼吸感）；減少動態時停住。
  late final AnimationController _bob;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations == true;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final coins = await CoinService.balance();
    await StoryStore.load();
    if (!mounted) return;
    setState(() {
      final name = prefs.getString(PrefsKeys.mascotName)?.trim();
      _name = (name == null || name.isEmpty) ? '兔咪' : name;
      _days = companionDays(prefs, DateTime.now());
      _streak = prefs.getInt(PrefsKeys.coinLoginStreak) ?? 0;
      _coins = coins;
      _stories = StoryStore.unlocked.value.length;
      _loaded = true;
    });
  }

  /// 本輪報到卡已蓋到第幾格（同 login_streak_page 的 cycle 計算）。
  int get _cycleDay {
    if (_streak <= 0) return 0;
    final m = CoinConfig.loginStreakMilestone;
    final d = _streak % m;
    return d == 0 ? m : d;
  }

  int get _round =>
      _streak <= 0 ? 1 : (_streak - 1) ~/ CoinConfig.loginStreakMilestone + 1;

  Future<void> _editName() async {
    playHaptic(HapticLevel.selection);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditPage()));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kStageBase,
      appBar: AppBar(
        backgroundColor: _kStageBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              children: [
                _buildPortrait(),
                const SizedBox(height: 6),
                _buildNameRow(),
                const SizedBox(height: 10),
                Center(child: _buildDaysSeal()),
                const SizedBox(height: 24),
                _buildStampCard(),
                const SizedBox(height: 14),
                _buildStatsRow(),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    '走過的每一天，都有留下足跡。',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppInk.soft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildPortrait() {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 身後暖白光暈，把角色從奶油底托出來。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0xB3FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: SizedBox.expand(),
          ),
          AnimatedBuilder(
            animation: _bob,
            builder: (_, child) {
              final t = _reduceMotion
                  ? 0.0
                  : Curves.easeInOut.transform(_bob.value);
              return Transform.translate(
                offset: Offset(0, 3 * t),
                child: child,
              );
            },
            child: ValueListenableBuilder<String>(
              valueListenable: WardrobeStore.selectedOutfit,
              builder: (_, outfitId, _) => Image.asset(
                _skinnedSmileAsset(outfitId),
                height: 184,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 左側留一個跟編輯鈕等寬的位子，讓名字真正置中。
        const SizedBox(width: 36),
        Flexible(
          child: Text(
            _name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppInk.strong,
            ),
          ),
        ),
        IconButton(
          onPressed: _editName,
          tooltip: '改名字',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          icon: const Icon(
            Icons.edit_outlined,
            size: 19,
            color: AppInk.iconFaint,
          ),
        ),
      ],
    );
  }

  /// 「相識第 N 天」橡皮章落款（同慶祝頁墨印的視覺語言，靜態、小一號）。
  Widget _buildDaysSeal() {
    return Transform.rotate(
      angle: -0.045,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _kNumberInk.withValues(alpha: 0.72),
            width: 2.2,
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '相識第 '),
              TextSpan(
                text: '$_days',
                style: AppType.digits(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _kNumberInk,
                ),
              ),
              const TextSpan(text: ' 天'),
            ],
          ),
          style: const TextStyle(
            color: _kNumberInk,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
      ),
    );
  }

  /// 報到卡（靜態版）：本輪 7 格，蓋過的是金腳印、之後是虛線空格。
  Widget _buildStampCard() {
    final milestone = CoinConfig.loginStreakMilestone;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kRayGold.withValues(alpha: 0.55)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              if (_round >= 2) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _kRayGold.withValues(alpha: 0.8)),
                  ),
                  child: Text(
                    '第 $_round 輪',
                    style: AppType.digits(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _kDeepGold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '連續 $_streak 天',
                style: AppType.digits(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _kDeepGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Semantics(
            label: '本輪已報到 $_cycleDay 天，滿 $milestone 天有加碼',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var day = 1; day <= milestone; day++) ...[
                    if (day > 1) const SizedBox(width: 6),
                    Expanded(child: _buildDaySlot(day)),
                  ],
                ],
              ),
            ),
          ),
          if (_streak <= 0) ...[
            const SizedBox(height: 8),
            const Text(
              '第一個腳印，今天打開就能蓋。',
              style: TextStyle(fontSize: 11.5, color: AppInk.soft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDaySlot(int day) {
    final stamped = day <= _cycleDay;
    final isGift = day == CoinConfig.loginStreakMilestone;
    const slotSize = 34.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$day',
          style: AppType.digits(
            fontWeight: FontWeight.w800,
            color: day == _cycleDay ? _kDeepGold : AppInk.faint,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: slotSize,
          height: slotSize,
          child: stamped
              ? Image.asset(_kCoinAsset, width: slotSize, height: slotSize)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    const CustomPaint(
                      size: Size.square(slotSize),
                      painter: _DashedSlotPainter(),
                    ),
                    if (isGift)
                      Icon(
                        Icons.card_giftcard_rounded,
                        size: slotSize * 0.52,
                        color: const Color(0xFFC99B4C),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            leading: Image.asset(_kCoinAsset, width: 30),
            label: '足跡幣',
            value: '$_coins',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _kRayGold.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 17,
                color: _kDeepGold,
              ),
            ),
            label: '回憶本',
            value: '$_stories 冊',
          ),
        ),
      ],
    );
  }
}

/// 檔案頁的小統計卡（足跡幣 / 回憶本）。
class _StatTile extends StatelessWidget {
  final Widget leading;
  final String label;
  final String value;

  const _StatTile({
    required this.leading,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kRayGold.withValues(alpha: 0.55)),
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppInk.soft,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: AppType.digits(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _kNumberInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 報到卡空格：虛線圓圈＋淡奶油底（同慶祝頁 _DashedSlotPainter 的靜態款）。
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
