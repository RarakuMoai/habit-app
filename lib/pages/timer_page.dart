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
import '../utils/timer_mutex.dart';
import '../widgets/hold_repeat_button.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/timer_ring_painter.dart';
import 'home/room_ambient_overlay.dart';
import 'home/room_metrics.dart';
import 'timer/exercise_timer.dart';
import 'timer/game_timer.dart';
import 'timer/metronome_timer.dart';

// 計時頁上層模式：專注（番茄鐘）／運動（間歇訓練）／節拍器（單純打拍）／
// 遊戲（桌遊／下棋輪流計時）。
enum _TimerMode { focus, exercise, metronome, game }

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

  // 上層模式（專注/運動/節拍器/遊戲），記住上次選擇
  _TimerMode _topMode = _TimerMode.focus;

  // 切換列顯示順序（四個都常駐；遊戲計時器預設開、不再走功能開關）。
  static const List<_TimerMode> _availableModes = [
    _TimerMode.focus,
    _TimerMode.exercise,
    _TimerMode.metronome,
    _TimerMode.game,
  ];

  // ── 設定（持久化）──
  // 目前生效中的設定（驅動計時，等於「選中那一格」的值）
  int _focusMin = 25;
  int _shortMin = 5;
  int _longMin = 15;
  int _rounds = 4; // 一節幾顆番茄（1–8）
  bool _longBreakEnabled = true; // 結尾長休息（全域，跨方案共用）

  // 自訂槽：3 個可命名槽，跟預設組互不影響。_customSlot = 目前生效的槽。
  // 槽0 向後相容舊的單一自訂 key。
  static const int _customSlots = 3;
  final List<int> _customFocus = [25, 25, 25];
  final List<int> _customShort = [5, 5, 5];
  final List<int> _customRounds = [4, 4, 4];
  final List<String> _customName = ['', '', ''];
  int _customSlot = 0;

  // 槽顯示名：空白就顯示「自訂N」
  String _customLabel(int i) =>
      _customName[i].trim().isEmpty ? '自訂${i + 1}' : _customName[i].trim();

  // 目前選的方案：0/1/2=_presets、_customIndex=自訂（哪一槽看 _customSlot）。
  static const int _customIndex = 3;
  int _selected = 0;

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
    TimerMutex.register(ActiveTimer.focus, _pauseForOther);
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
    TimerMutex.unregister(ActiveTimer.focus);
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
      _topMode = switch (prefs.getString(PrefsKeys.timerMode)) {
        'exercise' => _TimerMode.exercise,
        'metronome' => _TimerMode.metronome,
        'game' => _TimerMode.game,
        _ => _TimerMode.focus,
      };
      // 3 個自訂槽：槽0 讀不到新 key 就回退舊單槽 key（向後相容遷移）。
      for (var i = 0; i < _customSlots; i++) {
        final fF = i == 0
            ? (prefs.getInt(PrefsKeys.timerFocusMinutes) ?? 25)
            : 25;
        final fS = i == 0
            ? (prefs.getInt(PrefsKeys.timerShortBreakMinutes) ?? 5)
            : 5;
        final fR = i == 0 ? (prefs.getInt(PrefsKeys.timerRounds) ?? 4) : 4;
        _customFocus[i] = (prefs.getInt(PrefsKeys.timerCustomFocus(i)) ?? fF)
            .clamp(5, 120);
        _customShort[i] = (prefs.getInt(PrefsKeys.timerCustomShort(i)) ?? fS)
            .clamp(1, 30);
        _customRounds[i] = (prefs.getInt(PrefsKeys.timerCustomRounds(i)) ?? fR)
            .clamp(1, 8);
        _customName[i] = prefs.getString(PrefsKeys.timerCustomName(i)) ?? '';
      }
      _customSlot = (prefs.getInt(PrefsKeys.timerCustomSlot) ?? 0).clamp(
        0,
        _customSlots - 1,
      );
      _longMin = prefs.getInt(PrefsKeys.timerLongBreakMinutes) ?? 15;
      _longBreakEnabled =
          prefs.getBool(PrefsKeys.timerLongBreakEnabled) ?? true;
      // 上次選的方案；舊版沒存過就用「槽0 是否剛好等於某個預設」推回，否則自訂
      final savedSel = prefs.getInt(PrefsKeys.timerSelectedPreset);
      if (savedSel != null) {
        _selected = savedSel.clamp(0, _customIndex);
      } else {
        final i = _presets.indexWhere(
          (p) =>
              p.focus == _customFocus[0] &&
              p.brk == _customShort[0] &&
              p.rounds == _customRounds[0],
        );
        _selected = i >= 0 ? i : _customIndex;
      }
      _applySelected();
      _statsDate = today;
      _todayTomatoes = prefs.getInt(PrefsKeys.timerTomatoes(today)) ?? 0;
      _todayFocusMin = prefs.getInt(PrefsKeys.timerFocusMinutesDay(today)) ?? 0;
      // 待機預覽第一顆專注的時長
      _phaseTotal = _focusMin * 60;
      _secondsLeft = _phaseTotal;
    });
  }

  // 把目前選中那一格的數值灌進生效中的設定（自訂槽或預設組）
  void _applySelected() {
    if (_selected == _customIndex) {
      _focusMin = _customFocus[_customSlot];
      _shortMin = _customShort[_customSlot];
      _rounds = _customRounds[_customSlot];
    } else {
      final p = _presets[_selected];
      _focusMin = p.focus;
      _shortMin = p.brk;
      _rounds = p.rounds;
    }
  }

  // 持久化：3 個自訂槽（含名稱）＋目前槽＋全域長休息＋選中的方案。
  // 槽0 同時回寫舊 key，維持向後相容。
  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < _customSlots; i++) {
      await prefs.setInt(PrefsKeys.timerCustomFocus(i), _customFocus[i]);
      await prefs.setInt(PrefsKeys.timerCustomShort(i), _customShort[i]);
      await prefs.setInt(PrefsKeys.timerCustomRounds(i), _customRounds[i]);
      await prefs.setString(PrefsKeys.timerCustomName(i), _customName[i]);
    }
    await prefs.setInt(PrefsKeys.timerCustomSlot, _customSlot);
    await prefs.setInt(PrefsKeys.timerFocusMinutes, _customFocus[0]);
    await prefs.setInt(PrefsKeys.timerShortBreakMinutes, _customShort[0]);
    await prefs.setInt(PrefsKeys.timerRounds, _customRounds[0]);
    await prefs.setInt(PrefsKeys.timerLongBreakMinutes, _longMin);
    await prefs.setBool(PrefsKeys.timerLongBreakEnabled, _longBreakEnabled);
    await prefs.setInt(PrefsKeys.timerSelectedPreset, _selected);
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
  double get _progress {
    if (_idle || _finished || _phaseTotal <= 0) return 0;
    return 1 - (_secondsLeft / _phaseTotal).clamp(0.0, 1.0);
  }

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
    TimerMutex.release(ActiveTimer.focus);
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

  // 被另一個計時器搶走時自動暫停自己（保留剩餘秒數），不發音效。
  void _pauseForOther() {
    if (!_isRunning) return;
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
    TimerMutex.release(ActiveTimer.focus);
  }

  void _startPause() {
    if (_isRunning) {
      _pauseForOther();
      playFeedback(SfxCue.tap);
      return;
    }
    // 啟動前先取得鎖：若另一個計時器正在跑，會自動暫停它（保留進度），跳提示告知
    final paused = TimerMutex.acquire(ActiveTimer.focus);
    if (paused != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(paused.pausedMessage)));
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
    TimerMutex.release(ActiveTimer.focus);
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

  // 選方案（預設組或自訂）：只在待機/完成可切換。進行或暫停中要先按停止(重設)
  // 回待機，否則會改了設定卻對不上已組好的當前那節。自訂槽的數值不受影響。
  void _selectPreset(int index) {
    if (!_idle && !_finished) {
      playHaptic(HapticLevel.light);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('請先按「重設」歸零，才能切換方案喔')));
      return;
    }
    setState(() {
      _selected = index;
      _applySelected();
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

  // 各模式主色：專注=番茄色（隨階段變）、運動=青綠、節拍器=紫、遊戲=藍
  Color _accentFor(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => _phaseColor,
    _TimerMode.exercise => _exerciseAccent,
    _TimerMode.metronome => kMetronomeAccent,
    _TimerMode.game => kGameAccent,
  };

  ActiveTimer _activeTimerFor(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => ActiveTimer.focus,
    _TimerMode.exercise => ActiveTimer.exercise,
    _TimerMode.metronome => ActiveTimer.metronome,
    _TimerMode.game => ActiveTimer.game,
  };

  // 切換列每個模式的圖示與標籤。
  (IconData, String) _modeChrome(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => (Icons.psychology_rounded, '專注'),
    _TimerMode.exercise => (Icons.directions_run_rounded, '運動'),
    _TimerMode.metronome => (Icons.av_timer_rounded, '節拍器'),
    _TimerMode.game => (Icons.casino_rounded, '遊戲'),
  };

  void _switchMode(_TimerMode mode) {
    if (mode == _topMode) return;
    // 目前這顆正在倒數時鎖住切換（與方案切換一致）：要先按重設歸零。
    // 暫停中不鎖——切到別頁進度仍保留在各自的 widget 裡，不會遺失。
    if (TimerMutex.active == _activeTimerFor(_topMode)) {
      playHaptic(HapticLevel.light);
      // 節拍器的按鈕是「停止」、番茄/運動才是「重設」，提示要對應目前模式
      final verb = _topMode == _TimerMode.metronome ? '停止' : '重設';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('請先按「$verb」，才能切換模式喔')));
      return;
    }
    setState(() => _topMode = mode);
    SharedPreferences.getInstance().then(
      (p) => p.setString(PrefsKeys.timerMode, switch (mode) {
        _TimerMode.exercise => 'exercise',
        _TimerMode.metronome => 'metronome',
        _TimerMode.game => 'game',
        _TimerMode.focus => 'focus',
      }),
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  @override
  Widget build(BuildContext context) {
    // 頁面主色隨模式切換：專注用番茄色、運動用青綠、節拍器用紫
    final color = _accentFor(_topMode);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: MascotAppBar(accent: color),
      body: Stack(
        children: [
          // 場景背景：延伸到 AppBar 後面，高度跟首頁同一套「寬度錨點」
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: roomSceneHeight(MediaQuery.of(context).size.width),
            child: const RepaintBoundary(
              // 試做：套用首頁同款時段光影（光束/塵埃/時段色罩）。
              // 翻車就把 ambience 拿掉、或關 kRoomAmbienceEnabled 總開關。
              child: MascotSceneBackground(
                'assets/scenes/timer/timer_bg.png',
                ambience: SceneAmbience(
                  tint: true,
                  glasslessAsset: 'assets/scenes/timer/timer_bg_glassless.png',
                  windowRect: Rect.fromLTRB(0.006, 0.0, 0.23, 0.265),
                ),
              ),
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
                  // 四模式都常駐（IndexedStack）：切換時各自計時狀態不會被丟掉。
                  // 遊戲固定佔 index 3；四模式都保活，切回來不會丟計時狀態。
                  Expanded(
                    child: IndexedStack(
                      index: switch (_topMode) {
                        _TimerMode.focus => 0,
                        _TimerMode.exercise => 1,
                        _TimerMode.metronome => 2,
                        _TimerMode.game => 3,
                      },
                      sizing: StackFit.expand,
                      children: [
                        _buildTimerContent(_phaseColor),
                        const ExerciseTimer(),
                        const MetronomeTimer(),
                        const GameTimer(),
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

  // 模式分段切換（玻璃膠囊風，跟全 app 卡片語彙一致）。只渲染已啟用的模式
  // 四欄較擠時自動縮小圖示/字級給 SE 排下。
  Widget _buildModeSwitch(Color color) {
    final modes = _availableModes;
    final crowded = modes.length >= 4;
    final iconSize = crowded ? 15.0 : 16.0;
    final fontSize = crowded ? 12.5 : 13.5;
    final iconGap = crowded ? 3.0 : 4.0;

    Widget seg(_TimerMode mode) {
      final selected = _topMode == mode;
      final segColor = _accentFor(mode);
      final (icon, label) = _modeChrome(mode);
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
                  size: iconSize,
                  color: selected ? Colors.white : AppInk.soft,
                ),
                SizedBox(width: iconGap),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppInk.soft,
                    ),
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
          for (var i = 0; i < modes.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            seg(modes[i]),
          ],
        ],
      ),
    );
  }

  // 圓盤滑動定位（用模擬器截圖微調）：x=0 置中、負值偏左；y 負值偏上。
  static const Alignment _kFullRingAlign = Alignment(0.0, -0.32);
  static const Alignment _kCompactRingAlign = Alignment(-0.46, -0.16);
  // >=0 時強制 t（截圖微調圓盤定位用），平時 -1。
  static const double _kDebugForceT = -1;

  Widget _buildTimerContent(Color color) {
    // 保留原本完整/緊湊兩個端點排版；中間用「圓盤共用滑動」連續交接。
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // 超矮（SE + 六分頁兩列導覽 + 面板展開，內容高 ~120）：緊湊版的
        // 圓點/預設列也塞不下，切到只留圓盤＋主控制的超緊湊版。
        if (h < 230) return _buildUltraCompactLayout(color, h);
        var t = Curves.easeInOutCubic.transform(_smoothRange(390, 520, h));
        if (_kDebugForceT >= 0) t = _kDebugForceT;
        if (t <= 0) return _buildCompactLayout(color, h);
        if (t >= 1) return _buildFullLayout(color);
        return _blendTimerLayouts(color, h, t);
      },
    );
  }

  // 圓盤共用滑動：交接過程中圓盤是「單一」元件，連續在緊湊（左側、較小）↔
  // 完整（中央、較大）兩個位置間滑動＋縮放，不再瞬移也不會出現雙圓盤殘影；
  // 周邊文字/按鈕（圓盤挖空成等大留白）淡入淡出。兩端 (t=0/1) 用真實排版。
  Widget _blendTimerLayouts(Color color, double height, double t) {
    final fullHeight = math.max(height, 520.0);
    final ringSize = 170 + (246 - 170) * t; // 緊湊 170 → 完整 246
    final ringAlign = Alignment.lerp(_kCompactRingAlign, _kFullRingAlign, t)!;
    // 周邊錯開淡入淡出且「不重疊」：t<0.5 只有緊湊在淡出、t>0.5 只有完整在淡入，
    // 任一幀最多一套周邊在做 saveLayer；中段只剩圓盤在滑。看不見的那套直接不建，
    // 省掉每幀的 build／排版／saveLayer 成本。
    final compactOpacity = Curves.easeIn.transform((1 - 2 * t).clamp(0.0, 1.0));
    final fullOpacity = Curves.easeIn.transform((2 * t - 1).clamp(0.0, 1.0));
    return ClipRect(
      child: Stack(
        children: [
          if (compactOpacity > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: compactOpacity,
                  child: _buildCompactLayout(color, height, showRing: false),
                ),
              ),
            ),
          if (fullOpacity > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: fullOpacity,
                  child: OverflowBox(
                    minHeight: fullHeight,
                    maxHeight: fullHeight,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: fullHeight,
                      child: _buildFullLayout(color, showRing: false),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Align(
                  alignment: ringAlign,
                  child: _buildTimerCircle(ringSize, color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _smoothRange(double start, double end, double value) {
    final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  // 完整版面（面板收合）：環吸收剩餘高度置中，統計列釘在底部收尾
  Widget _buildFullLayout(Color color, {bool showRing = true}) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _phaseChip(color),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildCycleDots(),
        ),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) {
                final ring = math.min(math.min(c.maxWidth, c.maxHeight), 246.0);
                return showRing
                    ? _buildTimerCircle(ring, color)
                    : SizedBox.square(dimension: ring);
              },
            ),
          ),
        ),
        _controlsRow(color),
        const SizedBox(height: 10),
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

  // 超緊湊版面（高度連緊湊版都放不下）：圓盤＋狀態＋主控制並排，
  // 圓點與預設列讓位；把面板上拉即可回到緊湊/完整版。
  Widget _buildUltraCompactLayout(Color color, double h) {
    final ringSize = (h - 12).clamp(80.0, 150.0);
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildTimerCircle(ringSize, color),
          const SizedBox(width: 18),
          // 高度不足時右欄（狀態＋控制）等比縮小，任何高度都不溢出。
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _phaseChip(color, small: true),
                  const SizedBox(height: 8),
                  _controlsRow(color, compact: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 緊湊版面（兔咪面板展開）：環和控制並排，一眼可見、一指可按
  Widget _buildCompactLayout(Color color, double h, {bool showRing = true}) {
    final ringSize = (h - 110).clamp(110.0, 170.0);
    return Column(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              showRing
                  ? _buildTimerCircle(ringSize, color)
                  : SizedBox.square(dimension: ringSize),
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
          icon: Icons.replay_rounded,
          label: '重設',
          onTap: _reset,
          size: compact ? 44 : 54,
          faded: _idle,
        ),
        SizedBox(width: gap),
        // 主鈕比兩側大；下方補一格與側鈕文字同高的留白，三顆圓心對齊
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mainButton(color, size: compact ? 62 : 78),
            const SizedBox(height: _sideLabelGap + _sideLabelHeight),
          ],
        ),
        SizedBox(width: gap),
        _sideButton(
          icon: Icons.skip_next_rounded,
          label: '跳過',
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
      height: 50, // 與運動統計列等高，切換模式不位移（兩處需一致）
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
    if (_idle) {
      // 分鐘為主、講白節奏：專注×次數 · 休息 · 結尾長休（依設定條件顯示）。
      // 只有 1 顆時沒有中間休息；休息 0 分或關閉長休都略過。
      final parts = <String>['專注 $_focusMin 分 ×$_rounds'];
      if (_rounds > 1 && _shortMin > 0) parts.add('休息 $_shortMin 分');
      if (_longBreakEnabled && _longMin > 0) parts.add('結尾長休 $_longMin 分');
      return parts.join(' · ');
    }
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

  // 方案/子模式選擇列的固定高度槽：與運動 _kindPicker 等高，FittedBox 縮放後
  // 高度也固定，切換模式時版面不位移（兩處數值務必一致）。
  static const double _pickerRowHeight = 52;

  Widget _buildPresetRow() {
    final locked = !_idle && !_finished; // 進行/暫停中鎖住，要先停止
    return SizedBox(
      height: _pickerRowHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Opacity(
            opacity: locked ? 0.45 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _presets.length; i++) ...[
                    _presetChip(
                      name: _presets[i].label,
                      detail:
                          '${_presets[i].focus}/${_presets[i].brk} ×${_presets[i].rounds}',
                      selected: _selected == i,
                      onTap: () => _selectPreset(i),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 自訂永遠顯示自己記住的配置，點預設不會被改寫
                  _presetChip(
                    name: _customLabel(_customSlot),
                    detail:
                        '${_customFocus[_customSlot]}/${_customShort[_customSlot]} ×${_customRounds[_customSlot]}',
                    selected: _selected == _customIndex,
                    onTap: _openSettingsSheet,
                  ),
                ],
              ),
            ),
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
    // 同預設：只在待機/完成可調，進行/暫停中先停止回待機
    if (!_idle && !_finished) {
      playHaptic(HapticLevel.light);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('請先按「重設」歸零，才能切換方案喔')));
      return;
    }
    // 點自訂＝選中自訂槽，預覽立刻換成記住的自訂配置
    setState(() {
      _selected = _customIndex;
      _applySelected();
      if (_idle || _finished) {
        _phase = _Phase.idle;
        _phaseTotal = _focusMin * 60;
        _secondsLeft = _phaseTotal;
      }
    });
    _persistSettings();
    playFeedback(SfxCue.tap);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // sheet 內改值：寫進自訂槽 + 同步生效中的設定 + 持久化；
            // 待機時更新第一顆專注預覽。改值也代表「選中自訂」。
            void apply(VoidCallback change) {
              setState(() {
                change();
                _selected = _customIndex;
                _applySelected();
                if (_idle || _finished) {
                  _phase = _Phase.idle;
                  _phaseTotal = _focusMin * 60;
                  _secondsLeft = _phaseTotal;
                }
              });
              setSheet(() {});
              _persistSettings();
            }

            // 切換槽＝選它當生效方案（沿用 apply：換 slot 後 _applySelected 會
            // 把生效設定指向該槽）。
            void selectSlot(int i) => apply(() => _customSlot = i);

            // 槽分頁：名稱 + 配置小字，選中走實色。
            Widget slotTab(int i) {
              final sel = _customSlot == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => selectSlot(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFFFF7043)
                          : const Color(0xFFFFF3EE),
                      borderRadius: BorderRadius.circular(13),
                      border: sel
                          ? null
                          : Border.all(color: const Color(0xFFFFE0D4)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _customLabel(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: sel ? Colors.white : AppInk.strong,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_customFocus[i]}/${_customShort[i]} ×${_customRounds[i]}',
                          style: AppType.digits(
                            fontSize: 10.5,
                            color: sel
                                ? Colors.white.withValues(alpha: 0.9)
                                : AppInk.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
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
                  // 內容捲動、「完成」固定在底（footer），面板再長也按得到。
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                              // 3 個自訂槽分頁（你的「上面三個選項」）
                              Row(
                                children: [
                                  slotTab(0),
                                  const SizedBox(width: 8),
                                  slotTab(1),
                                  const SizedBox(width: 8),
                                  slotTab(2),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                // 換槽時 key 變 → 重建帶入該槽名稱當初值
                                key: ValueKey('slotname_$_customSlot'),
                                initialValue: _customName[_customSlot],
                                onChanged: (v) =>
                                    apply(() => _customName[_customSlot] = v),
                                maxLength: 8,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppInk.strong,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                  hintText: '幫這個自訂取名（例如 工作 / 讀書）',
                                  hintStyle: const TextStyle(
                                    fontSize: 13,
                                    color: AppInk.faint,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.drive_file_rename_outline_rounded,
                                    size: 18,
                                    color: Color(0xFFFF7043),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFFAF6F2),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(13),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
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
                                value: _customFocus[_customSlot],
                                min: 5,
                                max: 120,
                                step: 1,
                                onChanged: (v) =>
                                    apply(() => _customFocus[_customSlot] = v),
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: '短休息',
                                sub: '番茄之間喘口氣',
                                icon: Icons.local_cafe_rounded,
                                color: const Color(0xFF66BB6A),
                                value: _customShort[_customSlot],
                                min: 1,
                                max: 30,
                                step: 1,
                                onChanged: (v) =>
                                    apply(() => _customShort[_customSlot] = v),
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: '回合數',
                                sub: '這一節做幾顆番茄',
                                icon: Icons.tag_rounded,
                                color: const Color(0xFFFF7043),
                                value: _customRounds[_customSlot],
                                min: 1,
                                max: 8,
                                step: 1,
                                unit: '顆',
                                onChanged: (v) =>
                                    apply(() => _customRounds[_customSlot] = v),
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
                                onChanged: (v) =>
                                    apply(() => _longBreakEnabled = v),
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
                              const SizedBox(height: 4),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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
          // 換階段時用 _idx 重建，從 0 起新進度，避免進度弧由滿「倒帶」回 0
          key: ValueKey(_idx),
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 1000),
          builder: (context, p, child) => CustomPaint(
            // 與運動模式共用同一顆圓環外觀，只差傳入的番茄配色
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
                    _timeString,
                    style: TextStyle(
                      fontSize: size * 0.2,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.05,
                      // 等寬數字：倒數時各位數不左右跳動。
                      // 刻意不用 AppType.digits：Baloo 2 沒有 tabular figures，
                      // 倒數會左右抖
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

  // 兩側小按鈕（重設/跳過）：白底髮絲線 + flat 陰影，跟卡片語彙一致；
  // 圓鈕下方掛一行小文字，避免單看圖示猜不出意圖
  static const double _sideLabelGap = 6;
  static const double _sideLabelHeight = 16;
  Widget _sideButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = 54,
    bool faded = false,
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
}
