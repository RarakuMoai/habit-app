import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/coin_config.dart';
import '../utils/coin_service.dart';
import '../utils/mascot.dart';
import '../utils/notification_service.dart';
import '../utils/prefs_keys.dart';
import '../utils/sfx_service.dart';
import '../utils/timer_mutex.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/hold_repeat_button.dart';
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';
import '../widgets/scene_rooms.dart';
import '../widgets/scroll_continuation_area.dart';
import '../widgets/timer_mode_frame.dart';
import '../widgets/timer_ring_painter.dart';
import 'home/room_metrics.dart';
import 'timer/exercise_timer.dart';
import 'timer/game_timer.dart';
import 'timer/metronome_timer.dart';

// 計時頁上層模式：專注／運動（間歇訓練）／節拍器（單純打拍）／
// 遊戲（桌遊／下棋輪流計時）。
enum _TimerMode { focus, exercise, metronome, game }

// 專注模式階段。idle=待機、finished=整次循環完成；長休息只在最後（可關）。
enum _Phase { idle, focus, shortBreak, longBreak, finished }

// 階段序列的一個項目（round：第幾個專注回合，休息沿用前一回合的編號）
typedef _Step = ({_Phase phase, int dur, int round});

typedef _FocusProfileDefault = ({
  int focus,
  int shortBreak,
  int rounds,
  int longBreak,
  bool longBreakEnabled,
});

// 四格只代表初始範本；預設名稱由 l10n 提供（_defaultProfileName），
// 使用者之後可改名與改掉所有時間，存過的名字照原樣顯示。
const List<_FocusProfileDefault> _focusProfileDefaults = [
  (focus: 25, shortBreak: 5, rounds: 4, longBreak: 15, longBreakEnabled: true),
  (focus: 50, shortBreak: 10, rounds: 3, longBreak: 15, longBreakEnabled: true),
  (focus: 15, shortBreak: 3, rounds: 4, longBreak: 15, longBreakEnabled: true),
  (focus: 25, shortBreak: 5, rounds: 4, longBreak: 15, longBreakEnabled: true),
];

class _FocusProfile {
  final _FocusProfileDefault defaults;
  String name;
  int focus;
  int shortBreak;
  int rounds;
  int longBreak;
  bool longBreakEnabled;

  _FocusProfile(this.defaults)
    : name = '',
      focus = defaults.focus,
      shortBreak = defaults.shortBreak,
      rounds = defaults.rounds,
      longBreak = defaults.longBreak,
      longBreakEnabled = defaults.longBreakEnabled;

