import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/advanced_settings_page.dart';
import 'package:habit_app/pages/data_deletion_page.dart';
import 'package:habit_app/pages/feature_settings_page.dart';
import 'package:habit_app/pages/profile_edit_page.dart';
import 'package:habit_app/pages/review_page.dart';
import 'package:habit_app/pages/settings_page.dart';
import 'package:habit_app/pages/story_reveal_page.dart';
import 'package:habit_app/pages/wardrobe_page.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_catalog.dart';
import 'package:habit_app/utils/wardrobe_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Short-screen regression: production-width page parents, real English copy,
// maximum production text scale, and reduced-motion state.
void main() {
  Future<void> pumpCompact(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.userNickname: 'Robin',
      PrefsKeys.mascotName: 'Tumi',
      PrefsKeys.userHeight: 165.0,
      PrefsKeys.userWeight: 55.0,
      PrefsKeys.timerEnabled: true,
      PrefsKeys.waterEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.familyEnabled: true,
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Nunito',
          scaffoldBackgroundColor: AppSurfaces.canvas,
          colorScheme: ColorScheme.fromSeed(seedColor: AppPalette.brand),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: page,
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  for (final entry in <String, Widget>{
    'settings': const SettingsPage(),
    'features': const FeatureSettingsPage(),
    'advanced settings': const AdvancedSettingsPage(),
    'data deletion': const DataDeletionPage(),
    'profile editing': const ProfileEditPage(),
    'review': const ReviewPage(),
  }.entries) {
    testWidgets('${entry.key}: 320 × 568, English at 1.3 remains scrollable', (
      tester,
    ) async {
      await pumpCompact(tester, entry.value);
      final scroller = find.byType(Scrollable).first;
      final state = tester.state<ScrollableState>(scroller);
      while (state.position.pixels < state.position.maxScrollExtent) {
        state.position.jumpTo(
          (state.position.pixels + 180).clamp(
            0,
            state.position.maxScrollExtent,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('wardrobe: compact English categories and outfit actions fit', (
    tester,
  ) async {
    WardrobeStore.reset();
    AudioSettingsService.musicMuted.value = true;
    MascotPanelPrefs.openValue.value = 1;
    addTearDown(() => AudioSettingsService.musicMuted.value = false);
    await pumpCompact(tester, const WardrobePage());
    expect(find.text('Looks'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Memories'), findsOneWidget);
    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Memories'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('story reveal: reduced motion makes the full caption readable', (
    tester,
  ) async {
    final event = storyEventById('comeback');
    await pumpCompact(
      tester,
      StoryRevealPage(event: event, date: DateTime(2026, 9, 10)),
    );
    for (final line in event.pages.first.captions) {
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text(line),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
      expect(opacity.duration, Duration.zero);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
