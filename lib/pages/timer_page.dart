import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/mascot.dart';
import '../utils/notification_service.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../widgets/hold_repeat_button.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import 'timer/exercise_timer.dart';

// 計時頁上層模式：專注（番茄鐘）／運動（間歇訓練）
enum _TimerMode { focus, exercise }

// 專注模式階段。idle=待機、finished=整節完成；長休息只在整節最後（可關）。
enum _Phase { idle, focus, shortBreak, longBreak, finished }

// 階段序列的一個項目（round：第幾顆番茄，休息沿用前一顆的編號）
typedef _Step = ({_Phase phase, int dur, int round});

// （已移除 _TimerSettingField：自訂改純步進器，不再有自製鍵盤與作用中欄位）

// 時長預設組（分鐘 + 回合數）。「自訂」不在列表內，由設定 sheet 調出任意組合。
const _presets = [
  (label: '經典', focus: 25, brk: 5, rounds: 4),
  (label: '深度', focus: 50, brk: 10, rounds: 3),
  (label: '輕量', focus: 15, brk: 3, rounds: 4),
];

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 通知 id 區段：鏈式排程最多 _maxChainNotifs 則，id 從 base 遞增
  static const int _notifIdBase = 1001;
  static const int _maxChainNotifs = 20;

  // 上層模式（專注/運動），記住上次選擇
  _TimerMode _topMode = _TimerMode.focus;

  // ── 設定（持久化）──
  int _focusMin = 25;
  int _shortMin = 5;
  int _longMin = 15;
  int _rounds = 4; // 一節幾顆番茄（1–8）
  bool _longBreakEnabled = true; // 結尾長休息（整節最後）

  // ── 計時狀態（有限一節：[專注→短休息]×(N-1)→專注→(長休息)→完成）──
  // 階段序列在按下開始時組好，背景回來用 wall-clock 逐段補算。
  List<_Step> _seq = const [];
  int _idx = 0;
  _Phase _phase = _Phase.idle;
  int _round = 1; // 目前第幾顆番茄（1..N）
  int _secondsLeft = 0;
  // 當前階段總秒數快照：計時中改設定不影響本階段的進度環
  int _phaseTotal = 0;
  bool _isRunning = false;
  Timer? _timer;
  // 執行中才有值：當前階段絕對結束時刻。
  // 用 wall-clock 算 remaining，app 切到背景再回來時間還是對的。
  DateTime? _endTime;

  // ── 今日統計（持久化，per-day key）──
  String _statsDate = '';
  int _todayTomatoes = 0;
  int _todayFocusMin = 0;

  // 計時中圓圈的呼吸光暈（repeat reverse，暫停時停在原處不晃）
  late final AnimationController _breath;

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

  // App 從背景回來，立刻重算剩餘秒數（可能已跨多個自動接續階段）
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
    setState(() {
      _topMode = prefs.getString(PrefsKeys.timerMode) == 'exercise'
          ? _TimerMode.exercise
          : _TimerMode.focus;
      _focusMin = prefs.getInt(PrefsKeys.timerFocusMinutes) ?? 25;
      _shortMin = prefs.getInt(PrefsKeys.timerShortBreakMinutes) ?? 5;
      _longMin = prefs.getInt(PrefsKeys.timerLongBreakMinutes) ?? 15;
      _rounds = (prefs.getInt(PrefsKeys.timerRounds) ?? 4).clamp(1, 8);
      _longBreakEnabled =
          prefs.getBool(PrefsKeys.timerLongBreakEnabled) ?? true;
      _statsDate = today;
      _todayTomatoes = prefs.getInt(PrefsKeys.timerTomatoes(today)) ?? 0;
      _todayFocusMin = prefs.getInt(PrefsKeys.timerFocusMinutesDay(today)) ?? 0;
      // 待機預覽第一顆專注的時長
      _phaseTotal = _focusMin * 60;
      _secondsLeft = _phaseTotal;
    });
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.timerFocusMinutes, _focusMin);
    await prefs.setInt(PrefsKeys.timerShortBreakMinutes, _shortMin);
    await prefs.setInt(PrefsKeys.timerLongBreakMinutes, _longMin);
    await prefs.setInt(PrefsKeys.timerRounds, _rounds);
    await prefs.setBool(PrefsKeys.timerLongBreakEnabled, _longBreakEnabled);
  }

  // 完成一顆番茄：寫進今日統計（跨日自動歸零換 key）
  Future<void> _recordTomato(int minutes) async {
    final today = _dateStr(DateTime.now());
    if (_statsDate != today) {
      _statsDate = today;
      _todayTomatoes = 0;
      _todayFocusMin = 0;
    }
    _todayTomatoes++;
    _todayFocusMin += minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.timerTomatoes(today), _todayTomatoes);
    await prefs.setInt(PrefsKeys.timerFocusMinutesDay(today), _todayFocusMin);
  }

  // ── 階段序列（有限一節）──

  bool get _idle => _phase == _Phase.idle;
  bool get _finished => _phase == _Phase.finished;

  // 一節：[專注→短休息]×(N-1) → 第N顆專注 → (結尾長休息) → 完成
  List<_Step> _buildSequence() {
    final seq = <_Step>[];
    final n = _rounds.clamp(1, 8);
    for (var r = 1; r <= n; r++) {
      seq.add((phase: _Phase.focus, dur: _focusMin * 60, round: r));
      if (r < n) {
        seq.add((phase: _Phase.shortBreak, dur: _shortMin * 60, round: r));
      }
    }
    if (_longBreakEnabled) {
      seq.add((phase: _Phase.longBreak, dur: _longMin * 60, round: n));
    }
    return seq;
  }

  // 當前階段已完成比例 0~1（給進度圓環用）
  double get _progress =>
      1 - (_secondsLeft / math.max(_phaseTotal, 1)).clamp(0.0, 1.0);

  void _enterStep(int idx) {
    final s = _seq[idx];
    _idx = idx;
    _phase = s.phase;
    _round = s.round;
    _phaseTotal = s.dur;
    _secondsLeft = s.dur;
  }

  // 完成一個專注階段 → 記番茄 + 給金幣（跳過不算，所以只在自然完成時呼叫）
  void _awardIfFocus(_Step step) {
    if (step.phase != _Phase.focus) return;
    _recordTomato(step.dur ~/ 60);
    CoinService.award(CoinSource.tomatoDone, note: '番茄 ${step.dur ~/ 60} 分');
  }

  // 由絕對結束時刻反推剩餘秒數；背景期間跨了多個階段就逐段補算（含給幣）。
  void _refreshFromEndTime() {
    var end = _endTime;
    if (end == null) return;
    var remaining = end.difference(DateTime.now()).inSeconds;
    var crossed = false;
    while (remaining <= 0) {
      crossed = true;
      _awardIfFocus(_seq[_idx]);
      if (_idx + 1 >= _seq.length) {
        _finishSession();
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

  void _finishSession() {
    _stopTicker();
    _cancelAllNotifs();
    setState(() {
      _isRunning = false;
      _phase = _Phase.finished;
      _secondsLeft = 0;
      _endTime = null;
    });
    MascotPersona.interact(MascotContext.allDone);
    playFeedback(SfxCue.success);
  }

  // 跨階段回饋：音效 + 兔咪換情緒（多階段一次補算也只播一次）
  void _boundaryFeedback() {
    MascotPersona.interact(
      _phase == _Phase.focus
          ? MascotContext.openApp
          : MascotContext.completedOne,
    );
    playFeedback(SfxCue.complete);
  }

  void _stopTicker() {
    _timer?.cancel();
    _breath.stop();
  }

  Future<void> _cancelAllNotifs() async {
    for (var i = 0; i < _maxChainNotifs; i++) {
      await NotificationService.cancel(_notifIdBase + i);
    }
  }

  // 把目前序列剩下的每個階段結束都排好通知（鎖屏/背景時提醒）
  Future<void> _scheduleNotifs() async {
    final ok = await NotificationService.ensurePermission();
    if (!ok || _endTime == null) return;
    var fireAt = _endTime!;
    for (var i = _idx; i < _seq.length && (i - _idx) < _maxChainNotifs; i++) {
      final isLast = i == _seq.length - 1;
      final (title, body) = isLast
          ? ('🎉 完成這一節', '$_rounds 顆番茄達成，辛苦了！')
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
    _Phase.focus => ('🍅 開始專注', '第 ${next.round} / $_rounds 顆'),
    _Phase.shortBreak => ('☕ 休息一下', '喘口氣，等等繼續'),
    _Phase.longBreak => ('🛋️ 長休息', '這一節快結束了'),
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
    // 從待機 / 完成 → 重新組序列從頭開始
    if (_idle || _finished) {
      _seq = _buildSequence();
      _enterStep(0);
    }
    final end = DateTime.now().add(Duration(seconds: _secondsLeft));
    setState(() {
      _endTime = end;
      _isRunning = true;
    });
    _breath.repeat(reverse: true);
    _scheduleNotifs();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshFromEndTime(),
    );
    MascotPersona.interact(
      _phase == _Phase.focus ? MascotContext.openApp : MascotContext.halfDone,
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
  }

  // 重設：停止並回到待機（第一顆專注的預覽）
  void _reset() {
    _stopTicker();
    _cancelAllNotifs();
    setState(() {
      _isRunning = false;
      _phase = _Phase.idle;
      _round = 1;
      _idx = 0;
      _phaseTotal = _focusMin * 60;
      _secondsLeft = _phaseTotal;
      _endTime = null;
    });
    MascotPersona.interact(MascotContext.notStarted);
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  // 跳過當前階段（不計番茄）：前進到序列下一項，到底就完成
  void _skipPhase() {
    if (_idle || _finished) return;
    _stopTicker();
    _cancelAllNotifs();
    if (_idx + 1 >= _seq.length) {
      _finishSession();
      return;
    }
    setState(() => _enterStep(_idx + 1));
    if (_isRunning) {
      _endTime = DateTime.now().add(Duration(seconds: _secondsLeft));
      _breath.repeat(reverse: true);
      _scheduleNotifs();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromEndTime(),
      );
    }
    MascotPersona.interact(
      _phase == _Phase.focus
          ? MascotContext.openApp
          : MascotContext.completedOne,
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // 套用預設組（計時中不可用；待機時更新第一顆專注預覽）
  void _applyPreset(int focus, int brk, int rounds) {
    if (_isRunning) {
      playHaptic(HapticLevel.light);
      return;
    }
    setState(() {
      _focusMin = focus;
      _shortMin = brk;
      _rounds = rounds;
      if (_idle || _finished) {
        _phase = _Phase.idle;
        _phaseTotal = _focusMin * 60;
        _secondsLeft = _phaseTotal;
      }
    });
    _persistSettings();
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // ── UI ──

  String get _timeString {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // 番茄紅橘 / 嫩綠 / 湖水綠：比 Material 原色再暖一階，貼整體插畫調性
  Color get _phaseColor => switch (_phase) {
    _Phase.focus => const Color(0xFFFF7043),
    _Phase.shortBreak => const Color(0xFF66BB6A),
    _Phase.longBreak => const Color(0xFF26A69A),
    _Phase.finished => const Color(0xFF66BB6A),
    _Phase.idle => const Color(0xFFFF7043),
  };

  String get _phaseLabel => switch (_phase) {
    _Phase.focus => '專注時間',
    _Phase.shortBreak => '短休息',
    _Phase.longBreak => '長休息',
    _Phase.finished => '完成',
    _Phase.idle => '準備開始',
  };

  IconData get _phaseIcon => switch (_phase) {
    _Phase.focus => Icons.local_fire_department_rounded,
    _Phase.shortBreak => Icons.local_cafe_rounded,
    _Phase.longBreak => Icons.spa_rounded,
    _Phase.finished => Icons.emoji_events_rounded,
    _Phase.idle => Icons.local_fire_department_rounded,
  };

  static const Color _exerciseAccent = Color(0xFF26A69A);

  void _switchMode(_TimerMode mode) {
    if (mode == _topMode) return;
    setState(() => _topMode = mode);
    SharedPreferences.getInstance().then(
      (p) => p.setString(
        PrefsKeys.timerMode,
        mode == _TimerMode.exercise ? 'exercise' : 'focus',
      ),
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  @override
  Widget build(BuildContext context) {
    // 頁面主色隨模式切換：專注用番茄色、運動用青綠
    final color = _topMode == _TimerMode.focus ? _phaseColor : _exerciseAccent;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: MascotAppBar(accent: color),
      body: Stack(
        children: [
          // 場景背景：延伸到 AppBar 後面，跟首頁同樣 56% 高度
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.56,
            child: const MascotSceneBackground(
              'assets/scenes/timer/timer_bg.png',
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: color,
              scene: PersonaScene(accent: color),
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  _buildModeSwitch(color),
                  const SizedBox(height: 4),
                  // 兩模式都常駐（IndexedStack）：切換時各自計時狀態不會被丟掉
                  Expanded(
                    child: IndexedStack(
                      index: _topMode == _TimerMode.focus ? 0 : 1,
                      sizing: StackFit.expand,
                      children: [
                        _buildTimerContent(_phaseColor),
                        const ExerciseTimer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 專注 / 運動 分段切換（玻璃膠囊風，跟全 app 卡片語彙一致）
  Widget _buildModeSwitch(Color color) {
    Widget seg(_TimerMode mode, IconData icon, String label) {
      final selected = _topMode == mode;
      final segColor = mode == _TimerMode.focus ? _phaseColor : _exerciseAccent;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? segColor : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: segColor.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? Colors.white : AppInk.soft,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          seg(_TimerMode.focus, Icons.psychology_rounded, '專注'),
          const SizedBox(width: 4),
          seg(_TimerMode.exercise, Icons.directions_run_rounded, '運動'),
        ],
      ),
    );
  }

  Widget _buildTimerContent(Color color) {
    // 依可用高度切換版面：兔咪面板展開時走緊湊並排版，
    // 不捲動就能看到時間、按到開始 —— 修掉「展開時只剩半顆圓」的問題
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return h < 360
            ? _buildCompactLayout(color, h)
            : _buildFullLayout(color, h);
      },
    );
  }

  // 完整版面（面板收合）：環吸收剩餘高度置中，統計列釘在底部收尾
  Widget _buildFullLayout(Color color, double h) {
    final ringSize = (h - 312).clamp(148.0, 246.0);
    return Column(
      children: [
        const SizedBox(height: 8),
        _phaseChip(color),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildCycleDots(),
        ),
        Expanded(child: Center(child: _buildTimerCircle(ringSize, color))),
        _controlsRow(color),
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
        _buildPresetRow(),
        const SizedBox(height: 12),
        _statsBar(),
        const SizedBox(height: 10),
      ],
    );
  }

  // 緊湊版面（兔咪面板展開）：環和控制並排，一眼可見、一指可按
  Widget _buildCompactLayout(Color color, double h) {
    final ringSize = (h - 110).clamp(110.0, 170.0);
    return Column(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimerCircle(ringSize, color),
              const SizedBox(width: 22),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _phaseChip(color, small: true),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildCycleDots(),
                  ),
                  const SizedBox(height: 14),
                  _controlsRow(color, compact: true),
                ],
              ),
            ],
          ),
        ),
        _buildPresetRow(),
        const SizedBox(height: 12),
      ],
    );
  }

  // 狀態標籤（換階段時縮放淡入交接）
  Widget _phaseChip(Color color, {bool small = false}) {
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

  Widget _controlsRow(Color color, {bool compact = false}) {
    final gap = compact ? 16.0 : 24.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _sideButton(
          icon: Icons.refresh_rounded,
          onTap: _reset,
          size: compact ? 44 : 54,
          faded: _idle,
        ),
        SizedBox(width: gap),
        _mainButton(color, size: compact ? 62 : 78),
        SizedBox(width: gap),
        _sideButton(
          icon: Icons.skip_next_rounded,
          onTap: _skipPhase,
          size: compact ? 44 : 54,
          faded: _idle || _finished,
        ),
      ],
    );
  }

  // 今日統計列：固定顯示（沒有也給一句留白語，當頁面的底部收尾）
  Widget _statsBar() {
    final hasAny = _todayTomatoes > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: hasAny ? 0.92 : 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasAny
              ? const Color(0xFFFF7043).withValues(alpha: 0.16)
              : const Color(0x0A46342B),
        ),
        boxShadow: AppShadows.flat,
      ),
      child: hasAny
          ? Row(
              children: [
                Expanded(
                  child: _statPill(
                    icon: Icons.eco_rounded,
                    label: '今日番茄',
                    value: '×$_todayTomatoes',
                    color: const Color(0xFFFF7043),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statPill(
                    icon: Icons.hourglass_bottom_rounded,
                    label: '專注時間',
                    value: '$_todayFocusMin 分',
                    color: const Color(0xFF66BB6A),
                  ),
                ),
              ],
            )
          : const Center(
              child: Text(
                '今天還沒種下番茄，按下開始吧',
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

  // 這一節已完成的番茄數（= 已通過的 focus 階段數）
  int _completedTomatoes() {
    if (_finished) return _rounds;
    if (_idle) return 0;
    var c = 0;
    for (var i = 0; i < _idx && i < _seq.length; i++) {
      if (_seq[i].phase == _Phase.focus) c++;
    }
    return c;
  }

  // 計時狀態說明：執行中顯示預計結束時刻，比固定口號更有「進行中」的感覺
  String _statusLine() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return _phase == _Phase.focus ? '專注中 · $hh:$mm 結束' : '休息中 · $hh:$mm 結束';
    }
    if (_finished) return '這一節完成了 🎉';
    if (_idle) return '專注 $_focusMin 分 · 一節 $_rounds 顆番茄';
    return '已暫停 · 按開始繼續';
  }

  // 進度小番茄（實心帶葉子 = 已完成），共 N 顆 = 這一節的回合數
  Widget _buildCycleDots() {
    final filled = _completedTomatoes().clamp(0, _rounds);
    const tomato = Color(0xFFE8604C);
    const leaf = Color(0xFF7CB163);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_rounds, (i) {
        final active = i < filled;
        return SizedBox(
          width: 18,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                width: active ? 11 : 9,
                height: active ? 11 : 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? tomato : tomato.withValues(alpha: 0.28),
                ),
              ),
              if (active)
                Positioned(
                  top: 0.5,
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Container(
                      width: 5.5,
                      height: 2.6,
                      decoration: BoxDecoration(
                        color: leaf,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPresetRow() {
    final isCustom = !_presets.any(
      (p) => p.focus == _focusMin && p.brk == _shortMin && p.rounds == _rounds,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Opacity(
        opacity: _isRunning ? 0.45 : 1,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final p in _presets) ...[
                _presetChip(
                  name: p.label,
                  detail: '${p.focus}/${p.brk} ×${p.rounds}',
                  selected:
                      !isCustom &&
                      p.focus == _focusMin &&
                      p.brk == _shortMin &&
                      p.rounds == _rounds,
                  onTap: () => _applyPreset(p.focus, p.brk, p.rounds),
                ),
                const SizedBox(width: 8),
              ],
              _presetChip(
                name: '自訂',
                detail: isCustom ? '$_focusMin/$_shortMin ×$_rounds' : '自由配',
                selected: isCustom,
                onTap: _openSettingsSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 預設組膠囊：名稱 + 時長兩行，選中走實色填底（對齊全 app 卡片語彙）
  Widget _presetChip({
    required String name,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const accent = Color(0xFFFF7043);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minWidth: 60),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: selected ? null : AppCardStyle.hairline,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.24),
                    blurRadius: 13,
                    offset: const Offset(0, 5),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppInk.strong,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              detail,
              style: AppType.digits(
                fontSize: 11,
                color: selected
                    ? Colors.white.withValues(alpha: 0.9)
                    : AppInk.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 自訂設定 sheet ──

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
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // sheet 內改值：同步父頁 state + 持久化；待機時更新第一顆專注預覽。
            // 設定只在「下次開始」組序列時生效，所以暫停中改值不動當前倒數。
            void apply(VoidCallback change) {
              setState(() {
                change();
                if (_idle || _finished) {
                  _phase = _Phase.idle;
                  _phaseTotal = _focusMin * 60;
                  _secondsLeft = _phaseTotal;
                }
              });
              setSheet(() {});
              _persistSettings();
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.86,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _phaseColor.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
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
                                color: const Color(
                                  0xFFFF7043,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                color: Color(0xFFFF7043),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '番茄鐘設定',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppInk.strong,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '安排你的專注節奏',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppInk.soft,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppInk.iconFaint,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _settingsSummaryCard(),
                        const SizedBox(height: 14),
                        _settingsSectionTitle(
                          icon: Icons.av_timer_rounded,
                          title: '時間長度',
                        ),
                        const SizedBox(height: 8),
                        _timerStepperCard(
                          label: '專注',
                          sub: '進入安靜工作段',
                          icon: Icons.local_fire_department_rounded,
                          color: const Color(0xFFFF7043),
                          value: _focusMin,
                          min: 5,
                          max: 120,
                          step: 1,
                          onChanged: (v) => apply(() => _focusMin = v),
                        ),
                        const SizedBox(height: 8),
                        _timerStepperCard(
                          label: '短休息',
                          sub: '番茄之間喘口氣',
                          icon: Icons.local_cafe_rounded,
                          color: const Color(0xFF66BB6A),
                          value: _shortMin,
                          min: 1,
                          max: 30,
                          step: 1,
                          onChanged: (v) => apply(() => _shortMin = v),
                        ),
                        const SizedBox(height: 8),
                        _timerStepperCard(
                          label: '回合數',
                          sub: '這一節做幾顆番茄',
                          icon: Icons.tag_rounded,
                          color: const Color(0xFFFF7043),
                          value: _rounds,
                          min: 1,
                          max: 8,
                          step: 1,
                          unit: '顆',
                          onChanged: (v) => apply(() => _rounds = v),
                        ),
                        const SizedBox(height: 16),
                        _settingsSectionTitle(
                          icon: Icons.spa_rounded,
                          title: '結尾長休息',
                        ),
                        const SizedBox(height: 8),
                        _timerSwitchTile(
                          label: '結尾長休息',
                          sub: '整節最後加一段較長的放鬆',
                          icon: Icons.spa_rounded,
                          value: _longBreakEnabled,
                          onChanged: (v) => apply(() => _longBreakEnabled = v),
                        ),
                        const SizedBox(height: 8),
                        _timerStepperCard(
                          label: '長休息',
                          sub: '一節結束後放鬆',
                          icon: Icons.self_improvement_rounded,
                          color: const Color(0xFF26A69A),
                          value: _longMin,
                          min: 5,
                          max: 60,
                          step: 1,
                          enabled: _longBreakEnabled,
                          onChanged: (v) => apply(() => _longMin = v),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF7043),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.check_rounded, size: 19),
                            label: const Text(
                              '完成',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF7043).withValues(alpha: 0.14),
            const Color(0xFF66BB6A).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF7043).withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.timer_rounded,
              color: Color(0xFFFF7043),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_focusMin / $_shortMin 分 ×$_rounds',
                  style: AppType.digits(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _longBreakEnabled
                      ? '一節 $_rounds 顆 · 結尾長休 $_longMin 分'
                      : '一節 $_rounds 顆番茄',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppInk.soft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFFFF7043)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppInk.strong,
          ),
        ),
      ],
    );
  }

  Widget _timerStepperCard({
    required String label,
    required String sub,
    required IconData icon,
    required Color color,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    String unit = '分鐘',
    bool enabled = true,
  }) {
    final canDecrease = enabled && value > min;
    final canIncrease = enabled && value < max;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.46,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x0A46342B)),
          boxShadow: AppShadows.flat,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppInk.soft,
                    ),
                  ),
                ],
              ),
            ),
            _stepButton(
              icon: Icons.remove_rounded,
              color: color,
              onTap: canDecrease
                  ? () => onChanged(math.max(min, value - step))
                  : null,
            ),
            Container(
              width: 66,
              margin: const EdgeInsets.symmetric(horizontal: 7),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                children: [
                  Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: AppType.digits(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            _stepButton(
              icon: Icons.add_rounded,
              color: color,
              onTap: canIncrease
                  ? () => onChanged(math.min(max, value + step))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // 加減鈕：點一下 ±step；按住連發（HoldRepeatButton），到極值自動停用
  Widget _stepButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final active = onTap != null;
    return HoldRepeatButton(
      onTrigger: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF5EEE8),
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: active ? color : AppInk.iconFaint),
        ),
      ),
    );
  }

  Widget _timerSwitchTile({
    required String label,
    required String sub,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    const accent = Color(0xFFFF7043);
    return Material(
      color: const Color(0xFFFFFCF8),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          playHaptic(HapticLevel.selection);
          onChanged(!value);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x0A46342B)),
            boxShadow: AppShadows.flat,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (value ? accent : AppInk.faint).withValues(
                    alpha: value ? 0.12 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: value ? accent : AppInk.faint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppInk.soft,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: accent,
                onChanged: (v) {
                  playHaptic(HapticLevel.selection);
                  onChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 環內副標：執行中報結束時刻，暫停/待機給情境短語
  String _ringSubtitle() {
    if (_idle) return '一節 $_rounds 顆';
    if (_finished) return '這一節完成 🎉';
    if (!_isRunning) return '已暫停';
    return switch (_phase) {
      _Phase.focus => '第 $_round / $_rounds 顆',
      _Phase.shortBreak => '喘口氣',
      _Phase.longBreak => '好好放鬆',
      _ => '',
    };
  }

  Widget _buildTimerCircle(double size, Color color) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          // 執行中光暈隨呼吸放大縮小；暫停/待機固定在最小值
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
        // 進度圓環：每秒 tick 之間用 1 秒線性補間，看起來是連續掃過
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 1000),
          builder: (context, p, child) => CustomPaint(
            painter: _TomatoDialPainter(
              progress: p,
              color: color,
              phase: _phase,
            ),
            child: child,
          ),
          child: Container(
            margin: EdgeInsets.all(size * 0.155),
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
                    color: color.withValues(alpha: 0.62),
                    size: size * 0.085,
                  ),
                  SizedBox(height: size * 0.015),
                  Text(
                    _timeString,
                    style: TextStyle(
                      fontSize: size * 0.18,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.05,
                      // 等寬數字：倒數時各位數不左右跳動。
                      // 刻意不用 AppType.digits：Baloo 2 沒有 tabular figures，
                      // 倒數會左右抖
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: size * 0.014),
                  Text(
                    _ringSubtitle(),
                    style: TextStyle(
                      fontSize: math.max(11.0, size * 0.058),
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

  // 主按鈕（開始/暫停）：Material ripple + 圖示縮放切換
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

  // 兩側小按鈕（重設/跳過）：白底髮絲線 + flat 陰影，跟卡片語彙一致
  Widget _sideButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 54,
    bool faded = false,
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
            onTap: faded ? null : onTap,
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
}

// 番茄儀表盤：外圈保留精準倒數，內層用柔和果實量感承接背景插畫。
class _TomatoDialPainter extends CustomPainter {
  final double progress;
  final Color color;
  final _Phase phase;

  const _TomatoDialPainter({
    required this.progress,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final stroke = math.max(8.0, shortest * 0.048);
    final radius = shortest / 2 - stroke * 0.8;
    final bodyRadius = radius - stroke * 1.05;

    final bodyRect = Rect.fromCircle(center: center, radius: bodyRadius);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.36, -0.42),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.96),
          color.withValues(alpha: phase == _Phase.focus ? 0.15 : 0.10),
          color.withValues(alpha: phase == _Phase.focus ? 0.25 : 0.18),
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, bodyRadius, bodyPaint);

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, shortest * 0.007)
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.08);
    for (final angle in [-0.70, 0.0, 0.70]) {
      final path = Path()
        ..moveTo(
          center.dx + math.sin(angle) * bodyRadius * 0.18,
          center.dy - bodyRadius * 0.76,
        )
        ..quadraticBezierTo(
          center.dx + math.sin(angle) * bodyRadius * 0.40,
          center.dy,
          center.dx + math.sin(angle) * bodyRadius * 0.22,
          center.dy + bodyRadius * 0.74,
        );
      canvas.drawPath(path, groovePaint);
    }

    final leafPaint = Paint()..color = const Color(0xFF79B66A);
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + (i - 2) * 0.38;
      final leafCenter =
          center +
          Offset(
            math.cos(angle) * bodyRadius * 0.50,
            math.sin(angle) * bodyRadius * 0.50,
          );
      canvas.save();
      canvas.translate(leafCenter.dx, leafCenter.dy);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: bodyRadius * 0.18,
          height: bodyRadius * 0.36,
        ),
        leafPaint,
      );
      canvas.restore();
    }

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-bodyRadius * 0.34, -bodyRadius * 0.30),
        width: bodyRadius * 0.38,
        height: bodyRadius * 0.18,
      ),
      highlight,
    );

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
    if (p <= 0) {
      return;
    }
    final sweep = 2 * math.pi * p;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          color.withValues(alpha: 0.62),
          color,
          color.withValues(alpha: 0.74),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );

    // 弧端旋鈕：白心 + accent 描邊 + 柔光，倒數的「現在」更有存在感
    final angle = -math.pi / 2 + sweep;
    final knob =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    canvas.drawCircle(
      knob,
      stroke * 0.78,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(knob, stroke * 0.62, Paint()..color = Colors.white);
    canvas.drawCircle(
      knob,
      stroke * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TomatoDialPainter old) =>
      old.progress != progress || old.color != color || old.phase != phase;
}
