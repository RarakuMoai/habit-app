import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/prefs_keys.dart';

// 遊戲計時器的純邏輯層：狀態機 + 時間運算 + undo 歷史，不碰任何 UI/音效/
// 鎖屏/互斥。副作用一律由 GameSession 接線，畫面（卡片/全螢幕）只透過
// ChangeNotifier 監聽重繪——所有狀態變化都從這裡的方法出去，通知是唯一
// 出口，不存在「改了狀態忘記通知另一個畫面」的空間。

/// 計時模式：每回合（每位玩家每輪都重置秒數）／棋鐘（每人一桶累計時間）。
enum GameClockMode { turn, bank }

/// 戰局階段。idle=未開局（待機預覽）、finished=棋鐘決出勝負。
enum GameClockPhase { idle, running, paused, finished }

/// 由 tick 驅動、需要音效回饋的邏輯事件。使用者主動操作（開始/換手/重設）
/// 的回饋由 GameSession 在意圖方法裡直接發，不走事件。
enum GameClockEvent {
  /// 最後幾秒每秒提示
  warnTick,

  /// 每回合模式歸零進入超時（不換手，往上數）
  turnTimeUp,

  /// 棋鐘：有人時間用完出局，戰局尚未結束
  playerFlagged,

  /// 棋鐘：決出勝負
  finished,
}

const int kGameMinPlayers = 2;
const int kGameMaxPlayers = 8;

/// 一個座位（玩家）。[id] 是穩定識別（拖曳排序的動畫 key 用），排序移動的
/// 是整個物件，不再有多條平行陣列靠 index 對位的問題。
class GamePlayer {
  final int id;
  String name;
  double remaining = 0;
  bool flagged = false;

  GamePlayer(this.id, [this.name = '']);
}

/// 「上一位」還原用的戰局快照：每次換手／棋鐘超時前存一份，整包蓋回去，
/// 兩種模式通用，不用個別反推增秒/超時邏輯。
class _GameSnapshot {
  final int active;
  final List<double> remaining;
  final List<bool> flagged;
  final int winner;

  _GameSnapshot(this.active, this.remaining, this.flagged, this.winner);
}

/// 秒數 → M:SS（負值＝超時，前面加 +）。
String formatGameClock(double s) {
  final neg = s < 0;
  final t = s.abs().ceil();
  final core = '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  return neg ? '+$core' : core;
}

/// 設定/摘要用的友善時長（5 秒 / 1 分 30 秒）。
String formatGameDuration(int s) {
  if (s < 60) return '$s 秒';
  final m = s ~/ 60;
  final ss = s % 60;
  return ss == 0 ? '$m 分' : '$m 分 $ss 秒';
}

class GameClockController extends ChangeNotifier {
  GameClockController() {
    _resetPreview(); // 未載入設定前也保持合法的待機預覽（每人滿格）
  }

  // ── 設定（透過 mutator 修改；開局後鎖定）──
  GameClockMode _mode = GameClockMode.turn;
  int _count = 2;
  int _turnSeconds = 30;
  int _bankSeconds = 300;
  int _increment = 0; // Fischer：棋鐘每完成一手加幾秒
  bool _warnEnabled = true;
  int _warnSeconds = 5;
  bool _loaded = false;

  /// 8 個座位常駐（隱藏座位保留名字，人數改回來名字還在），
  /// 戰局操作只碰前 [playerCount] 位。
  final List<GamePlayer> _seats = List.generate(
    kGameMaxPlayers,
    GamePlayer.new,
  );

  // ── 戰局狀態 ──
  GameClockPhase _phase = GameClockPhase.idle;
  int _active = 0;
  int _winner = -1;
  final List<_GameSnapshot> _history = [];

  /// 圓環進度（每幀更新走 ValueListenable，不走 notifyListeners；
  /// 數字/離散狀態只在跨秒或換手時通知）。
  final ValueNotifier<double> ringProgress = ValueNotifier<double>(1);

  /// tick 驅動的邏輯事件出口（GameSession 對映成音效/觸覺）。
  void Function(GameClockEvent event)? onEvent;

  /// 棋鐘超時被「上一位」還原時，給該玩家的寬限秒數。直接還原負秒數會讓
  /// 之後的歸零判斷（before > 0）永遠不成立＝該玩家再也不會被判出局。
  static const double undoGraceSeconds = 5;

  static const int _maxHistory = 100;

  // ── 衍生 ──

  GameClockMode get mode => _mode;
  int get playerCount => _count;
  int get turnSeconds => _turnSeconds;
  int get bankSeconds => _bankSeconds;
  int get increment => _increment;
  bool get warnEnabled => _warnEnabled;
  int get warnSeconds => _warnSeconds;
  bool get loaded => _loaded;

  GameClockPhase get phase => _phase;
  bool get started => _phase != GameClockPhase.idle;
  bool get running => _phase == GameClockPhase.running;
  bool get paused => _phase == GameClockPhase.paused;
  bool get finished => _phase == GameClockPhase.finished;
  int get activeIndex => _active;
  int get winnerIndex => _winner;
  bool get canUndo => _history.isNotEmpty && started;

