import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/pages/weight_page.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/water_entries.dart';
import 'package:habit_app/utils/weight_records.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';
import 'shared_preferences_failure_test_helper.dart';

String _logicalToday() =>
    LogicalDate.stringFor(DateTime.now(), LogicalDate.defaultHour);

List<Map<String, dynamic>> _storedHabits(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(l10nTestApp(home: page));
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator();
    PreferenceWriteGuard.debugReset();
    LogicalDate.notifier.value = LogicalDate.defaultHour;
  });

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
    PreferenceWriteGuard.debugReset();
    LogicalDate.notifier.value = LogicalDate.defaultHour;
  });

  testWidgets('Water legacy mirror 失敗後重試只加入一杯', (tester) async {
    final today = _logicalToday();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: LogicalDate.defaultHour,
      PrefsKeys.waterCupMl: 250,
      PrefsKeys.waterGoalMl: 2000,
    });
    await _pumpPage(tester, const WaterPage());
    final state = tester.state(find.byType(WaterPage)) as dynamic;
    expect(state.debugTotalMl, 0);

    final failingStore = installFailFirstWriteStore(
      'flutter.${PrefsKeys.waterDay(today)}',
      throwSynchronously: true,
    );
    expect(await state.debugAddCup() as bool, isFalse);
    expect(failingStore.didFail, isTrue);

    var prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      parseWaterEntries(
        prefs.getString(PrefsKeys.waterEntries(today)),
        maxEntryMl: 12000, // units-ok
      ),
      isEmpty,
      reason: 'canonical commit marker 不能早於可能失敗的 legacy mirror',
    );
    expect(state.debugTotalMl, 0, reason: '失敗的 mutation 不得先改 UI');

    expect(await state.debugAddCup() as bool, isTrue);
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final entries = parseWaterEntries(
      prefs.getString(PrefsKeys.waterEntries(today)),
      maxEntryMl: 12000, // units-ok
    );
    expect(entries, hasLength(1));
    expect(entries.single.ml, 250);
    expect(state.debugTotalMl, 250);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Water canonical 最終寫入失敗後重開不會復活該杯', (tester) async {
    final today = _logicalToday();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: LogicalDate.defaultHour,
      PrefsKeys.waterCupMl: 250,
      PrefsKeys.waterGoalMl: 2000,
    });
    await _pumpPage(tester, const WaterPage());
    var state = tester.state(find.byType(WaterPage)) as dynamic;
    expect(state.debugTotalMl, 0);

    final failingStore = installFailFirstWriteStore(
      'flutter.${PrefsKeys.waterEntries(today)}',
      throwSynchronously: true,
    );
    expect(await state.debugAddCup() as bool, isFalse);
    expect(failingStore.didFail, isTrue);

    var prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.containsKey(PrefsKeys.waterEntries(today)), isTrue);
    expect(
      parseWaterEntries(
        prefs.getString(PrefsKeys.waterEntries(today)),
        maxEntryMl: 12000, // units-ok
      ),
      isEmpty,
      reason: 'canonical 空基準必須保留，不能把部分 mirror 當成成功 mutation',
    );
    expect(prefs.getInt(PrefsKeys.waterDay(today)), 1);
    expect(state.debugTotalMl, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _pumpPage(tester, const WaterPage());
    state = tester.state(find.byType(WaterPage)) as dynamic;
    expect(
      state.debugTotalMl,
      0,
      reason: '重開後 canonical [] 必須壓過 legacy mirror',
    );

    expect(await state.debugAddCup() as bool, isTrue);
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final entries = parseWaterEntries(
      prefs.getString(PrefsKeys.waterEntries(today)),
      maxEntryMl: 12000, // units-ok
    );
    expect(entries, hasLength(1));
    expect(entries.single.ml, 250);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Water goal callback 暫時失敗會以 durable state 自動重試', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: LogicalDate.defaultHour,
      PrefsKeys.waterCupMl: 500,
      PrefsKeys.waterGoalMl: 500,
    });
    final events = <bool>[];
    var reachedAttempts = 0;

    Future<void> onGoalChanged(bool reached) async {
      events.add(reached);
      if (reached && reachedAttempts++ == 0) {
        throw StateError('transient goal sync failure');
      }
    }

    await _pumpPage(tester, WaterPage(onGoalStatusChanged: onGoalChanged));
    expect(events, [false]);
    final state = tester.state(find.byType(WaterPage)) as dynamic;

    expect(await state.debugAddCup() as bool, isTrue);
    expect(state.debugTotalMl, 500);
    expect(events, [false, true, true]);
    expect(reachedAttempts, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Water goal callbacks 依 mutation 順序串行，不會 true/false 重疊', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: LogicalDate.defaultHour,
      PrefsKeys.waterCupMl: 500,
      PrefsKeys.waterGoalMl: 500,
    });
    final releaseReached = Completer<void>();
    final events = <bool>[];
    var activeCallbacks = 0;
    var maxActiveCallbacks = 0;

    Future<void> onGoalChanged(bool reached) async {
      events.add(reached);
      activeCallbacks++;
      if (activeCallbacks > maxActiveCallbacks) {
        maxActiveCallbacks = activeCallbacks;
      }
      if (reached) await releaseReached.future;
      activeCallbacks--;
    }

    await _pumpPage(tester, WaterPage(onGoalStatusChanged: onGoalChanged));
    expect(events, [false], reason: '初始 load 會 force 回報未達標');
    final state = tester.state(find.byType(WaterPage)) as dynamic;

    final add = state.debugAddCup() as Future<bool>;
    for (var i = 0; i < 20 && state.debugTotalMl != 500; i++) {
      await tester.pump();
    }
    for (var i = 0; i < 20 && events.length < 2; i++) {
      await tester.pump();
    }
    expect(events, [false, true]);
    expect(activeCallbacks, 1);

    final remove = state.debugRemoveCup() as Future<bool>;
    for (var i = 0; i < 20 && state.debugTotalMl != 0; i++) {
      await tester.pump();
    }
    expect(events, [
      false,
      true,
    ], reason: 'false callback 必須排在仍未完成的 true callback 後面');
    expect(maxActiveCallbacks, 1);

    releaseReached.complete();
    expect(await add, isTrue);
    expect(await remove, isTrue);
    expect(events, [false, true, false]);
    expect(maxActiveCallbacks, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Weight records 已落地但 habit sync 失敗時，重試會修復 linked habit', (
    tester,
  ) async {
    final today = _logicalToday();
    final record = <String, dynamic>{
      'date': today,
      'time': '08:00',
      'weight': 60.0,
    };
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: LogicalDate.defaultHour,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.weightRecords: jsonEncode([record]),
      PrefsKeys.habits: jsonEncode([
        {
          'id': 'weight',
          'name': '體重紀錄',
          'done': true,
          'frequency': 'daily',
          'createdAt': today,
        },
      ]),
    });
    await _pumpPage(tester, const WeightPage());
    final state = tester.state(find.byType(WeightPage)) as dynamic;
    expect(state.debugRecordCount, 1);

    final failingStore = installFailFirstWriteStore(
      'flutter.${PrefsKeys.habits}',
      throwSynchronously: true,
    );
    expect(await state.debugDeleteRecord(record) as bool, isFalse);
    expect(failingStore.didFail, isTrue);

    var prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      parseWeightRecords(prefs.getString(PrefsKeys.weightRecords)),
      isEmpty,
      reason: '第一輪 record commit 已成功，只有 derived habit 尚待修復',
    );
    expect(_storedHabits(prefs).single['done'], isTrue);
    expect(state.debugRecordCount, 1, reason: '整輪成功前 UI 保留舊快照');

    expect(await state.debugDeleteRecord(record) as bool, isTrue);
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      parseWeightRecords(prefs.getString(PrefsKeys.weightRecords)),
      isEmpty,
    );
    expect(_storedHabits(prefs).single['done'], isFalse);
    expect(state.debugRecordCount, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  });
}
