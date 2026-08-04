// 共用 AppBar：透明背景，左 = 日期 pill，右 = 設定按鈕。
//
// 所有兔咪頁面共用同一條 header，標題由兔咪 + 背景場景承載，
// AppBar 只剩兩件套：日期 + 設定。時段已由完整背景承擔，日期不再重複放
// 日／夜 icon，避免純裝飾圖示搶走場景焦點。
//
// 使用上需要把 Scaffold 設成 `extendBodyBehindAppBar: true`，否則
// 透明 AppBar 下方會留一塊空白。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../pages/review_page.dart';
import '../pages/settings_page.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import '../utils/mini_game_session.dart';
import 'audio_control_button.dart';
import 'reward_animation_anchor.dart';

class MascotAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 頁面識別色（用於音量按鈕）。
  final Color accent;

  /// 額外塞在「設定」前面的 actions。
  final List<Widget> extraActions;

  /// 是否顯示「足跡」鈕（彙總習慣/喝水/專注/運動的回顧）。
  /// 預設全頁共用同一入口；個別頁面語境不合時可關掉。
  final bool showReview;

  /// 從設定頁返回後要做的事（重新載入資料等）。
  final VoidCallback? onSettingsReturn;

  /// 足跡、聲音或設定開始動作前呼叫。顯示中的 overlay 小遊戲會由
  /// [MiniGameSession] 自動暫停；這個 callback 留給頁面自己的額外狀態。
  final VoidCallback? onBeforeAction;

  const MascotAppBar({
    super.key,
    required this.accent,
    this.extraActions = const [],
    this.showReview = true,
    this.onSettingsReturn,
    this.onBeforeAction,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);
    final weekdays = [
      l10n.weekdayShortMon,
      l10n.weekdayShortTue,
      l10n.weekdayShortWed,
      l10n.weekdayShortThu,
      l10n.weekdayShortFri,
      l10n.weekdayShortSat,
      l10n.weekdayShortSun,
    ];
    final dateStr = l10n.abDateWeekday(
      now.month,
      now.day,
      weekdays[now.weekday - 1],
    );

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leadingWidth: 136,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: MascotPill(label: dateStr),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          // 金幣餘額兼足跡入口：和音量/設定一樣是白色圓鈕，
          // 腳印內顯示短版金幣數，完整數字留給足跡頁與語意標籤。
          child: CoinPill(
            onReviewTap: showReview
                ? () {
                    _beforeAction();
                    _openReview(context);
                  }
                : null,
          ),
        ),
        ...extraActions,
        AudioControlButton(
          style: AudioControlStyle.appBar,
          accent: accent,
          onBeforeOpen: _beforeAction,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _circleAction(
            icon: Icons.settings_outlined,
            iconColor: AppInk.strong,
            tooltip: l10n.abSettings,
            onPressed: () async {
              _beforeAction();
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

  void _beforeAction() {
    MiniGameSession.pauseActive();
    onBeforeAction?.call();
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
              color: const Color(0xFF8D6E63).withValues(alpha: 0.22),
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

  // 設定 / 足跡的推頁轉場。
  //
  // 這裡曾經是自訂的 `PageRouteBuilder` + `SlideTransition`（「共用右滑入」），
  // 看起來跟系統轉場很像，但**裸 PageRouteBuilder 不走 theme 的
  // pageTransitionsTheme**，所以它靜靜地拿掉了兩樣東西：iOS 的邊緣滑回手勢，
  // 以及舊頁的視差退場。全 app 其他 16 個推頁點都用 MaterialPageRoute，
  // 只有這兩頁滑不回去——那不是風格差異，是功能少一塊。
  //
  // 改回平台路由：18 個推頁點手感一致、滑回手勢回來、而且少維護一段程式。
  // 之後若真的要做品牌轉場，必須從 `CupertinoPageRoute` 或
  // `PageTransitionsTheme` 走，不能用裸 PageRouteBuilder 換掉整個轉場層。
  MaterialPageRoute<void> _slideRoute(WidgetBuilder builder) {
    return MaterialPageRoute<void>(builder: builder);
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
    CoinService.rewardPulse.addListener(_onRewardPulse);
  }

  @override
  void dispose() {
    CoinService.notifier.removeListener(_onCoinChanged);
    CoinService.rewardPulse.removeListener(_onRewardPulse);
    _pop.dispose();
    super.dispose();
  }

  void _onCoinChanged() {
    if (mounted && CoinService.presentationBalance.value == null) {
      _pop.forward(from: 0);
    }
  }

  void _onRewardPulse() {
    if (mounted) _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return RewardAnimationAnchor(
      kind: RewardAnimationAnchorKind.coinBalance,
      child: ScaleTransition(
        scale: _scale,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            CoinService.notifier,
            CoinService.presentationBalance,
          ]),
          builder: (_, _) => _CoinBalanceButton(
            coins: CoinService.visibleBalance,
            onReviewTap: widget.onReviewTap,
          ),
        ),
      ),
    );
  }
}

