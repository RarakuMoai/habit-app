import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 共用工具鈕的真實外框。金幣、音量及設定使用同尺寸與表面，間距由 AppBar 管理。
class MascotToolbarSurface extends StatelessWidget {
  static const size = 48.0;
  static const gap = 8.0;
  final Widget child;

  const MascotToolbarSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Material(
      color: AppSurfaces.card.withValues(alpha: 0.94),
      elevation: 1,
      shadowColor: AppInk.strong.withValues(alpha: 0.10),
      shape: const CircleBorder(side: BorderSide(color: Color(0xB3FFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}
