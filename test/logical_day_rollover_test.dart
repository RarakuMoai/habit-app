// 跨日在真實 widget 樹上的行為：MainPage 訂閱 coordinator → 先刷新喝水/體重的
// 自動完成旗標 → 再把 revision 傳給首頁 / 喝水頁 / 體重頁。
//
// 這裡釘住的是「使用者看得到的」那一層：畫面換成新一天、昨天的達標不會污染
// 今天、問候只出現一次、兔咪回到中性。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/main.dart';
import 'package:habit_app/pages/home/completion_presentation_controller.dart';
import 'package:habit_app/pages/home/greeting_banner.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/pages/water_page.dart';
import 'package:habit_app/pages/weight_page.dart';
import 'package:habit_app/utils/app_feedback.dart';
import 'package:habit_app/utils/coin_service.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/preference_write_guard.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';
import 'shared_preferences_failure_test_helper.dart';

class _FakeClock {
  DateTime now;
  _FakeClock(this.now);
  DateTime call() => now;
}

Map<String, dynamic> _habit(
  String name, {
  required String id,
  bool done = false,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'done': done,
    'frequency': 'daily',
    'createdAt': '2026-01-02',
  };
}

/// 昨天（07-31）兩個每日習慣完成了一個，連勝 4（跨日後應歸零）。
///
/// 兩個刻意的選擇：
/// 1. 不用「喝足夠的水」「體重紀錄」當預設資料——它們的勾選會被喝水／體重的
///    當日狀態覆寫（既有行為），會蓋掉這裡想觀察的跨日效果。
/// 2. 不讓每日習慣「全部完成」——那會掛上 all-done 慶祝層，而
///    `RoomSceneEffectsPainter._paintCompletionAura` 有個既有的 radial
///    gradient 參數錯誤，一畫就丟 ArgumentError。那是 all-done／VFX 的問題，
///    不在本 milestone 範圍內；連勝加一的結算路徑改由 coordinator 測試覆蓋。
Map<String, Object> _yesterdayPartlyDone({List<Map<String, dynamic>>? habits}) {
  return {
    PrefsKeys.lastOpenDate: '2026-07-31',
    PrefsKeys.streak: 4,
    PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
    PrefsKeys.habits: jsonEncode(
      habits ?? [_habit('走路', id: 'h1', done: true), _habit('閱讀', id: 'h2')],
    ),
    // 每日登入獎勵走真實日曆日；先標成今天已領，讓慶祝頁不要插進來。
    PrefsKeys.coinLastLoginDate: _calendarToday(),
  };
}

String _calendarToday() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

late _FakeClock _clock;

