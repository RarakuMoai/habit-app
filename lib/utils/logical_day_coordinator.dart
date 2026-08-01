// 邏輯日的唯一生命週期擁有者。
//
// 為什麼需要它：習慣狀態住在常駐於 IndexedStack 的首頁，而首頁沒有 lifecycle
// observer 也沒有計時器；跨日結算原本綁在 `HomePage.initState` 的一次性載入
// 裡，所以「前景跨過換日線」與「背景過夜後 resume」都不會重新結算，使用者會
// 同時看到新一天的報到與昨天的完成狀態。
//
// 責任邊界（刻意很窄）：
//   ✔ 現在是哪個邏輯日、換日時間是幾點
//   ✔ 冷啟動 / resume / 前景邊界計時器 / 換日設定變更的偵測
//   ✔ 跨日結算（連勝 + 當日勾選重置）恰好一次
//   ✔ settlement journal、冪等、in-flight 合併、廣播、重新排程
//   ✘ UI、每日登入獎勵、金幣、回憶事件、導覽、音訊、兔咪演出
//
// 訂閱者只有 `MainPage`：它收到 stamp 後**先**刷新喝水/體重的自動完成旗標，
// 再把 revision 往下傳給首頁 / 喝水頁 / 體重頁。順序不能反過來，否則昨天的
// 達標旗標會把新一天的連動習慣直接標成已完成（見 engineering_guardrails）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'habit_history.dart';
import 'logical_date.dart';
import 'prefs_keys.dart';

/// 邊界計時器的看門狗上限。
///
/// 下一個換日邊界可能遠在 20 幾小時後，但長計時器擋不住「使用者或系統把時鐘
/// 往前 / 往後調」——那會讓它在錯誤的時間醒來。所以把單次等待夾到一小時：
/// 最壞情況一小時內自我校正，而每次醒來只是算個字串再重排，成本遠低於
/// SceneTimeController 既有的每分鐘 tick。
const Duration kLogicalDayWatchdogInterval = Duration(hours: 1);

/// 觸發來源；只影響 log 與測試可讀性，不影響結算結果。
enum LogicalDayTrigger { cold, resume, boundaryTimer, dayStartHourChanged, manual }

/// 目前邏輯日的快照。MainPage 訂閱它，並把 revision 往下傳。
@immutable
class LogicalDayStamp {
  /// 目前邏輯日（yyyy-MM-dd）。
  final String logicalDate;

  /// 目前換日時間（小時）。頁面不要再自己存一份真相。
  final int dayStartHour;

  /// 每次真正廣播 +1；下游用它判斷「要不要重新載入」。
  final int revision;

  /// 這一天的跨日 transition 身分；沒有結算過就是 null。
  /// 同一個 id 只該消費一次問候（見 [LogicalDayCoordinator.consumeGreeting]）。
  final String? transitionId;

  /// journal 記錄的「已結算到哪一個邏輯日」。
  final String? settledLogicalDate;

  const LogicalDayStamp({
    required this.logicalDate,
    required this.dayStartHour,
    required this.revision,
    this.transitionId,
    this.settledLogicalDate,
  });

  @override
  String toString() =>
      'LogicalDayStamp($logicalDate, h=$dayStartHour, rev=$revision, '
      'transition=$transitionId)';
}

/// 結算日誌。
///
/// ⚠️ 這是**冪等的 commit marker**，不是跨多個 SharedPreferences key 的真正
/// transaction——SharedPreferences 沒有交易。安全性來自兩件事：
///   1. 連勝這種「累加」運算被 journal 擋住，同一個邏輯日只算一次；
///   2. 其餘步驟（勾選重置、marker 推進）都是冪等的覆寫，重跑結果相同。
/// 重跑的輸入是「上一個使用者邏輯日的歷史」，那份資料不會被重置動到，所以
/// process 在中途被殺，下次啟動重跑會得到同一個連勝值。
enum LogicalDayJournalKind {
  /// 真的做過一次跨日結算。
  settlement,

  /// 升級用的基準點：這個裝置在本版本上還沒跨過日，先把「目前的連勝」記下來，
  /// 讓下一次結算有可信的基準，不必去讀可能是中間狀態的 [PrefsKeys.streak]。
  baseline,
}

