// 設定頁系共用 UI：有留白的紙張卡面，標題與說明可以隨文字尺寸自然換行。
import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 設定頁的導航入口列：圖示底塊、標題、說明與前進箭頭。
class SettingsTileCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const SettingsTileCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsGroupCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        minTileHeight: 88,
        horizontalTitleGap: 14,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: iconColor.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppInk.strong,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppInk.soft,
                  ),
                ),
              ),
        trailing:
            trailing ??
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppInk.soft,
            ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppCardStyle.radius),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 設定頁的容器卡：暖白底與髮絲線，裝任意內容
/// （單位切換、換日時間軸這類非單純入口列的區塊）。
class SettingsGroupCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const SettingsGroupCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppSurfaces.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        side: const BorderSide(color: AppSurfaces.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
