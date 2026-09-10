import 'package:flutter/material.dart';

import 'app_style.dart';

/// 全頁共同的紙色、字級、焦點與表單語言；功能頁只選擇自己的識別色。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.brand,
    primary: AppPalette.brand,
    onPrimary: AppSurfaces.card,
    secondary: AppPalette.habit,
    surface: AppSurfaces.card,
    onSurface: AppInk.strong,
    error: AppInk.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: AppSurfaces.canvas,
    canvasColor: AppSurfaces.canvas,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  final primary = FilledButton.styleFrom(
    minimumSize: const Size(48, 52),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    shape: shape,
    textStyle: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppInk.strong, displayColor: AppInk.strong)
        .copyWith(
          headlineMedium: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 28,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: AppInk.strong,
            letterSpacing: -0.6,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: AppInk.strong,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            height: 1.5,
            color: AppInk.strong,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppSurfaces.canvas,
      foregroundColor: AppInk.strong,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppInk.strong,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppSurfaces.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        side: const BorderSide(color: AppSurfaces.divider),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppSurfaces.fill,
      hintStyle: const TextStyle(color: AppInk.soft),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppSurfaces.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppPalette.brand, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primary),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 52),
        elevation: 0,
        backgroundColor: AppPalette.brand,
        foregroundColor: AppSurfaces.card,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        side: const BorderSide(color: AppSurfaces.divider),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppSurfaces.divider,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppPalette.brand,
      linearTrackColor: AppSurfaces.fill,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppInk.strong,
      contentTextStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppSurfaces.card,
      ),
      actionTextColor: const Color(0xFFCBE7C5),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppSurfaces.card,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: AppInk.strong.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppSurfaces.divider),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppSurfaces.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: AppInk.strong,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppSurfaces.card,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x66343E38),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppCardStyle.sheetRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 5,
      inactiveTrackColor: AppSurfaces.divider,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppInk.strong,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        color: AppSurfaces.card,
      ),
    ),
  );
}