@immutable
class LogicalDayJournal {
  final LogicalDayJournalKind kind;

  /// 已經結算完成的邏輯日。
  final String settledDay;

  /// 結算後的連勝值。重跑時用它當基準，避免讀到「已經加過但 journal 沒寫成」
  /// 的 [PrefsKeys.streak] 而重複累加。
  final int streakAfter;

  /// 被結算掉的那一天有沒有全部完成（問候語用）。
  final bool yesterdayAllDone;

  /// 結算前的 lastOpenDate。問候語要靠它算久違天數，而 marker 已被推進。
  final String? previousOpenDate;

  const LogicalDayJournal({
    required this.kind,
    required this.settledDay,
    required this.streakAfter,
    required this.yesterdayAllDone,
    required this.previousOpenDate,
  });

  /// 這一天有沒有被真正結算過（baseline 不算）。
  bool settledOn(String logicalDate) =>
      kind == LogicalDayJournalKind.settlement && settledDay == logicalDate;

  static LogicalDayJournal? read(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.logicalDayJournal);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final day = decoded['settledDay'];
      if (day is! String) return null;
      return LogicalDayJournal(
        kind: decoded['kind'] == 'baseline'
            ? LogicalDayJournalKind.baseline
            : LogicalDayJournalKind.settlement,
        settledDay: day,
        streakAfter: (decoded['streakAfter'] as num?)?.toInt() ?? 0,
        yesterdayAllDone: decoded['yesterdayAllDone'] == true,
        previousOpenDate: decoded['previousOpenDate'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(SharedPreferences prefs) {
    // 單次 setString：journal 本身不會出現「寫了一半」的狀態。
    return prefs.setString(
      PrefsKeys.logicalDayJournal,
      jsonEncode({
        'kind': kind.name,
        'settledDay': settledDay,
        'streakAfter': streakAfter,
        'yesterdayAllDone': yesterdayAllDone,
        'previousOpenDate': previousOpenDate,
      }),
    );
  }
}

/// 一次跨日結算的計算結果。
@immutable
class LogicalDaySettlementResult {
  final int streak;
  final bool allDone;
  const LogicalDaySettlementResult({
    required this.streak,
    required this.allDone,
  });
}

/// 純函式結算：只看「上一個使用者邏輯日」的完成狀態決定連勝。
///
/// [historyDoneIds] 是那一天的歷史完成集合；傳 null 代表 history key 完全不
/// 存在（舊資料遷移），此時退而用持久化 habits 的 `done` 旗標。
///
/// 缺席多日只會被結算一次（呼叫端只針對 lastOpenDate 那一天呼叫），維持既有
/// 的 anti-guilt 語意：缺席三天不會歸零三次，也不會自動加三天。
LogicalDaySettlementResult settleLogicalDay({
  required List<Map<String, dynamic>> dailyHabits,
  required Set<String>? historyDoneIds,
  required int previousStreak,
}) {
  if (dailyHabits.isEmpty) {
    // 沒有每日習慣時連勝不動（既有行為）。
    return LogicalDaySettlementResult(streak: previousStreak, allDone: false);
  }
  final allDone = historyDoneIds != null
      ? dailyHabits.every((h) {
          final id = h['id'];
          return id is String && historyDoneIds.contains(id);
        })
      : dailyHabits.every((h) => h['done'] == true);
  return LogicalDaySettlementResult(
    streak: allDone ? previousStreak + 1 : 0,
    allDone: allDone,
  );
}

class LogicalDayCoordinator with WidgetsBindingObserver {
  LogicalDayCoordinator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static LogicalDayCoordinator? _singleton;
  static LogicalDayCoordinator get instance =>
      _singleton ??= LogicalDayCoordinator();

  /// 測試用：換掉全域單例（會先收掉舊的，避免殘留 observer / timer）。
  @visibleForTesting
  static set debugInstance(LogicalDayCoordinator? next) {
    _singleton?.dispose();
    _singleton = next;
  }

  final DateTime Function() _clock;

  late final _StampNotifier _stamp = _StampNotifier(null)
    ..onListenersChanged = _scheduleBoundary;
  ValueListenable<LogicalDayStamp?> get stamp => _stamp;

  /// 最近一次失敗（測試/診斷用）。失敗不會往外拋，避免擋住啟動流程。
  Object? lastError;

  bool _started = false;
  bool _disposed = false;
  int _revision = 0;
  Timer? _timer;
  bool _foreground = true;

  Future<void>? _inFlight;
  bool _pendingRecheck = false;

  /// 還沒被消費的問候 transition。只有「這一次呼叫真的跨過去了」才會擺上，
  /// 所以 RootRestart 或重新訂閱 notifier 都不會重播舊問候。
  String? _pendingGreetingId;

  // ── 生命週期 ─────────────────────────────────────────────

  /// 掛上 observer 與換日設定監聽，並完成第一次驗證。冪等：重複呼叫只會再做
  /// 一次驗證（RootRestart 之後需要這個），不會重複註冊。
  Future<void> start() {
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      LogicalDate.notifier.addListener(_onDayStartHourChanged);
      return ensureCurrent(trigger: LogicalDayTrigger.cold);
    }
    return ensureCurrent(trigger: LogicalDayTrigger.manual);
  }

  /// 收掉 observer / timer。正式版單例不呼叫；測試 reset 用。重複呼叫安全。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      LogicalDate.notifier.removeListener(_onDayStartHourChanged);
      _started = false;
    }
    _stamp.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // MainPage 也會 await 同一個 ensureCurrent，兩邊會合併成一次。
      unawaited(ensureCurrent(trigger: LogicalDayTrigger.resume));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // 背景不留計時器（省電，而且 iOS 背景 Dart timer 本來就不可靠）。
      _foreground = false;
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onDayStartHourChanged() {
    unawaited(ensureCurrent(trigger: LogicalDayTrigger.dayStartHourChanged));
  }

