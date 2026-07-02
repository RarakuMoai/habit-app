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
          // 金幣餘額兼足跡入口：和音量/設定一樣是白色圓鈕，
          // 腳印內顯示短版金幣數，完整數字留給足跡頁與語意標籤。
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
  static const _reviewBrown = Color(0xFF7A4A17);

  final int coins;

  /// 非 null 時：整顆可點 → 開足跡。
  final VoidCallback? onReviewTap;
  const _CoinBalanceButton({required this.coins, this.onReviewTap});

  @override
  Widget build(BuildContext context) {
    final canOpenReview = onReviewTap != null;
    final label = canOpenReview ? '足跡與金幣，$coins 金幣' : '金幣 $coins';
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
                color: Colors.black.withValues(alpha: 0.10),
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
      child: Tooltip(message: '足跡與金幣', child: button),
    );
  }
}

class _PawCoinIcon extends StatelessWidget {
  final int coins;

  const _PawCoinIcon({required this.coins});

  String get _label => coins > 999 ? '999+' : '$coins';
  double get _fontSize => _label.length > 3 ? 10.2 : 12.4;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          size: const Size.square(38),
          painter: const _PawOutlinePainter(
            color: _CoinBalanceButton._reviewBrown,
            glowColor: _CoinBalanceButton._reviewAmber,
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 4.5,
          height: 13,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Transform.translate(
                offset: const Offset(0, 0.6),
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

class _PawOutlinePainter extends CustomPainter {
  final Color color;
  final Color glowColor;

  const _PawOutlinePainter({required this.color, required this.glowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 掌墊改用圓角矩形（不是純橢圓）：橢圓四角收得太快，塞不下金幣數字
    // （長到 999+ 4 個字）就會頂到趾墊；圓角矩形中間留一塊方正安全區給
    // 數字，看起來仍是圓潤肉墊、不會像方塊。
    // 四顆趾墊：內側兩顆較大較高、外側兩顆較小較低，呈扇形展開，彼此與掌墊
    // 都留白分開才會一眼認出是腳印，之前用一條連續外框描全部反而糊成一坨。
    final palm = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.16, h * 0.50, w * 0.84, h * 0.92),
      Radius.circular(w * 0.14),
    );
    final toes = <Rect>[
      Rect.fromCenter(
        center: Offset(w * 0.165, h * 0.465),
        width: w * 0.20,
        height: h * 0.20,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.375, h * 0.255),
        width: w * 0.225,
        height: h * 0.265,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.625, h * 0.255),
        width: w * 0.225,
        height: h * 0.265,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.835, h * 0.465),
        width: w * 0.20,
        height: h * 0.20,
      ),
    ];
    final paw = Path()..addRRect(palm);
    for (final toe in toes) {
      paw.addOval(toe);
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        center: const Alignment(0, 0.25),
        radius: 0.78,
        colors: [
          glowColor.withValues(alpha: 0.20),
          glowColor.withValues(alpha: 0.055),
        ],
      ).createShader(Offset.zero & size);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.2
      ..color = glowColor.withValues(alpha: 0.20);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.35
      ..color = color.withValues(alpha: 0.94);

    canvas.drawPath(paw, fill);
    canvas.drawPath(paw, glow);
    canvas.drawPath(paw, stroke);
  }

  @override
  bool shouldRepaint(covariant _PawOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glowColor != glowColor;
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
