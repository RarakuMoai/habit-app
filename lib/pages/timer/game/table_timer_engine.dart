// 桌遊計時器的回合狀態機（純邏輯，無 UI 依賴）。
//
// 計時原則：剩餘時間永遠由「牆鐘時間差」算出（turnStartedAt +
// 已暫停累計），內部 Timer 只負責觸發重繪與跨越門檻事件——掉幀、
// 慢景框都不會讓時間飄移。時間與 Timer 都可注入，單測不用等真時間。
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'table_timer_models.dart';

/// 對局階段。超時不是獨立階段（見 [TableTimerEngine.inOvertime]）：
/// 超時仍在 running，只是剩餘時間為負。
/// [finished] 只在棋鐘總時間制出現：有人時間用盡＝旗倒終局。
enum TablePhase { ready, running, paused, finished }

/// 引擎對外的時間驅動事件（點擊換人是 UI 主動呼叫，不在此列）。
enum TableTimerEvent {
  /// 進入「明顯提醒」區（剩 warnSeconds 秒）。
  warn,

  /// 加強提醒區內每跨過一整秒觸發一次（剩 5、4、3…）。
  criticalTick,

  /// 時間用完（超時瞬間，手動模式進入超時態）。
  expire,

  /// 超時且設定自動換人，引擎自己把回合推進了。
  autoAdvance,
}

class TableTimerEngine extends ChangeNotifier {
  TableTimerEngine(
    this.config, {
    DateTime Function()? clock,
    this.autoTick = true,
  }) : _now = clock ?? DateTime.now {
    players = config.activePlayers;
    stats = [for (final _ in players) TurnStats()];
    _banks = [for (final _ in players) Duration(seconds: config.bankSeconds)];
  }

  final TableTimerConfig config;

  /// 測試時關掉內部 Timer，改由測試自己呼叫 [tick]。
  final bool autoTick;

  final DateTime Function() _now;
  Timer? _timer;

  late final List<TablePlayer> players;
  late final List<TurnStats> stats;

  /// 時間驅動事件出口（UI 掛上去播音效/震動）。
  void Function(TableTimerEvent event)? onEvent;

  TablePhase _phase = TablePhase.ready;
  int _currentIndex = 0;
  int _turnCount = 0; // 本局累計第幾手（從 1 起算）

  DateTime? _turnStartedAt; // 本回合最近一次「開始跑」的時刻
  Duration _turnCarry = Duration.zero; // 暫停累計的已消耗時間

  // 棋鐘總時間制：每人的時間庫（每回合制不看它）
  late final List<Duration> _banks;
  int? _flagFallIndex; // 旗倒的人（總時間制終局）

  // 誤觸救援：最近一次換人前的完整快照（單步）
  _TurnSnapshot? _undoSnapshot;

  // 事件去重：warn/expire 每回合只發一次；criticalTick 記上次發過的秒數
  bool _warned = false;
  bool _expired = false;
  int _lastCriticalSecond = -1;

  bool get isFree => config.mode == TableGameMode.free;

  /// 棋鐘總時間制（時間庫）。
  bool get isBank => config.usesBank;

  /// 旗倒的人（只在 [TablePhase.finished] 非 null）。
  int? get flagFallIndex => _flagFallIndex;

  /// 有上一步可回（快照式單步救援）。
  bool get canUndo =>
      _undoSnapshot != null &&
      (_phase == TablePhase.running || _phase == TablePhase.paused);

  /// 已結算的總手數（結算面用：0 = 沒真的玩，直接離開不秀小結）。
  int get settledTurns => stats.fold(0, (sum, s) => sum + s.turns);
  TablePhase get phase => _phase;
  int get currentIndex => _currentIndex;
  int get turnCount => _turnCount;
  TablePlayer get currentPlayer => players[_currentIndex];
  TablePlayer get nextPlayer => players[(_currentIndex + 1) % players.length];

  /// 本回合已消耗時間（free 模式的主顯示）。
  Duration get elapsedInTurn {
    final started = _turnStartedAt;
    final running = (_phase == TablePhase.running && started != null)
        ? _now().difference(started)
        : Duration.zero;
    return _turnCarry + running;
  }

  /// 剩餘時間（可為負 = 超時中）。free 模式無意義，回 zero。
  /// 總時間制看目前玩家的時間庫，每回合制看 turnSeconds。
  Duration get remaining {
    if (isFree) return Duration.zero;
    final total = isBank
        ? _banks[_currentIndex]
        : Duration(seconds: config.turnSeconds);
    return total - elapsedInTurn;
  }

