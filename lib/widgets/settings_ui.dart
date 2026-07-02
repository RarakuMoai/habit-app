// 設定頁系共用 UI：暖白卡面的入口列 / 容器卡。
//
// 視覺語彙對齊 app_style：暖白 AppSurfaces.card、髮絲線描邊、flat 暖棕陰影、
// 圓角 14（設定列比內容卡略小一階，維持「工具頁」的密度）。
import 'package:flutter/material.dart';

import '../utils/app_style.dart';

const double _kSettingsRadius = 14;

/// 設定頁的導航入口列：圓底 icon + 標題 + 副標 + chevron。
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
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppInk.strong,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(fontSize: 12, color: AppInk.soft),
              ),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: AppInk.iconFaint),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kSettingsRadius),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 設定頁的容器卡：暖白底 + 髮絲線 + flat 陰影，裝任意內容
/// （單位切換、換日時間軸這類非單純入口列的區塊）。
class SettingsGroupCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const SettingsGroupCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(_kSettingsRadius),
        border: Border.all(color: AppSurfaces.divider),
        boxShadow: AppShadows.flat,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
