import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 同一份導覽排版的兩種材質，方便在真實場景比較。
/// NAV_GLASS 只供本輪候選比較；高對比模式一律使用實底。
const navigationGlass = bool.fromEnvironment('NAV_GLASS');

class NavigationSurface extends StatelessWidget {
  final Widget child;
  const NavigationSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final glass = navigationGlass && !MediaQuery.highContrastOf(context);
    const radius = BorderRadius.all(Radius.circular(26));
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: glass ? null : AppSurfaces.card,
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppSurfaces.card.withValues(alpha: 0.88),
                  AppSurfaces.fill.withValues(alpha: 0.66),
                ],
              )
            : null,
        borderRadius: radius,
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: 0.85)
              : AppSurfaces.divider,
        ),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: glass
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
