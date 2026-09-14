import 'package:flutter/material.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/widgets/entry_loading_scene.dart';

void main() => runApp(const EntryLoadingPreviewApp());

/// A stable native-size surface for reviewing the short startup wallpaper.
///
/// The production entrance lasts only 1320 ms, shorter than a simulator
/// screenshot round trip. Keeping this target on the real painter makes color
/// and symbol reviews repeatable without changing production timing.
class EntryLoadingPreviewApp extends StatelessWidget {
  const EntryLoadingPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
      backgroundColor: EntrySceneMotion.paper,
      body: EntryLoadingScene(label: '', showStatus: false),
    ),
  );
}
