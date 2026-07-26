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

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/mascot.dart';
import '../utils/prefs_keys.dart';
import '../utils/story_store.dart';
import '../utils/wardrobe_catalog.dart';
import '../utils/wardrobe_store.dart';
import 'profile_edit_page.dart';
import 'review_page.dart';

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
  final VoidCallback? onCoinTap;

  const MascotCallingCard({
    super.key,
    required this.name,
    required this.companionDays,
    required this.coinBalance,
    required this.onTap,
    this.onCoinTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      label: l10n.mpCardSemantics(name, companionDays, coinBalance),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFBF2), Color(0xFFFFEED3), Color(0xFFFFE2CC)],
            stops: [0, 0.58, 1],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kRayGold.withValues(alpha: 0.72)),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            splashColor: _kRayGold.withValues(alpha: 0.24),
            highlightColor: _kRayGold.withValues(alpha: 0.10),
            onTap: () {
              playHaptic(HapticLevel.selection);
              onTap();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  const Positioned(
                    right: -30,
                    top: -38,
                    child: _CallingCardGlow(
                      size: 112,
                      color: Color(0x45F39A7A),
                    ),
                  ),
                  Positioned(
                    right: -14,
                    bottom: -20,
                    child: Transform.rotate(
                      angle: -0.24,
                      child: Opacity(
                        opacity: 0.08,
                        child: Image.asset(
                          _kCoinAsset,
                          width: 92,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const _FaceAvatar(diameter: 76),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFF18A72,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.favorite_rounded,
                                          size: 12,
                                          color: Color(0xFFE46F5B),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            l10n.mpPartnerBadge(name),
                                            key: const ValueKey(
                                              'mascot-calling-card-title',
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFFB95747),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                      color: AppInk.strong,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: l10n.mpTogetherPrefix),
                                        TextSpan(
                                          text: '$companionDays',
                                          style: AppType.digits(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: _kNumberInk,
                                          ),
                                        ),
                                        TextSpan(text: l10n.mpDaySuffix),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _kNumberInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: _CallingCardAction(
                                icon: Icons.badge_rounded,
                                label: l10n.mpViewProfile,
                                foreground: Color(0xFF9C5D3D),
                                background: Color(0xB3FFFFFF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Semantics(
                                button: onCoinTap != null,
                                label: l10n.mpViewCoins(coinBalance),
                                child: Material(
                                  key: const ValueKey(
                                    'mascot-calling-card-coins',
                                  ),
                                  color: const Color(0xFFFFD873),
                                  borderRadius: BorderRadius.circular(15),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(15),
                                    onTap: onCoinTap == null
                                        ? null
                                        : () {
                                            playHaptic(HapticLevel.selection);
                                            onCoinTap!();
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Image.asset(_kCoinAsset, width: 20),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              '$coinBalance',
                                              overflow: TextOverflow.ellipsis,
                                              style: AppType.digits(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                                color: _kNumberInk,
                                              ),
                                            ),
                                          ),
                                          if (onCoinTap != null) ...[
                                            const SizedBox(width: 2),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: _kDeepGold,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}

class _CallingCardGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _CallingCardGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: SizedBox.square(dimension: size),
    );
  }
}

/// 檔案頁底色：奶油紙張上疊很淡的晨光與薰衣草光暈，讓內容有場景感，
/// 但裝飾留在卡片外圍，不穿過文字或操作區。
class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('mascot-profile-backdrop'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8EA), Color(0xFFFFF2E9), Color(0xFFF6F0FF)],
          stops: [0, 0.56, 1],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -86,
            top: 30,
            child: _CallingCardGlow(size: 220, color: Color(0x20F39A7A)),
          ),
          const Positioned(
            left: -118,
            top: 360,
            child: _CallingCardGlow(size: 250, color: Color(0x189C7DDA)),
          ),
          Positioned(
            right: -18,
            bottom: 46,
            child: Transform.rotate(
              angle: -0.22,
              child: Opacity(
                opacity: 0.035,
                child: Image.asset(
                  _kCoinAsset,
                  width: 132,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallingCardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _CallingCardAction({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: foreground,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 17, color: foreground),
        ],
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD66B), Color(0xFFF18A72)],
        ),
        shape: BoxShape.circle,
        boxShadow: AppShadows.flat,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFCF7),
          shape: BoxShape.circle,
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
  AppLocalizations get _l10n => AppLocalizations.of(context);

  bool _loaded = false;
  String _name = MascotName.fallback;
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
      _name = (name == null || name.isEmpty) ? MascotName.fallback : name;
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

  void _openReview() {
    playHaptic(HapticLevel.selection);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReviewPage()));
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = _loaded
        ? _l10n.mpProfileTitle(_name)
        : _l10n.mpProfileTitleFallback;
    return Scaffold(
      backgroundColor: _kStageBase,
      appBar: AppBar(
        title: Text(pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        foregroundColor: _kNumberInk,
        iconTheme: const IconThemeData(color: _kNumberInk),
        titleTextStyle: const TextStyle(
          color: AppInk.strong,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF8EA), Color(0xFFFFF0E8)],
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _ProfileBackdrop(),
          if (_loaded)
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _buildIdentityCard(),
                const SizedBox(height: 18),
                _buildStampCard(),
                const SizedBox(height: 14),
                _buildStatsRow(),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    _l10n.mpEveryDayLeaves,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppInk.soft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return DecoratedBox(
      key: const ValueKey('mascot-profile-identity-card'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEFFFFFFF), Color(0xF5FFF4E2), Color(0xF5FFE8E3)],
          stops: [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _kRayGold.withValues(alpha: 0.62)),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            const Positioned(
              right: -42,
              top: -54,
              child: _CallingCardGlow(size: 154, color: Color(0x38F39A7A)),
            ),
            Positioned(
              left: -26,
              top: 78,
              child: Transform.rotate(
                angle: 0.18,
                child: Opacity(
                  opacity: 0.055,
                  child: Image.asset(
                    _kCoinAsset,
                    width: 104,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
              child: Column(
                children: [
                  _buildPortrait(),
                  const SizedBox(height: 2),
                  _buildNameRow(),
                  const SizedBox(height: 10),
                  Center(child: _buildDaysSeal()),
                ],
              ),
            ),
          ],
        ),
      ),
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
          tooltip: _l10n.mpRename,
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
              TextSpan(text: _l10n.mpKnownForPrefix),
              TextSpan(
                text: '$_days',
                style: AppType.digits(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _kNumberInk,
                ),
              ),
              TextSpan(text: _l10n.mpDaySuffix),
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
              Text(
                _l10n.mpCheckinCard,
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
                    _l10n.mpRound(_round),
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
                _l10n.mpStreakDays(_streak),
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
            label: _l10n.mpCheckinSemantics(_cycleDay, milestone),
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
            Text(
              _l10n.mpFirstFootprint,
              style: const TextStyle(fontSize: 11.5, color: AppInk.soft),
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
            label: _l10n.mpCoins,
            value: '$_coins',
            onTap: _openReview,
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
            label: _l10n.mpMemoryBook,
            value: _l10n.mpVolumes(_stories),
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
  final VoidCallback? onTap;

  const _StatTile({
    required this.leading,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kRayGold.withValues(alpha: onTap == null ? 0.55 : 0.82),
        ),
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
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
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _kDeepGold,
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).mpStatSemantics(label, value),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const ValueKey('mascot-profile-coins'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: content,
        ),
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
