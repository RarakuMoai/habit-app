import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import 'model.dart';
import 'page.dart';

class EntryPreviewApp extends StatelessWidget {
  const EntryPreviewApp({
    super.key,
    required this.model,
    this.onAudio,
    this.onVoice,
    this.coverAsset = 'assets/scenes/home/home_day.webp',
    this.coverContainsMascot = false,
  });
  final EntryPreviewModel model;
  final Future<void> Function(bool enabled, bool room)? onAudio;
  final VoidCallback? onVoice;
  final String coverAsset;
  final bool coverContainsMascot;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: model.language == 'system' ? null : Locale(model.language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (locales, supported) {
        for (final locale in locales ?? <Locale>[]) {
          if (locale.languageCode == 'zh') return const Locale('zh');
          if (locale.languageCode == 'en') return const Locale('en');
        }
        return const Locale('en');
      },
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: AppSurfaces.card,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppInk.strong,
          surface: AppSurfaces.card,
        ),
        textTheme: const TextTheme(bodyMedium: TextStyle(color: AppInk.strong)),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppSurfaces.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppCardStyle.sheetRadius),
            ),
          ),
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: model.reduceMotion || media.disableAnimations,
            textScaler: model.textScale == null
                ? media.textScaler
                : TextScaler.linear(model.textScale!),
          ),
          child: child!,
        );
      },
      home: EntryPreviewPage(
        model: model,
        onAudio: onAudio,
        onVoice: onVoice,
        coverAsset: coverAsset,
        coverContainsMascot: coverContainsMascot,
      ),
    ),
  );
}
