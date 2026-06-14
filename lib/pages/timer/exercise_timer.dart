import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/coin_config.dart';
import '../../utils/coin_service.dart';
import '../../utils/mascot.dart';
import '../../utils/metronome_service.dart';
import '../../utils/notification_service.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/hold_repeat_button.dart';
import '../../widgets/timer_ring_painter.dart';

// 計時頁「運動」模式：間歇訓練計時器。
// 引擎沿用番茄鐘那套 wall-clock（用 endTime 反推剩餘）＋背景回來補算多階段
// ＋鏈式通知，所以鎖屏也準。五種子模式（Tabata / HIIT / EMOM / 重訓 / 超慢跑），
// 階段序列：準備 →（暖身）→ [運動 → 休息]×回合 → 完成。

enum ExerciseKind { tabata, hiit, emom, gym, jog }

enum _ExPhase { idle, prep, warmup, work, rest, finished }

// 子模式靜態資訊（名稱/說明/圖示/主色）
typedef _ExMeta = ({String name, String desc, IconData icon, Color color});

const Map<ExerciseKind, _ExMeta> _exMeta = {
  ExerciseKind.tabata: (
    name: 'Tabata',
    desc: '20 秒衝刺 / 10 秒喘息',
    icon: Icons.bolt_rounded,
    color: Color(0xFFEF5350),
  ),
  ExerciseKind.hiit: (
    name: 'HIIT',
    desc: '高強度有氧間歇',
    icon: Icons.whatshot_rounded,
    color: Color(0xFFFF8A50),
  ),
  ExerciseKind.emom: (
    name: 'EMOM',
    desc: '每分鐘一組循環',
    icon: Icons.repeat_rounded,
    color: Color(0xFF66BB6A),
  ),
  ExerciseKind.gym: (
    name: '重訓',
    desc: '組數與組間休息',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF42A5F5),
  ),
  ExerciseKind.jog: (
    name: '超慢跑',
    desc: '180 BPM 輕鬆節拍',
    icon: Icons.directions_run_rounded,
    color: Color(0xFFAB47BC),
  ),
};

// 可調設定（會持久化）。loop=true（EMOM）時沒有獨立休息段。
class _ExConfig {
  int work;
  int rest;
  int rounds;
  int prep;
  bool warmupOn;
  int warmup;
  int bpm;
  bool metronomeOn;
  bool metronomeSoundOn;
  double metronomeVolume;
  MetronomeTone metronomeTone;
  final bool loop;

  _ExConfig({
    required this.work,
    required this.rest,
    required this.rounds,
    required this.prep,
    required this.warmupOn,
    required this.warmup,
    required this.bpm,
    required this.metronomeOn,
    required this.metronomeSoundOn,
    required this.metronomeVolume,
    required this.metronomeTone,
    required this.loop,
  });
}

_ExConfig _defaultConfig(ExerciseKind k) => switch (k) {
  ExerciseKind.tabata => _ExConfig(
    work: 20,
    rest: 10,
    rounds: 8,
    prep: 5,
    warmupOn: false,
    warmup: 60,
    bpm: 0,
    metronomeOn: false,
    metronomeSoundOn: false,
    metronomeVolume: 0.0,
    metronomeTone: MetronomeTone.kick,
    loop: false,
  ),
  ExerciseKind.hiit => _ExConfig(
    work: 30,
    rest: 30,
    rounds: 10,
    prep: 5,
    warmupOn: true,
    warmup: 120,
    bpm: 0,
    metronomeOn: false,
    metronomeSoundOn: false,
    metronomeVolume: 0.0,
    metronomeTone: MetronomeTone.kick,
    loop: false,
  ),
  ExerciseKind.emom => _ExConfig(
    work: 60,
    rest: 0,
    rounds: 10,
    prep: 5,
    warmupOn: false,
    warmup: 60,
    bpm: 0,
    metronomeOn: false,
    metronomeSoundOn: false,
    metronomeVolume: 0.0,
    metronomeTone: MetronomeTone.kick,
    loop: true,
  ),
  ExerciseKind.gym => _ExConfig(
    work: 40,
    rest: 90,
    rounds: 5,
    prep: 5,
    warmupOn: false,
    warmup: 0,
    bpm: 0,
    metronomeOn: false,
    metronomeSoundOn: false,
    metronomeVolume: 0.0,
    metronomeTone: MetronomeTone.kick,
    loop: false,
  ),
  ExerciseKind.jog => _ExConfig(
    work: 1800,
    rest: 0,
    rounds: 1,
    prep: 5,
    warmupOn: true,
    warmup: 180,
    bpm: 180,
    metronomeOn: true,
    metronomeSoundOn: true,
    metronomeVolume: 0.75,
    metronomeTone: MetronomeTone.kick,
    loop: true,
  ),
};

// 階段序列的一個項目
typedef _Step = ({_ExPhase phase, int dur, int round});

class ExerciseTimer extends StatefulWidget {
  const ExerciseTimer({super.key});

  @override
  State<ExerciseTimer> createState() => ExerciseTimerState();
}