Future<void> _pumpMain(WidgetTester tester, DateTime at) async {
  _clock = _FakeClock(at);
  LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
    clock: _clock.call,
  );
  // 冷啟動 barrier：coordinator 先完成第一次驗證，MainPage / HomePage 才開始
  // 初始化（正式路徑在 _loadStartupState 裡 await 同一件事）。
  await LogicalDayCoordinator.instance.start();
  await tester.pumpWidget(l10nTestApp(home: const MainPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

/// 推進時鐘並讓 coordinator 重新驗證（等同前景邊界計時器醒來）。
Future<void> _crossTo(WidgetTester tester, DateTime at) async {
  _clock.now = at;
  await LogicalDayCoordinator.instance.ensureCurrent(
    trigger: LogicalDayTrigger.boundaryTimer,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 12));
}

/// 驅動需要 widget rebuild 才能完成的 barrier，並回傳 Future 的錯誤（若有）。
Future<Object?> _pumpUntilSettled(
  WidgetTester tester,
  Future<void> future, {
  required String reason,
}) async {
  var done = false;
  Object? error;
  unawaited(
    future.then<void>(
      (_) => done = true,
      onError: (Object e, StackTrace _) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 30 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: reason);
  return error;
}

List<Map<String, dynamic>> _storedHabits(SharedPreferences prefs) {
  return (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

HomePage _homeWidget(WidgetTester tester) =>
    tester.widget<HomePage>(find.byType(HomePage));

/// 進度用 state 的 getter 讀，不靠 find.text——同樣的「done / total」字串在
/// 進度列與分段標題各出現一次。
dynamic _homeState(WidgetTester tester) =>
    tester.state(find.byType(HomePage)) as dynamic;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
    PreferenceWriteGuard.debugReset();
    LogicalDate.notifier.value = LogicalDate.defaultHour;
    CoinService.dailyRewardShowing.value = false;
  });

  testWidgets('前景跨日：習慣數量不變、勾選全部重置、進度歸零', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-07-31');
    expect(_homeState(tester).dailyDoneCount, 1, reason: '跨日前顯示昨天的進度');

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-01');
    expect(_homeState(tester).dailyDoneCount, 0, reason: '新的一天進度歸零');
    expect((_homeState(tester).habits as List).length, 2);

    final prefs = await SharedPreferences.getInstance();
    final habits = _storedHabits(prefs);
    expect(habits.length, 2, reason: '不得出現重複習慣');
    expect(habits.every((h) => h['done'] == false), isTrue);
    expect(prefs.getInt(PrefsKeys.streak), 0, reason: '昨天沒有全完成 → 連勝歸零');

    await _teardownTree(tester);
  });

  testWidgets('coordinator 結算窗口內的舊日打勾會被拒絕，不寫進新日', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect((_homeState(tester).habits as List)[1]['done'], isFalse);

    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    final pending = LogicalDayCoordinator.instance.ensureCurrent(
      trigger: LogicalDayTrigger.boundaryTimer,
    );
    _homeState(tester).toggleHabit(1);
    await pending;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final prefs = await SharedPreferences.getInstance();
    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-01');
    expect((_homeState(tester).habits as List)[1]['done'], isFalse);
    expect(
      _storedHabits(prefs).every((habit) => habit['done'] == false),
      isTrue,
    );
    expect(prefs.getString(PrefsKeys.habitDoneDay('2026-08-01')), isNull);

    await _teardownTree(tester);
  });

  testWidgets('先接受的舊日寫入會排在跨日結算前，不會在 reset 後覆寫回來', (tester) async {
    SharedPreferences.setMockInitialValues(
      _yesterdayPartlyDone(
        habits: [
          _habit('走路', id: 'h1', done: true),
          _habit('閱讀', id: 'h2'),
          _habit('伸展', id: 'h3'),
        ],
      ),
    );
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    // 同一個 synchronous stack：先接受打勾並排 storage write，完全不 pump，
    // 緊接著開始 settlement。全域 FIFO 的位置必須在呼叫當下就保留。
    _homeState(tester).toggleHabit(1);
    expect((_homeState(tester).habits as List)[1]['done'], isTrue);
    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    await LogicalDayCoordinator.instance.ensureCurrent(
      trigger: LogicalDayTrigger.boundaryTimer,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      _storedHabits(prefs).every((habit) => habit['done'] == false),
      isTrue,
      reason: '舊日 snapshot 必須先落地，再由 settlement reset；不能反向超車',
    );
    expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect((_homeState(tester).habits as List)[1]['done'], isFalse);
    await _teardownTree(tester);
  });

  testWidgets('coordinator 發布後但子頁尚未 rebuild，舊 Home 的 tap 仍被拒絕', (tester) async {
    SharedPreferences.setMockInitialValues(
      _yesterdayPartlyDone(
        habits: [
          _habit('走路', id: 'h1', done: true),
          _habit('閱讀', id: 'h2'),
          _habit('伸展', id: 'h3'),
        ],
      ),
    );
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    final staleHomeState = _homeState(tester);

    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    await LogicalDayCoordinator.instance.ensureCurrent(
      trigger: LogicalDayTrigger.boundaryTimer,
    );
    // 刻意不 pump：Coordinator 已發布新 revision，但 Home widget 還持有舊 stamp。
    staleHomeState.toggleHabit(1);
    expect((staleHomeState.habits as List)[1]['done'], isFalse);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      _storedHabits(prefs).every((habit) => habit['done'] == false),
      isTrue,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect((_homeState(tester).habits as List)[1]['done'], isFalse);
    await _teardownTree(tester);
  });

  testWidgets('resume barrier 返回時，Main flags 與 Home 都已套用新 revision', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(_homeState(tester).dailyDoneCount, 1);

    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    final resumed = mainState.debugHandleResumed() as Future<void>;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await resumed;

    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-01');
    expect(_homeState(tester).dailyDoneCount, 0);
    expect(_homeState(tester).debugReloading, isFalse);

    await _teardownTree(tester);
  });

  testWidgets('Home 一次載入失敗會喚醒 barrier，修復後 resume 可重試成功', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.onboardingDate: '2026-01-01T00:00:00.000',
      PrefsKeys.habits: '{',
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    await _pumpMain(tester, DateTime(2026, 8, 1, 9));
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    final readinessError = await _pumpUntilSettled(
      tester,
      mainState.debugMainReady as Future<void>,
      reason: 'Home decode 失敗必須回報 Main，不得讓 startup barrier 永久等待',
    );
    expect(readinessError, isA<FormatException>());
    expect(tester.takeException(), isNull, reason: '失敗由 readiness barrier 接住');
    expect(_homeState(tester).isLoading, isTrue);
    expect(_homeState(tester).debugReloading, isFalse);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.habits,
      jsonEncode([_habit('修復後習慣', id: 'repaired')]),
    );
    final triggerBefore = _homeWidget(tester).reloadTrigger;
    final resumeError = await _pumpUntilSettled(
      tester,
      mainState.debugHandleResumed() as Future<void>,
      reason: 'storage 修復後，同一 logical day 的 resume 必須能重試 Home',
    );
    expect(resumeError, isNull);
    expect(_homeWidget(tester).reloadTrigger, triggerBefore + 1);
    expect(_homeState(tester).isLoading, isFalse);
    expect(_homeState(tester).debugReloading, isFalse);
    expect((_homeState(tester).habits as List).single['id'], 'repaired');

    await _teardownTree(tester);
  });

  testWidgets('損壞 marker 直接掛 MainPage 不會形成未處理 Future error', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: 'not-a-date',
      PrefsKeys.habits: jsonEncode([_habit('走路', id: 'h1')]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    _clock = _FakeClock(DateTime(2026, 8, 1, 9));
    LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
      clock: _clock.call,
    );

    await tester.pumpWidget(l10nTestApp(home: const MainPage()));
    await tester.pump();
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    final readinessError = await _pumpUntilSettled(
      tester,
      mainState.debugMainReady as Future<void>,
      reason: 'malformed marker 的 startup Future 必須有明確完成/失敗',
    );

    expect(readinessError, isA<FormatException>());
    expect(tester.takeException(), isNull);
    expect(CoinService.dailyRewardShowing.value, isFalse);

    await _teardownTree(tester);
  });

  testWidgets('settings 一次寫入失敗後，同 revision 會自動重排並完成', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.waterEnabled: true,
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.habits: jsonEncode([_habit('走路', id: 'walk')]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    final failingStore = installFailFirstWriteStore(
      'flutter.${PrefsKeys.habits}',
      throwSynchronously: true,
      failFirstRecoveryReload: true,
    );

    await _pumpMain(tester, DateTime(2026, 8, 1, 9));
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    final readinessError = await _pumpUntilSettled(
      tester,
      mainState.debugMainReady as Future<void>,
      reason: 'settings one-shot failure 後必須在同 revision 自動重試',
    );

    expect(readinessError, isNull);
    expect(failingStore.didFail, isTrue);
    expect(failingStore.didRecoveryReloadFail, isTrue);
    expect(find.byType(WaterPage, skipOffstage: false), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
      _storedHabits(prefs).any((habit) => habit['name'] == '喝足夠的水'),
      isTrue,
      reason: 'readiness 完成時第二次寫入必須已經落到 durable store，不只留在 cache',
    );
    expect(tester.takeException(), isNull);

    await _teardownTree(tester);
  });

  testWidgets('Water 非跨日刷新完成後，同日 resume 不會等待已消費的 trigger', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.waterEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.habits: jsonEncode([
        _habit('喝足夠的水', id: 'water'),
        _habit('體重紀錄', id: 'weight'),
      ]),
      PrefsKeys.weightRecords: jsonEncode([]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    await _pumpMain(tester, DateTime(2026, 8, 1, 9));
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    expect(
      await _pumpUntilSettled(
        tester,
        mainState.debugMainReady as Future<void>,
        reason: '初始 dependent reload 必須完成',
      ),
      isNull,
    );

    final waterFinder = find.byType(WaterPage, skipOffstage: false);
    final weightFinder = find.byType(WeightPage, skipOffstage: false);
    final waterState = tester.state(waterFinder) as dynamic;
    final reloadsBefore = waterState.debugReloadCount as int;

    // 體重資料變動只需要 Water 重算建議，不是 logical-day 變更。
    tester.widget<WeightPage>(weightFinder).onRecordsChanged!.call();
    for (
      var i = 0;
      i < 30 && waterState.debugReloadCount == reloadsBefore;
      i++
    ) {
      await tester.pump();
    }
    expect(waterState.debugReloadCount, reloadsBefore + 1);
    final incidentalTrigger = tester
        .widget<WaterPage>(waterFinder)
        .reloadTrigger;

    final resumeError = await _pumpUntilSettled(
      tester,
      mainState.debugHandleResumed() as Future<void>,
      reason: '同日 resume 不得等待已完成卻未記錄的 Water trigger',
    );
    expect(resumeError, isNull);
    expect(
      tester.widget<WaterPage>(waterFinder).reloadTrigger,
      incidentalTrigger,
      reason: '同日 resume 不應製造另一輪 reload 來解開 barrier',
    );
    expect(waterState.debugReloadCount, reloadsBefore + 1);

    await _teardownTree(tester);
  });

  testWidgets('前景跨日：今天的歷史清空、昨天的歷史原封不動', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(PrefsKeys.habitDoneDay('2026-07-31')),
      jsonEncode(['h1']),
      reason: '昨天的歷史是結算的輸入，絕不能被動到',
    );
    expect(
      prefs.getString(PrefsKeys.habitDoneDay('2026-08-01')),
      isNull,
      reason: '新的一天沒有完成，空集合不留空殼 key',
    );

    await _teardownTree(tester);
  });

  testWidgets('dayStartHour 讓日期回退時，不用目前 habits 覆寫過去歷史', (tester) async {
    const oldHistory = '["past-b","past-a"]';
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: 0,
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.habitDoneDay('2026-07-31'): oldHistory,
      PrefsKeys.habits: jsonEncode([
        _habit('現在已完成', id: 'current', done: true),
        _habit('尚未完成', id: 'pending'),
      ]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    await _pumpMain(tester, DateTime(2026, 8, 1, 1));
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    expect(
      await _pumpUntilSettled(
        tester,
        mainState.debugMainReady as Future<void>,
        reason: 'rollback 測試的初始 Main barrier 必須完成',
      ),
      isNull,
    );
    final prefs = await SharedPreferences.getInstance();
    final augustHistoryBefore = prefs.getString(
      PrefsKeys.habitDoneDay('2026-08-01'),
    );
    expect(augustHistoryBefore, jsonEncode(['current']));
    MascotPersona.setForContext(
      MascotEmotion.happy.assetPath,
      MascotContext.tapReaction,
      speech: '這是同一天的互動狀態。',
      force: true,
    );
    await tester.pump();

    await LogicalDate.save(prefs, 4);
    final resumeError = await _pumpUntilSettled(
      tester,
      mainState.debugHandleResumed() as Future<void>,
      reason: 'dayStart rollback 的 dependent-page barrier 不得卡住',
    );

    expect(resumeError, isNull);
    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-07-31');
    expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');
    expect(prefs.getString(PrefsKeys.habitDoneDay('2026-07-31')), oldHistory);
    expect(
      prefs.getString(PrefsKeys.habitDoneDay('2026-08-01')),
      augustHistoryBefore,
    );

    // 把設定改回午夜只是同一個 logical day 的 rollback round-trip，不能被誤認
    // 為第二次新日 transition 而清掉兔咪狀態。
    await LogicalDate.save(prefs, 0);
    final restoreError = await _pumpUntilSettled(
      tester,
      mainState.debugHandleResumed() as Future<void>,
      reason: 'dayStart restore 的 dependent-page barrier 不得卡住',
    );
    expect(restoreError, isNull);
    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-01');
    expect(MascotPersona.current.value.speech, '這是同一天的互動狀態。');

    await _teardownTree(tester);
  });

  testWidgets('昨天的喝水達標旗標不會帶進今天', (tester) async {
    // 沒有「喝足夠的水」習慣，喝水頁就不會被 WaterHabitLink 自動啟用。
    // 喝水頁自己讀真實時鐘算今天（本 milestone 不改它的功能規則），掛上來會用
    // 真實日期覆寫達標回報，會蓋掉這裡要觀察的東西。
    final base = _yesterdayPartlyDone();
    base[PrefsKeys.waterGoalDate] = '2026-07-31';
    SharedPreferences.setMockInitialValues(base);

    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(
      _homeWidget(tester).waterHabitAutoComplete,
      isTrue,
      reason: '跨日前昨天確實達標',
    );

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(
      _homeWidget(tester).waterHabitAutoComplete,
      isFalse,
      reason:
          'MainPage 必須先用新的一天重算旗標，才輪到 Home 重載；'
          '順序錯的話昨天的達標會被寫成今天已完成',
    );

    await _teardownTree(tester);
  });

  testWidgets('昨天記過體重不會把今天的體重習慣勾起來', (tester) async {
    final base = _yesterdayPartlyDone(
      habits: [
        _habit('體重紀錄', id: 'h1', done: true),
        _habit('走路', id: 'h2'),
      ],
    );
    base[PrefsKeys.weightRecords] = jsonEncode([
      {'date': '2026-07-31', 'weight': 60.0},
    ]);
    SharedPreferences.setMockInitialValues(base);

    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(_homeWidget(tester).weightHabitAutoComplete, isTrue);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(_homeWidget(tester).weightHabitAutoComplete, isFalse);
    final prefs = await SharedPreferences.getInstance();
    final weight = _storedHabits(prefs).firstWhere((h) => h['name'] == '體重紀錄');
    expect(weight['done'], isFalse);

    await _teardownTree(tester);
  });

  testWidgets('同日 resume 不重置、不重載、不問候', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: '2026-08-01',
      PrefsKeys.streak: 4,
      PrefsKeys.habitDoneDay('2026-08-01'): jsonEncode(['h1']),
      PrefsKeys.habits: jsonEncode([
        _habit('走路', id: 'h1', done: true),
        _habit('閱讀', id: 'h2'),
      ]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    await _pumpMain(tester, DateTime(2026, 8, 1, 9));
    final revisionBefore = _homeWidget(tester).dayStamp!.revision;
    expect(_homeState(tester).dailyDoneCount, 1);

    // 同一天多次 resume
    for (var i = 0; i < 3; i++) {
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(_homeState(tester).dailyDoneCount, 1, reason: '同日不得重置勾選');
    expect(
      _homeWidget(tester).dayStamp!.revision,
      revisionBefore,
      reason: '沒有變化就不該廣播，下游也不該白重載',
    );
    expect(find.byType(GreetingBanner), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.streak), 4);

    await _teardownTree(tester);
  });

  testWidgets('跨日後兔咪回到中性 baseline（無台詞）', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    // 昨天留下來的兔咪狀態必須是**首頁自己寫的**——production 就是這樣：
    // 打卡、撤銷、里程碑都走 Home 的 origin 與收據。撤銷同時留下一個屬於
    // 昨天、兩秒後會回寫 Persona 的本地 transient timer，一個動作蓋兩件事。
    //
    // 刻意不用 `force` 直接寫一份 external 狀態來當「昨天的狀態」：跨日只有
    // 資格收自己那一份，external 較新的狀態不得被覆寫（見下一個測試）。
    _homeState(tester).toggleHabit(0);
    await tester.pump();
    expect(MascotPersona.origin, MascotStateOrigin.home);
    expect(MascotPersona.current.value.speech, isNotNull);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(
      MascotPersona.current.value.speech,
      isNull,
      reason: '新的一天 MI baseline 要回中性，否則會和歸零的進度對不上',
    );
    expect(MascotPersona.current.value.bubble, isNull);

    // 昨日的 timer 到期後也不能把新日 neutral baseline 改成 notStarted/sleep。
    await tester.pump(const Duration(seconds: 3));
    expect(
      MascotPersona.current.value.assetPath,
      MascotEmotion.neutralFront.assetPath,
    );
    expect(MascotPersona.current.value.speech, isNull);

    await _teardownTree(tester);
  });

  testWidgets('跨日前被其他分頁接手：新日的中性重設完全不碰它', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    _homeState(tester).toggleHabit(0);
    await tester.pump();
    expect(MascotPersona.origin, MascotStateOrigin.home);

    // 其他分頁（喝水過量，優先度 40）在跨日之前接手。從這一刻起，首頁手上
    // 的收據——不管是還握著的、還是收拾自己之後留下的——都對不上了。
    MascotPersona.interact(MascotContext.overhydration);
    final externalClaim = MascotPersona.claim;
    final externalLease = MascotPersona.speechLease;
    final externalState = MascotPersona.current.value;
    expect(externalState.speech, isNotNull);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

    expect(_homeState(tester).dailyDoneCount, 0, reason: '新的一天進度歸零');
    expect(
      MascotPersona.claim,
      externalClaim,
      reason: '換日只能收自己的狀態，不得覆寫較新的 external claim',
    );
    expect(MascotPersona.speechLease, externalLease);
    expect(MascotPersona.current.value.assetPath, externalState.assetPath);
    expect(MascotPersona.current.value.speech, externalState.speech);
    expect(tester.takeException(), isNull);

    await _teardownTree(tester);
  });

  testWidgets('跨日問候只出現一次，重複驗證不重播', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
    expect(find.byType(GreetingBanner), findsNothing);

    await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GreetingBanner), findsOneWidget);

    // 同一個 transition 再驗證幾次（resume、重新訂閱）都不該再冒一次
    for (var i = 0; i < 3; i++) {
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(GreetingBanner), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('改 dayStartHour：三個頁面拿到同一個 revision，且各只重載一次', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dayStartHour: 4,
      PrefsKeys.waterEnabled: true,
      PrefsKeys.weightTrackingEnabled: true,
      PrefsKeys.lastOpenDate: '2026-07-31',
      PrefsKeys.streak: 4,
      PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['walk']),
      PrefsKeys.habits: jsonEncode([
        _habit('喝足夠的水', id: 'water'),
        _habit('體重紀錄', id: 'weight'),
        _habit('走路', id: 'walk', done: true),
      ]),
      PrefsKeys.weightRecords: jsonEncode([]),
      PrefsKeys.coinLastLoginDate: _calendarToday(),
    });
    // 凌晨 1 點、換日 4 點 → 今天還是 07-31
    await _pumpMain(tester, DateTime(2026, 8, 1, 1));
    final mainState = tester.state(find.byType(MainPage)) as dynamic;
    expect(
      await _pumpUntilSettled(
        tester,
        mainState.debugMainReady as Future<void>,
        reason: '初始 Home/Water/Weight barrier 必須完成',
      ),
      isNull,
    );
    expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-07-31');
    final homeReloadsBefore = _homeState(tester).debugReloadCount as int;
    final waterFinder = find.byType(WaterPage, skipOffstage: false);
    final weightFinder = find.byType(WeightPage, skipOffstage: false);
    final waterTriggerBefore = tester
        .widget<WaterPage>(waterFinder)
        .reloadTrigger;
    final weightTriggerBefore = tester
        .widget<WeightPage>(weightFinder)
        .reloadTrigger;
    final waterState = tester.state(waterFinder) as dynamic;
    final weightState = tester.state(weightFinder) as dynamic;
    final waterReloadsBefore = waterState.debugReloadCount as int;
    final weightReloadsBefore = weightState.debugReloadCount as int;
    final revisionBefore = _homeWidget(tester).dayStamp!.revision;

    // 使用者把換日改成午夜 → 今天變成 08-01
    final prefs = await SharedPreferences.getInstance();
    await LogicalDate.save(prefs, 0); // notifier 只通知 coordinator
    final resumeError = await _pumpUntilSettled(
      tester,
      mainState.debugHandleResumed() as Future<void>,
      reason: 'resume 必須等 Home/Water/Weight 都套用新 trigger',
    );
    expect(resumeError, isNull);

    final home = _homeWidget(tester);
    final water = tester.widget<WaterPage>(waterFinder);
    final weight = tester.widget<WeightPage>(weightFinder);
    expect(home.dayStamp!.logicalDate, '2026-08-01');
    expect(home.dayStamp!.dayStartHour, 0);
    expect(home.dayStamp!.revision, revisionBefore + 1, reason: '同一次變更只該廣播一次');
    expect(_homeState(tester).debugReloadCount, homeReloadsBefore + 1);
    expect(
      water.reloadTrigger,
      waterTriggerBefore + 1,
      reason: '兩條通知路徑並存的話，喝水頁會連續載入兩次',
    );
    expect(weight.reloadTrigger, weightTriggerBefore + 1);
    expect(waterState.debugReloadCount, waterReloadsBefore + 1);
    expect(weightState.debugReloadCount, weightReloadsBefore + 1);

    await _teardownTree(tester);
  });

  testWidgets('跨日途中把整棵樹拆掉：不丟 setState 例外', (tester) async {
    SharedPreferences.setMockInitialValues(_yesterdayPartlyDone());
    await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

    _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
    final pending = LogicalDayCoordinator.instance.ensureCurrent(
      trigger: LogicalDayTrigger.boundaryTimer,
    );
    await tester.pumpWidget(const SizedBox());
    await pending;
    await tester.pump(const Duration(seconds: 12));

    expect(tester.takeException(), isNull);
  });

  // ── 跨日時的 Persona 收拾：不得在 build 中通知 notifier ──────────
  //
  // MainPage 的 dayStamp 重建會走到 HomePage.didUpdateWidget → loadHabits →
  // 演出作廢。那一段若同步寫全域 ValueNotifier，正在 build 的 listener 會被
  // markNeedsBuild，framework 直接拋例外。

  group('跨日的 Persona 收拾', () {
    /// 五件、昨天完成一件：點一件是 2/5 的**普通完成**（不是全完成、也沒
    /// 跨過一半），這一組要的就是那種「沒有自己台詞」的中間拍。
    Map<String, Object> seed() => _yesterdayPartlyDone(
      habits: [
        _habit('走路', id: 'h1', done: true),
        _habit('閱讀', id: 'h2'),
        _habit('伸展', id: 'h3'),
        _habit('喝茶', id: 'h4'),
        _habit('寫字', id: 'h5'),
      ],
    );

    /// 預設 800×600 的畫布會把習慣卡擠出畫面；這一組要真的點得到卡片。
    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(430, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// 讓兔咪處於「狀態是首頁的、台詞是開場問候的」混合擁有權。
    Future<void> mixedOwnership(WidgetTester tester) async {
      MascotPersona.setForContext(
        MascotEmotion.neutralFront.assetPath,
        MascotContext.openApp,
        speech: '醒了醒了。',
        force: true,
        origin: MascotStateOrigin.opening,
      );
      await tester.tap(find.text('閱讀'));
      await tester.pump();
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.origin, MascotStateOrigin.home);
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      expect(MascotPersona.current.value.bubble, EmotionBubble.note);
    }

    testWidgets('真實跨日不得拋出 framework 例外，且舊 Home 狀態被收掉', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
      await mixedOwnership(tester);

      final cues = <SfxCue>[];
      final haptics = <HapticLevel>[];
      final voices = <SfxCue>[];
      debugFeedbackSink = (cue, haptic) {
        if (cue != null) cues.add(cue);
        if (haptic != HapticLevel.none) haptics.add(haptic);
      };
      MascotPersona.debugVoiceSink = voices.add;
      addTearDown(() {
        debugFeedbackSink = null;
        MascotPersona.debugVoiceSink = null;
      });

      await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

      expect(
        tester.takeException(),
        isNull,
        reason: '跨日的重建中不得同步通知 Persona 的 notifier',
      );
      expect(_homeState(tester).dailyDoneCount, 0, reason: '新的一天進度歸零');
      expect(
        MascotPersona.origin,
        MascotStateOrigin.opening,
        reason: '舊那一代 Home 的狀態擁有權要收掉',
      );
      expect(MascotPersona.current.value.bubble, isNull, reason: 'Home 的泡泡要收掉');
      // 重載等待期間不得漏出上一代的**打卡演出**（跨日本身的解鎖音效不算）。
      expect(cues, isNot(contains(SfxCue.success)));
      expect(haptics, isEmpty);
      expect(voices, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(
        cues,
        isNot(contains(SfxCue.success)),
        reason: '延後期間也不得補播舊的 impact',
      );
      expect(voices, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('連續兩次跨日重建：不重複清理，也不拋例外', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
      await mixedOwnership(tester);

      await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));
      expect(tester.takeException(), isNull);
      await _crossTo(tester, DateTime(2026, 8, 2, 4, 0, 1));
      expect(tester.takeException(), isNull);

      expect(_homeWidget(tester).dayStamp!.logicalDate, '2026-08-02');
      expect(_homeState(tester).dailyDoneCount, 0);
      expect(MascotPersona.origin, MascotStateOrigin.opening);

      await _teardownTree(tester);
    });

    testWidgets('跨日之後由其他分頁接手：遲到的舊收拾不得清掉它', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
      await mixedOwnership(tester);

      await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));
      expect(tester.takeException(), isNull);
      // 跨日自己的當日問候排在 400ms 後（既有行為：它會把兔咪收回中性）。
      // 等它跑完，之後的狀態才確定是「其他分頁的」。
      await tester.pump(const Duration(milliseconds: 600));

      // 其他分頁接手。這一刻之後，上一代 Home 排的任何收拾都只帶著更舊的
      // 收據，compare-and-clear 自然對不上。
      MascotPersona.interact(MascotContext.overhydration);
      final waterClaim = MascotPersona.claim;
      final waterLease = MascotPersona.speechLease;
      final waterSpeech = MascotPersona.current.value.speech;

      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(
        MascotPersona.claim,
        waterClaim,
        reason: '舊 callback 帶的是舊收據，不得清掉較新的狀態',
      );
      expect(MascotPersona.speechLease, waterLease);
      expect(MascotPersona.current.value.speech, waterSpeech);

      await _teardownTree(tester);
    });

    // ── 換日只收自己的 state，台詞的租約整份原封不動 ────────────
    //
    // 開場問候的**狀態擁有權**與**台詞租約**是兩條各自的壽命。換日只有資格
    // 動自己那一半：無條件的全域重設會建立一份新的 opening 租約，把還沒講完
    // 的問候文字一起清掉。

    /// production 冷啟動順序：coordinator 先 settle，`main()` 才建立開場問候的
    /// 租約，最後 MainPage / HomePage 才 mount。
    Future<void> pumpAfterColdOpening(WidgetTester tester, DateTime at) async {
      _clock = _FakeClock(at);
      LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
        clock: _clock.call,
      );
      await LogicalDayCoordinator.instance.start();
      MascotPersona.resetToOpening();
      await tester.pumpWidget(l10nTestApp(home: const MainPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }

    testWidgets('冷啟動的開場問候：跨日之後文字、租約、來源、期限完全相同', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await pumpAfterColdOpening(tester, DateTime(2026, 8, 1, 3, 58));

      final opening = MascotPersona.current.value.speech!;
      final openingLease = MascotPersona.speechLease;
      expect(
        MascotPersona.speechDeadline,
        isNull,
        reason: '冷啟動的問候刻意沒有期限：它停在畫面上直到下一次互動',
      );

      // 狀態是首頁的、台詞仍然是開場問候的混合擁有權。
      await tester.tap(find.text('閱讀'));
      await tester.pump();
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.origin, MascotStateOrigin.home);
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      expect(MascotPersona.current.value.speech, opening);
      expect(MascotPersona.speechLease, openingLease);

      final cues = <SfxCue>[];
      final haptics = <HapticLevel>[];
      final voices = <SfxCue>[];
      debugFeedbackSink = (cue, haptic) {
        if (cue != null) cues.add(cue);
        if (haptic != HapticLevel.none) haptics.add(haptic);
      };
      MascotPersona.debugVoiceSink = voices.add;
      addTearDown(() {
        debugFeedbackSink = null;
        MascotPersona.debugVoiceSink = null;
      });

      await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

      expect(tester.takeException(), isNull);
      expect(_homeState(tester).dailyDoneCount, 0, reason: '新的一天進度歸零');
      expect(
        (
          MascotPersona.current.value.speech,
          MascotPersona.speechLease,
          MascotPersona.speechOrigin,
          MascotPersona.speechDeadline,
        ),
        (opening, openingLease, MascotStateOrigin.opening, null),
        reason: '換日只能收 state；台詞的文字、租約身分、來源與絕對期限是同一條壽命',
      );
      // state 那一半確實收乾淨了。
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.neutralFront.assetPath,
      );
      expect(MascotPersona.current.value.bubble, isNull);
      expect(cues, isNot(contains(SfxCue.success)));
      expect(haptics, isEmpty);
      expect(voices, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('有期限的開場問候：跨日不重排它的絕對期限', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));

      // 有期限的 opening 租約（十秒後由它自己的計時器收掉），對上「狀態是
      // 首頁的、台詞是問候的」混合擁有權。
      await mixedOwnership(tester);
      final lease = MascotPersona.speechLease;
      final deadline = MascotPersona.speechDeadline;
      expect(deadline, isNotNull, reason: '這一份問候有期限，和冷啟動那份不同');

      await _crossTo(tester, DateTime(2026, 8, 1, 4, 0, 1));

      expect(tester.takeException(), isNull);
      // 租約整份相等就是「沒有重排」的完整證明：`_openSpeechLease` 只要被叫到
      // 就一定會遞增 speech revision，而期限是租約自己的絕對欄位。
      expect(MascotPersona.speechLease, lease, reason: '不得換一份新租約');
      expect(MascotPersona.speechDeadline, deadline, reason: '絕對期限原樣保留');
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      expect(MascotPersona.current.value.speech, '醒了醒了。');
      // 狀態那一半照樣收乾淨。
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.neutralFront.assetPath,
      );
      expect(MascotPersona.current.value.bubble, isNull);

      await _teardownTree(tester);
    });

    testWidgets('延後清理執行前整棵樹被 dispose：只收捕捉到的那一份', (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(seed());
      await _pumpMain(tester, DateTime(2026, 8, 1, 3, 58));
      await mixedOwnership(tester);
      final homeClaim = MascotPersona.claim;

      _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
      unawaited(
        LogicalDayCoordinator.instance.ensureCurrent(
          trigger: LogicalDayTrigger.boundaryTimer,
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(
        MascotPersona.claim,
        isNot(homeClaim),
        reason: 'dispose 之後那一代擁有的狀態仍然要收掉',
      );
      expect(MascotPersona.origin, MascotStateOrigin.opening);

      await tester.pump(const Duration(seconds: 12));
    });
  });

  // ── 換日的 Persona settlement 是一筆順序無關的交易 ────────────────
  //
  // 一輪 reload 會產生兩件事，而且**誰先誰後沒有保證**：收拾舊 Home 狀態
  // （可能同步、也可能被推到 post-frame），以及套用新快照（storage 的 async
  // 續體）。用一個全域欄位做兩階段橋接時，snapshot 先到就會把「要收成中性」
  // 這個需求整個丟掉，而遲到又失敗的 stale 收拾還會把新一輪的收據擦掉。
  //
  // 這一組把兩種順序都釘住，並證明 stale 的那一筆寫不到現行的那一筆。

  group('換日 settlement 交易', () {
    /// 五件、昨天完成一件：再點一件 = 2/5，落在 `expect` 這張立繪上
    /// （比率 > 0 且 < 0.5），跟新一天的 `neutralFront` 分得開。
    Map<String, Object> fiveHabits() => _yesterdayPartlyDone(
      habits: [
        _habit('走路', id: 'h1', done: true),
        _habit('閱讀', id: 'h2'),
        _habit('伸展', id: 'h3'),
        _habit('喝茶', id: 'h4'),
        _habit('寫字', id: 'h5'),
      ],
    );

    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(430, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// 掛一個「昨天」的首頁，並做出混合擁有權：
    /// 姿勢是 Home 的（expect），台詞仍然是開場問候的。
    ///
    /// [finiteLease] = true 時問候帶十秒絕對期限；false 走 production 的冷啟動
    /// 路徑（`resetToOpening`，沒有期限）。兩者都不得被換日碰到。
    Future<dynamic> mountYesterdayHome(
      WidgetTester tester, {
      required bool finiteLease,
    }) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(fiveHabits());
      _clock = _FakeClock(DateTime(2026, 8, 1, 3, 58));
      LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
        clock: _clock.call,
      );
      await LogicalDayCoordinator.instance.start();
      if (finiteLease) {
        MascotPersona.setForContext(
          MascotEmotion.neutralFront.assetPath,
          MascotContext.openApp,
          speech: '醒了醒了。',
          force: true,
          origin: MascotStateOrigin.opening,
        );
      } else {
        MascotPersona.resetToOpening();
      }
      final stamp = LogicalDayCoordinator.instance.stamp.value!;
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
        ),
      );
      await tester.pump();
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();

      await tester.tap(find.text('閱讀'));
      await tester.pump();
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(home.dailyDoneCount, 2);
      expect(MascotPersona.origin, MascotStateOrigin.home);
      expect(MascotPersona.speechOrigin, MascotStateOrigin.opening);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.expect.assetPath,
        reason: '2/5 的 Home baseline 是 expect',
      );
      return home;
    }

    Future<LogicalDayStamp> settleNewDay() async {
      _clock.now = DateTime(2026, 8, 1, 4, 0, 1);
      await LogicalDayCoordinator.instance.ensureCurrent(
        trigger: LogicalDayTrigger.boundaryTimer,
      );
      return LogicalDayCoordinator.instance.stamp.value!;
    }

    Future<void> pumpUntilLoaded(WidgetTester tester, dynamic home) async {
      for (var i = 0; i < 30 && home.debugReloading == true; i++) {
        await tester.pump();
      }
    }

    /// 台詞那一半必須一個位元都沒被動到。
    void expectOpeningUntouched(
      String? text,
      MascotSpeechLease lease,
      DateTime? deadline,
    ) {
      expect(
        (
          MascotPersona.current.value.speech,
          MascotPersona.speechLease,
          MascotPersona.speechOrigin,
          MascotPersona.speechDeadline,
        ),
        (text, lease, MascotStateOrigin.opening, deadline),
        reason: '換日只收 state；台詞的文字、租約身分、來源與絕對期限是同一條壽命',
      );
    }

    for (final lease in [
      (label: '無期限的冷啟動問候', finite: false),
      (label: '有期限的問候', finite: true),
    ]) {
      testWidgets('${lease.label}：收拾先到，快照後到（Order 1）', (tester) async {
        final home = await mountYesterdayHome(
          tester,
          finiteLease: lease.finite,
        );
        final opening = MascotPersona.current.value.speech;
        final openingLease = MascotPersona.speechLease;
        final deadline = MascotPersona.speechDeadline;
        expect(deadline, lease.finite ? isNotNull : isNull);

        final stamp = await settleNewDay();

        // 把 storage 卡住：新快照會晚於延後的收拾抵達。
        final entered = Completer<void>();
        final release = Completer<void>();
        final blocker = LogicalDayCoordinator.instance.synchronizeStorage(
          () async {
            entered.complete();
            await release.future;
          },
        );
        await entered.future;

        final cues = <SfxCue>[];
        final haptics = <HapticLevel>[];
        final voices = <SfxCue>[];
        debugFeedbackSink = (cue, haptic) {
          if (cue != null) cues.add(cue);
          if (haptic != HapticLevel.none) haptics.add(haptic);
        };
        MascotPersona.debugVoiceSink = voices.add;
        addTearDown(() {
          debugFeedbackSink = null;
          MascotPersona.debugVoiceSink = null;
        });

        await tester.pumpWidget(
          l10nTestApp(
            home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
          ),
        );
        expect(home.debugReloading, isTrue);
        expect(home.dailyDoneCount, 2, reason: '快照還卡在 storage 鎖後面');
        expect(
          MascotPersona.origin,
          MascotStateOrigin.opening,
          reason: '收拾已經把舊 Home 的擁有權放掉了',
        );
        expect(MascotPersona.current.value.bubble, isNull);
        expectOpeningUntouched(opening, openingLease, deadline);

        release.complete();
        await blocker;
        await pumpUntilLoaded(tester, home);

        expect(home.dailyDoneCount, 0);
        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.neutralFront.assetPath,
          reason: '收拾先到時，快照抵達後要用交易自己的收據再收成中性',
        );
        expect(MascotPersona.current.value.bubble, isNull);
        expectOpeningUntouched(opening, openingLease, deadline);
        expect(tester.takeException(), isNull);
        expect(cues, isNot(contains(SfxCue.success)));
        expect(haptics, isEmpty);
        expect(voices, isEmpty);

        await _teardownTree(tester);
      });

      testWidgets('${lease.label}：快照先到，收拾後到（Order 2）', (tester) async {
        final home = await mountYesterdayHome(
          tester,
          finiteLease: lease.finite,
        );
        final opening = MascotPersona.current.value.speech;
        final openingLease = MascotPersona.speechLease;
        final deadline = MascotPersona.speechDeadline;
        final stamp = await settleNewDay();
        final element =
            tester.element(find.byType(HomePage)) as StatefulElement;
        int? doneAtFirstPostFrame;
        MascotStateOrigin? originAtFirstPostFrame;

        // 這個 callback 註冊在 Home 的延後收拾之前，所以它看得到「新快照已經
        // 套用、但收拾還沒跑」的那一刻。
        SchedulerBinding.instance.addPostFrameCallback((_) {
          doneAtFirstPostFrame = home.dailyDoneCount as int;
          originAtFirstPostFrame = MascotPersona.origin;
        });
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          element.owner!.buildScope(element, () {
            element.update(
              HomePage(key: const ValueKey('home'), dayStamp: stamp),
            );
          });
        });
        await tester.pump();

        expect(
          doneAtFirstPostFrame,
          0,
          reason: '這一輪確實是「快照先到」：第一個 post-frame 就已經是新的一天',
        );
        expect(
          originAtFirstPostFrame,
          MascotStateOrigin.home,
          reason: '那一刻舊 Home 的 claim 都還在，收拾根本還沒跑',
        );
        expect(home.dailyDoneCount, 0);
        expect(
          MascotPersona.current.value.assetPath,
          MascotEmotion.neutralFront.assetPath,
          reason: '需求不能因為收拾還沒回來就被丟掉，否則會停在昨天的 expect',
        );
        expect(MascotPersona.current.value.bubble, isNull);
        expectOpeningUntouched(opening, openingLease, deadline);
        expect(tester.takeException(), isNull);

        await _teardownTree(tester);
      });
    }

    testWidgets('遲到又失敗的 stale 收拾：不得擦掉新一輪的收據', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      MascotClaim? newerSettledClaim;
      String? newerSettledAsset;
      Future<void>? staleReload;

      // 這個 callback 註冊在前：它會在 stale 收拾之前建立並**同步**收掉一個
      // 更新的 Home claim，拿到收據 B′。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        home.toggleHabit(0); // 撤銷 → 新的 Home claim
        expect(MascotPersona.origin, MascotStateOrigin.home);
        home.loadHabits(); // post-frame 不在 build 階段：同步收掉它
        expect(MascotPersona.origin, MascotStateOrigin.opening);
        newerSettledClaim = MascotPersona.claim;
        newerSettledAsset = MascotPersona.current.value.assetPath;
      });
      // 這一輪 reload 在 transient 階段開始，收拾被推到 post-frame——排在
      // 上面那個 callback 後面。
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        staleReload = home.loadHabits() as Future<void>;
      });
      await tester.pump();
      if (staleReload != null) await staleReload;
      await tester.pump();

      expect(newerSettledClaim, isNotNull);
      expect(
        MascotPersona.claim,
        newerSettledClaim,
        reason: 'stale 收拾的 compare 正確失敗，全域一個位元都不該動',
      );
      expect(MascotPersona.current.value.assetPath, newerSettledAsset);

      // 下一次正常換日必須還用得到 B′。
      final stamp = await settleNewDay();
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
        ),
      );
      await pumpUntilLoaded(tester, home);

      expect(home.dailyDoneCount, 0);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.neutralFront.assetPath,
        reason: 'stale 那一筆不得把換日要用的收據擦掉',
      );
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('連續兩次成功收拾：只由最新那一筆交易決定換日的結果', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;

      await home.loadHabits(); // 第一筆：同步收拾成功
      await tester.pump();
      await tester.tap(find.text('伸展')); // 新的 Home claim
      await tester.pump();
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.origin, MascotStateOrigin.home);
      await home.loadHabits(); // 第二筆：同樣同步收拾成功
      await tester.pump();

      final stamp = await settleNewDay();
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
        ),
      );
      await pumpUntilLoaded(tester, home);

      expect(home.dailyDoneCount, 0);
      expect(
        MascotPersona.current.value.assetPath,
        MascotEmotion.neutralFront.assetPath,
      );
      expectOpeningUntouched(opening, openingLease, null);
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('external 在換日前接手：交易終止為 no-op，完全不覆寫它', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);

      MascotPersona.interact(MascotContext.overhydration);
      final externalClaim = MascotPersona.claim;
      final externalLease = MascotPersona.speechLease;
      final externalState = MascotPersona.current.value;

      final stamp = await settleNewDay();
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
        ),
      );
      await pumpUntilLoaded(tester, home);

      expect(home.dailyDoneCount, 0, reason: '資料照樣換成新的一天');
      expect(
        MascotPersona.claim,
        externalClaim,
        reason: '收拾 compare 失敗 → 交易終止，不得留下可復活的收據',
      );
      expect(MascotPersona.speechLease, externalLease);
      expect(MascotPersona.current.value.assetPath, externalState.assetPath);
      expect(MascotPersona.current.value.speech, externalState.speech);
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('新的 Home 寫入明確 supersede 舊交易：舊收拾不得清掉它', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      MascotClaim? freshClaim;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        // 舊交易的收拾還沒跑，這裡先同步寫進一個新的 Home 狀態。
        // 用撤銷是因為它**當場**就寫 persona；打卡的第一次寫入要等到
        // 300ms 後的衝擊點。
        home.toggleHabit(0); // 撤銷「走路」→ 新的 Home claim
        freshClaim = MascotPersona.claim;
      });
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        home.loadHabits();
      });
      await tester.pump();
      await tester.pump();

      expect(freshClaim, isNotNull);
      expect(
        MascotPersona.origin,
        MascotStateOrigin.home,
        reason: '新的 Home 寫入明確接手，舊那一筆的收拾整段 no-op',
      );
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('延後收拾執行前整棵樹被拆掉：不丟例外，也不影響下一次 mount', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final homeClaim = MascotPersona.claim;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        home.loadHabits();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(
        MascotPersona.claim,
        isNot(homeClaim),
        reason: 'dispose 之後那一代擁有的狀態仍然要收',
      );

      // 新的一次 mount 完全不受上一代的 stale callback 影響。
      MascotPersona.resetToOpening();
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(
            key: const ValueKey('home2'),
            dayStamp: LogicalDayCoordinator.instance.stamp.value,
          ),
        ),
      );
      await tester.pump();
      final next = tester.state(find.byType(HomePage)) as dynamic;
      await next.loadHabits();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expectOpeningUntouched(opening, openingLease, null);

      await _teardownTree(tester);
    });

    // ── 連續作廢時的責任交接 ──────────────────────────────────
    //
    // 第二次 `loadHabits()` 進來時，本地的 claim／lease 已經被第一次清空了，
    // 所以它自己拿不到擁有權。舊版直接讓這筆「空交易」supersede 上一筆——
    // 而上一筆手上還握著一份**捕捉好、卻還沒執行**的收拾責任，於是那份收拾
    // 永遠不會發生：同日 reload 殘留 Home origin 與音符泡泡，換日則停在昨天
    // 的 expect。supersede 不等於「那些事不用做了」，責任要原子地交接過來。

    /// 沒有任何習慣預先完成：點第一件會讓 Home **自己**寫下「今天第一件。」，
    /// 台詞的租約因此也是 Home 的。
    Future<dynamic> mountHomeOwningSpeech(WidgetTester tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues(
        _yesterdayPartlyDone(
          habits: [
            _habit('走路', id: 'h1'),
            _habit('閱讀', id: 'h2'),
            _habit('伸展', id: 'h3'),
            _habit('喝茶', id: 'h4'),
            _habit('寫字', id: 'h5'),
          ],
        ),
      );
      _clock = _FakeClock(DateTime(2026, 8, 1, 3, 58));
      LogicalDayCoordinator.debugInstance = LogicalDayCoordinator(
        clock: _clock.call,
      );
      await LogicalDayCoordinator.instance.start();
      MascotPersona.resetToOpening();
      final stamp = LogicalDayCoordinator.instance.stamp.value!;
      await tester.pumpWidget(
        l10nTestApp(
          home: HomePage(key: const ValueKey('home'), dayStamp: stamp),
        ),
      );
      await tester.pump();
      final home = tester.state(find.byType(HomePage)) as dynamic;
      await home.loadHabits();
      await tester.pump();

      await tester.tap(find.text('走路'));
      await tester.pump();
      await tester.pump(CompletionPresentationController.kSpeakDelay);
      expect(MascotPersona.current.value.speech, '今天第一件。');
      expect(MascotPersona.speechOrigin, MascotStateOrigin.home);
      return home;
    }

    /// 這一段期間不得有任何舊演出漏播。
    ({List<SfxCue> cues, List<HapticLevel> haptics, List<SfxCue> voices})
    watchFeedback(WidgetTester tester) {
      final cues = <SfxCue>[];
      final haptics = <HapticLevel>[];
      final voices = <SfxCue>[];
      debugFeedbackSink = (cue, haptic) {
        if (cue != null) cues.add(cue);
        if (haptic != HapticLevel.none) haptics.add(haptic);
      };
      MascotPersona.debugVoiceSink = voices.add;
      addTearDown(() {
        debugFeedbackSink = null;
        MascotPersona.debugVoiceSink = null;
      });
      return (cues: cues, haptics: haptics, voices: voices);
    }

    testWidgets('T1 還欠著收拾時 T2 進來：同日 reload 仍然把它收乾淨', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;
      final log = watchFeedback(tester);
      Future<void>? first;
      Future<void>? second;
      SchedulerPhase? phase;

      // 兩次 loadHabits 都在 build 階段：T1 把收拾推到 post-frame，T2 進來時
      // 本地欄位已經是空的。
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        phase = SchedulerBinding.instance.schedulerPhase;
        first = home.loadHabits() as Future<void>;
        second = home.loadHabits() as Future<void>;
      });
      await tester.pump();
      if (first != null) await first;
      if (second != null) await second;
      await tester.pump();

      expect(phase, SchedulerPhase.transientCallbacks);
      expect(
        (MascotPersona.origin, MascotPersona.current.value.bubble),
        (MascotStateOrigin.opening, null),
        reason: 'claim:null 的新交易不得把上一筆唯一的收拾責任丟掉',
      );
      expectOpeningUntouched(opening, openingLease, null);
      expect(tester.takeException(), isNull);
      expect(log.cues, isNot(contains(SfxCue.success)));
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('T1 還欠著收拾時 T2 進來：換日仍然收到中性', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;
      final stamp = await settleNewDay();
      final element = tester.element(find.byType(HomePage)) as StatefulElement;
      final log = watchFeedback(tester);
      Future<void>? second;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        element.owner!.buildScope(element, () {
          // didUpdateWidget 開 T1（帶著舊 Home claim）
          element.update(
            HomePage(key: const ValueKey('home'), dayStamp: stamp),
          );
          // T2 自己拿不到 claim
          second = home.loadHabits() as Future<void>;
        });
      });
      await tester.pump();
      if (second != null) await second;
      await pumpUntilLoaded(tester, home);
      await tester.pump();

      expect(home.dailyDoneCount, 0, reason: '新的一天照樣套用');
      expect(
        (
          MascotPersona.current.value.assetPath,
          MascotPersona.current.value.bubble,
        ),
        (MascotEmotion.neutralFront.assetPath, null),
        reason: 'T2 必須同時接下收拾責任與新一天的中性需求',
      );
      expectOpeningUntouched(opening, openingLease, null);
      expect(tester.takeException(), isNull);
      expect(log.cues, isNot(contains(SfxCue.success)));
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('needsNeutral 在 T2 之前抵達：一樣收斂到中性', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;
      final stamp = await settleNewDay();
      final element = tester.element(find.byType(HomePage)) as StatefulElement;
      int? doneBeforeT2;
      MascotStateOrigin? originBeforeT2;

      // 註冊在前：T1 的快照續體在 mid-frame 就把 needsNeutral 記在 T1 上，
      // 這個 callback 才啟動 claim:null 的 T2，而 T1 的收拾還沒跑。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        doneBeforeT2 = home.dailyDoneCount as int;
        originBeforeT2 = MascotPersona.origin;
        home.loadHabits();
      });
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        element.owner!.buildScope(element, () {
          element.update(
            HomePage(key: const ValueKey('home'), dayStamp: stamp),
          );
        });
      });
      await tester.pump();
      await pumpUntilLoaded(tester, home);
      await tester.pump();

      expect(doneBeforeT2, 0, reason: 'T1 的快照先到了新的一天');
      expect(
        originBeforeT2,
        MascotStateOrigin.home,
        reason: 'T2 開始時 T1 的收拾仍然欠著',
      );
      expect(
        (
          MascotPersona.current.value.assetPath,
          MascotPersona.current.value.bubble,
        ),
        (MascotEmotion.neutralFront.assetPath, null),
        reason: 'needsNeutral 是累積需求，不得因為換一筆交易就消失',
      );
      expectOpeningUntouched(opening, openingLease, null);
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('連續作廢仍然精確清掉 Home 自己那句台詞', (tester) async {
      final home = await mountHomeOwningSpeech(tester);
      final homeLease = MascotPersona.speechLease;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        home.loadHabits();
        home.loadHabits();
      });
      await tester.pump();
      await tester.pump();

      expect(MascotPersona.current.value.speech, isNull);
      expect(MascotPersona.origin, MascotStateOrigin.opening);
      expect(
        MascotPersona.speechLease,
        isNot(homeLease),
        reason: 'Home 自己的租約要被精確收掉，不是留著',
      );
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('T1 → external 接手 → T2：完全不碰 external 的狀態與台詞', (tester) async {
      final home = await mountHomeOwningSpeech(tester);
      MascotClaim? externalClaim;
      MascotSpeechLease? externalLease;
      MascotState? externalState;

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        home.loadHabits(); // T1 捕捉舊 Home claim，收拾排在 post-frame
        MascotPersona.interact(MascotContext.overhydration);
        externalClaim = MascotPersona.claim;
        externalLease = MascotPersona.speechLease;
        externalState = MascotPersona.current.value;
        home.loadHabits(); // T2 接下 T1 的責任，但收據已經對不上了
      });
      await tester.pump();
      await tester.pump();

      expect(MascotPersona.claim, externalClaim);
      expect(MascotPersona.speechLease, externalLease);
      expect(MascotPersona.current.value.assetPath, externalState!.assetPath);
      expect(MascotPersona.current.value.speech, externalState!.speech);
      expect(tester.takeException(), isNull);

      await _teardownTree(tester);
    });

    testWidgets('連續四次作廢：收拾責任只執行一次，而且沒有遺失', (tester) async {
      final home = await mountYesterdayHome(tester, finiteLease: false);
      final opening = MascotPersona.current.value.speech;
      final openingLease = MascotPersona.speechLease;
      final log = watchFeedback(tester);
      final claims = <MascotClaim>[];
      void record() => claims.add(MascotPersona.claim);

      MascotPersona.current.addListener(record);
      addTearDown(() => MascotPersona.current.removeListener(record));

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        home.loadHabits();
        home.loadHabits();
        home.loadHabits();
        home.loadHabits();
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        MascotPersona.origin,
        MascotStateOrigin.opening,
        reason: '四次連續作廢之後，那份收拾仍然要發生',
      );
      expect(MascotPersona.current.value.bubble, isNull);
      expect(claims, hasLength(1), reason: '捕捉到的那份 Home claim 最多只清理一次');
      expectOpeningUntouched(opening, openingLease, null);
      expect(tester.takeException(), isNull);
      expect(log.cues, isNot(contains(SfxCue.success)));
      expect(log.haptics, isEmpty);
      expect(log.voices, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('收拾成功／失敗 × 快照先到／收拾先到 × 空交易接手：全部收斂', (tester) async {
      for (final external in [false, true]) {
        for (final snapshotFirst in [false, true]) {
          final home = await mountYesterdayHome(tester, finiteLease: false);
          final opening = MascotPersona.current.value.speech;
          final openingLease = MascotPersona.speechLease;
          final stamp = await settleNewDay();
          final element =
              tester.element(find.byType(HomePage)) as StatefulElement;
          final reason = 'external=$external snapshotFirst=$snapshotFirst';
          MascotClaim? externalClaim;

          if (snapshotFirst) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              home.loadHabits(); // claim:null 的接手者
            });
          }
          SchedulerBinding.instance.scheduleFrameCallback((_) {
            element.owner!.buildScope(element, () {
              element.update(
                HomePage(key: const ValueKey('home'), dayStamp: stamp),
              );
              if (external) {
                MascotPersona.interact(MascotContext.overhydration);
                externalClaim = MascotPersona.claim;
              }
              if (!snapshotFirst) home.loadHabits();
            });
          });
          await tester.pump();
          await pumpUntilLoaded(tester, home);
          await tester.pump();

          expect(home.dailyDoneCount, 0, reason: reason);
          if (external) {
            expect(MascotPersona.claim, externalClaim, reason: reason);
          } else {
            expect(
              (
                MascotPersona.current.value.assetPath,
                MascotPersona.current.value.bubble,
              ),
              (MascotEmotion.neutralFront.assetPath, null),
              reason: reason,
            );
            expectOpeningUntouched(opening, openingLease, null);
          }
          expect(tester.takeException(), isNull, reason: reason);

          await _teardownTree(tester);
          LogicalDayCoordinator.debugInstance = null;
          MascotPersona.resetToIdle();
        }
      }
    });
  });
}
