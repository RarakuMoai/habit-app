// Entry's asynchronous visual gate must protect real MainPage presentation.
// Like logical_day_rollover_test, this mounts MainPage and drives its barriers
// without initializing native audio. The existing 2.8 s BGM warm-up is drained
// only after unmount; quietArrival still exercises the real daily reward write.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/story_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() complete) async {
  for (var i = 0; i < 50 && !complete(); i++) {
    await tester.pump();
  }
  expect(complete(), isTrue);
  expect(tester.takeException(), isNull);
}

Future<void> _resume(WidgetTester tester, dynamic state) async {
  var completed = false;
  final resumed = state.debugHandleResumed() as Future<void>;
  unawaited(resumed.then((_) => completed = true));
  await _pumpUntil(tester, () => completed);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 12));
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    PreferenceWriteGuard.debugReset();
    MascotPersona.voiceMuted = true;
    MascotPanelPrefs.openValue.value = 0;
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    StoryStore.pendingReveal.value = [];
    StoryEvents.debugCatalog = const [];
    final today = LogicalDate.stringFor(
      DateTime.now(),
      LogicalDate.defaultHour,
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.onboardingDone: true,
      PrefsKeys.lastOpenDate: today,
      PrefsKeys.coinBalance: 128,
      // No coinLastLoginDate: a reward really is available behind the gate.
      PrefsKeys.habits: jsonEncode([
        {
          'id': 'entry-gate',
          'name': '閱讀',
          'createdAt': today,
          'frequency': 'daily',
          'done': false,
        },
      ]),
    });
    prefs = await SharedPreferences.getInstance();
    await CoinService.load();
    await LogicalDayCoordinator.instance.start();
  });

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
    PreferenceWriteGuard.debugReset();
    MascotPersona.resetToIdle();
    MascotPersona.voiceMuted = false;
    StoryStore.pendingReveal.value = [];
    StoryEvents.debugCatalog = null;
    CoinService.dailyRewardShowing.value = false;
  });

  Future<({Completer<bool> gate, dynamic state})> mount(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<bool>();
    var requested = false;
    await tester.pumpWidget(
      l10nTestApp(
        home: MainPage(
          quietArrival: true,
          onEntryReady: () {
            requested = true;
            return gate.future;
          },
        ),
      ),
    );
    await _pumpUntil(tester, () => requested);
    return (gate: gate, state: tester.state(find.byType(MainPage)) as dynamic);
  }

  void expectNoReward() {
    expect(prefs.getString(PrefsKeys.coinLastLoginDate), isNull);
    expect(prefs.getInt(PrefsKeys.coinBalance), 128);
    expect(CoinService.dailyRewardShowing.value, isFalse);
  }

  for (final admitted in [true, false]) {
    testWidgets(
      'arrival result=$admitted gates reward and cannot be bypassed by resume',
      (tester) async {
        final entry = await mount(tester);
        expectNoReward();
        // A real resume can arrive while the parent is decoding the room.
        await _resume(tester, entry.state);
        expectNoReward();
        entry.gate.complete(admitted);
        if (admitted) {
          await _pumpUntil(
            tester,
            () => prefs.getInt(PrefsKeys.coinBalance)! > 128,
          );
          expect(prefs.getString(PrefsKeys.coinLastLoginDate), isNotNull);
        } else {
          await tester.pump();
          await _resume(tester, entry.state);
          expectNoReward();
        }
        await _unmount(tester);
      },
    );
  }

  testWidgets(
    'disposed Main ignores late successful arrival without rewarding',
    (tester) async {
      final entry = await mount(tester);
      expectNoReward();
      await tester.pumpWidget(const SizedBox.shrink());
      entry.gate.complete(true);
      await tester.pump();
      expectNoReward();
      await _unmount(tester);
    },
  );
}