class ExerciseTimerState extends State<ExerciseTimer>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // 通知 id 區段（與番茄鐘 1001..1006 分開）
  static const int _notifIdBase = 1100;
  static const int _maxNotifs = 40;
  static const Duration _tickerInterval = Duration(milliseconds: 100);

  ExerciseKind _kind = ExerciseKind.tabata;
  final Map<ExerciseKind, _ExConfig> _configs = {
    for (final k in ExerciseKind.values) k: _defaultConfig(k),
  };

  // ── 計時狀態 ──
  List<_Step> _seq = const [];
  int _idx = 0;
  _ExPhase _phase = _ExPhase.idle;
  int _round = 1;
  int _secondsLeft = 0;
  int _phaseTotal = 0;
  bool _isRunning = false;
  Timer? _timer;
  Timer? _boundaryTimer;
  DateTime? _endTime;
  bool _phaseCompleteHold = false;
  bool _advancingBoundary = false;
  int _completedWorkSeconds = 0;
  // 本階段已經嗶過的「剩餘秒數」（3→2→1 各一次，換階段歸零）
  int _lastCueSec = 0;

  // ── 節拍器（超慢跑）──
  // 聲音走 MetronomeService 的無縫循環（音訊引擎等速）；擺錘＋觸覺走這個 Ticker
  // 的連續正弦相位（每幀讀當下 BPM，改速平順不跳）。兩者開跑時對齊。
  bool _metroRunning = false;
  Ticker? _metroTicker;
  final ValueNotifier<double> _pendAngle = ValueNotifier<double>(0);
  double _pendPhase = math.pi / 2; // 起手在極端＝第一拍
  Duration _lastTickElapsed = Duration.zero;
  int _lastBeatIndex = -1;
  Timer? _loopRegenDebounce; // 改 BPM 連按時，延遲重生音訊循環
  static const double _pendMaxAngle = 0.46; // 擺幅 ±約 26°

  // ── 今日統計（per-day key）──
  String _statsDate = '';
  int _todaySessions = 0;
  int _todayMinutes = 0;

  late final AnimationController _breath;

  _ExConfig get _cfg => _configs[_kind]!;
  bool get _idle => _phase == _ExPhase.idle;
  bool get _finished => _phase == _ExPhase.finished;
  bool get _jogWorkActive =>
      _kind == ExerciseKind.jog && _phase == _ExPhase.work && _isRunning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _metroTicker = createTicker(_onMetroTick);
    _loadPrefs();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loopRegenDebounce?.cancel();
    _stopMetronome();
    _metroTicker?.dispose();
    _pendAngle.dispose();
    _breath.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopMetronome();
    }
    if (state == AppLifecycleState.resumed && _isRunning) {
      _refreshFromEndTime();
      _syncMetronome();
    }
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateStr(DateTime.now());
    for (final k in ExerciseKind.values) {
      final id = k.name;
      final d = _defaultConfig(k);
      _configs[k] = _ExConfig(
        work: prefs.getInt(PrefsKeys.exerciseWork(id)) ?? d.work,
        rest: prefs.getInt(PrefsKeys.exerciseRest(id)) ?? d.rest,
        rounds: prefs.getInt(PrefsKeys.exerciseRounds(id)) ?? d.rounds,
        prep: prefs.getInt(PrefsKeys.exercisePrep(id)) ?? d.prep,
        warmupOn: prefs.getBool(PrefsKeys.exerciseWarmupOn(id)) ?? d.warmupOn,
        warmup: prefs.getInt(PrefsKeys.exerciseWarmup(id)) ?? d.warmup,
        bpm: prefs.getInt(PrefsKeys.exerciseBpm(id)) ?? d.bpm,
        metronomeOn:
            prefs.getBool(PrefsKeys.exerciseMetronomeOn(id)) ?? d.metronomeOn,
        metronomeSoundOn:
            prefs.getBool(PrefsKeys.exerciseMetronomeSoundOn(id)) ??
            d.metronomeSoundOn,
        metronomeVolume:
            prefs.getDouble(PrefsKeys.exerciseMetronomeVolume(id)) ??
            d.metronomeVolume,
        metronomeTone: MetronomeTone.fromId(
          prefs.getString(PrefsKeys.exerciseMetronomeTone(id)) ??
              d.metronomeTone.id,
        ),
        loop: d.loop,
      );
    }
    final savedKind = prefs.getString(PrefsKeys.exerciseSubMode);
    _kind = ExerciseKind.values.firstWhere(
      (k) => k.name == savedKind,
      orElse: () => ExerciseKind.tabata,
    );
    if (!mounted) return;
    setState(() {
      _statsDate = today;
      _todaySessions = prefs.getInt(PrefsKeys.exerciseSessions(today)) ?? 0;
      _todayMinutes = prefs.getInt(PrefsKeys.exerciseMinutesDay(today)) ?? 0;
    });
  }

  Future<void> _persistConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _kind.name;
    final c = _cfg;
    await prefs.setInt(PrefsKeys.exerciseWork(id), c.work);
    await prefs.setInt(PrefsKeys.exerciseRest(id), c.rest);
    await prefs.setInt(PrefsKeys.exerciseRounds(id), c.rounds);
    await prefs.setInt(PrefsKeys.exercisePrep(id), c.prep);
    await prefs.setBool(PrefsKeys.exerciseWarmupOn(id), c.warmupOn);
    await prefs.setInt(PrefsKeys.exerciseWarmup(id), c.warmup);
    await prefs.setInt(PrefsKeys.exerciseBpm(id), c.bpm);
    await prefs.setBool(PrefsKeys.exerciseMetronomeOn(id), c.metronomeOn);
    await prefs.setBool(
      PrefsKeys.exerciseMetronomeSoundOn(id),
      c.metronomeSoundOn,
    );
    await prefs.setDouble(
      PrefsKeys.exerciseMetronomeVolume(id),
      c.metronomeVolume,
    );
    await prefs.setString(
      PrefsKeys.exerciseMetronomeTone(id),
      c.metronomeTone.id,
    );
  }

  Future<void> _recordSession(int workSeconds) async {
    if (workSeconds < 30) return;
    final today = _dateStr(DateTime.now());
    if (_statsDate != today) {
      _statsDate = today;
      _todaySessions = 0;
      _todayMinutes = 0;
    }
    final addedMinutes = math.max(1, (workSeconds / 60).round()).toInt();
    final nextSessions = _todaySessions + 1;
    final nextMinutes = _todayMinutes + addedMinutes;
    if (mounted) {
      setState(() {
        _todaySessions = nextSessions;
        _todayMinutes = nextMinutes;
      });
    } else {
      _todaySessions = nextSessions;
      _todayMinutes = nextMinutes;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.exerciseSessions(today), _todaySessions);
    await prefs.setInt(PrefsKeys.exerciseMinutesDay(today), _todayMinutes);
  }

  Future<void> _clearTodayStats() async {
    final ok = await _confirmClearTodayStats();
    if (!ok) return;
    final today = _dateStr(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.exerciseSessions(today));
    await prefs.remove(PrefsKeys.exerciseMinutesDay(today));
    if (!mounted) return;
    setState(() {
      _statsDate = today;
      _todaySessions = 0;
      _todayMinutes = 0;
    });
    playFeedback(SfxCue.cancel, haptic: HapticLevel.selection);
  }

  Future<bool> _confirmClearTodayStats() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除今日運動成果？'),
        content: const Text('會把今天的運動次數與累計分鐘歸零。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── 階段序列 ──

  // 由設定組出整段訓練的階段序列：準備 →（暖身）→ [運動 →(休息)]×回合
  // 最後一組不接休息，直接完成。
  List<_Step> _buildSequence(_ExConfig c) {
    final seq = <_Step>[];
    if (c.prep > 0) {
      seq.add((phase: _ExPhase.prep, dur: c.prep, round: 0));
    }
    if (c.warmupOn && c.warmup > 0) {
      seq.add((phase: _ExPhase.warmup, dur: c.warmup, round: 0));
    }
    final rounds = math.max(1, c.rounds);
    for (var r = 1; r <= rounds; r++) {
      seq.add((phase: _ExPhase.work, dur: math.max(1, c.work), round: r));
      final isLast = r == rounds;
      if (!c.loop && c.rest > 0 && !isLast) {
        seq.add((phase: _ExPhase.rest, dur: c.rest, round: r));
      }
    }
    return seq;
  }

  int _currentWorkElapsedSeconds({bool full = false}) {
    if (_phase != _ExPhase.work || _phaseTotal <= 0) return 0;
    if (full) return _phaseTotal;
    final end = _endTime;
    if (_isRunning && end != null) {
      final leftMs = end.difference(DateTime.now()).inMilliseconds;
      final elapsedMs = (_phaseTotal * 1000 - leftMs).clamp(
        0,
        _phaseTotal * 1000,
      );
      return elapsedMs ~/ 1000;
    }
    return (_phaseTotal - _secondsLeft).clamp(0, _phaseTotal);
  }

  void _addCurrentWorkElapsed({bool full = false}) {
    _completedWorkSeconds += _currentWorkElapsedSeconds(full: full);
  }

  double get _progress {
    if (_idle || _finished || _phaseTotal <= 0) return 0;
    if (_phaseCompleteHold) return 1;
    final end = _endTime;
    if (_isRunning && end != null) {
      final leftMs = end.difference(DateTime.now()).inMilliseconds;
      final totalMs = _phaseTotal * 1000;
      return 1 - (leftMs.clamp(0, totalMs) / totalMs);
    }
    return 1 - (_secondsLeft / _phaseTotal).clamp(0.0, 1.0);
  }

  // 進入某序列項目（設定當前階段並重置倒數，不負責排計時器）
  void _enterStep(int idx) {
    final step = _seq[idx];
    _idx = idx;
    _phase = step.phase;
    _round = step.round;
    _phaseTotal = step.dur;
    _secondsLeft = step.dur;
    _phaseCompleteHold = false;
    _lastCueSec = 0; // 換階段重置倒數提示音
  }

  // ── 計時推進 ──

  void _refreshFromEndTime() {
    if (_advancingBoundary) return;
    var end = _endTime;
    if (end == null) return;
    final remainingMs = end.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0 && remainingMs > -900) {
      _holdCompletedPhase(end);
      return;
    }
    var remaining = (remainingMs / 1000).ceil();
    var crossed = false;
    while (remaining <= 0) {
      crossed = true;
      _addCurrentWorkElapsed(full: true);
      if (_idx + 1 >= _seq.length) {
        _finish();
        return;
      }
      _enterStep(_idx + 1);
      end = end!.add(Duration(seconds: _phaseTotal));
      remaining = (end.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    }
    if (crossed) _boundaryFeedback();
    setState(() {
      _endTime = end;
      _secondsLeft = remaining;
    });
    _maybeCountdownCue(remaining);
    _syncMetronome();
  }

  // 階段倒數最後 3 秒嗶提示（3→2→1 各一次，第 1 秒那聲較強）。
  // 沿用節拍器預設短音（溫和鼓聲）；番茄鐘不呼叫，所以只有運動會嗶。
  void _maybeCountdownCue(int remaining) {
    if (!_isRunning || remaining < 1 || remaining > 3) return;
    if (remaining == _lastCueSec) return;
    _lastCueSec = remaining;
    final last = remaining == 1;
    MetronomeService.instance.play(volume: last ? 1.0 : 0.55);
    playHaptic(last ? HapticLevel.medium : HapticLevel.light);
  }

  void _holdCompletedPhase(DateTime endedAt) {
    if (_advancingBoundary) return;
    _advancingBoundary = true;
    _stopMetronome();
    setState(() {
      _secondsLeft = 0;
      _phaseCompleteHold = true;
    });
    _boundaryTimer?.cancel();
    _boundaryTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_isRunning || _endTime != endedAt) {
        _advancingBoundary = false;
        _phaseCompleteHold = false;
        return;
      }
      if (_idx + 1 >= _seq.length) {
        _addCurrentWorkElapsed(full: true);
        _advancingBoundary = false;
        _phaseCompleteHold = false;
        _finish();
        return;
      }
      _addCurrentWorkElapsed(full: true);
      _enterStep(_idx + 1);
      final nextEnd = endedAt.add(Duration(seconds: _phaseTotal));
      final remaining =
          (nextEnd.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil()
              .clamp(0, _phaseTotal);
      _boundaryFeedback();
      setState(() {
        _endTime = nextEnd;
        _secondsLeft = remaining;
        _phaseCompleteHold = false;
      });
      _advancingBoundary = false;
      _syncMetronome();
    });
  }

  void _boundaryFeedback() {
    MascotPersona.interact(
      _phase == _ExPhase.rest
          ? MascotContext.halfDone
          : MascotContext.completedOne,
    );
    playFeedback(SfxCue.complete);
  }

  void _stopTicker() {
    _timer?.cancel();
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    _advancingBoundary = false;
    _phaseCompleteHold = false;
    _breath.stop();
    _stopMetronome();
  }

  void _stopMetronome() {
    // 已停就不重複動作（prep/warmup 期間 _syncMetronome 每 100ms 會呼到這）
    if (!_metroRunning && !(_metroTicker?.isActive ?? false)) return;
    _metroRunning = false;
    _metroTicker?.stop();
    _pendAngle.value = 0;
    unawaited(MetronomeService.instance.stopLoop());
  }

  // 啟動/維持節拍器。聲音＝音訊引擎無縫循環（取樣級等速）；擺錘＋觸覺＝Ticker
  // 連續正弦相位（每幀讀當下 BPM）。兩者開跑時都從「極端＝第一拍」對齊。
  void _syncMetronome() {
    if (!_jogWorkActive) {
      _stopMetronome();
      return;
    }
    if (_metroRunning) return; // 已在跑，避免每次 tick 重啟
    _metroRunning = true;
    _pendPhase = math.pi / 2; // 起手在極端
    _lastTickElapsed = Duration.zero;
    _lastBeatIndex = -1;
    if (_metroTicker != null && !_metroTicker!.isActive) {
      _metroTicker!.start();
    }
    if (_cfg.metronomeSoundOn) {
      unawaited(
        MetronomeService.instance.startOrUpdateLoop(
          bpm: _cfg.bpm,
          tone: _cfg.metronomeTone,
          volume: _cfg.metronomeVolume,
        ),
      );
    }
  }

  // 每幀：相位前進 π/拍（讀當下 BPM→改速平順）；越過極端時觸發觸覺。
  void _onMetroTick(Duration elapsed) {
    if (!_metroRunning) return;
    final dtSec = (elapsed - _lastTickElapsed).inMicroseconds / 1e6;
    _lastTickElapsed = elapsed;
    final bpm = _cfg.bpm.clamp(30, 240);
    _pendPhase += math.pi * bpm / 60 * dtSec;
    _pendAngle.value = _pendMaxAngle * math.sin(_pendPhase);
    final idx = ((_pendPhase - math.pi / 2) / math.pi).floor();
    if (idx != _lastBeatIndex) {
      _lastBeatIndex = idx;
      if (_cfg.metronomeOn) playHaptic(HapticLevel.selection);
    }
  }

  // 環內即時改 BPM：擺速每幀即時跟上；音訊循環 debounce 後重生（避免連按狂寫檔）。
  void _setBpm(int v) {
    final nv = v.clamp(30, 240);
    if (nv == _cfg.bpm) return;
    setState(() => _cfg.bpm = nv);
    _persistConfig();
    if (!_jogWorkActive || !_cfg.metronomeSoundOn) return;
    _loopRegenDebounce?.cancel();
    _loopRegenDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || !_jogWorkActive || !_cfg.metronomeSoundOn) return;
      unawaited(
        MetronomeService.instance.startOrUpdateLoop(
          bpm: _cfg.bpm,
          tone: _cfg.metronomeTone,
          volume: _cfg.metronomeVolume,
        ),
      );
    });
  }

  void _previewMetronome() {
    final volume = _cfg.metronomeVolume <= 0 ? 0.75 : _cfg.metronomeVolume;
    MetronomeService.instance.play(volume: volume, tone: _cfg.metronomeTone);
    playHaptic(HapticLevel.selection);
  }

  Future<void> _cancelAllNotifs() async {
    for (var i = 0; i < _maxNotifs; i++) {
      await NotificationService.cancel(_notifIdBase + i);
    }
  }

  // 沿著剩餘序列把每個階段結束通知排好（鎖屏／背景時提醒）
  Future<void> _scheduleNotifs() async {
    final ok = await NotificationService.ensurePermission();
    if (!ok || _endTime == null) return;
    var fireAt = _endTime!;
    for (var i = _idx; i < _seq.length && (i - _idx) < _maxNotifs; i++) {
      final isLast = i == _seq.length - 1;
      final (title, body) = isLast
          ? ('🎉 訓練完成', '辛苦了，做得好！')
          : _notifFor(_seq[i + 1]);
      await NotificationService.scheduleAt(
        fireAt,
        id: _notifIdBase + (i - _idx),
        title: title,
        body: body,
      );
      if (isLast) break;
      fireAt = fireAt.add(Duration(seconds: _seq[i + 1].dur));
    }
  }

  (String, String) _notifFor(_Step next) => switch (next.phase) {
    _ExPhase.work =>
      _kind == ExerciseKind.jog
          ? ('🏃 保持節奏', '${_cfg.bpm} BPM，輕鬆跑起來')
          : ('💪 開始運動', '第 ${next.round} / ${_cfg.rounds} 組'),
    _ExPhase.rest => ('😮‍💨 休息一下', '深呼吸，準備下一組'),
    _ExPhase.warmup => ('🤸 開始暖身', '先動一動身體'),
    _ => ('開始', ''),
  };

  // ── 操作 ──

  void _startPause() {
    if (_isRunning) {
      final remaining = _endTime != null
          ? (_endTime!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, _phaseTotal)
          : _secondsLeft;
      _stopTicker();
      _cancelAllNotifs();
      setState(() {
        _secondsLeft = remaining;
        _isRunning = false;
        _endTime = null;
      });
      _stopMetronome();
      playFeedback(SfxCue.tap);
      return;
    }

    // 從待機 / 完成開始：重新組序列
    if (_idle || _finished) {
      _seq = _buildSequence(_cfg);
      _completedWorkSeconds = 0;
      _enterStep(0);
    }
    // 預載倒數提示音（一次性 player），避免第一聲（剩 3 秒）才 lazy init 而延遲
    unawaited(MetronomeService.instance.init());
    final end = DateTime.now().add(Duration(seconds: _secondsLeft));
    setState(() {
      _isRunning = true;
      _endTime = end;
    });
    _breath.repeat(reverse: true);
    _scheduleNotifs();
    _timer = Timer.periodic(_tickerInterval, (_) => _refreshFromEndTime());
    _syncMetronome();
    MascotPersona.interact(MascotContext.halfDone);
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
  }

  void _reset() {
    _stopTicker();
    _cancelAllNotifs();
    setState(() {
      _isRunning = false;
      _phase = _ExPhase.idle;
      _round = 1;
      _idx = 0;
      _secondsLeft = 0;
      _phaseTotal = 0;
      _endTime = null;
      _completedWorkSeconds = 0;
    });
    MascotPersona.interact(MascotContext.notStarted);
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  void _skip() {
    if (_idle) return;
    _addCurrentWorkElapsed();
    _stopTicker();
    _cancelAllNotifs();
    if (_idx + 1 >= _seq.length) {
      _finish();
      return;
    }
    setState(() => _enterStep(_idx + 1));
    if (_isRunning) {
      final end = DateTime.now().add(Duration(seconds: _secondsLeft));
      _endTime = end;
      _breath.repeat(reverse: true);
      _scheduleNotifs();
      _timer = Timer.periodic(_tickerInterval, (_) => _refreshFromEndTime());
      _syncMetronome();
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  void _finish() {
    _stopTicker();
    _cancelAllNotifs();
    final workSeconds = _completedWorkSeconds;
    setState(() {
      _isRunning = false;
      _phase = _ExPhase.finished;
      _secondsLeft = 0;
      _endTime = null;
    });
    _stopMetronome();
    _recordSession(workSeconds);
    if (workSeconds >= 30) {
      CoinService.award(
        CoinSource.exerciseDone,
        note: '${_exMeta[_kind]!.name} 完成',
      );
    }
    MascotPersona.interact(MascotContext.allDone);
    playFeedback(SfxCue.success);
  }

  void _selectKind(ExerciseKind k) {
    if (_isRunning || k == _kind) return;
    setState(() {
      _kind = k;
      _phase = _ExPhase.idle;
      _idx = 0;
      _secondsLeft = 0;
      _phaseTotal = 0;
      _completedWorkSeconds = 0;
    });
    _stopMetronome();
    SharedPreferences.getInstance().then(
      (p) => p.setString(PrefsKeys.exerciseSubMode, k.name),
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // ── 顯示 ──

  Color get _phaseColor => switch (_phase) {
    _ExPhase.work => _exMeta[_kind]!.color,
    _ExPhase.rest => const Color(0xFF66BB6A),
    _ExPhase.warmup => const Color(0xFFFFA726),
    _ExPhase.finished => const Color(0xFF42A5F5),
    _ => const Color(0xFF26A69A),
  };

  String get _phaseLabel => switch (_phase) {
    _ExPhase.idle => _exMeta[_kind]!.name,
    _ExPhase.prep => '準備',
    _ExPhase.warmup => '暖身',
    _ExPhase.work => _kind == ExerciseKind.jog ? '保持節奏' : '運動',
    _ExPhase.rest => '休息',
    _ExPhase.finished => '完成',
  };

  IconData get _phaseIcon => switch (_phase) {
    _ExPhase.work => _exMeta[_kind]!.icon,
    _ExPhase.rest => Icons.self_improvement_rounded,
    _ExPhase.warmup => Icons.accessibility_new_rounded,
    _ExPhase.finished => Icons.emoji_events_rounded,
    _ => _exMeta[_kind]!.icon,
  };

  String get _timeString {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _ringSubtitle() {
    if (_idle) {
      final c = _cfg;
      if (_kind == ExerciseKind.jog) {
        return '${c.bpm} BPM · ${c.work ~/ 60} 分';
      }
      return c.loop
          ? '${c.work}s × ${c.rounds} 組'
          : '${c.work}s / ${c.rest}s × ${c.rounds}';
    }
    if (_finished) return '今天又動了一次';
    if (_kind == ExerciseKind.jog && _phase == _ExPhase.work) {
      return '${_cfg.bpm} BPM · 小步頻';
    }
    if (_phase == _ExPhase.work || _phase == _ExPhase.rest) {
      return '第 $_round / ${_cfg.rounds} 組';
    }
    return _phaseLabel;
  }

  @override
  Widget build(BuildContext context) {
    // 與專注模式相同：完整版面固定元件約 380px 高，留餘裕到 470 才用它，
    // 拖曳/彈簧時不會出現固定元件擠不下的瞬間 overflow；不夠高就走緊湊並排版。
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return h < 470 ? _buildCompactLayout(h) : _buildFullLayout();
      },
    );
  }

  // 完整版面：對齊專注模式的「徽章 → 圓盤 → 控制 → 狀態 → 預設 → 統計」節奏。
  Widget _buildFullLayout() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _phaseChip(),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildExerciseDots(),
        ),
        // 環依實際剩餘空間決定大小（不再用固定下限），拖曳到中間高度也不撐破
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) => _buildRing(
                math.min(math.min(c.maxWidth, c.maxHeight), 246.0),
              ),
            ),
          ),
        ),
        _controlsRow(),
        const SizedBox(height: 10),
        // 完整版面只在 h≥470 出現，狀態行常駐即可（避免拖曳時忽隱忽現、環一跳一跳）
        Text(
          _statusLine(),
          style: const TextStyle(
            color: AppInk.soft,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        _kindPicker(),
        const SizedBox(height: 12),
        _statsBar(),
        const SizedBox(height: 10),
      ],
    );
  }

  // 緊湊版面：跟專注模式一樣讓圓盤與控制並排，面板展開時仍好按。
  Widget _buildCompactLayout(double h) {
    final ringSize = (h - 110).clamp(110.0, 170.0);
    return Column(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildRing(ringSize),
              const SizedBox(width: 22),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _phaseChip(small: true),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildExerciseDots(),
                  ),
                  const SizedBox(height: 14),
                  _controlsRow(compact: true),
                ],
              ),
            ],
          ),
        ),
        _kindPicker(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _phaseChip({bool small = false}) {
    final color = _phaseColor;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: Container(
        key: ValueKey(_phase),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 12 : 16,
          vertical: small ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_phaseIcon, size: small ? 15 : 17, color: color),
            SizedBox(width: small ? 5 : 7),
            Text(
              _phaseLabel,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: small ? 13 : 15.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _completedWorkSteps() {
    if (_finished) return math.max(1, _cfg.rounds);
    if (_idle) return 0;
    var count = 0;
    for (var i = 0; i < _idx && i < _seq.length; i++) {
      if (_seq[i].phase == _ExPhase.work) count++;
    }
    if (_phaseCompleteHold && _phase == _ExPhase.work) count++;
    return count;
  }

  Widget _buildExerciseDots() {
    final total = math.max(1, _cfg.rounds);
    final shown = math.min(total, 12);
    final filled = _completedWorkSteps().clamp(0, total);
    final color = _exMeta[_kind]!.color;
    return SizedBox(
      height: 16,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(shown, (i) {
            final threshold = ((i + 1) * total / shown).ceil();
            final active = filled >= threshold;
            return SizedBox(
              width: 18,
              height: 16,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  width: active ? 11 : 9,
                  height: active ? 11 : 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? color : color.withValues(alpha: 0.24),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.22),
                              blurRadius: 6,
                              spreadRadius: 0.5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  String _statusLine() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return '$_phaseLabel中 · $hh:$mm 結束';
    }
    if (_finished) return '完成 ${_exMeta[_kind]!.name}，今天又多動了一段';
    final c = _cfg;
    if (_kind == ExerciseKind.jog) {
      return '超慢跑 · ${c.work ~/ 60} 分 · 暖身 ${c.warmupOn ? c.warmup ~/ 60 : 0} 分';
    }
    final rest = c.loop ? '循環' : '休息 ${c.rest} 秒';
    return '${_exMeta[_kind]!.name} · 運動 ${c.work} 秒 · $rest';
  }

  Widget _tonePicker({
    required Color color,
    required MetronomeTone selected,
    required ValueChanged<MetronomeTone> onSelected,
  }) {
    const tones = MetronomeTone.values;
    IconData iconFor(MetronomeTone tone) => switch (tone) {
      MetronomeTone.kick => Icons.radio_button_checked_rounded,
      MetronomeTone.wood => Icons.forest_rounded,
      MetronomeTone.lowWood => Icons.spa_rounded,
      MetronomeTone.bell => Icons.notifications_none_rounded,
      MetronomeTone.clap => Icons.back_hand_rounded,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = ((constraints.maxWidth - 8) / 2).clamp(118.0, 180.0);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tone in tones)
              _toneTile(
                color: color,
                width: tileWidth,
                icon: iconFor(tone),
                label: tone.label,
                selected: selected == tone,
                onTap: () => onSelected(tone),
              ),
          ],
        );
      },
    );
  }

  Widget _toneTile({
    required Color color,
    required double width,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.38)
                  : const Color(0xFFE8DDD4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: selected ? color : AppInk.soft),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : AppInk.strong,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  // 子模式選擇列（執行中鎖定），位置與專注模式的預設列對齊。
  // 固定高度槽：與專注 _buildPresetRow 的 _pickerRowHeight 等高（兩處數值務必一致），
  // 切換模式時版面不位移。
  static const double _pickerRowHeight = 52;

  Widget _kindPicker() {
    return SizedBox(
      height: _pickerRowHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Opacity(
            opacity: _isRunning ? 0.45 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final k in ExerciseKind.values) ...[
                    _kindChip(k),
                    if (k != ExerciseKind.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindChip(ExerciseKind k) {
    final meta = _exMeta[k]!;
    final selected = k == _kind;
    return GestureDetector(
      onTap: () => _selectKind(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minWidth: 62),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? meta.color : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: selected ? null : AppCardStyle.hairline,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: meta.color.withValues(alpha: 0.24),
                    blurRadius: 13,
                    offset: const Offset(0, 5),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meta.icon,
              size: 16,
              color: selected ? Colors.white : meta.color,
            ),
            const SizedBox(height: 1),
            Text(
              meta.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppInk.strong,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 環內即時 BPM 步進器（超慢跑運動中顯示）：− 數字 + ，按住連發。
  Widget _inlineBpm(double size, Color color) {
    final bpm = _cfg.bpm;
    Widget btn(IconData icon, VoidCallback? onTap) {
      final active = onTap != null;
      return HoldRepeatButton(
        onTrigger: onTap,
        child: Container(
          width: size * 0.12,
          height: size * 0.12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 0.16 : 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: size * 0.07,
            color: active ? color : AppInk.faint,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.025,
        vertical: size * 0.01,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, bpm > 30 ? () => _setBpm(bpm - 1) : null),
          SizedBox(width: size * 0.02),
          Text(
            '$bpm BPM',
            style: AppType.digits(
              fontSize: size * 0.07,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          SizedBox(width: size * 0.02),
          btn(Icons.add_rounded, bpm < 240 ? () => _setBpm(bpm + 1) : null),
        ],
      ),
    );
  }

  Widget _buildRing(double size) {
    final color = _phaseColor;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          final t = _isRunning
              ? Curves.easeInOut.transform(_breath.value)
              : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.16 + 0.13 * t),
                  blurRadius: 24 + 14 * t,
                  spreadRadius: 2 + 5 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: TweenAnimationBuilder<double>(
          // 換階段時用 _idx 重建，從 0 起新進度，避免進度弧由滿「倒帶」回 0
          key: ValueKey(_idx),
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 180),
          builder: (context, p, child) => CustomPaint(
            painter: TimerRingPainter(progress: p, color: color),
            child: child,
          ),
          child: Container(
            margin: EdgeInsets.all(size * 0.14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF5EB)],
              ),
              border: Border.all(color: const Color(0x12A85A3A)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 節拍器擺錘：只在超慢跑運動段顯示，疊在文字後方
                if (_jogWorkActive)
                  Positioned.fill(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _pendAngle,
                      builder: (context, angle, _) => CustomPaint(
                        painter: _PendulumPainter(angle: angle, color: color),
                      ),
                    ),
                  ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 超慢跑運動中留白，讓擺錘端球露在數字上方（不與 icon 打架）
                      if (_jogWorkActive)
                        SizedBox(height: size * 0.1)
                      else
                        Icon(
                          _phaseIcon,
                          color: color.withValues(alpha: 0.7),
                          size: size * 0.1,
                        ),
                      SizedBox(height: size * 0.01),
                      Text(
                        _idle ? _phaseLabel : _timeString,
                        style: TextStyle(
                          fontSize: _idle ? size * 0.13 : size * 0.2,
                          fontWeight: FontWeight.w900,
                          color: color,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: size * 0.015),
                      // 超慢跑運動中：環內即時調 BPM；其餘顯示情境副標
                      if (_jogWorkActive)
                        _inlineBpm(size, color)
                      else
                        Text(
                          _ringSubtitle(),
                          style: TextStyle(
                            fontSize: math.max(11.0, size * 0.056),
                            fontWeight: FontWeight.w600,
                            color: AppInk.soft,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsRow({bool compact = false}) {
    // 待機時左鈕＝設定（此時才會調參數）；進行/暫停時左鈕＝重設。
    // 右鈕＝跳過當前階段，待機時淡化停用。
    final gap = compact ? 16.0 : 24.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _sideButton(
          icon: _idle ? Icons.tune_rounded : Icons.replay_rounded,
          label: _idle ? '設定' : '重設',
          onTap: _idle ? _openSettingsSheet : _reset,
          size: compact ? 44 : 54,
        ),
        SizedBox(width: gap),
        // 主鈕較大；下方補一格與側鈕文字同高的留白，三顆圓心對齊
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mainButton(_phaseColor, size: compact ? 62 : 78),
            const SizedBox(height: _sideLabelGap + _sideLabelHeight),
          ],
        ),
        SizedBox(width: gap),
        _sideButton(
          icon: Icons.skip_next_rounded,
          label: '跳過',
          onTap: _idle ? () {} : _skip,
          faded: _idle,
          size: compact ? 44 : 54,
        ),
      ],
    );
  }

  Widget _mainButton(Color color, {double size = 78}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: _startPause,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(_isRunning),
                  color: Colors.white,
                  size: size * 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 圓鈕下方掛一行小文字，避免單看圖示猜不出意圖（與番茄鐘一致）
  static const double _sideLabelGap = 6;
  static const double _sideLabelHeight = 16;
  Widget _sideButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool faded = false,
    double size = 54,
  }) {
    return Opacity(
      opacity: faded ? 0.35 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.fromBorderSide(
                const BorderSide(color: Color(0x0A46342B)),
              ),
              boxShadow: AppShadows.flat,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(icon, color: AppInk.soft, size: size * 0.42),
                ),
              ),
            ),
          ),
          const SizedBox(height: _sideLabelGap),
          SizedBox(
            height: _sideLabelHeight,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsBar() {
    final hasAny = _todaySessions > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 50, // 與專注統計列等高，切換模式不位移（兩處需一致）
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: hasAny ? 0.92 : 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasAny
              ? const Color(0xFF26A69A).withValues(alpha: 0.16)
              : const Color(0x0A46342B),
        ),
        boxShadow: AppShadows.flat,
      ),
      child: hasAny
          ? Row(
              children: [
                Expanded(
                  child: _statPill(
                    icon: Icons.local_fire_department_rounded,
                    label: '今日運動',
                    value: '×$_todaySessions',
                    color: const Color(0xFFFF8A50),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statPill(
                    icon: Icons.timer_rounded,
                    label: '累計',
                    value: '$_todayMinutes 分',
                    color: const Color(0xFF26A69A),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '清除今日運動統計',
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _clearTodayStats,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 17,
                          color: AppInk.faint,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: Text(
                '今天還沒動，選個模式開始吧',
                style: TextStyle(
                  fontSize: 13,
                  color: AppInk.soft,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
    );
  }

  Widget _statPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label $value',
                maxLines: 1,
                style: AppType.digits(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 設定 sheet：調整當前子模式的 準備/暖身/運動/休息/組數 ──
  void _openSettingsSheet() {
    if (_isRunning) {
      playHaptic(HapticLevel.light);
      return;
    }
    playFeedback(SfxCue.tap);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = _cfg;
          void apply(VoidCallback change) {
            setState(() {
              change();
              if (!_isRunning && _idle) {
                _secondsLeft = 0;
                _phaseTotal = 0;
              }
            });
            setSheet(() {});
            _persistConfig();
          }

          final meta = _exMeta[_kind]!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: meta.color.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8DDD4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: meta.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(meta.icon, color: meta.color, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${meta.name} 設定',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_kind == ExerciseKind.jog) ...[
                    _stepRow(
                      label: '慢跑時間',
                      value: c.work ~/ 60,
                      unit: '分',
                      step: 1,
                      min: 1,
                      max: 120,
                      onChanged: (v) => apply(() => c.work = v * 60),
                    ),
                    _stepRow(
                      label: '節拍速度',
                      value: c.bpm,
                      unit: 'BPM',
                      step: 1,
                      min: 30,
                      max: 240,
                      onChanged: (v) {
                        apply(() => c.bpm = v);
                        _stopMetronome();
                        _syncMetronome();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '節拍器音效',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppInk.strong,
                              ),
                            ),
                          ),
                          Switch(
                            value: c.metronomeSoundOn,
                            activeThumbColor: meta.color,
                            onChanged: (v) {
                              apply(() {
                                c.metronomeSoundOn = v;
                                if (v && c.metronomeVolume <= 0) {
                                  c.metronomeVolume = 0.75;
                                }
                              });
                              if (v) _previewMetronome();
                            },
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: c.metronomeSoundOn
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _volumeRow(
                                  color: meta.color,
                                  value: c.metronomeVolume,
                                  onChanged: (v) =>
                                      apply(() => c.metronomeVolume = v),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _tonePicker(
                                    color: meta.color,
                                    selected: c.metronomeTone,
                                    onSelected: (tone) {
                                      apply(() => c.metronomeTone = tone);
                                      _previewMetronome();
                                    },
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '觸覺節拍',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppInk.strong,
                              ),
                            ),
                          ),
                          Switch(
                            value: c.metronomeOn,
                            activeThumbColor: meta.color,
                            onChanged: (v) => apply(() => c.metronomeOn = v),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _stepRow(
                      label: '運動時間',
                      value: c.work,
                      unit: '秒',
                      step: 5,
                      min: 5,
                      max: 600,
                      onChanged: (v) => apply(() => c.work = v),
                    ),
                  ],
                  if (!c.loop && _kind != ExerciseKind.jog)
                    _stepRow(
                      label: '休息時間',
                      value: c.rest,
                      unit: '秒',
                      step: 5,
                      min: 0,
                      max: 600,
                      onChanged: (v) => apply(() => c.rest = v),
                    ),
                  if (_kind != ExerciseKind.jog)
                    _stepRow(
                      label: '組數',
                      value: c.rounds,
                      unit: '組',
                      step: 1,
                      min: 1,
                      max: 99,
                      onChanged: (v) => apply(() => c.rounds = v),
                    ),
                  _stepRow(
                    label: '開始前準備',
                    value: c.prep,
                    unit: '秒',
                    step: 5,
                    min: 0,
                    max: 60,
                    onChanged: (v) => apply(() => c.prep = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '暖身',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppInk.strong,
                            ),
                          ),
                        ),
                        Switch(
                          value: c.warmupOn,
                          activeThumbColor: meta.color,
                          onChanged: (v) => apply(() => c.warmupOn = v),
                        ),
                      ],
                    ),
                  ),
                  if (c.warmupOn)
                    _stepRow(
                      label: '暖身時間',
                      value: c.warmup,
                      unit: '秒',
                      step: 10,
                      min: 0,
                      max: 600,
                      onChanged: (v) => apply(() => c.warmup = v),
                    ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: () => apply(() {
                        final d = _defaultConfig(_kind);
                        c.work = d.work;
                        c.rest = d.rest;
                        c.rounds = d.rounds;
                        c.prep = d.prep;
                        c.warmupOn = d.warmupOn;
                        c.warmup = d.warmup;
                        c.bpm = d.bpm;
                        c.metronomeOn = d.metronomeOn;
                        c.metronomeSoundOn = d.metronomeSoundOn;
                        c.metronomeVolume = d.metronomeVolume;
                        c.metronomeTone = d.metronomeTone;
                      }),
                      child: const Text('還原預設'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stepRow({
    required String label,
    required int value,
    required String unit,
    required int step,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    // 點一下 ±step；按住連發。到極值時 onTrigger 傳 null 自動停用。
    Widget btn(IconData icon, VoidCallback? onTap) => HoldRepeatButton(
      onTrigger: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F2),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE8DDD4)),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? AppInk.faint : AppInk.soft,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppInk.strong,
              ),
            ),
          ),
          btn(
            Icons.remove_rounded,
            value > min
                ? () => onChanged((value - step).clamp(min, max))
                : null,
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$value $unit',
              textAlign: TextAlign.center,
              style: AppType.digits(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppInk.strong,
              ),
            ),
          ),
          btn(
            Icons.add_rounded,
            value < max
                ? () => onChanged((value + step).clamp(min, max))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _volumeRow({
    required Color color,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final pct = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.volume_down_rounded, size: 18, color: color),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 1.0),
              divisions: 20,
              activeColor: color,
              inactiveColor: color.withValues(alpha: 0.16),
              onChanged: onChanged,
              onChangeEnd: (v) {
                MetronomeService.instance.play(
                  volume: v,
                  tone: _cfg.metronomeTone,
                );
              },
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: AppType.digits(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppInk.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 節拍器擺錘：支點在圓心略下方，桿往上、頂端發光球隨拍左右擺（疊在數字後方）。
class _PendulumPainter extends CustomPainter {
  final double angle; // 擺桿角度（弧度，0=正上、±為左右）
  final Color color;

  const _PendulumPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    final pivot = Offset(center.dx, center.dy + h * 0.17);
    final armLen = h * 0.45;
    final tip = Offset(
      pivot.dx + math.sin(angle) * armLen,
      pivot.dy - math.cos(angle) * armLen,
    );

    // 擺桿
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..strokeWidth = math.max(2.0, w * 0.018)
        ..strokeCap = StrokeCap.round,
    );

    // 支點
    canvas.drawCircle(
      pivot,
      math.max(2.0, w * 0.02),
      Paint()..color = color.withValues(alpha: 0.5),
    );

    // 端球：柔光暈 + 實心 + 白描邊
    canvas.drawCircle(
      tip,
      w * 0.075,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(tip, w * 0.05, Paint()..color = color);
    canvas.drawCircle(
      tip,
      w * 0.05,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_PendulumPainter old) =>
      old.angle != angle || old.color != color;
}