class _CoinBalanceButton extends StatelessWidget {
  static const _reviewGold = Color(0xFFE5A327);
  static const _reviewAmber = Color(0xFFFFC44D);
  static const _reviewBrown = Color(0xFF7A4A17);

  final int coins;

  /// 非 null 時：整顆可點 → 開足跡。
  final VoidCallback? onReviewTap;
  const _CoinBalanceButton({required this.coins, this.onReviewTap});

  @override
  Widget build(BuildContext context) {
    final canOpenReview = onReviewTap != null;
    final l10n = AppLocalizations.of(context);
    final label = canOpenReview
        ? l10n.abCoinsWithReview(coins)
        : l10n.abCoinsOnly(coins);
    final button = SizedBox.square(
      dimension: 48,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: _reviewAmber.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onReviewTap,
            splashColor: _reviewGold.withValues(alpha: 0.14),
            highlightColor: _reviewGold.withValues(alpha: 0.07),
            child: Center(
              child: SizedBox.square(
                dimension: 38,
                child: _PawCoinIcon(coins: coins),
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
      child: Tooltip(message: l10n.abFootprintsAndCoins, child: button),
    );
  }
}

class _PawCoinIcon extends StatelessWidget {
  final int coins;

  const _PawCoinIcon({required this.coins});

  String get _label => coins > 999 ? '999+' : '$coins';
  // 實際字級交給下方 FittedBox(contain) 依掌墊框放大填滿，這裡只給基準。
  double get _fontSize => 12.0;

  // 單／雙位數被 FittedBox 放得較大，視覺重心容易往下；三位數較扁，
  // 反而要稍微往掌墊下緣靠。幅度刻意壓在 1px 左右。
  double get _labelDy {
    if (coins < 100) return -0.2;
    if (coins < 1000) return 1.0;
    return 0.6;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Image.asset(
          'assets/icon/ui/paw_footprint_coin_round.png',
          width: 35,
          height: 35,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        // 數字填滿掌墊：框對準量出來的掌墊內接矩形（中心 y≈0.68，偏下），
        // 用 contain 讓字放大填滿又不頂到肉墊邊線。
        Positioned(
          left: 10,
          right: 10,
          top: 20,
          bottom: 7,
          child: Center(
            child: FittedBox(
              child: Transform.translate(
                offset: Offset(0, _labelDy),
                child: Text(
                  _label,
                  maxLines: 1,
                  style: AppType.digits(
                    color: _CoinBalanceButton._reviewBrown,
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 白底圓角小膠囊（日期等簡短場景資訊用）。
class MascotPill extends StatelessWidget {
  final String label;

  const MascotPill({super.key, required this.label});

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
            color: const Color(0xFF8D6E63).withValues(alpha: 0.26),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Baloo 2 的 ascent 佔比大，字形在行框內偏上（模擬器實測高
          // 1.2pt），往下平移做光學置中；用 Transform 不影響膠囊高度
          Transform.translate(
            offset: const Offset(0, 1.2),
            child: Text(
              label,
              style: AppType.digits(color: AppInk.strong, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
