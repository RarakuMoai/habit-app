// 共用 AppBar：透明背景，左 = 日期 pill，右 = 設定按鈕。
//
// 所有兔咪頁面共用同一條 header，標題由兔咪 + 背景場景承載，
// AppBar 只剩兩件套：日期（含日/夜 icon）+ 設定。
//
// 使用上需要把 Scaffold 設成 `extendBodyBehindAppBar: true`，否則
// 透明 AppBar 下方會留一塊空白。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/review_page.dart';
import '../pages/settings_page.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import 'audio_control_button.dart';

class MascotAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 影響日期 pill icon 顏色（其餘元素統一灰底白字）。
  final Color accent;

  /// 額外塞在「設定」前面的 actions。
  final List<Widget> extraActions;

  /// 是否顯示「足跡」鈕（彙總習慣/喝水/專注/運動的回顧）。
  /// 預設全頁共用同一入口；個別頁面語境不合時可關掉。
  final bool showReview;

  /// 從設定頁返回後要做的事（重新載入資料等）。
  final VoidCallback? onSettingsReturn;

  const MascotAppBar({
    super.key,
    required this.accent,
    this.extraActions = const [],
    this.showReview = true,
    this.onSettingsReturn,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isNight = now.hour >= 22 || now.hour < 6;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final dateStr = '${now.month}月${now.day}日 週${weekdays[now.weekday - 1]}';

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leadingWidth: 160,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: MascotPill(
            icon: isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
            label: dateStr,
            color: accent,
          ),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          // 金幣餘額兼足跡入口：足跡 icon 與金幣數並列，不互相遮擋。
          child: CoinPill(
            onReviewTap: showReview ? () => _openReview(context) : null,
          ),
        ),
        ...extraActions,
        AudioControlButton(style: AudioControlStyle.appBar, accent: accent),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _circleAction(
            icon: Icons.settings_outlined,
            iconColor: Colors.grey.shade800,
            tooltip: '設定',
            onPressed: () async {
              await Navigator.of(
                context,
              ).push(_slideRoute((_) => const SettingsPage()));
              onSettingsReturn?.call();
            },
          ),
        ),
      ],
    );
  }

  // 白圓底 + 陰影的 AppBar 圓鈕；足跡 / 設定共用同一視覺語言。
  Widget _circleAction({
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(icon, color: iconColor),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }

  void _openReview(BuildContext context) {
    Navigator.of(context).push(_slideRoute((_) => const ReviewPage()));
  }

  // 共用「右滑入」轉場：足跡 / 設定同一套手感。
  PageRouteBuilder<void> _slideRoute(WidgetBuilder builder) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut)).animate(anim),
        child: child,
      ),
    );
  }
}

/// 金幣餘額：監聽 [CoinService.notifier]，全頁 app bar 顯示；
/// 餘額變動時輕輕 pop 一下，保留獎勵感但不搶主頁視覺。
class CoinPill extends StatefulWidget {
  /// 非 null 時：整顆可點 → 開足跡。null 時退回純顯示、不可點。
  final VoidCallback? onReviewTap;
  const CoinPill({super.key, this.onReviewTap});

  @override
  State<CoinPill> createState() => _CoinPillState();
}

class _CoinPillState extends State<CoinPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.22), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));
    CoinService.notifier.addListener(_onCoinChanged);
  }

  @override
  void dispose() {
    CoinService.notifier.removeListener(_onCoinChanged);
    _pop.dispose();
    super.dispose();
  }

  void _onCoinChanged() {
    if (mounted) _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: ValueListenableBuilder<int>(
        valueListenable: CoinService.notifier,
        builder: (_, coins, _) =>
            _CoinBalanceButton(coins: coins, onReviewTap: widget.onReviewTap),
      ),
    );
  }
}

class _CoinBalanceButton extends StatelessWidget {
  static const _reviewGold = Color(0xFFE5A327);
  static const _reviewAmber = Color(0xFFFFC44D);
  static const _reviewCream = Color(0xFFFFF7E7);
  static const _reviewBrown = Color(0xFF7A4A17);

  final int coins;

  /// 非 null 時：整顆可點 → 開足跡。
  final VoidCallback? onReviewTap;
  const _CoinBalanceButton({required this.coins, this.onReviewTap});

  @override
  Widget build(BuildContext context) {
    final canOpenReview = onReviewTap != null;
    final label = canOpenReview ? '金幣 $coins，看足跡' : '金幣 $coins';
    final button = SizedBox(
      height: 42,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, _reviewCream],
            ),
            border: Border.all(color: _reviewAmber.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: _reviewGold.withValues(alpha: 0.20),
                blurRadius: 13,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.90),
                blurRadius: 4,
                offset: const Offset(-1, -1),
              ),
              BoxShadow(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.10),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onReviewTap,
            splashColor: _reviewGold.withValues(alpha: 0.14),
            highlightColor: _reviewGold.withValues(alpha: 0.07),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 7, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 32,
                    child: _ReviewFootprintIcon(),
                  ),
                  const SizedBox(width: 5),
                  _CoinCountInline(coins: coins),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!canOpenReview) {
      return Semantics(
        label: label,
        child: Tooltip(message: label, child: button),
      );
    }
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(message: '看足跡', child: button),
    );
  }
}

class _ReviewFootprintIcon extends StatelessWidget {
  const _ReviewFootprintIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(
          color: _CoinBalanceButton._reviewAmber.withValues(alpha: 0.30),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 5,
            right: 4,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 9,
              color: _CoinBalanceButton._reviewGold.withValues(alpha: 0.70),
            ),
          ),
          Positioned(
            left: 5,
            bottom: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _CoinBalanceButton._reviewAmber.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 4),
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _CoinBalanceButton._reviewGold,
                _CoinBalanceButton._reviewBrown,
              ],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Icon(Icons.pets_rounded, size: 21),
          ),
        ],
      ),
    );
  }
}

class _CoinCountInline extends StatelessWidget {
  final int coins;

  const _CoinCountInline({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC44D), Color(0xFFE59A1D)],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9D6715).withValues(alpha: 0.24),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.paid_rounded, size: 9, color: Colors.white),
            const SizedBox(width: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$coins',
                  style: AppType.digits(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 白底圓角小膠囊（日期、連續天數等都用這個）。
class MascotPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const MascotPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          // Baloo 2 的 ascent 佔比大，字形在行框內偏上（模擬器實測高
          // 1.2pt），往下平移做光學置中；用 Transform 不影響膠囊高度
          Transform.translate(
            offset: const Offset(0, 1.2),
            child: Text(
              label,
              style: AppType.digits(
                color: Colors.grey.shade800,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
