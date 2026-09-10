import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 同一份導覽排版的兩種材質，方便在真實場景比較。
/// 玻璃為預設；保留實底比較開關，高對比模式一律使用實底。
const navigationGlass = bool.fromEnvironment('NAV_GLASS', defaultValue: true);

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
                  Colors.white.withValues(alpha: 0.72),
                  AppSurfaces.card.withValues(alpha: 0.48),
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x148B7665),
            blurRadius: 22,
            offset: Offset(0, 7),
          ),
          BoxShadow(color: Color(0x0CFFFFFF), blurRadius: 2, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: glass
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