  /// 顯示用剩餘整秒（無條件進位：59.2 秒顯示 60，歸零瞬間才顯示 0）。
  int get remainingSeconds {
    final ms = remaining.inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// 超時已過秒數（手動模式的紅色正數）。
  int get overtimeSeconds {
    final ms = -remaining.inMilliseconds;
    return ms <= 0 ? 0 : ms ~/ 1000;
  }

  bool get inOvertime =>
      !isFree && _phase == TablePhase.running && remaining < Duration.zero;

  /// 顯示用：某位玩家的時間庫剩餘整秒（總時間制）。輪到的人算上
  /// 進行中的消耗，其他人就是庫存。
  int bankDisplaySeconds(int i) {
    final ms = (i == _currentIndex ? remaining : _banks[i]).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// 0.0–1.0 倒數環進度（剩餘比例）。
  double get ringProgress {
    if (isFree || config.turnSeconds <= 0) return 1.0;
    final total = config.turnSeconds * 1000;
    return (remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// 警示層級：0 正常、1 明顯提醒（琥珀）、2 加強（紅）、3 超時。
  int get urgency {
    if (isFree || _phase != TablePhase.running) return 0;
    final ms = remaining.inMilliseconds;
    if (ms <= 0) return 3;
    if (ms <= config.criticalSeconds * 1000) return 2;
    if (ms <= config.warnSeconds * 1000) return 1;
    return 0;
  }

  /// 第一次點擊：從 ready 起跑。預設玩家 0；棋鐘用 [at] 指定
  /// 起跑方（實體棋鐘慣例：按自己那側＝啟動對方的鐘）。
  void start({int? at}) {
    if (_phase != TablePhase.ready) return;
    if (at != null) _currentIndex = at.clamp(0, players.length - 1);
    _phase = TablePhase.running;
    _turnCount = 1;
    _beginTurnClock();
    _ensureTimer();
    notifyListeners();
  }

  /// 換下一位（點擊主畫面 / 棋鐘按自己那半 / 超時自動）。
  void advance() {
    if (_phase != TablePhase.running) return;
    // 總時間制：庫存其實已用盡（tick 還沒跑到）→ 走旗倒，不是換人
    if (isBank && remaining <= Duration.zero) {
      tick();
      return;
    }
    _undoSnapshot = _TurnSnapshot.capture(this);
    final spent = elapsedInTurn;
    _settleStats(spent);
    if (isBank) {
      _banks[_currentIndex] +=
          Duration(seconds: config.incrementSeconds) - spent;
    }
    _currentIndex = (_currentIndex + 1) % players.length;
    _turnCount += 1;
    _beginTurnClock();
    notifyListeners();
  }

  /// 誤觸救援：整包回到「上一次換人前」的狀態（單步快照）。
  /// 時間庫、統計都精確還原，被打斷的那一手時間整段重來。
  void undo() {
    final snap = _undoSnapshot;
    if (!canUndo || snap == null) return;
    snap.restore(this);
    _undoSnapshot = null;
    _beginTurnClock();
    if (_phase == TablePhase.paused) _phase = TablePhase.running;
    notifyListeners();
  }

  void pause() {
    if (_phase != TablePhase.running) return;
    _turnCarry = elapsedInTurn;
    _turnStartedAt = null;
    _phase = TablePhase.paused;
    notifyListeners();
  }

  void resume() {
    if (_phase != TablePhase.paused) return;
    _turnStartedAt = _now();
    _phase = TablePhase.running;
    notifyListeners();
  }

  /// 重開目前這一回合（時間重來，輪到的人不變）。
  void restartTurn() {
    if (_phase == TablePhase.ready) return;
    _beginTurnClock();
    if (_phase == TablePhase.paused) _phase = TablePhase.running;
    notifyListeners();
  }

  /// 內部 Timer 每跳呼叫；測試用假時鐘時手動呼叫。
  void tick() {
    if (_phase != TablePhase.running) return;
    if (isFree) {
      notifyListeners(); // 正數計時只要重繪，沒有門檻事件
      return;
    }
    final ms = remaining.inMilliseconds;

    if (!_warned && ms <= config.warnSeconds * 1000 && ms > 0) {
      _warned = true;
      onEvent?.call(TableTimerEvent.warn);
    }
    if (ms > 0 && ms <= config.criticalSeconds * 1000) {
      final sec = (ms / 1000).ceil();
      if (sec != _lastCriticalSecond) {
        _lastCriticalSecond = sec;
        onEvent?.call(TableTimerEvent.criticalTick);
      }
    }
    if (!_expired && ms <= 0) {
      _expired = true;
      onEvent?.call(TableTimerEvent.expire);
      if (isBank) {
        // 旗倒終局：時間花完的這手也計入統計，鐘停在 0:00
        _settleStats(elapsedInTurn);
        _banks[_currentIndex] = Duration.zero;
        _turnCarry = Duration.zero;
        _turnStartedAt = null;
        _flagFallIndex = _currentIndex;
        _phase = TablePhase.finished;
        notifyListeners();
        return;
      }
      if (config.autoAdvance) {
        advance();
        onEvent?.call(TableTimerEvent.autoAdvance);
        return; // advance 已 notify
      }
    }
    notifyListeners();
  }

  void _beginTurnClock() {
    _turnStartedAt = _now();
    _turnCarry = Duration.zero;
    _warned = false;
    _expired = false;
    _lastCriticalSecond = -1;
  }

  /// 結算目前玩家這一手的統計（換人／旗倒前呼叫）。
  void _settleStats(Duration spent) {
    final st = stats[_currentIndex];
    st.turns += 1;
    st.totalThink += spent;
  }

  void _ensureTimer() {
    if (!autoTick || _timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) => tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// 換人前的完整快照（單步 undo 用）：輪到誰、手數、時間庫、統計。
class _TurnSnapshot {
  final int index;
  final int turnCount;
  final List<Duration> banks;
  final List<int> statTurns;
  final List<Duration> statThink;

  _TurnSnapshot._({
    required this.index,
    required this.turnCount,
    required this.banks,
    required this.statTurns,
    required this.statThink,
  });

  factory _TurnSnapshot.capture(TableTimerEngine e) => _TurnSnapshot._(
    index: e._currentIndex,
    turnCount: e._turnCount,
    banks: List.of(e._banks),
    statTurns: [for (final s in e.stats) s.turns],
    statThink: [for (final s in e.stats) s.totalThink],
  );

  void restore(TableTimerEngine e) {
    e._currentIndex = index;
    e._turnCount = turnCount;
    for (var i = 0; i < e._banks.length; i++) {
      e._banks[i] = banks[i];
    }
    for (var i = 0; i < e.stats.length; i++) {
      e.stats[i]
        ..turns = statTurns[i]
        ..totalThink = statThink[i];
    }
  }
}