  // ── 主流程 ───────────────────────────────────────────────

  /// 驗證目前邏輯日，必要時結算並廣播。重複呼叫安全：
  /// 進行中的呼叫會被合併成同一個 Future，且結束後補跑一次最後檢查。
  Future<void> ensureCurrent({required LogicalDayTrigger trigger}) {
    if (_disposed) return Future<void>.value();
    final inFlight = _inFlight;
    if (inFlight != null) {
      _pendingRecheck = true;
      return inFlight;
    }
    late Future<void> future;
    future = _run(trigger).whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
      if (_pendingRecheck) {
        _pendingRecheck = false;
        unawaited(ensureCurrent(trigger: LogicalDayTrigger.manual));
      }
    });
    _inFlight = future;
    return future;
  }

  Future<void> _run(LogicalDayTrigger trigger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 用 load 而不是 hourOf：順便讓全域 notifier 與 prefs 對齊。值沒變就
      // 不會再廣播，所以不會和自己的 listener 互相觸發成迴圈。
      final hour = LogicalDate.load(prefs);
      final now = _clock();
      final nowDate = LogicalDate.stringFor(now, hour);
      final nowDay = LogicalDate.dayOf(now, hour);

      final lastOpen = prefs.getString(PrefsKeys.lastOpenDate);
      final lastOpenDay = lastOpen == null ? null : DateTime.tryParse(lastOpen);

      // 只有「邏輯日真的往前走」才算跨日。換日時間往後調會讓今天的字串往回
      // 跳，那不是新的一天——往回跳只重新廣播，不結算（既有規則）。
      final crossedForward =
          lastOpenDay != null && nowDay.isAfter(lastOpenDay);
      final firstEver = lastOpenDay == null;

      var journal = LogicalDayJournal.read(prefs);

      if (crossedForward || firstEver) {
        if (!(journal?.settledOn(nowDate) ?? false)) {
          journal = await _settle(
            prefs,
            journal: journal,
            previousOpenDate: lastOpen,
            nowDate: nowDate,
            settleStreak: crossedForward,
          );
        }
        // journal 是 commit marker，寫在所有 mutation 之前；下面每一步都是
        // 冪等覆寫，而且答案全部從 journal 讀，所以 process 在任何一步被殺，
        // 下次啟動重跑都會補完剩下的，而且不會再算一次連勝。
        await prefs.setInt(PrefsKeys.streak, journal!.streakAfter);
        await _resetDailyDone(prefs);
        await prefs.setString(PrefsKeys.lastOpenDate, nowDate);
        _pendingGreetingId = 'day:$nowDate';
      } else if (journal == null && lastOpen != null) {
        // 升級用戶第一次在本版本開啟、而且今天還沒跨日：先立一個基準點，
        // 讓下一次結算能從「已知的連勝」出發，而不是從可能是舊版中間狀態的
        // PrefsKeys.streak 出發。
        journal = LogicalDayJournal(
          kind: LogicalDayJournalKind.baseline,
          settledDay: lastOpen,
          streakAfter: prefs.getInt(PrefsKeys.streak) ?? 0,
          yesterdayAllDone: false,
          previousOpenDate: null,
        );
        await journal.write(prefs);
      }

      final settledToday = journal?.settledOn(nowDate) ?? false;
      _publish(
        LogicalDayStamp(
          logicalDate: nowDate,
          dayStartHour: hour,
          revision: _revision + 1,
          transitionId: settledToday ? 'day:$nowDate' : null,
          settledLogicalDate: settledToday ? nowDate : null,
        ),
      );
      lastError = null;
    } catch (e, st) {
      // 失敗不往外拋：啟動流程與 resume 演出都不該被邏輯日檢查擋住。
      // 什麼都不推進，下一次 resume / 邊界計時器會再試一次。
      lastError = e;
      debugPrint('LogicalDayCoordinator failed ($trigger): $e\n$st');
    } finally {
      _scheduleBoundary();
    }
  }

  /// 算出這次跨日的結果並把它 commit 進 journal。
  ///
  /// 這是整個流程唯一「非冪等」的一步（連勝是累加），所以它被 journal 擋住：
  /// 同一個邏輯日只會跑一次。journal 寫在任何 mutation 之前，之後的步驟全部
  /// 從 journal 讀答案，因此中途被殺也不會重複累加。
  Future<LogicalDayJournal> _settle(
    SharedPreferences prefs, {
    required LogicalDayJournal? journal,
    required String? previousOpenDate,
    required String nowDate,
    required bool settleStreak,
  }) async {
    // 基準優先取 journal 記的「已 commit 的連勝」，不取 PrefsKeys.streak——
    // 後者可能是上一輪寫到一半的中間值。
    final previousStreak =
        journal?.streakAfter ?? prefs.getInt(PrefsKeys.streak) ?? 0;

    var result = LogicalDaySettlementResult(
      streak: previousStreak,
      allDone: false,
    );

    if (settleStreak && previousOpenDate != null) {
      final dailyHabits = _readHabits(prefs)
          .where((h) => (h['frequency'] ?? 'daily') != 'weekly')
          .toList();
      result = settleLogicalDay(
        dailyHabits: dailyHabits,
        historyDoneIds: _historyDoneIds(prefs, previousOpenDate, dailyHabits),
        previousStreak: previousStreak,
      );
    }

    final next = LogicalDayJournal(
      kind: LogicalDayJournalKind.settlement,
      settledDay: nowDate,
      streakAfter: result.streak,
      yesterdayAllDone: result.allDone,
      previousOpenDate: previousOpenDate,
    );
    await next.write(prefs);
    return next;
  }

  /// 上一個使用者邏輯日的完成集合；null 代表「沒有可信的歷史」，呼叫端要退回
  /// 用持久化 habits 的 done 旗標。
  ///
  /// 兩個判定條件：
  ///   1. history key 必須存在。注意 [HabitHistory.setDoneIdsOn] 在空集合時會
  ///      `remove` key，所以「那天什麼都沒完成」與「還沒有歷史」在 storage 上
  ///      長得一樣；但這種情況下 fallback 讀到的 done 旗標同樣是全 false，兩條
  ///      路的結果一致，不會把「真的全部未完成」誤判成有完成。
  ///   2. 每個每日習慣都要有 id。歷史以 id 記錄，遷移前的舊習慣沒有 id、永遠
  ///      不會出現在歷史裡，只能走 fallback。
  Set<String>? _historyDoneIds(
    SharedPreferences prefs,
    String date,
    List<Map<String, dynamic>> dailyHabits,
  ) {
    if (!prefs.containsKey(PrefsKeys.habitDoneDay(date))) return null;
    final allHaveId = dailyHabits.every(
      (h) => h['id'] is String && (h['id'] as String).isNotEmpty,
    );
    if (!allHaveId) return null;
    return HabitHistory.doneIdsOn(prefs, date).toSet();
  }

  /// 把每日習慣的勾選清空。冪等覆寫：重跑不會有副作用。
  /// 每週習慣走 weeklyDates，不在這裡動。
  Future<void> _resetDailyDone(SharedPreferences prefs) async {
    final habits = _readHabits(prefs);
    var changed = false;
    for (final habit in habits) {
      if ((habit['frequency'] ?? 'daily') != 'weekly' &&
          habit['done'] != false) {
        habit['done'] = false;
        changed = true;
      }
    }
    if (changed) {
      await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    }
  }

  List<Map<String, dynamic>> _readHabits(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.habits);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 廣播 ─────────────────────────────────────────────────

  /// 只在「真的有變化」時廣播：同一天的 resume 不會讓下游白重載一次。
  void _publish(LogicalDayStamp next) {
    final current = _stamp.value;
    final changed =
        current == null ||
        current.logicalDate != next.logicalDate ||
        current.dayStartHour != next.dayStartHour ||
        current.transitionId != next.transitionId;
    if (!changed) return;
    _revision = next.revision;
    _stamp.value = next;
  }

  /// 問候只該播一次。回傳 true 代表這次由呼叫端負責播。
  ///
  /// 待消費的 token 存在 coordinator（單例）而不是 widget state，所以
  /// RootRestart、widget rebuild、重新訂閱 notifier 都不會重播舊問候。
  bool consumeGreeting(String? transitionId) {
    if (transitionId == null) return false;
    if (_pendingGreetingId != transitionId) return false;
    _pendingGreetingId = null;
    return true;
  }

  // ── 邊界計時器 ───────────────────────────────────────────

  void _scheduleBoundary() {
    _timer?.cancel();
    _timer = null;
    // 沒有訂閱者就不排程：沒人在看的時候，前景邊界檢查沒有意義（下一次
    // resume 或重新訂閱都會補驗證）。同時讓 widget 樹拆掉的測試不留 timer。
    if (_disposed || !_started || !_foreground || !_stamp.hasAnyListener) {
      return;
    }
    final hour = _stamp.value?.dayStartHour ?? LogicalDate.defaultHour;
    final now = _clock();
    var delay = nextBoundaryAfter(now, hour).difference(now);
    if (delay < Duration.zero) delay = Duration.zero;
    if (delay > kLogicalDayWatchdogInterval) {
      delay = kLogicalDayWatchdogInterval;
    } else {
      // 多等一秒，避免時鐘精度讓我們剛好卡在邊界前一毫秒醒來。
      delay += const Duration(seconds: 1);
    }
    _timer = Timer(delay, () {
      // 醒來一律以實際時鐘重新驗證，不假設一定已經跨日（看門狗就是這樣運作的）。
      unawaited(ensureCurrent(trigger: LogicalDayTrigger.boundaryTimer));
    });
  }

  /// 下一個換日邊界（本地時間）。
  ///
  /// 刻意用「年/月/日/時」重建 DateTime，而不是 `add(Duration(days: 1))`：
  /// 後者加的是絕對 24 小時，遇到 DST 或時區的日曆跳轉會偏掉一小時。
  @visibleForTesting
  static DateTime nextBoundaryAfter(DateTime now, int dayStartHour) {
    final h = dayStartHour.clamp(LogicalDate.minHour, LogicalDate.maxHour);
    final day = LogicalDate.dayOf(now, h);
    final end = DateTime(day.year, day.month, day.day + 1, h);
    if (end.isAfter(now)) return end;
    // DST 之類讓邊界落在現在之前時，往後再推一個日曆日。
    return DateTime(day.year, day.month, day.day + 2, h);
  }

  @visibleForTesting
  bool get hasScheduledBoundary => _timer != null;
}

/// 只是為了讓 coordinator 知道「還有沒有人在訂閱」，用來決定要不要排邊界計時器。
class _StampNotifier extends ValueNotifier<LogicalDayStamp?> {
  _StampNotifier(super.value);

  VoidCallback? onListenersChanged;

  bool get hasAnyListener => hasListeners;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    onListenersChanged?.call();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    onListenersChanged?.call();
  }
}