  /// 目前戰局中的玩家（前 [playerCount] 個座位）。
  UnmodifiableListView<GamePlayer> get players =>
      UnmodifiableListView(_seats.sublist(0, _count));

  GamePlayer playerAt(int i) => _seats[i];
  GamePlayer get activePlayer => _seats[_active];

  int get fullSeconds =>
      _mode == GameClockMode.turn ? _turnSeconds : _bankSeconds;

  /// 每回合模式歸零後進入超時（往上數，等使用者換手）。
  bool get turnOvertime =>
      _mode == GameClockMode.turn && started && activePlayer.remaining < 0;

  String nameOf(int i) {
    final n = _seats[i].name.trim();
    return n.isEmpty ? '玩家${i + 1}' : n;
  }

  double progressOf(int i) {
    final p = _seats[i];
    if (p.flagged || p.remaining <= 0) return 0;
    return (p.remaining / fullSeconds).clamp(0.0, 1.0);
  }

  // ── 載入 / 持久化（key 沿用舊版，既有設定無痛沿用）──

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _count = (p.getInt(PrefsKeys.gameTimerPlayerCount) ?? 2).clamp(
      kGameMinPlayers,
      kGameMaxPlayers,
    );
    final stored = p.getStringList(PrefsKeys.gameTimerNames) ?? const [];
    for (var i = 0; i < kGameMaxPlayers; i++) {
      _seats[i].name = i < stored.length ? stored[i] : '';
    }
    _mode = p.getString(PrefsKeys.gameTimerMode) == 'bank'
        ? GameClockMode.bank
        : GameClockMode.turn;
    _turnSeconds = (p.getInt(PrefsKeys.gameTimerTurnSeconds) ?? 30).clamp(
      5,
      600,
    );
    _bankSeconds = (p.getInt(PrefsKeys.gameTimerBankSeconds) ?? 300).clamp(
      30,
      3600,
    );
    _increment = (p.getInt(PrefsKeys.gameTimerIncrement) ?? 0).clamp(0, 60);
    _warnEnabled = p.getBool(PrefsKeys.gameTimerWarnEnabled) ?? true;
    _warnSeconds = (p.getInt(PrefsKeys.gameTimerWarnSeconds) ?? 5).clamp(3, 30);
    _resetPreview();
    _loaded = true;
    notifyListeners();
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(PrefsKeys.gameTimerPlayerCount, _count);
    await p.setStringList(PrefsKeys.gameTimerNames, [
      for (final s in _seats) s.name,
    ]);
    await p.setString(
      PrefsKeys.gameTimerMode,
      _mode == GameClockMode.bank ? 'bank' : 'turn',
    );
    await p.setInt(PrefsKeys.gameTimerTurnSeconds, _turnSeconds);
    await p.setInt(PrefsKeys.gameTimerBankSeconds, _bankSeconds);
    await p.setInt(PrefsKeys.gameTimerIncrement, _increment);
    await p.setBool(PrefsKeys.gameTimerWarnEnabled, _warnEnabled);
    await p.setInt(PrefsKeys.gameTimerWarnSeconds, _warnSeconds);
  }

  // ── 設定 mutator（設定面板只在待機開，仍防禦性擋掉開局後的結構變更）──

  void setMode(GameClockMode v) => _applySetting(() => _mode = v);

  void setPlayerCount(int v) =>
      _applySetting(() => _count = v.clamp(kGameMinPlayers, kGameMaxPlayers));

  void setTurnSeconds(int v) =>
      _applySetting(() => _turnSeconds = v.clamp(5, 600));

  void setBankSeconds(int v) =>
      _applySetting(() => _bankSeconds = v.clamp(30, 3600));

  void setIncrement(int v) => _applySetting(() => _increment = v.clamp(0, 60));

  void setWarnEnabled(bool v) => _applySetting(() => _warnEnabled = v);

  void setWarnSeconds(int v) =>
      _applySetting(() => _warnSeconds = v.clamp(3, 30));

  void renamePlayer(int i, String name) => _applySetting(() {
    _seats[i].name = name;
  });

  /// 拖曳排序：搬整個座位物件（名字跟著人走），先手指到的還是同一位。
  void movePlayer(int oldIndex, int newIndex) {
    if (started) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _count) return;
    if (newIndex < 0 || newIndex >= _count) return;
    final activePlayer = _seats[_active];
    final moved = _seats.removeAt(oldIndex);
    _seats.insert(newIndex, moved);
    final next = _seats.indexOf(activePlayer);
    _active = next >= 0 && next < _count ? next : 0;
    _resetPreview();
    notifyListeners();
  }

  /// 待機時點玩家卡＝指定先手。
  void pickFirstPlayer(int i) {
    if (started || i < 0 || i >= _count) return;
    _active = i;
    ringProgress.value = progressOf(_active);
    notifyListeners();
  }

  void _applySetting(VoidCallback change) {
    if (started) return;
    change();
    _resetPreview();
    notifyListeners();
  }

  // 待機預覽：每人滿格、無人出局、保留目前選的先手。
  void _resetPreview() {
    final full = fullSeconds.toDouble();
    for (final s in _seats) {
      s.remaining = full;
      s.flagged = false;
    }
    if (_active >= _count) _active = 0;
    _winner = -1;
    ringProgress.value = 1;
  }

  // ── 戰局操作 ──

  /// 開始（idle→新開局）或繼續（paused→接著跑）。
  /// 決出勝負後要先 [reset]；回傳是否真的有啟動。
  bool start() {
    if (running || finished) return false;
    if (_phase == GameClockPhase.idle) {
      _resetPreview();
      _history.clear();
    }
    _phase = GameClockPhase.running;
    ringProgress.value = progressOf(_active);
    notifyListeners();
    return true;
  }

  bool pause() {
    if (!running) return false;
    _phase = GameClockPhase.paused;
    notifyListeners();
    return true;
  }

  /// 換手：棋鐘先給剛走完的玩家加 Fischer 增秒，再輪到下一位未出局者。
  bool pass() {
    if (!running) return false;
    _pushSnapshot();
    final p = activePlayer;
    if (_mode == GameClockMode.bank &&
        _increment > 0 &&
        !p.flagged &&
        p.remaining > 0) {
      p.remaining += _increment;
    }
    _advance();
    notifyListeners();
    return true;
  }

  /// 上一位：回到換手（或棋鐘超時）前那一刻。沒有歷史可還原時回 false。
  bool undo() {
    if (!canUndo) return false;
    final snap = _history.removeLast();
    _active = snap.active;
    for (var i = 0; i < _count; i++) {
      _seats[i].remaining = snap.remaining[i];
      _seats[i].flagged = snap.flagged[i];
    }
    _winner = snap.winner;
    // 還原掉勝負後回暫停（使用者按繼續再開），進行中則維持進行。
    if (_phase == GameClockPhase.finished) _phase = GameClockPhase.paused;
    ringProgress.value = progressOf(_active);
    notifyListeners();
    return true;
  }

  bool reset() {
    if (!started) return false;
    _phase = GameClockPhase.idle;
    _history.clear();
    _resetPreview();
    notifyListeners();
    return true;
  }

  /// 每幀扣目前玩家的時間：圓環走 [ringProgress] 平滑更新，跨整秒才通知
  /// 重繪數字並發最後幾秒提示；歸零交給 [_onTimeUp]。
  void tick(double dt) {
    if (!running || dt <= 0) return;
    final p = activePlayer;
    final before = p.remaining;
    final after = before - dt;
    p.remaining = after;
    ringProgress.value = progressOf(_active);

    if (before > 0 && after <= 0) {
      _onTimeUp();
      return;
    }
    if (after.ceil() != before.ceil()) {
      if (_warnEnabled && after > 0 && after.ceil() <= _warnSeconds) {
        onEvent?.call(GameClockEvent.warnTick);
      }
      notifyListeners();
    }
  }

  void _onTimeUp() {
    if (_mode == GameClockMode.bank) {
      // 快照存「寬限版」：被還原時該玩家拿回幾秒，而不是負秒數的死局。
      _pushSnapshot(graceFor: _active);
      final p = activePlayer;
      p.remaining = 0;
      p.flagged = true;
      final alive = [
        for (var i = 0; i < _count; i++)
          if (!_seats[i].flagged) i,
      ];
      if (alive.length <= 1) {
        _winner = alive.isEmpty ? -1 : alive.first;
        _phase = GameClockPhase.finished;
        ringProgress.value = 0;
        onEvent?.call(GameClockEvent.finished);
      } else {
        _advance();
        onEvent?.call(GameClockEvent.playerFlagged);
      }
    } else {
      // 每回合模式：不換手，進入超時往上數，等使用者按下一位。
      onEvent?.call(GameClockEvent.turnTimeUp);
    }
    notifyListeners();
  }

  // 輪到下一位未出局玩家；每回合模式幫新的一手裝滿秒數。
  void _advance() {
    var n = _active;
    for (var step = 0; step < _count; step++) {
      n = (n + 1) % _count;
      if (!_seats[n].flagged) break;
    }
    _active = n;
    if (_mode == GameClockMode.turn) {
      _seats[_active].remaining = _turnSeconds.toDouble();
    }
    ringProgress.value = progressOf(_active);
  }

  void _pushSnapshot({int? graceFor}) {
    final remaining = [for (var i = 0; i < _count; i++) _seats[i].remaining];
    if (graceFor != null) remaining[graceFor] = undoGraceSeconds;
    _history.add(
      _GameSnapshot(_active, remaining, [
        for (var i = 0; i < _count; i++) _seats[i].flagged,
      ], _winner),
    );
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  @override
  void dispose() {
    ringProgress.dispose();
    super.dispose();
  }
}