  void restoreDefaults(String defaultName) {
    name = defaultName;
    focus = defaults.focus;
    shortBreak = defaults.shortBreak;
    rounds = defaults.rounds;
    longBreak = defaults.longBreak;
    longBreakEnabled = defaults.longBreakEnabled;
  }
}

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
  int _rounds = 4; // 一次循環的專注回合數（1–8）
  bool _longBreakEnabled = true;

  // 主畫面四個快捷方案各自保存完整設定；預設值只用於初次載入與個別恢復。
  final List<_FocusProfile> _profiles = [
    for (final defaults in _focusProfileDefaults) _FocusProfile(defaults),
  ];
  static const int _profileCount = 4;
  static const int _customIndex = 3;
  int _selected = 0;
  int _legacyCustomSlot = 0;

  // ── 計時狀態（有限循環：[專注→短休息]×(N-1)→專注→(長休息)→完成）──
  // 階段序列在按下開始時組好，背景回來用 wall-clock 逐段補算。
  List<_Step> _seq = const [];
  int _idx = 0;
  _Phase _phase = _Phase.idle;
  int _round = 1; // 目前第幾個專注回合（1..N）
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
  int _todayFocusRounds = 0;
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
    // 進行中被移出畫面（如功能開關關掉計時分頁）＝本次循環已停止，別讓排程好的
    // 鎖屏通知繼續照時間發。App 遭系統砍不會走 dispose，背景提醒不受影響。
    if (_isRunning) unawaited(_cancelAllNotifs());
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

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // 各格方案的預設名（l10n）。只在「沒存過名字」與「恢復初始值」時使用，
  // 使用者存過的名字照原樣顯示，不做即時翻譯（見 docs/i18n_migration.md）。
  String _defaultProfileName(int index) => switch (index) {
    0 => _l10n.focusProfileClassic,
    1 => _l10n.focusProfileDeep,
    2 => _l10n.focusProfileLight,
    _ => _l10n.focusProfileCustom,
  };

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
      // 新版四方案都可編輯。若是第一次升級，前三個沿用初始範本；第四個
      // 從舊版最後使用的自訂槽遷移，保留使用者原本的名稱與時間。
      _legacyCustomSlot = (prefs.getInt(PrefsKeys.timerCustomSlot) ?? 0).clamp(
        0,
        2,
      );
      final legacyLong = (prefs.getInt(PrefsKeys.timerLongBreakMinutes) ?? 15)
          .clamp(5, 60);
      final legacyLongEnabled =
          prefs.getBool(PrefsKeys.timerLongBreakEnabled) ?? true;
      for (var i = 0; i < _profileCount; i++) {
        final profile = _profiles[i];
        final defaults = profile.defaults;
        final isLegacyCustom = i == _customIndex;
        final legacyName = isLegacyCustom
            ? prefs.getString(PrefsKeys.timerCustomName(_legacyCustomSlot))
            : null;
        final loadedName = prefs.getString(PrefsKeys.timerFocusProfileName(i));
        profile.name = (loadedName ?? legacyName ?? _defaultProfileName(i))
            .trim();
        if (profile.name.isEmpty) profile.name = _defaultProfileName(i);
        profile.focus =
            (prefs.getInt(PrefsKeys.timerFocusProfileFocus(i)) ??
                    (isLegacyCustom
                        ? prefs.getInt(
                                PrefsKeys.timerCustomFocus(_legacyCustomSlot),
                              ) ??
                              prefs.getInt(PrefsKeys.timerFocusMinutes)
                        : null) ??
                    defaults.focus)
                .clamp(5, 120);
        profile.shortBreak =
            (prefs.getInt(PrefsKeys.timerFocusProfileShort(i)) ??
                    (isLegacyCustom
                        ? prefs.getInt(
                                PrefsKeys.timerCustomShort(_legacyCustomSlot),
                              ) ??
                              prefs.getInt(PrefsKeys.timerShortBreakMinutes)
                        : null) ??
                    defaults.shortBreak)
                .clamp(1, 30);
        profile.rounds =
            (prefs.getInt(PrefsKeys.timerFocusProfileRounds(i)) ??
                    (isLegacyCustom
                        ? prefs.getInt(
                                PrefsKeys.timerCustomRounds(_legacyCustomSlot),
                              ) ??
                              prefs.getInt(PrefsKeys.timerRounds)
                        : null) ??
                    defaults.rounds)
                .clamp(1, 8);
        profile.longBreak =
            (prefs.getInt(PrefsKeys.timerFocusProfileLong(i)) ?? legacyLong)
                .clamp(5, 60);
        profile.longBreakEnabled =
            prefs.getBool(PrefsKeys.timerFocusProfileLongEnabled(i)) ??
            legacyLongEnabled;
      }
      // 上次選的快捷方案；舊版沒存過就從舊自訂數值推回最接近的初始範本。
      final savedSel = prefs.getInt(PrefsKeys.timerSelectedPreset);
      if (savedSel != null) {
        _selected = savedSel.clamp(0, _customIndex);
      } else {
        final legacyFocus = prefs.getInt(PrefsKeys.timerFocusMinutes) ?? 25;
        final legacyShort = prefs.getInt(PrefsKeys.timerShortBreakMinutes) ?? 5;
        final legacyRounds = prefs.getInt(PrefsKeys.timerRounds) ?? 4;
        final i = _focusProfileDefaults.indexWhere(
          (p) =>
              p.focus == legacyFocus &&
              p.shortBreak == legacyShort &&
              p.rounds == legacyRounds,
        );
        _selected = i >= 0 ? i : _customIndex;
      }
      _applySelected();
      _statsDate = today;
      _todayFocusRounds = prefs.getInt(PrefsKeys.timerTomatoes(today)) ?? 0;
      _todayFocusMin = prefs.getInt(PrefsKeys.timerFocusMinutesDay(today)) ?? 0;
      // 待機預覽第一個專注回合的時長
      _phaseTotal = _focusMin * 60;
      _secondsLeft = _phaseTotal;
    });
  }

  // 把目前選中方案的完整數值灌進計時引擎。
  void _applySelected() {
    final profile = _profiles[_selected];
    _focusMin = profile.focus;
    _shortMin = profile.shortBreak;
    _rounds = profile.rounds;
    _longMin = profile.longBreak;
    _longBreakEnabled = profile.longBreakEnabled;
  }

  // 持久化四個方案；同時回寫舊 key，保留舊版本或其他既有程式碼的相容性。
  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < _profileCount; i++) {
      final profile = _profiles[i];
      await prefs.setString(PrefsKeys.timerFocusProfileName(i), profile.name);
      await prefs.setInt(PrefsKeys.timerFocusProfileFocus(i), profile.focus);
      await prefs.setInt(
        PrefsKeys.timerFocusProfileShort(i),
        profile.shortBreak,
      );
      await prefs.setInt(PrefsKeys.timerFocusProfileRounds(i), profile.rounds);
      await prefs.setInt(PrefsKeys.timerFocusProfileLong(i), profile.longBreak);
      await prefs.setBool(
        PrefsKeys.timerFocusProfileLongEnabled(i),
        profile.longBreakEnabled,
      );
    }
    final selected = _profiles[_selected];
    final custom = _profiles[_customIndex];
    await prefs.setInt(
      PrefsKeys.timerCustomFocus(_legacyCustomSlot),
      custom.focus,
    );
    await prefs.setInt(
      PrefsKeys.timerCustomShort(_legacyCustomSlot),
      custom.shortBreak,
    );
    await prefs.setInt(
      PrefsKeys.timerCustomRounds(_legacyCustomSlot),
      custom.rounds,
    );
    await prefs.setString(
      PrefsKeys.timerCustomName(_legacyCustomSlot),
      custom.name,
    );
    await prefs.setInt(PrefsKeys.timerFocusMinutes, selected.focus);
    await prefs.setInt(PrefsKeys.timerShortBreakMinutes, selected.shortBreak);
    await prefs.setInt(PrefsKeys.timerRounds, selected.rounds);
    await prefs.setInt(PrefsKeys.timerLongBreakMinutes, selected.longBreak);
    await prefs.setBool(
      PrefsKeys.timerLongBreakEnabled,
      selected.longBreakEnabled,
    );
    await prefs.setInt(PrefsKeys.timerSelectedPreset, _selected);
  }

  // 完成一個專注回合：寫進今日統計（跨日自動歸零換 key）。
  Future<void> _recordFocusRound(int minutes) async {
    final today = _dateStr(DateTime.now());
    if (_statsDate != today) {
      _statsDate = today;
      _todayFocusRounds = 0;
      _todayFocusMin = 0;
    }
    _todayFocusRounds++;
    _todayFocusMin += minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.timerTomatoes(today), _todayFocusRounds);
    await prefs.setInt(PrefsKeys.timerFocusMinutesDay(today), _todayFocusMin);
  }

  // ── 階段序列（有限循環）──

  bool get _idle => _phase == _Phase.idle;
  bool get _finished => _phase == _Phase.finished;

  // [專注→短休息]×(N-1) → 第 N 個專注回合 → (結尾長休息) → 完成
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

  // 完成一個專注階段 → 記錄回合 + 給金幣（跳過不算，只在自然完成時呼叫）。
  void _awardIfFocus(_Step step) {
    if (step.phase != _Phase.focus) return;
    _recordFocusRound(step.dur ~/ 60);
    CoinService.award(
      CoinSource.tomatoDone,
      note: _l10n.coinNoteFocus(step.dur ~/ 60),
    );
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
          ? MascotContext.focusStarted
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
          ? (_l10n.notifFocusAllDoneTitle, _l10n.notifFocusAllDoneBody(_rounds))
          : _notifFor(_seq[i + 1]);
      await NotificationService.scheduleAt(
        fireAt,
        id: _notifIdBase + (i - _idx),
        title: title,
        body: body,
        channelName: _l10n.nsTimerChannel,
        channelDescription: _l10n.nsTimerChannelDesc,
      );
      if (isLast) break;
      fireAt = fireAt.add(Duration(seconds: _seq[i + 1].dur));
    }
  }

  (String, String) _notifFor(_Step next) => switch (next.phase) {
    _Phase.focus => (
      _l10n.notifFocusStartTitle,
      _l10n.roundOfTotal(next.round, _rounds),
    ),
    _Phase.shortBreak => (
      _l10n.notifShortBreakTitle,
      _l10n.notifShortBreakBody,
    ),
    _Phase.longBreak => (_l10n.notifLongBreakTitle, _l10n.notifLongBreakBody),
    _ => (_l10n.notifStartFallback, ''),
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
        ..showSnackBar(SnackBar(content: Text(paused.pausedMessage(_l10n))));
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
      _phase == _Phase.focus
          ? MascotContext.focusStarted
          : MascotContext.halfDone,
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
  }

  // 重設：停止並回到待機（第一個專注回合的預覽）。
  void _reset() {
    _stopTicker();
    _cancelAllNotifs();
    _breath.reset();
    setState(() {
      _isRunning = false;
      _seq = const [];
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

  // 跳過當前階段（不計入完成回合）：前進到序列下一項，到底就完成。
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
          ? MascotContext.focusStarted
          : MascotContext.completedOne,
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  String _profileLabel(int index) {
    final name = _profiles[index].name.trim();
    return name.isEmpty ? _defaultProfileName(index) : name;
  }

  // 主畫面的四格只負責快速切換；編輯則一律由獨立的「設定」按鈕進入。
  void _selectProfile(int index) {
    if (!_idle && !_finished) {
      playHaptic(HapticLevel.light);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_l10n.focusSwitchNeedsReset)));
      return;
    }
    setState(() {
      _selected = index;
      _applySelected();
      _phase = _Phase.idle;
      _round = 1;
      _idx = 0;
      _phaseTotal = _focusMin * 60;
      _secondsLeft = _phaseTotal;
    });
    unawaited(_persistSettings());
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // ── UI ──

  String get _timeString {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // 專注暖橘 / 嫩綠 / 湖水綠：比 Material 原色再暖一階，貼整體插畫調性。
  Color get _phaseColor => switch (_phase) {
    _Phase.focus => const Color(0xFFFF7043),
    _Phase.shortBreak => const Color(0xFF66BB6A),
    _Phase.longBreak => const Color(0xFF26A69A),
    _Phase.finished => const Color(0xFF66BB6A),
    _Phase.idle => const Color(0xFFFF7043),
  };

  String get _phaseLabel => switch (_phase) {
    _Phase.focus => _l10n.phaseFocusTime,
    _Phase.shortBreak => _l10n.phaseShortBreak,
    _Phase.longBreak => _l10n.phaseLongBreak,
    _Phase.finished => _l10n.phaseFinished,
    _Phase.idle => _l10n.phaseIdle,
  };

  IconData get _phaseIcon => switch (_phase) {
    _Phase.focus => Icons.local_fire_department_rounded,
    _Phase.shortBreak => Icons.local_cafe_rounded,
    _Phase.longBreak => Icons.spa_rounded,
    _Phase.finished => Icons.emoji_events_rounded,
    _Phase.idle => Icons.local_fire_department_rounded,
  };

  static const Color _exerciseAccent = Color(0xFF26A69A);

  // 各模式主色：專注=暖橘（隨階段變）、運動=青綠、節拍器=紫、遊戲=藍。
  Color _accentFor(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => _phaseColor,
    _TimerMode.exercise => _exerciseAccent,
    _TimerMode.metronome => kMetronomeAccent,
    _TimerMode.game => kGameAccent,
  };

  ActiveTimer? _activeTimerFor(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => ActiveTimer.focus,
    _TimerMode.exercise => ActiveTimer.exercise,
    _TimerMode.metronome => ActiveTimer.metronome,
    _TimerMode.game => null,
  };

  // 切換列每個模式的圖示與標籤。
  (IconData, String) _modeChrome(_TimerMode mode) => switch (mode) {
    _TimerMode.focus => (Icons.psychology_rounded, _l10n.modeFocus),
    _TimerMode.exercise => (Icons.directions_run_rounded, _l10n.modeExercise),
    _TimerMode.metronome => (Icons.av_timer_rounded, _l10n.modeMetronome),
    _TimerMode.game => (Icons.casino_rounded, _l10n.modeGame),
  };

  void _switchMode(_TimerMode mode) {
    if (mode == _topMode) return;
    // 切換模式時一致地暫停目前工具並保留進度；節拍器則停止播放但保留設定。
    // 四個子頁都由 IndexedStack 保活，切回來仍可接續。
    final activeTimer = _activeTimerFor(_topMode);
    ActiveTimer? paused;
    if (activeTimer != null && TimerMutex.active == activeTimer) {
      paused = TimerMutex.pauseActive();
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
    if (paused != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _l10n.timerPausedCanResume(paused.pausedMessage(_l10n)),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 頁面主色隨模式切換：專注用暖橘、運動用青綠、節拍器用紫。
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
              child: FourPeriodRoomScene(room: FourPeriodRoom.timer),
            ),
          ),
          SafeArea(
            child: MascotPageShell(
              accent: color,
              sceneHeight: sceneRegionHeightAnchored(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top,
              ),
              scene: PersonaScene(
                accent: color,
                lightGeometry: FourPeriodRoom.timer.light,
              ),
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
      // 與 TimerModeFrame 的 horizontalInset 對齊，切換列和標頭同一條邊線。
      margin: const EdgeInsets.symmetric(
        horizontal: TimerModeMetrics.horizontalInset,
      ),
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

  Widget _buildTimerContent(Color color) {
    return TimerModeFrame(
      heroBuilder: (context, size) => _buildTimerCircle(size, color),
      status: TimerStatusPill(
        stateKey: _phase,
        color: color,
        icon: _phaseIcon,
        label: _phaseLabel,
      ),
      progress: _buildCycleDots(),
      controls: TimerControlCluster(
        accent: color,
        primaryIcon: _isRunning
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
        onPrimary: _startPause,
        leading: TimerSecondaryAction(
          icon: Icons.replay_rounded,
          label: _l10n.timerResetLabel,
          onTap: _idle ? null : _reset,
        ),
        trailing: TimerSecondaryAction(
          icon: Icons.skip_next_rounded,
          label: _l10n.timerSkipLabel,
          onTap: _idle || _finished ? null : _skipPhase,
        ),
      ),
      statusLine: Text(
        _statusLine(),
        style: const TextStyle(
          color: AppInk.soft,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      quickPicker: _buildProfilePicker(),
      footer: _todayFocusRounds > 0 ? _statsBar() : null,
      topAction: TimerSettingsAction(
        color: const Color(0xFFFF7043),
        onTap: _openSettingsSheet,
      ),
    );
  }

  // 今日統計列：有完成紀錄時才顯示，讓四種工具的主面板保有相近空間。
  Widget _statsBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 50, // 與運動統計列等高，切換模式不位移（兩處需一致）
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF7043).withValues(alpha: 0.16),
        ),
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          Expanded(
            child: _statPill(
              icon: Icons.check_circle_rounded,
              label: _l10n.statTodayDone,
              value: _l10n.roundsCount(_todayFocusRounds),
              color: const Color(0xFFFF7043),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statPill(
              icon: Icons.hourglass_bottom_rounded,
              label: _l10n.phaseFocusTime,
              value: _l10n.minutesCount(_todayFocusMin),
              color: const Color(0xFF66BB6A),
            ),
          ),
        ],
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

  // 這次循環已完成的專注回合數（= 已通過的 focus 階段數）。
  int _completedFocusRounds() {
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
      final t = '$hh:$mm';
      return _phase == _Phase.focus
          ? _l10n.focusRunningUntil(t)
          : _l10n.breakRunningUntil(t);
    }
    if (_finished) return _l10n.focusSessionDoneLine;
    if (_idle) {
      // 分鐘為主、講白節奏：專注×次數 · 休息 · 結尾長休（依設定條件顯示）。
      // 只有 1 回合時沒有中間休息；休息 0 分或關閉長休都略過。
      final parts = <String>[_l10n.focusIdleFocusPart(_focusMin, _rounds)];
      if (_rounds > 1 && _shortMin > 0) {
        parts.add(_l10n.focusIdleBreakPart(_shortMin));
      }
      if (_longBreakEnabled && _longMin > 0) {
        parts.add(_l10n.focusIdleLongPart(_longMin));
      }
      return parts.join(' · ');
    }
    return _l10n.pausedPressStart;
  }

  // 簡單圓點表示每個專注回合，避免引入額外的番茄鐘概念。
  Widget _buildCycleDots() {
    final filled = _completedFocusRounds().clamp(0, _rounds);
    const accent = Color(0xFFE8604C);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_rounds, (i) {
        final active = i < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            width: active ? 11 : 9,
            height: active ? 11 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? accent : Colors.transparent,
              border: Border.all(
                color: active ? accent : accent.withValues(alpha: 0.34),
                width: 1.5,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildProfilePicker() {
    final locked = !_idle && !_finished;
    return SizedBox(
      height: 52,
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
                  for (var i = 0; i < _profileCount; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _profileChip(index: i),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileChip({
    required int index,
    VoidCallback? onTap,
    double? width,
  }) {
    const accent = Color(0xFFFF7043);
    final profile = _profiles[index];
    final selected = _selected == index;
    return GestureDetector(
      onTap: onTap ?? () => _selectProfile(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: width,
        constraints: width == null
            ? const BoxConstraints(minWidth: 60, maxWidth: 84)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              _profileLabel(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppInk.strong,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${profile.focus}/${profile.shortBreak} ×${profile.rounds}',
              maxLines: 1,
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

  // ── 專注方案與設定 sheet ──

  Future<void> _openSettingsSheet() async {
    // 設定頁可直接切換四個方案；進行中先重設，避免改到已建立的階段序列。
    if (!_idle && !_finished) {
      playHaptic(HapticLevel.light);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_l10n.focusSettingsNeedsReset)));
      return;
    }
    var editingProfileIndex = _selected;
    var nameFieldRevision = 0;
    playFeedback(SfxCue.tap);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final profileIndex = editingProfileIndex;
            final profile = _profiles[profileIndex];

            void refreshPreview() {
              _applySelected();
              _phase = _Phase.idle;
              _phaseTotal = _focusMin * 60;
              _secondsLeft = _phaseTotal;
            }

            void applyProfile(VoidCallback change) {
              setState(() {
                change();
                refreshPreview();
              });
              setSheet(() {});
              unawaited(_persistSettings());
            }

            void selectEditingProfile(int index) {
              if (index == editingProfileIndex) return;
              FocusScope.of(ctx).unfocus();
              nameFieldRevision++;
              setState(() {
                editingProfileIndex = index;
                _selected = index;
                refreshPreview();
              });
              setSheet(() {});
              unawaited(_persistSettings());
              playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
            }

            Future<void> restoreProfile() async {
              FocusScope.of(ctx).unfocus();
              final currentName = _profileLabel(profileIndex);
              final defaultName = _defaultProfileName(profileIndex);
              final confirmed = await showAppConfirmDialog(
                ctx,
                title: _l10n.restoreProfileTitle(defaultName),
                message: _l10n.restoreProfileMessage(currentName),
                confirmLabel: _l10n.restoreProfileConfirm,
                danger: true,
              );
              if (!confirmed || !mounted || !ctx.mounted) return;
              nameFieldRevision++;
              applyProfile(() => profile.restoreDefaults(defaultName));
              playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
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
                        child: ScrollContinuationArea(
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _l10n.focusSettingsTitle,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: AppInk.strong,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _l10n.focusSettingsSubtitle,
                                          style: const TextStyle(
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
                              _settingsSectionTitle(
                                icon: Icons.view_carousel_rounded,
                                title: _l10n.sectionFocusProfiles,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                key: const ValueKey(
                                  'focus-settings-profile-picker',
                                ),
                                width: double.infinity,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns = constraints.maxWidth < 300
                                        ? 2
                                        : 4;
                                    final chipWidth =
                                        (constraints.maxWidth -
                                            8 * (columns - 1)) /
                                        columns;
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (var i = 0; i < _profileCount; i++)
                                          _profileChip(
                                            index: i,
                                            width: chipWidth,
                                            onTap: () =>
                                                selectEditingProfile(i),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              _settingsSectionTitle(
                                icon: Icons.label_rounded,
                                title: _l10n.sectionProfileName,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                key: ValueKey(
                                  'focus-profile-$profileIndex-$nameFieldRevision',
                                ),
                                initialValue: _profileLabel(profileIndex),
                                maxLength: 12,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: _defaultProfileName(profileIndex),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFFD7CCC5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.edit_rounded,
                                    color: profile.name.trim().isEmpty
                                        ? AppInk.iconFaint
                                        : const Color(0xFFFF7043),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFFFFCF8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: Color(0x0A46342B),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: Color(0x0A46342B),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFFF7043),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                onChanged: (value) =>
                                    applyProfile(() => profile.name = value),
                              ),
                              _settingsSummaryCard(),
                              const SizedBox(height: 14),
                              _settingsSectionTitle(
                                icon: Icons.av_timer_rounded,
                                title: _l10n.sectionTimeAndRounds,
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: _l10n.modeFocus,
                                sub: _l10n.focusStepperSub,
                                icon: Icons.local_fire_department_rounded,
                                color: const Color(0xFFFF7043),
                                value: _focusMin,
                                min: 5,
                                max: 120,
                                step: 1,
                                onChanged: (v) =>
                                    applyProfile(() => profile.focus = v),
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: _l10n.phaseShortBreak,
                                sub: _l10n.shortBreakStepperSub,
                                icon: Icons.local_cafe_rounded,
                                color: const Color(0xFF66BB6A),
                                value: _shortMin,
                                min: 1,
                                max: 30,
                                step: 1,
                                onChanged: (v) =>
                                    applyProfile(() => profile.shortBreak = v),
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: _l10n.roundsStepperLabel,
                                sub: _l10n.roundsStepperSub,
                                icon: Icons.tag_rounded,
                                color: const Color(0xFFFF7043),
                                value: _rounds,
                                min: 1,
                                max: 8,
                                step: 1,
                                unit: _l10n.unitRoundsWord,
                                onChanged: (v) =>
                                    applyProfile(() => profile.rounds = v),
                              ),
                              const SizedBox(height: 16),
                              _settingsSectionTitle(
                                icon: Icons.spa_rounded,
                                title: _l10n.sectionEndLongBreak,
                              ),
                              const SizedBox(height: 8),
                              _timerSwitchTile(
                                label: _l10n.sectionEndLongBreak,
                                sub: _l10n.longBreakSwitchSub,
                                icon: Icons.spa_rounded,
                                value: _longBreakEnabled,
                                onChanged: (v) => applyProfile(
                                  () => profile.longBreakEnabled = v,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _timerStepperCard(
                                label: _l10n.phaseLongBreak,
                                sub: _l10n.longBreakStepperSub,
                                icon: Icons.self_improvement_rounded,
                                color: const Color(0xFF26A69A),
                                value: _longMin,
                                min: 5,
                                max: 60,
                                step: 1,
                                enabled: _longBreakEnabled,
                                onChanged: (v) =>
                                    applyProfile(() => profile.longBreak = v),
                              ),
                              const SizedBox(height: 14),
                              _restoreDefaultsTile(
                                defaultName: _defaultProfileName(profileIndex),
                                onTap: () => unawaited(restoreProfile()),
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
                          label: Text(
                            _l10n.commonDone,
                            style: const TextStyle(fontWeight: FontWeight.w800),
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
    if (!mounted) return;
    var namesChanged = false;
    for (var i = 0; i < _profiles.length; i++) {
      final profile = _profiles[i];
      final trimmed = profile.name.trim();
      if (trimmed == profile.name && trimmed.isNotEmpty) continue;
      profile.name = trimmed.isEmpty ? _defaultProfileName(i) : trimmed;
      namesChanged = true;
    }
    if (namesChanged) {
      setState(_applySelected);
      await _persistSettings();
    }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFFF7043),
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(
                _l10n.currentRhythmTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _longBreakEnabled
                      ? _l10n.withLongBreak(_longMin)
                      : _l10n.withoutLongBreak,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppInk.soft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _settingsSummaryMetric(
                  label: _l10n.modeFocus,
                  value: _l10n.minutesCount(_focusMin),
                  color: const Color(0xFFFF7043),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _settingsSummaryMetric(
                  label: _l10n.phaseShortBreak,
                  value: _l10n.minutesCount(_shortMin),
                  color: const Color(0xFF66BB6A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _settingsSummaryMetric(
                  label: _l10n.roundsStepperLabel,
                  value: _l10n.roundsCount(_rounds),
                  color: const Color(0xFFE8604C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsSummaryMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppInk.soft,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.digits(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _restoreDefaultsTile({
    required String defaultName,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFFAF6F2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x126B5145)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppInk.faint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.restore_rounded,
                  size: 18,
                  color: AppInk.soft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l10n.restoreProfileTileTitle(defaultName),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _l10n.restoreProfileTileSub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppInk.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppInk.iconFaint,
              ),
            ],
          ),
        ),
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
    String? unit,
    bool enabled = true,
  }) {
    unit ??= _l10n.unitMinutesWord;
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
    if (_idle) return _l10n.ringTotalRounds(_rounds);
    if (_finished) return _l10n.ringFocusDone;
    if (!_isRunning) return _l10n.ringPaused;
    return switch (_phase) {
      _Phase.focus => _l10n.roundOfTotal(_round, _rounds),
      _Phase.shortBreak => _l10n.ringBreathe,
      _Phase.longBreak => _l10n.ringRelax,
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
          // 把階段也納入 key：重設回 idle 時即使同為 idx 0，也不會
          // 沿用上一段的圓環動畫狀態。
          key: ValueKey((_phase, _idx)),
          tween: Tween(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 1000),
          builder: (context, p, child) => CustomPaint(
            // 與運動模式共用同一個圓環外觀，只差傳入的專注配色。
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
}
