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
import '../utils/bgm_service.dart';

class MascotAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 影響日期 pill icon 顏色（其餘元素統一灰底白字）。
  final Color accent;

  /// 額外塞在「設定」前面的 actions（例如首頁的連續天數 pill）。
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
            icon: isNight
                ? Icons.nightlight_round
                : Icons.wb_sunny_rounded,
            label: dateStr,
            color: accent,
          ),
        ),
      ),
      title: const SizedBox.shrink(),
      actions: [
        ...extraActions,
        // 聲音 toggle（全 app 共用，靜音狀態跟著 BgmService.muted）
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ValueListenableBuilder<bool>(
            valueListenable: BgmService.muted,
            builder: (_, isMuted, _) => DecoratedBox(
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
                  isMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.grey.shade800,
                ),
                tooltip: isMuted ? '取消靜音' : '靜音',
                onPressed: () => BgmService.instance.setMuted(!isMuted),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
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
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => const SettingsPage(),
                    transitionsBuilder: (_, anim, _, child) =>
                        SlideTransition(
                          position:
                              Tween(
                                    begin: const Offset(1.0, 0.0),
                                    end: Offset.zero,
                                  )
                                  .chain(
                                    CurveTween(curve: Curves.easeInOut),
                                  )
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
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
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
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
