// 共用 AppBar：透明背景，左 = 日期 pill，右 = 設定按鈕。
//
// 所有兔咪頁面共用同一條 header，標題由兔咪 + 背景場景承載，
// AppBar 只剩兩件套：日期（含日/夜 icon）+ 設定。
//
// 使用上需要把 Scaffold 設成 `extendBodyBehindAppBar: true`，否則
// 透明 AppBar 下方會留一塊空白。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/settings_page.dart';
import '../utils/app_style.dart';
import '../utils/coin_service.dart';
import 'audio_control_button.dart';

class MascotAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 影響日期 pill icon 顏色（其餘元素統一灰底白字）。
  final Color accent;

  /// 額外塞在「設定」前面的 actions。
  final List<Widget> extraActions;

  /// 從設定頁返回後要做的事（重新載入資料等）。
  final VoidCallback? onSettingsReturn;

  const MascotAppBar({
    super.key,
    required this.accent,
    this.extraActions = const [],
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
        const Padding(padding: EdgeInsets.only(right: 6), child: CoinPill()),
        ...extraActions,
        AudioControlButton(style: AudioControlStyle.appBar, accent: accent),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
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
                icon: Icon(
                  Icons.settings_outlined,
                  color: Colors.grey.shade800,
                ),
                tooltip: '設定',
                onPressed: () async {
                  await Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) => const SettingsPage(),
                      transitionsBuilder: (_, anim, _, child) =>
                          SlideTransition(
                            position:
                                Tween(
                                      begin: const Offset(1.0, 0.0),
                                      end: Offset.zero,
                                    )
                                    .chain(CurveTween(curve: Curves.easeInOut))
                                    .animate(anim),
                            child: child,
                          ),
                    ),
                  );
                  onSettingsReturn?.call();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 金幣餘額：監聽 [CoinService.notifier]，全頁 app bar 顯示；
/// 餘額變動時輕輕 pop 一下，保留獎勵感但不搶主頁視覺。
class CoinPill extends StatefulWidget {
  const CoinPill({super.key});

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
        builder: (_, coins, _) => _CoinBalanceChip(coins: coins),
      ),
    );
  }
}

class _CoinBalanceChip extends StatelessWidget {
  final int coins;
  const _CoinBalanceChip({required this.coins});

  @override
  Widget build(BuildContext context) {
    const coin = Color(0xFFE5A327);
    return Semantics(
      label: '金幣 $coins',
      child: Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E3).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFFE2A0).withValues(alpha: 0.95),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB47618).withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: coin,
              ),
              child: const Icon(
                Icons.paid_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 46),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$coins',
                  style: AppType.digits(
                    color: const Color(0xFF6D5526),
                    fontSize: 12.5,
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
