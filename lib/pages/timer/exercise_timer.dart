import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/coin_config.dart';
import '../../utils/coin_service.dart';
import '../../utils/mascot.dart';
import '../../utils/notification_service.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/hold_repeat_button.dart';

// 計時頁「運動」模式：間歇訓練計時器。
// 引擎沿用番茄鐘那套 wall-clock（用 endTime 反推剩餘）＋背景回來補算多階段
// ＋鏈式通知，所以鎖屏也準。四種子模式（Tabata / HIIT / EMOM / 重訓），
// 階段序列：準備 →（暖身）→ [運動 → 休息]×回合 → 完成。
// 超慢跑＋節拍器之後另做（不在此版）。

enum ExerciseKind { tabata, hiit, emom, gym }

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
};

// 可調設定（會持久化）。loop=true（EMOM）時沒有獨立休息段。
class _ExConfig {
  int work;
  int rest;
  int rounds;
  int prep;
  bool warmupOn;
  int warmup;
  final bool loop;

  _ExConfig({
    required this.work,
    required this.rest,
    required this.rounds,
    required this.prep,
    required this.warmupOn,
    required this.warmup,
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
    loop: false,
  ),
  ExerciseKind.hiit => _ExConfig(
    work: 30,
    rest: 30,
    rounds: 10,
    prep: 5,
    warmupOn: true,
    warmup: 120,
    loop: false,
  ),
  ExerciseKind.emom => _ExConfig(
    work: 60,
    rest: 0,
    rounds: 10,
    prep: 5,
    warmupOn: false,
    warmup: 60,
    loop: true,
  ),
  ExerciseKind.gym => _ExConfig(
    work: 40,
    rest: 90,
    rounds: 5,
    prep: 5,
    warmupOn: false,
    warmup: 0,
    loop: false,
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 通知 id 區段（與番茄鐘 1001..1006 分開）
  static const int _notifIdBase = 1100;
  static const int _maxNotifs = 40;

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
  DateTime? _endTime;

  // ── 今日統計（per-day key）──
  String _statsDate = '';
  int _todaySessions = 0;
  int _todayMinutes = 0;

  late final AnimationController _breath;

  _ExConfig get _cfg => _configs[_kind]!;
  bool get _idle => _phase == _ExPhase.idle;
  bool get _finished => _phase == _ExPhase.finished;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _loadPrefs();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breath.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      _refreshFromEndTime();
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
  }

  Future<void> _recordSession(int workSeconds) async {
    final today = _dateStr(DateTime.now());
    if (_statsDate != today) {
      _statsDate = today;
      _todaySessions = 0;
      _todayMinutes = 0;
    }
    _todaySessions++;
    _todayMinutes += (workSeconds / 60).round();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.exerciseSessions(today), _todaySessions);
    await prefs.setInt(PrefsKeys.exerciseMinutesDay(today), _todayMinutes);
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

  int get _totalWorkSeconds {
    final c = _cfg;
    return math.max(1, c.work) * math.max(1, c.rounds);
  }

  double get _progress =>
      1 - (_secondsLeft / math.max(_phaseTotal, 1)).clamp(0.0, 1.0);

  // 進入某序列項目（設定當前階段並重置倒數，不負責排計時器）
  void _enterStep(int idx) {
    final step = _seq[idx];
    _idx = idx;
    _phase = step.phase;
    _round = step.round;
    _phaseTotal = step.dur;
    _secondsLeft = step.dur;
  }

  // ── 計時推進 ──

  void _refreshFromEndTime() {
    var end = _endTime;
    if (end == null) return;
    var remaining = end.difference(DateTime.now()).inSeconds;
    var crossed = false;
    while (remaining <= 0) {
      crossed = true;
      if (_idx + 1 >= _seq.length) {
        _finish();
        return;
      }
      _enterStep(_idx + 1);
      end = end!.add(Duration(seconds: _phaseTotal));
      remaining = end.difference(DateTime.now()).inSeconds;
    }
    if (crossed) _boundaryFeedback();
    setState(() {
      _endTime = end;
      _secondsLeft = remaining;
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
    _breath.stop();
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
    _ExPhase.work => ('💪 開始運動', '第 ${next.round} / ${_cfg.rounds} 組'),
    _ExPhase.rest => ('😮‍💨 休息一下', '深呼吸，準備下一組'),
    _ExPhase.warmup => ('🤸 開始暖身', '先動一動身體'),
    _ => ('開始', ''),
  };

  // ── 操作 ──

  void _startPause() {
    if (_isRunning) {
      final remaining = _endTime != null
          ? _endTime!.difference(DateTime.now()).inSeconds.clamp(0, _phaseTotal)
          : _secondsLeft;
      _stopTicker();
      _cancelAllNotifs();
      setState(() {
        _secondsLeft = remaining;
        _isRunning = false;
        _endTime = null;
      });
      playFeedback(SfxCue.tap);
      return;
    }

    // 從待機 / 完成開始：重新組序列
    if (_idle || _finished) {
      _seq = _buildSequence(_cfg);
      _enterStep(0);
    }
    final end = DateTime.now().add(Duration(seconds: _secondsLeft));
    setState(() {
      _isRunning = true;
      _endTime = end;
    });
    _breath.repeat(reverse: true);
    _scheduleNotifs();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshFromEndTime(),
    );
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
    });
    MascotPersona.interact(MascotContext.notStarted);
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  void _skip() {
    if (_idle) return;
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
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromEndTime(),
      );
    }
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  void _finish() {
    _stopTicker();
    _cancelAllNotifs();
    final workSeconds = _totalWorkSeconds;
    setState(() {
      _isRunning = false;
      _phase = _ExPhase.finished;
      _secondsLeft = 0;
      _endTime = null;
    });
    _recordSession(workSeconds);
    CoinService.award(
      CoinSource.exerciseDone,
      note: '${_exMeta[_kind]!.name} 完成',
    );
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
    });
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
    _ExPhase.work => '運動',
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
      return c.loop
          ? '${c.work}s × ${c.rounds} 組'
          : '${c.work}s / ${c.rest}s × ${c.rounds}';
    }
    if (_finished) return '今天又動了一次';
    if (_phase == _ExPhase.work || _phase == _ExPhase.rest) {
      return '第 $_round / ${_cfg.rounds} 組';
    }
    return _phaseLabel;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return h < 360 ? _buildCompactLayout(h) : _buildFullLayout(h);
      },
    );
  }

  // 完整版面：對齊專注模式的「徽章 → 圓盤 → 控制 → 狀態 → 預設 → 統計」節奏。
  Widget _buildFullLayout(double h) {
    final ringSize = (h - 312).clamp(148.0, 246.0);
    return Column(
      children: [
        const SizedBox(height: 8),
        _phaseChip(),
        Expanded(child: Center(child: _buildRing(ringSize))),
        _controlsRow(),
        const SizedBox(height: 10),
        if (h > 440)
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

  String _statusLine() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return '$_phaseLabel中 · $hh:$mm 結束';
    }
    if (_finished) return '完成 ${_exMeta[_kind]!.name}，今天又多動了一段';
    final c = _cfg;
    final rest = c.loop ? '循環' : '休息 ${c.rest} 秒';
    return '${_exMeta[_kind]!.name} · 運動 ${c.work} 秒 · $rest';
  }

  // 子模式選擇列（執行中鎖定），位置與專注模式的預設列對齊。
  Widget _kindPicker() {
    return Padding(
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
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 1000),
          builder: (context, p, child) => CustomPaint(
            painter: _ExRingPainter(progress: p, color: color),
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
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
          icon: _idle ? Icons.tune_rounded : Icons.refresh_rounded,
          onTap: _idle ? _openSettingsSheet : _reset,
          size: compact ? 44 : 54,
        ),
        SizedBox(width: gap),
        _mainButton(_phaseColor, size: compact ? 62 : 78),
        SizedBox(width: gap),
        _sideButton(
          icon: Icons.skip_next_rounded,
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

  Widget _sideButton({
    required IconData icon,
    required VoidCallback onTap,
    bool faded = false,
    double size = 54,
  }) {
    return Opacity(
      opacity: faded ? 0.35 : 1,
      child: DecoratedBox(
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
    );
  }

  Widget _statsBar() {
    final hasAny = _todaySessions > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
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
                  _stepRow(
                    label: '運動時間',
                    value: c.work,
                    unit: '秒',
                    step: 5,
                    min: 5,
                    max: 600,
                    onChanged: (v) => apply(() => c.work = v),
                  ),
                  if (!c.loop)
                    _stepRow(
                      label: '休息時間',
                      value: c.rest,
                      unit: '秒',
                      step: 5,
                      min: 0,
                      max: 600,
                      onChanged: (v) => apply(() => c.rest = v),
                    ),
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
}

// 運動模式進度環：柔和內盤 + 12 刻度 + 進度弧（不含番茄葉子，給運動用的中性版）
class _ExRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ExRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(8.0, shortest * 0.048);
    final radius = shortest / 2 - stroke * 0.8;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, stroke * 0.16)
      ..color = color.withValues(alpha: 0.16);
    for (var i = 0; i < 12; i++) {
      final a = -math.pi / 2 + i * math.pi / 6;
      final outer = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
      final inner =
          center +
          Offset(
            math.cos(a) * (radius - stroke * (i % 3 == 0 ? 1.18 : 0.82)),
            math.sin(a) * (radius - stroke * (i % 3 == 0 ? 1.18 : 0.82)),
          );
      canvas.drawLine(inner, outer, tickPaint);
    }

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
        colors: [color.withValues(alpha: 0.7), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_ExRingPainter old) =>
      old.progress != progress || old.color != color;
}
