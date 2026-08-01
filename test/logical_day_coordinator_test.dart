// 邏輯日 coordinator：純結算、偵測與排程、以及 process 在結算中途被殺之後的
// 恢復。時間全部用可注入的 fake clock，不依賴真實等待。
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/logical_day_coordinator.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可推進的假時鐘。
class _FakeClock {
  DateTime now;
  _FakeClock(this.now);
  DateTime call() => now;
}

Map<String, dynamic> _habit(
  String name, {
  required String id,
  bool done = false,
  String frequency = 'daily',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'done': done,
    'frequency': frequency,
    'createdAt': '2026-01-02',
  };
}

String _habitsJson(List<Map<String, dynamic>> habits) => jsonEncode(habits);

/// 建一個掛好的 coordinator（含 observer / notifier listener）。
Future<(LogicalDayCoordinator, _FakeClock)> _startCoordinator(
  DateTime now,
) async {
  final clock = _FakeClock(now);
  final coordinator = LogicalDayCoordinator(clock: clock.call);
  LogicalDayCoordinator.debugInstance = coordinator;
  await coordinator.start();
  return (coordinator, clock);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LogicalDayCoordinator.debugInstance = null;
    LogicalDate.notifier.value = LogicalDate.defaultHour;
  });

  // ── 8.1 純結算 ───────────────────────────────────────────
  group('settleLogicalDay（純函式）', () {
    final daily = [
      _habit('喝水', id: 'h1'),
      _habit('走路', id: 'h2'),
    ];

    test('昨日全部完成 → 連勝 +1', () {
      final r = settleLogicalDay(
        dailyHabits: daily,
        historyDoneIds: {'h1', 'h2'},
        previousStreak: 4,
      );
      expect(r.streak, 5);
      expect(r.allDone, isTrue);
    });

    test('昨日沒有全部完成 → 連勝歸零', () {
      final r = settleLogicalDay(
        dailyHabits: daily,
        historyDoneIds: {'h1'},
        previousStreak: 4,
      );
      expect(r.streak, 0);
      expect(r.allDone, isFalse);
    });

    test('沒有每日習慣 → 連勝不動（既有 anti-guilt 行為）', () {
      final r = settleLogicalDay(
        dailyHabits: const [],
        historyDoneIds: const {},
        previousStreak: 4,
      );
      expect(r.streak, 4);
      expect(r.allDone, isFalse);
    });

    test('history key 存在但為空集合 → 視為全部未完成', () {
      final r = settleLogicalDay(
        dailyHabits: daily,
        historyDoneIds: const {},
        previousStreak: 4,
      );
      expect(r.streak, 0);
    });

    test('history 不存在（null）→ 退回持久化 habits 的 done 旗標', () {
      final r = settleLogicalDay(
        dailyHabits: [
          _habit('喝水', id: 'h1', done: true),
          _habit('走路', id: 'h2', done: true),
        ],
        historyDoneIds: null,
        previousStreak: 4,
      );
      expect(r.streak, 5, reason: '遷移 fallback 要能認出昨天其實完成了');
    });

    test('同一組輸入重跑得到同一個結果（冪等）', () {
      LogicalDaySettlementResult run() => settleLogicalDay(
        dailyHabits: daily,
        historyDoneIds: {'h1', 'h2'},
        previousStreak: 4,
      );
      expect(run().streak, run().streak);
      expect(run().streak, 5, reason: '純函式不得因為呼叫次數而累加');
    });
  });

  // ── 4.7 邊界計算 ─────────────────────────────────────────
  group('nextBoundaryAfter（本地日曆建構）', () {
    test('白天 → 下一個日曆日的換日時刻', () {
      final next = LogicalDayCoordinator.nextBoundaryAfter(
        DateTime(2026, 8, 1, 10),
        4,
      );
      expect(next, DateTime(2026, 8, 2, 4));
    });

    test('凌晨（還在前一個邏輯日）→ 今天的換日時刻', () {
      final next = LogicalDayCoordinator.nextBoundaryAfter(
        DateTime(2026, 8, 1, 2),
        4,
      );
      expect(next, DateTime(2026, 8, 1, 4));
    });

    test('hour=0 → 下一個午夜', () {
      final next = LogicalDayCoordinator.nextBoundaryAfter(
        DateTime(2026, 8, 1, 10),
        0,
      );
      expect(next, DateTime(2026, 8, 2));
    });

    test('跨月 / 跨年由 DateTime 正規化處理', () {
      expect(
        LogicalDayCoordinator.nextBoundaryAfter(DateTime(2026, 1, 31, 10), 4),
        DateTime(2026, 2, 1, 4),
      );
      expect(
        LogicalDayCoordinator.nextBoundaryAfter(DateTime(2026, 12, 31, 10), 4),
        DateTime(2027, 1, 1, 4),
      );
    });
  });

  // ── 8.2 fake clock 下的偵測與結算 ─────────────────────────
  group('冷啟動與邊界時刻', () {
    Future<void> seedYesterdayAllDone() async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1', 'h2']),
        PrefsKeys.habits: _habitsJson([
          _habit('喝水', id: 'h1', done: true),
          _habit('走路', id: 'h2', done: true),
        ]),
      });
    }

    test('冷啟動跨日：結算一次、勾選重置、marker 推進、廣播一次', () async {
      await seedYesterdayAllDone();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt(PrefsKeys.streak), 5);
      expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');
      final habits =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(habits.every((h) => h['done'] == false), isTrue);
      expect(habits.length, 2, reason: '不得出現重複習慣');
      expect(
        prefs.getString(PrefsKeys.habitDoneDay('2026-07-31')),
        jsonEncode(['h1', 'h2']),
        reason: '昨天的歷史不得被動到',
      );

      final stamp = coordinator.stamp.value!;
      expect(stamp.logicalDate, '2026-08-01');
      expect(stamp.transitionId, 'day:2026-08-01');
      expect(stamp.settledLogicalDate, '2026-08-01');
      expect(stamp.revision, 1);
    });

    test('同一 transition 重複 ensureCurrent：不重複結算、不重複廣播', () async {
      await seedYesterdayAllDone();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final firstRevision = coordinator.stamp.value!.revision;

      for (var i = 0; i < 3; i++) {
        await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);
      }

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5, reason: '連勝不得再加');
      expect(coordinator.stamp.value!.revision, firstRevision);
    });

    test('同日冷啟動：不結算、不動連勝、也沒有問候 token', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-08-01',
        PrefsKeys.streak: 4,
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt(PrefsKeys.streak), 4);
      final habits =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(habits[0]['done'], isTrue, reason: '同日不得清掉今天的勾選');
      expect(coordinator.stamp.value!.transitionId, isNull);
      expect(coordinator.consumeGreeting('day:2026-08-01'), isFalse);
    });

    test('23:59 / 00:01 / 03:59 都還算前一個邏輯日；04:00、04:01 才換日', () async {
      for (final probe in <(DateTime, String, bool)>[
        (DateTime(2026, 7, 31, 23, 59), '2026-07-31', false),
        (DateTime(2026, 8, 1, 0, 1), '2026-07-31', false),
        (DateTime(2026, 8, 1, 3, 59), '2026-07-31', false),
        (DateTime(2026, 8, 1, 4), '2026-08-01', true),
        (DateTime(2026, 8, 1, 4, 1), '2026-08-01', true),
      ]) {
        final (at, expectedDate, shouldSettle) = probe;
        await seedYesterdayAllDone();
        final (coordinator, _) = await _startCoordinator(at);
        final prefs = await SharedPreferences.getInstance();
        expect(coordinator.stamp.value!.logicalDate, expectedDate, reason: '$at');
        expect(prefs.getInt(PrefsKeys.streak), shouldSettle ? 5 : 4, reason: '$at');
        LogicalDayCoordinator.debugInstance = null;
      }
    });

    test('自訂 dayStartHour=0：00:01 就算新的一天', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dayStartHour: 0,
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      final (coordinator, _) = await _startCoordinator(
        DateTime(2026, 8, 1, 0, 1),
      );
      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');
      expect(coordinator.stamp.value!.dayStartHour, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
    });

    test('第一次啟動（沒有 lastOpenDate）：寫 marker 並給問候 token，但不動連勝', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.streak: 3,
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1')]),
      });
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');
      expect(prefs.getInt(PrefsKeys.streak), 3, reason: '沒有前一天可結算');
      expect(coordinator.consumeGreeting('day:2026-08-01'), isTrue);
    });
  });

  group('前景邊界與 lifecycle', () {
    Future<void> seed() async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
    }

    test('前景跨過邊界：把時鐘推過去再驗證，就會結算', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      // 03:58 開著 App：還是昨天
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 8, 1, 3, 58),
      );
      expect(coordinator.stamp.value!.logicalDate, '2026-07-31');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 4);

      // 邊界計時器醒來（以實際時鐘重新驗證）
      clock.now = DateTime(2026, 8, 1, 4, 0, 1);
      await coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.boundaryTimer,
      );

      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');
      expect(prefs.getInt(PrefsKeys.streak), 5);
      expect(coordinator.stamp.value!.revision, 2, reason: '真的變了才廣播');
    });

    test('邊界計時器醒來但還沒跨日：不結算、不廣播', () async {
      await seed();
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 8, 1, 3),
      );
      final revision = coordinator.stamp.value!.revision;
      clock.now = DateTime(2026, 8, 1, 3, 30);
      await coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.boundaryTimer,
      );
      expect(coordinator.stamp.value!.revision, revision);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 4);
    });

    test('背景 resume 跨日：resume 驗證會結算', () async {
      await seed();
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 7, 31, 21),
      );
      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(coordinator.hasScheduledBoundary, isFalse, reason: '背景不留計時器');

      clock.now = DateTime(2026, 8, 1, 9);
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.resume);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');
    });

    test('多次快速 pause/resume：只結算一次', () async {
      await seed();
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 7, 31, 21),
      );
      clock.now = DateTime(2026, 8, 1, 9);
      for (var i = 0; i < 4; i++) {
        coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
        coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.resume);
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.resume);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5, reason: '連勝只能加一次');
      expect(coordinator.stamp.value!.revision, 2);
    });

    test('併發 ensureCurrent：共用同一個 in-flight，不平行結算', () async {
      await seed();
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 7, 31, 21),
      );
      clock.now = DateTime(2026, 8, 1, 9);

      final a = coordinator.ensureCurrent(trigger: LogicalDayTrigger.resume);
      final b = coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);
      final c = coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.boundaryTimer,
      );
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isTrue);
      await Future.wait([a, b, c]);
      // 合併後還會補跑一次最後檢查，等它做完
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
    });

    test('transition 進行中再次跨日：補跑的最後檢查會用最新時鐘', () async {
      await seed();
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 8, 1, 9),
      );
      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');

      final inFlight = coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.manual,
      );
      // 還在跑的時候時鐘又跨了一天，並補一個 trigger
      clock.now = DateTime(2026, 8, 2, 9);
      final merged = coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.resume,
      );
      expect(identical(inFlight, merged), isTrue);
      await merged;
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);

      expect(
        coordinator.stamp.value!.logicalDate,
        '2026-08-02',
        reason: '被合併的那次不能被吞掉',
      );
    });

    test('dayStartHour 往後調（邏輯日往回跳）：重新廣播但不結算', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dayStartHour: 0,
        PrefsKeys.lastOpenDate: '2026-08-01',
        PrefsKeys.streak: 4,
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      // 凌晨 1 點、hour=0 → 今天是 08-01
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 1));
      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');

      // 使用者把換日改成 4 點 → 今天字串往回跳成 07-31
      final prefs = await SharedPreferences.getInstance();
      await LogicalDate.save(prefs, 4);
      await coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.dayStartHourChanged,
      );

      expect(coordinator.stamp.value!.logicalDate, '2026-07-31');
      expect(prefs.getInt(PrefsKeys.streak), 4, reason: '往回跳不是新的一天');
      expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');
      final habits =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(habits[0]['done'], isTrue, reason: '往回跳不得清掉勾選');
    });

    test('dayStartHour 往前調（邏輯日往前走）：正常結算一次', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dayStartHour: 4,
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      // 凌晨 1 點、hour=4 → 今天還是 07-31
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 1));
      expect(coordinator.stamp.value!.logicalDate, '2026-07-31');

      final prefs = await SharedPreferences.getInstance();
      await LogicalDate.save(prefs, 0); // 改成午夜換日 → 今天變 08-01
      await coordinator.ensureCurrent(
        trigger: LogicalDayTrigger.dayStartHourChanged,
      );

      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');
      expect(prefs.getInt(PrefsKeys.streak), 5);
    });

    test('dispose 後不留計時器', () async {
      await seed();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      void noop() {}
      coordinator.stamp.addListener(noop);
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);
      expect(coordinator.hasScheduledBoundary, isTrue);

      coordinator.dispose();
      expect(coordinator.hasScheduledBoundary, isFalse);
      LogicalDayCoordinator.debugInstance = null;
    });

    test('沒有訂閱者時不排邊界計時器（widget 樹拆掉不留 timer）', () async {
      await seed();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      expect(coordinator.hasScheduledBoundary, isFalse);
    });

    test('RootRestart：start 再呼叫一次是冪等的重新驗證', () async {
      await seed();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final revision = coordinator.stamp.value!.revision;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);

      await coordinator.start();
      await coordinator.start();

      expect(prefs.getInt(PrefsKeys.streak), 5, reason: '不得重複結算');
      expect(coordinator.stamp.value!.revision, revision);
    });

    test('問候 token 只能被消費一次；重新訂閱不會重播', () async {
      await seed();
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      final id = coordinator.stamp.value!.transitionId!;

      expect(coordinator.consumeGreeting(id), isTrue);
      expect(coordinator.consumeGreeting(id), isFalse);
      // 再驗證幾次（等同 RootRestart 後重新訂閱）也不會再拿到
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.manual);
      expect(coordinator.consumeGreeting(id), isFalse);
      expect(coordinator.consumeGreeting(null), isFalse);
    });
  });

  // ── 8.3 restart recovery ─────────────────────────────────
  group('process 在結算中途被殺之後重建 coordinator', () {
    // 場景：昨天（07-31）兩個每日習慣全完成，連勝 4 → 應該變 5。
    //
    // 寫入順序是 journal（commit marker）→ streak → habits reset →
    // lastOpenDate，所以中途被殺只會落在下面這四種狀態；journal 之後的每一步
    // 都是從 journal 讀答案的冪等覆寫。
    String journalJson({required String settledDay, required int streakAfter}) {
      return jsonEncode({
        'kind': 'settlement',
        'settledDay': settledDay,
        'streakAfter': streakAfter,
        'yesterdayAllDone': true,
        'previousOpenDate': '2026-07-31',
      });
    }

    Map<String, Object> partialState({
      required bool habitsReset,
      required int streak,
      String? journal,
      required String lastOpenDate,
    }) {
      return {
        PrefsKeys.lastOpenDate: lastOpenDate,
        PrefsKeys.streak: streak,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1', 'h2']),
        PrefsKeys.habits: _habitsJson([
          _habit('喝水', id: 'h1', done: !habitsReset),
          _habit('走路', id: 'h2', done: !habitsReset),
        ]),
        PrefsKeys.logicalDayJournal: ?journal,
      };
    }

    Future<void> expectSettled(SharedPreferences prefs) async {
      expect(prefs.getInt(PrefsKeys.streak), 5, reason: '連勝必須是 5，不得歸零或重複加');
      expect(prefs.getString(PrefsKeys.lastOpenDate), '2026-08-01');
      final journal = LogicalDayJournal.read(prefs)!;
      expect(journal.settledDay, '2026-08-01');
      expect(journal.streakAfter, 5);
      final habits =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(habits.length, 2, reason: '不得出現重複習慣');
      expect(habits.every((h) => h['done'] == false), isTrue);
      expect(
        prefs.getString(PrefsKeys.habitDoneDay('2026-07-31')),
        jsonEncode(['h1', 'h2']),
        reason: '歷史不得被破壞',
      );
    }

    test('狀態 0：什麼都還沒寫（完整跑一次）', () async {
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: false,
          streak: 4,
          lastOpenDate: '2026-07-31',
        ),
      );
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      await expectSettled(await SharedPreferences.getInstance());
    });

    test('狀態 1：journal 已寫入，streak / habits / marker 都還沒', () async {
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: false,
          streak: 4, // 還是舊值
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-07-31',
        ),
      );
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      // 不重算連勝，直接把 journal 的答案鏡像回 streak，再補完剩下的步驟。
      await expectSettled(await SharedPreferences.getInstance());
    });

    test('狀態 2：journal 與 streak 已寫入，habits 尚未重置', () async {
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: false,
          streak: 5,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-07-31',
        ),
      );
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      await expectSettled(await SharedPreferences.getInstance());
    });

    test('狀態 3：只剩 lastOpenDate 沒推進', () async {
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: true,
          streak: 5,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-07-31',
        ),
      );
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      await expectSettled(await SharedPreferences.getInstance());
    });

    test('狀態 4：全部落地、只差廣播 stamp', () async {
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: true,
          streak: 5,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-08-01',
        ),
      );
      final (coordinator, _) = await _startCoordinator(DateTime(2026, 8, 1, 9));
      await expectSettled(await SharedPreferences.getInstance());
      // stamp 仍然會補廣播，transition identity 可辨識。
      expect(coordinator.stamp.value!.logicalDate, '2026-08-01');
      expect(coordinator.stamp.value!.transitionId, 'day:2026-08-01');
    });

    test('四種中間狀態重跑都收斂到同一結果', () async {
      final results = <int>[];
      for (final state in <Map<String, Object>>[
        partialState(
          habitsReset: false,
          streak: 4,
          lastOpenDate: '2026-07-31',
        ),
        partialState(
          habitsReset: false,
          streak: 4,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-07-31',
        ),
        partialState(
          habitsReset: true,
          streak: 5,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-07-31',
        ),
        partialState(
          habitsReset: true,
          streak: 5,
          journal: journalJson(settledDay: '2026-08-01', streakAfter: 5),
          lastOpenDate: '2026-08-01',
        ),
      ]) {
        SharedPreferences.setMockInitialValues(state);
        await _startCoordinator(DateTime(2026, 8, 1, 9));
        final prefs = await SharedPreferences.getInstance();
        // 再多重跑幾次也不能變
        await LogicalDayCoordinator.instance.ensureCurrent(
          trigger: LogicalDayTrigger.manual,
        );
        results.add(prefs.getInt(PrefsKeys.streak)!);
        LogicalDayCoordinator.debugInstance = null;
      }
      expect(results, [5, 5, 5, 5]);
    });

    test('升級用戶同日開啟：先立 baseline journal，讓下一次結算有基準', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-08-01',
        PrefsKeys.streak: 7,
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      final (coordinator, clock) = await _startCoordinator(
        DateTime(2026, 8, 1, 9),
      );
      final prefs = await SharedPreferences.getInstance();
      final baseline = LogicalDayJournal.read(prefs)!;
      expect(baseline.kind, LogicalDayJournalKind.baseline);
      expect(baseline.streakAfter, 7);
      // baseline 不是 transition，不該給出問候身分
      expect(coordinator.stamp.value!.transitionId, isNull);

      // 隔天真的跨日 → 從 baseline 的 7 出發
      await prefs.setString(
        PrefsKeys.habitDoneDay('2026-08-01'),
        jsonEncode(['h1']),
      );
      clock.now = DateTime(2026, 8, 2, 9);
      await coordinator.ensureCurrent(trigger: LogicalDayTrigger.resume);
      expect(prefs.getInt(PrefsKeys.streak), 8);
    });

    test('舊版當機留下的中間狀態（streak 已加、沒有 journal）：不會歸零', () async {
      // 這是唯一無法完全還原的窗口：streak 是沒有日期標記的計數器，在沒有
      // journal 的情況下無法分辨 5 是不是已經含了昨天。取「不歸零」這一側。
      SharedPreferences.setMockInitialValues(
        partialState(
          habitsReset: true,
          streak: 5,
          lastOpenDate: '2026-07-31',
        ),
      );
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(PrefsKeys.streak),
        greaterThanOrEqualTo(5),
        reason: '寧可多算一天，也不能把使用者的連勝歸零（anti-guilt）',
      );
    });

    test('缺席多日：只結算 lastOpenDate 那一天，不歸零多次也不加多次', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-28',
        PrefsKeys.streak: 9,
        PrefsKeys.habitDoneDay('2026-07-28'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([_habit('喝水', id: 'h1', done: true)]),
      });
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 10, reason: '缺席三天只結算一次');
      expect(LogicalDayJournal.read(prefs)!.previousOpenDate, '2026-07-28');
    });

    test('history key 完全不存在（舊資料）→ 用持久化 habits 的 done 遷移一次', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        // 刻意沒有 habit_done_2026-07-31
        PrefsKeys.habits: _habitsJson([
          _habit('喝水', id: 'h1', done: true),
          _habit('走路', id: 'h2', done: true),
        ]),
      });
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
    });

    test('history key 不存在、且昨天其實沒完成 → 不會被誤判成完成', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habits: _habitsJson([
          _habit('喝水', id: 'h1', done: true),
          _habit('走路', id: 'h2'), // 沒完成
        ]),
      });
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 0);
    });

    test('每日習慣缺 id（遷移前）→ 走 fallback 而不是把歷史當成沒完成', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: jsonEncode([
          _habit('喝水', id: 'h1', done: true),
          {'name': '走路', 'done': true, 'frequency': 'daily'}, // 沒有 id
        ]),
      });
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
    });

    test('每週習慣不參與結算，也不會被清掉勾選', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.lastOpenDate: '2026-07-31',
        PrefsKeys.streak: 4,
        PrefsKeys.habitDoneDay('2026-07-31'): jsonEncode(['h1']),
        PrefsKeys.habits: _habitsJson([
          _habit('喝水', id: 'h1', done: true),
          _habit('跑步', id: 'w1', done: true, frequency: 'weekly'),
        ]),
      });
      await _startCoordinator(DateTime(2026, 8, 1, 9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.streak), 5);
      final habits =
          (jsonDecode(prefs.getString(PrefsKeys.habits)!) as List)
              .cast<Map<String, dynamic>>();
      expect(habits[0]['done'], isFalse);
      expect(habits[1]['done'], isTrue, reason: '每週習慣走 weeklyDates，不在這裡重置');
    });
  });
}
