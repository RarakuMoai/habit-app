import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/l10n/app_localizations.dart';
import 'package:habit_app/pages/onboarding_page.dart';
import 'package:habit_app/utils/app_theme.dart';
import 'package:habit_app/utils/audio_settings_service.dart';
import 'package:habit_app/utils/bgm_service.dart';
import 'package:habit_app/utils/companion_story_progress.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/widgets/audio_control_button.dart';
import 'package:habit_app/widgets/mascot_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'shared_preferences_delay_test_helper.dart';
import 'shared_preferences_failure_test_helper.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, String value) async {
  final finder = _key(value);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _open(
  WidgetTester tester, {
  bool preview = false,
  Future<bool> Function(bool)? replay,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('zh', 'TW'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    OnboardingPage(preview: preview, onReplayFinished: replay),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      routes: {
        '/home': (context) => Scaffold(
          body: Text('home:${ModalRoute.of(context)?.settings.arguments}'),
        ),
      },
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _toLast(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await _press(tester, 'onboarding-primary');
  }
}

Map<String, Object?> _values(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
  await CompanionStoryProgress.instance.resetForTesting();
}

void main() {
  setUp(() async {
    LogicalDayCoordinator.debugInstance = null;
    SharedPreferences.setMockInitialValues({
      PrefsKeys.musicMuted: true,
      PrefsKeys.sfxMuted: true,
      PrefsKeys.mascotName: '小雲',
      PrefsKeys.userNickname: '小晴',
    });
    AudioSettingsService.musicMuted.value = true;
    AudioSettingsService.sfxMuted.value = true;
    await CompanionStoryProgress.instance.resetForTesting();
  });

  testWidgets('six immediate scenes finish setup and replace with quiet home', (
    tester,
  ) async {
    await _open(tester);
    expect(_key('onboarding-scene-arrival'), findsOneWidget);
    expect(find.byType(MascotStage), findsNothing);
    expect(find.byType(AudioControlButton), findsOneWidget);
    await _press(tester, 'onboarding-primary');
    expect(find.byType(MascotStage), findsOneWidget);
    await _press(tester, 'onboarding-primary');
    await _press(tester, 'onboarding-primary');
    await tester.enterText(_key('onboarding-mascot-name'), '  Sunshine  ');
    await _press(tester, 'onboarding-primary');
    await tester.enterText(_key('onboarding-nickname'), '  ');
    await _press(tester, 'onboarding-primary');
    await _press(tester, 'onboarding-primary');
    expect(find.text('home:onboarding-arrival'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.onboardingDone), isTrue);
    expect(prefs.getInt(PrefsKeys.onboardingStoryVersion), 1);
    expect(prefs.getString(PrefsKeys.mascotName), 'Sunshine');
    expect(prefs.containsKey(PrefsKeys.userNickname), isFalse);
    expect(MascotName.value, 'Sunshine');
    for (final key in [
      PrefsKeys.waterEnabled,
      PrefsKeys.timerEnabled,
      PrefsKeys.familyEnabled,
      PrefsKeys.weightTrackingEnabled,
    ]) {
      expect(prefs.getBool(key), isTrue);
    }
    expect(prefs.containsKey(PrefsKeys.habits), isFalse);
    expect(
      CompanionStoryProgress.instance.state.completed.keys,
      contains('story_01'),
    );
    expect(
      CompanionStoryProgress.instance.state.completed['story_01']!.read,
      isTrue,
    );
    await _dispose(tester);
  });

  testWidgets(
    'preview edits local names but never writes or invokes callbacks',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final before = _values(prefs);
      final name = MascotName.value;
      final music = BgmService.instance.loadedAsset;
      var callbacks = 0;
      await _open(
        tester,
        preview: true,
        replay: (_) async {
          callbacks++;
          return true;
        },
      );
      expect(find.byType(AudioControlButton), findsNothing);
      for (var i = 0; i < 3; i++) {
        await _press(tester, 'onboarding-primary');
      }
      expect(
        tester
            .widget<TextField>(_key('onboarding-mascot-name'))
            .controller!
            .text,
        '小雲',
      );
      await tester.enterText(_key('onboarding-mascot-name'), '預覽');
      await _press(tester, 'onboarding-primary');
      await tester.enterText(_key('onboarding-nickname'), '預覽玩家');
      await _press(tester, 'onboarding-primary');
      await _press(tester, 'onboarding-primary');
      expect(find.text('open'), findsOneWidget);
      expect(callbacks, 0);
      expect(_values(prefs), before);
      expect(MascotName.value, name);
      expect(BgmService.instance.loadedAsset, music);
      expect(AudioSettingsService.musicMuted.value, isTrue);
      expect(AudioSettingsService.sfxMuted.value, isTrue);
      await _dispose(tester);
    },
  );

  testWidgets('replay reads saved names and only actual finish marks read', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final before = _values(prefs);
    final calls = <bool>[];
    await _open(
      tester,
      replay: (skipped) async {
        calls.add(skipped);
        return true;
      },
    );
    expect(find.byType(AudioControlButton), findsNothing);
    for (var i = 0; i < 3; i++) {
      await _press(tester, 'onboarding-primary');
    }
    expect(find.byType(TextField), findsNothing);
    expect(_key('onboarding-saved-name'), findsOneWidget);
    expect(tester.widget<Text>(_key('onboarding-saved-name')).data, '小雲');
    await _press(tester, 'onboarding-primary');
    expect(tester.widget<Text>(_key('onboarding-saved-name')).data, '小晴');
    await _press(tester, 'onboarding-primary');
    expect(calls, isEmpty);
    await _press(tester, 'onboarding-primary');
    expect(calls, [false]);
    expect(_values(prefs), before);
    await _dispose(tester);
  });

  for (final action in ['onboarding-back', 'onboarding-skip']) {
    testWidgets('replay $action closes without completion', (tester) async {
      var callbacks = 0;
      await _open(
        tester,
        replay: (_) async {
          callbacks++;
          return true;
        },
      );
      await _press(tester, action);
      expect(find.text('open'), findsOneWidget);
      expect(callbacks, 0);
      await _dispose(tester);
    });
  }

  testWidgets('normal skip records handled unread first meeting', (
    tester,
  ) async {
    await _open(tester);
    await _press(tester, 'onboarding-skip');
    expect(find.text('home:onboarding-arrival'), findsOneWidget);
    final state = CompanionStoryProgress.instance.state;
    expect(state.completed.keys, contains('story_01'));
    expect(state.completed['story_01']!.read, isFalse);
    expect(state.days, 1);
    await _dispose(tester);
  });

  testWidgets(
    'replay failed finish retries and ignores double taps while saving',
    (tester) async {
      final pending = Completer<bool>();
      var calls = 0;
      await _open(
        tester,
        replay: (_) {
          calls++;
          return calls == 1 ? pending.future : Future.value(true);
        },
      );
      await _toLast(tester);
      await _press(tester, 'onboarding-primary');
      await tester.tap(_key('onboarding-primary'));
      await tester.tap(_key('onboarding-skip'));
      await _settle(tester);
      expect(calls, 1);
      expect(
        tester.widget<IconButton>(_key('onboarding-back')).onPressed,
        isNull,
      );
      pending.complete(false);
      await _settle(tester);
      expect(_key('onboarding-error'), findsOneWidget);
      await _press(tester, 'onboarding-primary');
      expect(calls, 2);
      expect(find.text('open'), findsOneWidget);
      await _dispose(tester);
    },
  );

  for (final throws in [false, true]) {
    testWidgets('normal save failure keeps intro and retries, throws=$throws', (
      tester,
    ) async {
      final fail = installFailFirstWriteStore(
        'flutter.${PrefsKeys.onboardingDone}',
        throwSynchronously: throws,
      );
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = fail.delegate,
      );
      await _open(tester);
      await _press(tester, 'onboarding-skip');
      expect(fail.didFail, isTrue);
      expect(_key('onboarding-error'), findsOneWidget);
      expect(find.text('home:onboarding-arrival'), findsNothing);
      await _press(tester, 'onboarding-primary');
      expect(find.text('home:onboarding-arrival'), findsOneWidget);
      expect(CompanionStoryProgress.instance.state.days, 1);
      await _dispose(tester);
    });
  }

  testWidgets('normal finish waits for the current logical day', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 11, 3, 59);
    final coordinator = LogicalDayCoordinator(clock: () => now);
    LogicalDayCoordinator.debugInstance = coordinator;
    await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);
    expect(coordinator.stamp.value!.logicalDate, '2026-09-10');
    await _open(tester);
    now = DateTime(2026, 9, 11, 4, 1);
    await _press(tester, 'onboarding-skip');
    expect(find.text('home:onboarding-arrival'), findsOneWidget);
    final completion =
        CompanionStoryProgress.instance.state.completed['story_01'];
    expect(completion!.firstCompletedAt, '2026-09-11');
    expect(CompanionStoryProgress.instance.state.creditedDayKeys, {
      '2026-09-11',
    });
    await _dispose(tester);
  });

  testWidgets('normal back restores the previous scene without initializing', (
    tester,
  ) async {
    await _open(tester);
    for (var i = 0; i < 3; i++) {
      await _press(tester, 'onboarding-primary');
    }
    await tester.enterText(_key('onboarding-mascot-name'), 'Sunbeam');
    await _press(tester, 'onboarding-primary');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_key('onboarding-scene-mascot_name'), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('onboarding-mascot-name')).controller!.text,
      'Sunbeam',
    );
    expect(
      (await SharedPreferences.getInstance()).getBool(PrefsKeys.onboardingDone),
      isNull,
    );
    expect(CompanionStoryProgress.instance.state.completed, isEmpty);
    await _dispose(tester);
  });

  testWidgets(
    'normal pending save blocks skip, back and duplicate initialization',
    (tester) async {
      final delayed = installDelayFirstWriteStore(
        'flutter.${PrefsKeys.onboardingDone}',
      );
      addTearDown(delayed.restore);
      await _open(tester);
      await _press(tester, 'onboarding-skip');
      expect(delayed.didDelay, isTrue);
      expect(
        tester.widget<FilledButton>(_key('onboarding-primary')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_key('onboarding-skip')).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_key('onboarding-story'), findsOneWidget);
      delayed.release();
      await _settle(tester);
      expect(find.text('home:onboarding-arrival'), findsOneWidget);
      expect(CompanionStoryProgress.instance.state.days, 1);
      await _dispose(tester);
    },
  );
}
