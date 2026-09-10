// Native first-run review. Launches the real app root with an empty, in-memory
// profile and completes all nine onboarding steps. Run on an iOS simulator only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/main.dart' as app;
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/pages/story_reveal_page.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('First-run onboarding: all nine steps, choices and saved profile', (
    tester,
  ) async {
    // Mock preferences are process-local. No installed app's user data is read.
    SharedPreferences.setMockInitialValues({
      PrefsKeys.onboardingDone: false,
      PrefsKeys.unitSystem: 'metric',
      PrefsKeys.musicMuted: true,
      PrefsKeys.sfxMuted: true,
      // Keep the final landing screen deterministic; reward presentation has its
      // own integration tests and is unrelated to the first-run form.
      PrefsKeys.coinLastLoginDate: DateTime.now()
          .toIso8601String()
          .split('T')
          .first,
    });
    app.main();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(OnboardingPage).evaluate().isNotEmpty) break;
    }
    expect(find.byType(OnboardingPage), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(OnboardingPage)),
    );
    final output = Directory('${Directory.systemTemp.path}/experience-review');
    await output.create(recursive: true);
    final lifecycleEvents = <String>[];
    final lifecycleListener = AppLifecycleListener(
      onStateChange: (state) => lifecycleEvents.add(state.name),
    );
    addTearDown(lifecycleListener.dispose);
    final screenshotDigests = <String, String>{};

    void requireForeground(String phase) {
      final state = binding.lifecycleState;
      debugPrint(
        'REVIEW_FOREGROUND $phase lifecycle=${state?.name} '
        'framesEnabled=${binding.framesEnabled} '
        'sendFramesToEngine=${binding.sendFramesToEngine}',
      );
      expect(
        state,
        AppLifecycleState.resumed,
        reason:
            '$phase: native app is not foreground-active. Dismiss the '
            'simulator system alert and rerun; pumping the Flutter tree does '
            'not prove that UIKit is presenting those frames.',
      );
      expect(
        binding.framesEnabled && binding.sendFramesToEngine,
        isTrue,
        reason: '$phase: the native raster surface must receive frames.',
      );
    }

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      requireForeground('before-$name');
      await settle();
      requireForeground('capture-$name');
      final bytes = await binding.takeScreenshot(name);
      requireForeground('after-$name');
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      debugPrint('REVIEW_SCREENSHOT ${output.path}/$name.png');
      // Decode first: distinct PNG metadata must not disguise identical pixels.
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      late final String digest;
      try {
        final pixels = await frame.image.toByteData();
        expect(pixels, isNotNull, reason: '$name could not decode pixels');
        digest = sha256.convert(pixels!.buffer.asUint8List()).toString();
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
      final previous = screenshotDigests[digest];
      debugPrint('REVIEW_PIXELS $name sha256=$digest');
      expect(
        previous,
        isNull,
        reason:
            '$name exactly repeats $previous. Different onboarding '
            'states must render different native images; possible frozen '
            'UIKit surface or a system alert outside the app window.',
      );
      screenshotDigests[digest] = name;
      expect(tester.takeException(), isNull, reason: name);
    }

    Future<void> diagnose(String phase, {bool screenshot = false}) async {
      // This test seeded process-local preferences above. Only whitelist its
      // non-secret profile and first-memory values, never dump all app storage.
      final prefs = await SharedPreferences.getInstance();
      final routeSummaries = <String>{};
      for (final element
          in find.byType(Scaffold, skipOffstage: false).evaluate()) {
        final route = ModalRoute.of(element);
        if (route == null) continue;
        routeSummaries.add(
          '${route.runtimeType}:${route.settings.name} '
          'current=${route.isCurrent} active=${route.isActive}',
        );
      }
      final snapshot = <String, Object?>{
        'phase': phase,
        'lifecycle': binding.lifecycleState?.name,
        'lifecycleEvents': lifecycleEvents,
        'framesEnabled': binding.framesEnabled,
        'sendFramesToEngine': binding.sendFramesToEngine,
        'onboardingVisible': find.byType(OnboardingPage).evaluate().length,
        'mainVisible': find.byType(app.MainPage).evaluate().length,
        'mainIncludingOffstage': find
            .byType(app.MainPage, skipOffstage: false)
            .evaluate()
            .length,
        'navigationVisible': find
            .byKey(const ValueKey('main_navigation'))
            .evaluate()
            .length,
        'navigationIncludingOffstage': find
            .byKey(const ValueKey('main_navigation'), skipOffstage: false)
            .evaluate()
            .length,
        'visibleMemoryIds': [
          for (final element in find.byType(StoryRevealPage).evaluate())
            (element.widget as StoryRevealPage).event.id,
        ],
        'routes': routeSummaries.toList(),
        'fixturePreferences': {
          for (final key in [
            PrefsKeys.onboardingDone,
            PrefsKeys.mascotName,
            PrefsKeys.userNickname,
            PrefsKeys.waterEnabled,
            PrefsKeys.timerEnabled,
            PrefsKeys.familyEnabled,
            PrefsKeys.weightTrackingEnabled,
            PrefsKeys.userHeight,
            PrefsKeys.userWeight,
            PrefsKeys.userBirthday,
            PrefsKeys.habits,
            PrefsKeys.storyUnlocked,
            PrefsKeys.storyPendingReveal,
            PrefsKeys.coinLastLoginDate,
          ])
            key: prefs.get(key),
        },
      };
      final encoded = const JsonEncoder.withIndent('  ').convert(snapshot);
      final path = '${output.path}/onboarding-$phase.json';
      await File(path).writeAsString(encoded);
      debugPrint('REVIEW_DIAGNOSTIC $path\n$encoded');
      if (screenshot) {
        final name = 'onboarding-failure-$phase';
        try {
          final bytes = await binding.takeScreenshot(name);
          final path = '${output.path}/$name.png';
          await File(path).writeAsBytes(bytes);
          debugPrint('REVIEW_SCREENSHOT $path');
        } catch (error) {
          debugPrint('REVIEW_DIAGNOSTIC screenshot failed: $error');
        }
      }
    }

    Future<void> waitFor(Finder target, String phase) async {
      for (var i = 0; i < 40; i++) {
        if (target.evaluate().isNotEmpty) return;
        await tester.pump(const Duration(milliseconds: 250));
      }
      await diagnose(phase, screenshot: true);
      expect(target, findsOneWidget, reason: phase);
    }

    Future<void> primary() async {
      requireForeground('primary-action');
      await tester.tap(find.byKey(const ValueKey('onboarding-primary')));
      await settle();
    }

    Future<void> enter(String id, String value) async {
      final field = find.byKey(ValueKey('onboarding-$id'));
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.tap(field);
      await tester.enterText(field, value);
      await settle();
    }

    // The existing welcome words can be advanced explicitly, preserving the
    // character introduction without requiring the capture to race the typing.
    for (
      var i = 0;
      i < 8 && find.text(l10n.obContinue).evaluate().isEmpty;
      i++
    ) {
      await primary();
    }
    await capture('onboarding-01-welcome');
    await primary();
    await enter('mascot-name', '兔咪');
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('onboarding-02-name');
    await primary();
    await enter('nickname', '小日');
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('onboarding-03-nickname');
    await primary();
    await capture('onboarding-04-water');
    await primary();
    await capture('onboarding-05-focus');
    await primary();
    await capture('onboarding-06-family');
    await primary();
    for (final name in ['刷牙', '閱讀']) {
      final card = find.byKey(ValueKey('onboarding-habit-$name'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await settle();
    }
    final scroller = find.byType(SingleChildScrollView).hitTestable();
    await tester.drag(scroller, const Offset(0, 800));
    await capture('onboarding-07-habits');
    final frequency = find.byKey(const ValueKey('weekly-stepper-閱讀'));
    await tester.ensureVisible(frequency);
    await capture('onboarding-07-frequency');
    await primary();
    await capture('onboarding-08-profile');
    final gender = find.text(l10n.genderFemale);
    await tester.ensureVisible(gender);
    await tester.pump();
    await tester.tap(gender);
    await enter('height', '168');
    await capture('onboarding-08-keyboard');
    await enter('weight', '60');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle();
    final birthday = find.byKey(const ValueKey('onboarding-birthday'));
    await tester.ensureVisible(birthday);
    await tester.pump();
    await tester.tap(birthday);
    await settle();
    await tester.tap(find.text(l10n.bpDone).hitTestable());
    await settle();
    await primary();
    expect(find.text('9 / 9'), findsOneWidget);
    await capture('onboarding-09-ready');
    await primary();
    await diagnose('after-finish');

    // A real first-run profile creates habits. HomePage therefore unlocks
    // first_habit, and MainPage presents its full-screen memory after 1100ms.
    // The two-second settle above can already put /home offstage. The unit flow
    // uses a stub /home route and never executes this intentional presentation.
    final memory = find.byType(StoryRevealPage);
    await waitFor(memory, 'first-memory-not-shown');
    expect(tester.widget<StoryRevealPage>(memory).event.id, 'first_habit');
    expect(find.byType(OnboardingPage), findsNothing);
    expect(
      find.byKey(const ValueKey('main_navigation'), skipOffstage: false),
      findsOneWidget,
      reason: 'The completed home route exists beneath the first memory.',
    );
    await capture('onboarding-10-first-memory');
    final maxTaps =
        tester.widget<StoryRevealPage>(memory).event.pages.length * 2 + 1;
    for (var i = 0; i < maxTaps && memory.evaluate().isNotEmpty; i++) {
      // The first tap may reveal unfinished captions; later taps advance or
      // close the final page, following the production interaction.
      await tester.tap(memory.hitTestable());
      await settle();
    }
    if (memory.evaluate().isNotEmpty) {
      await diagnose('first-memory-did-not-close', screenshot: true);
      expect(memory, findsNothing);
    }
    await waitFor(
      find.byKey(const ValueKey('main_navigation')),
      'home-navigation-not-shown',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
    expect(prefs.getString(PrefsKeys.userNickname), '小日');
    expect(prefs.getString(PrefsKeys.mascotName), '兔咪');
    expect(prefs.getDouble(PrefsKeys.userHeight), 168);
    expect(prefs.getDouble(PrefsKeys.userWeight), 60);
    expect(prefs.getString(PrefsKeys.userBirthday), isNotNull);
    expect(prefs.getBool(PrefsKeys.familyEnabled), isTrue);
    final habits = (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
        .cast<Map<String, dynamic>>();
    expect(habits.singleWhere((h) => h['name'] == '閱讀')['weeklyTarget'], 3);
    await capture('onboarding-11-home');
    debugPrint('REVIEW_COMPLETE ${output.path}');
  });
}
