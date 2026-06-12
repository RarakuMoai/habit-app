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
import '../widgets/mascot_app_bar.dart';
import '../widgets/mascot_page_shell.dart';
import '../widgets/mascot_scene.dart';

// 番茄鐘三階段。長休息：每完成 [_TimerPageState._longBreakEvery] 顆番茄一次。
enum _Phase { focus, shortBreak, longBreak }

// 時長預設組（分鐘）。「自訂」不在列表內，由設定 sheet 調出任意組合。
const _presets = [
  (label: '經典', focus: 25, brk: 5),
  (label: '深度', focus: 50, brk: 10),
  (label: '輕量', focus: 15, brk: 3),
];

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const int _longBreakEvery = 4;
  // 通知 id 區段：鏈式排程最多 _maxChainNotifs 則，id 從 base 遞增
  static const int _notifIdBase = 1001;
  static const int _maxChainNotifs = 6;

  // ── 設定（持久化）──
  int _focusMin = 25;
  int _shortMin = 5;
  int _longMin = 15;
  bool _longBreakEnabled = true;
  bool _autoStartBreak = true; // 專注結束自動開始休息
  bool _autoStartFocus = false; // 休息結束自動開始下一輪專注

  // ── 計時狀態 ──
  _Phase _phase = _Phase.focus;
  int _secondsLeft = 25 * 60;
  // 當前階段總秒數快照：計時中改設定不影響本階段的進度環
  int _phaseTotal = 25 * 60;
  bool _isRunning = false;
  Timer? _timer;
  // 執行中才有值：當前階段絕對結束時刻。
  // 用 wall-clock 算 remaining，app 切到背景再回來時間還是對的。
  DateTime? _endTime;

  // 循環位置：自上次長休息以來完成的番茄數（0~4）
  int _cycleCount = 0;

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
      _focusMin = prefs.getInt(PrefsKeys.timerFocusMinutes) ?? 25;
      _shortMin = prefs.getInt(PrefsKeys.timerShortBreakMinutes) ?? 5;
      _longMin = prefs.getInt(PrefsKeys.timerLongBreakMinutes) ?? 15;
      _longBreakEnabled = prefs.getBool(PrefsKeys.timerLongBreakEnabled) ?? true;
      _autoStartBreak = prefs.getBool(PrefsKeys.timerAutoStartBreak) ?? true;
      _autoStartFocus = prefs.getBool(PrefsKeys.timerAutoStartFocus) ?? false;
      _statsDate = today;
      _todayTomatoes = prefs.getInt(PrefsKeys.timerTomatoes(today)) ?? 0;
      _todayFocusMin =
          prefs.getInt(PrefsKeys.timerFocusMinutesDay(today)) ?? 0;
      _secondsLeft = _phaseSeconds(_phase);
      _phaseTotal = _secondsLeft;
    });
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.timerFocusMinutes, _focusMin);
    await prefs.setInt(PrefsKeys.timerShortBreakMinutes, _shortMin);
    await prefs.setInt(PrefsKeys.timerLongBreakMinutes, _longMin);
    await prefs.setBool(PrefsKeys.timerLongBreakEnabled, _longBreakEnabled);
    await prefs.setBool(PrefsKeys.timerAutoStartBreak, _autoStartBreak);
    await prefs.setBool(PrefsKeys.timerAutoStartFocus, _autoStartFocus);
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
    await prefs.setInt(
      PrefsKeys.timerFocusMinutesDay(today),
      _todayFocusMin,
    );
  }

  // ── 階段邏輯 ──

  int _phaseSeconds(_Phase p) => switch (p) {
    _Phase.focus => _focusMin * 60,
    _Phase.shortBreak => _shortMin * 60,
    _Phase.longBreak => _longMin * 60,
  };

  // 當前階段已完成比例 0~1（給進度圓環用）
  double get _progress =>
      1 - (_secondsLeft / math.max(_phaseTotal, 1)).clamp(0.0, 1.0);

  // 指定階段完成後的下一階段（cycleAfter = 完成後的番茄數）
  _Phase _nextPhase(_Phase p, int cycleAfter) {
    if (p == _Phase.focus) {
      return (_longBreakEnabled && cycleAfter >= _longBreakEvery)
          ? _Phase.longBreak
          : _Phase.shortBreak;
    }
    return _Phase.focus;
  }

  /// 完成當前階段並推進狀態；回傳下一階段是否自動開始。
  bool _completePhase() {
    if (_phase == _Phase.focus) {
      _cycleCount++;
      _recordTomato(_phaseTotal ~/ 60);
      // 完成一顆番茄 +金幣（跳過的階段不會走到這裡，刷不了）
      CoinService.award(CoinSource.tomatoDone, note: '番茄 ${_phaseTotal ~/ 60} 分');
      _phase = _nextPhase(_Phase.focus, _cycleCount);
    } else {
      if (_phase == _Phase.longBreak) _cycleCount = 0;
      _phase = _Phase.focus;
    }
    _secondsLeft = _phaseSeconds(_phase);
    _phaseTotal = _secondsLeft;
    return _phase == _Phase.focus ? _autoStartFocus : _autoStartBreak;
  }

  // 由絕對結束時刻反推剩餘秒數。背景期間可能跨了多個自動接續的階段，
  // 用 while 逐段補算到「現在還在進行中」或「停在某階段起點」為止。
  void _refreshFromEndTime() {
    var end = _endTime;
    if (end == null) return;
    var remaining = end.difference(DateTime.now()).inSeconds;
    var crossed = false;
    while (remaining <= 0) {
      crossed = true;
      final continues = _completePhase();
      if (!continues) {
        _stopTicker();
        setState(() {
          _isRunning = false;
          _endTime = null;
        });
        _boundaryFeedback();
        return;
      }
      end = end!.add(Duration(seconds: _phaseTotal));
      remaining = end.difference(DateTime.now()).inSeconds;
    }
    if (crossed) _boundaryFeedback();
    setState(() {
      _endTime = end;
      _secondsLeft = remaining;
    });
  }

  // 跨階段的回饋：音效 + 兔咪換情緒（多階段一次補算也只播一次）
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

  // 沿著自動接續鏈把每個階段結束通知排好（最多 _maxChainNotifs 則）。
  // 鏈在「下一階段不自動開始」處截斷 —— 與 _completePhase 行為一致。
  Future<void> _scheduleChainNotifications(DateTime firstEnd) async {
    // 第一次排程才會跳系統權限 dialog；拒絕的話通知不響，倒數照走
    final ok = await NotificationService.ensurePermission();
    if (!ok) return;
    var end = firstEnd;
    var phase = _phase;
    var cycle = _cycleCount;
    for (var i = 0; i < _maxChainNotifs; i++) {
      final endingFocus = phase == _Phase.focus;
      await NotificationService.scheduleAt(
        end,
        id: _notifIdBase + i,
        title: endingFocus ? '🍅 專注時間結束' : '☕ 休息結束',
        body: endingFocus ? '辛苦了，休息一下吧。' : '回來開始下一輪專注。',
      );
      // 推進到下一階段；不自動接續就停
      if (endingFocus) {
        cycle++;
      } else if (phase == _Phase.longBreak) {
        cycle = 0;
      }
      final next = _nextPhase(phase, cycle);
      final autoNext =
          next == _Phase.focus ? _autoStartFocus : _autoStartBreak;
      if (!autoNext) break;
      phase = next;
      end = end.add(Duration(seconds: _phaseSeconds(phase)));
    }
  }

  // ── 操作 ──

  void _startPause() {
    if (_isRunning) {
      // 暫停：留下當前剩餘秒數、取消整條通知鏈
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
    } else {
      if (_secondsLeft <= 0) {
        _secondsLeft = _phaseSeconds(_phase);
        _phaseTotal = _secondsLeft;
      }
      final end = DateTime.now().add(Duration(seconds: _secondsLeft));
      setState(() {
        _endTime = end;
        _isRunning = true;
      });
      _breath.repeat(reverse: true);
      _scheduleChainNotifications(end);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromEndTime(),
      );
      MascotPersona.interact(
        _phase == _Phase.focus
            ? MascotContext.openApp
            : MascotContext.halfDone,
      );
      playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    }
  }

  // 重設：停止並回到全新循環（專注階段、循環歸零）
  void _reset() {
    _stopTicker();
    _cancelAllNotifs();
    setState(() {
      _isRunning = false;
      _phase = _Phase.focus;
      _cycleCount = 0;
      _secondsLeft = _phaseSeconds(_Phase.focus);
      _phaseTotal = _secondsLeft;
      _endTime = null;
    });
    MascotPersona.interact(MascotContext.notStarted);
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  // 跳過當前階段：不計番茄；跳過長休息視同休息結束（循環歸零）
  void _skipPhase() {
    _stopTicker();
    _cancelAllNotifs();
    setState(() {
      if (_phase == _Phase.focus) {
        _phase = _Phase.shortBreak;
      } else {
        if (_phase == _Phase.longBreak) _cycleCount = 0;
        _phase = _Phase.focus;
      }
      _secondsLeft = _phaseSeconds(_phase);
      _phaseTotal = _secondsLeft;
      _isRunning = false;
      _endTime = null;
    });
    MascotPersona.interact(
      _phase == _Phase.focus
          ? MascotContext.openApp
          : MascotContext.completedOne,
    );
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // 套用時長預設組（計時中不可用；待機/暫停會重設當前階段倒數）
  void _applyPreset(int focus, int brk) {
    if (_isRunning) {
      playHaptic(HapticLevel.light);
      return;
    }
    setState(() {
      _focusMin = focus;
      _shortMin = brk;
      _secondsLeft = _phaseSeconds(_phase);
      _phaseTotal = _secondsLeft;
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

  Color get _phaseColor => switch (_phase) {
    _Phase.focus => Colors.orange,
    _Phase.shortBreak => Colors.green,
    _Phase.longBreak => Colors.teal,
  };

  String get _phaseLabel => switch (_phase) {
    _Phase.focus => '🍅 專注時間',
    _Phase.shortBreak => '☕ 短休息',
    _Phase.longBreak => '🌿 長休息',
  };

  @override
  Widget build(BuildContext context) {
    final color = _phaseColor;

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
              child: _buildTimerContent(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerContent(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 狀態標籤（換階段時縮放淡入交接）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Container(
              key: ValueKey(_phase),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                _phaseLabel,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // 循環指示點：每 4 顆番茄一次長休息
          if (_longBreakEnabled) ...[
            const SizedBox(height: 10),
            _buildCycleDots(),
          ],

          const SizedBox(height: 16),

          // 計時圓圈：進度圓環 + 呼吸光暈（執行中才呼吸）
          _buildTimerCircle(color),

          const SizedBox(height: 18),

          // 按鈕
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _sideButton(icon: Icons.refresh, onTap: _reset),
              const SizedBox(width: 24),
              _mainButton(color),
              const SizedBox(width: 24),
              _sideButton(icon: Icons.skip_next, onTap: _skipPhase),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            _statusLine(),
            style: const TextStyle(color: AppInk.soft, fontSize: 14),
          ),

          const SizedBox(height: 12),

          // 時長預設組 + 自訂（計時中淡化停用）
          _buildPresetRow(),

          // 今日統計（有完成過才顯示，pop 一下增加成就感）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _todayTomatoes == 0
                ? const SizedBox(height: 8)
                : Padding(
                    key: ValueKey(_todayTomatoes),
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '今日 🍅×$_todayTomatoes · $_todayFocusMin 分鐘',
                        style: AppType.digits(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // 計時狀態說明：執行中顯示預計結束時刻，比固定口號更有「進行中」的感覺
  String _statusLine() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return _phase == _Phase.focus
          ? '專注中 · $hh:$mm 結束'
          : '休息中 · $hh:$mm 結束';
    }
    if (_phase == _Phase.focus) return '專注 $_focusMin 分鐘 · 休息 $_shortMin 分鐘';
    return '好好休息，準備下一輪！';
  }

  // 循環指示點：實心 = 本輪已完成的番茄
  Widget _buildCycleDots() {
    final filled = _cycleCount.clamp(0, _longBreakEvery);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_longBreakEvery, (i) {
        final active = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 9 : 7,
          height: active ? 9 : 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Colors.orange
                : Colors.orange.withValues(alpha: 0.22),
          ),
        );
      }),
    );
  }

  Widget _buildPresetRow() {
    final isCustom = !_presets.any(
      (p) => p.focus == _focusMin && p.brk == _shortMin,
    );
    return Opacity(
      opacity: _isRunning ? 0.45 : 1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final p in _presets) ...[
            _presetChip(
              label: '${p.label} ${p.focus}/${p.brk}',
              selected: !isCustom &&
                  p.focus == _focusMin &&
                  p.brk == _shortMin,
              onTap: () => _applyPreset(p.focus, p.brk),
            ),
            const SizedBox(width: 8),
          ],
          _presetChip(
            label: '自訂',
            icon: Icons.tune_rounded,
            selected: isCustom,
            onTap: _openSettingsSheet,
          ),
        ],
      ),
    );
  }

  Widget _presetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.orange : const Color(0xFFDDD0C4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected ? Colors.white : AppInk.soft,
              ),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: AppType.digits(
                color: selected ? Colors.white : AppInk.soft,
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // sheet 內改值：同步父頁 state + 持久化；待機時同步重設倒數
          void apply(VoidCallback change) {
            setSheet(() {});
            setState(() {
              change();
              if (!_isRunning) {
                _secondsLeft = _phaseSeconds(_phase);
                _phaseTotal = _secondsLeft;
              }
            });
            _persistSettings();
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              24 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8F0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text(
                      '番茄鐘設定',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppInk.iconFaint),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _stepperRow(
                  label: '專注時長',
                  value: _focusMin,
                  min: 5,
                  max: 120,
                  step: 5,
                  onChanged: (v) => apply(() => _focusMin = v),
                ),
                _stepperRow(
                  label: '短休息',
                  value: _shortMin,
                  min: 1,
                  max: 30,
                  step: 1,
                  onChanged: (v) => apply(() => _shortMin = v),
                ),
                _stepperRow(
                  label: '長休息',
                  value: _longMin,
                  min: 5,
                  max: 60,
                  step: 5,
                  enabled: _longBreakEnabled,
                  onChanged: (v) => apply(() => _longMin = v),
                ),
                const SizedBox(height: 4),
                _switchRow(
                  label: '長休息循環',
                  sub: '每 $_longBreakEvery 顆番茄後進長休息',
                  value: _longBreakEnabled,
                  onChanged: (v) => apply(() => _longBreakEnabled = v),
                ),
                _switchRow(
                  label: '專注結束自動休息',
                  sub: '番茄完成後直接開始倒數休息',
                  value: _autoStartBreak,
                  onChanged: (v) => apply(() => _autoStartBreak = v),
                ),
                _switchRow(
                  label: '休息結束自動專注',
                  sub: '不想被推著走就關著，自己按開始',
                  value: _autoStartFocus,
                  onChanged: (v) => apply(() => _autoStartFocus = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stepperRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppInk.strong,
                ),
              ),
            ),
            _stepBtn(
              Icons.remove_rounded,
              enabled && value > min
                  ? () => onChanged(math.max(min, value - step))
                  : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$value 分',
                textAlign: TextAlign.center,
                style: AppType.digits(fontSize: 16, color: AppInk.strong),
              ),
            ),
            _stepBtn(
              Icons.add_rounded,
              enabled && value < max
                  ? () => onChanged(math.min(max, value + step))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final active = onTap != null;
    return Material(
      color: active ? Colors.orange.withValues(alpha: 0.10) : const Color(0xFFFAF7F2),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                playHaptic(HapticLevel.selection);
                onTap();
              },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 19,
            color: active ? Colors.orange.shade600 : AppInk.iconFaint,
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppInk.strong,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 12, color: AppInk.soft),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: Colors.orange,
            onChanged: (v) {
              playHaptic(HapticLevel.selection);
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimerCircle(Color color) {
    return SizedBox(
      width: 224,
      height: 224,
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
                  color: color.withValues(alpha: 0.18 + 0.14 * t),
                  blurRadius: 26 + 14 * t,
                  spreadRadius: 3 + 5 * t,
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
            painter: _RingPainter(progress: p, color: color),
            child: child,
          ),
          child: Container(
            margin: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Center(
              child: Text(
                _timeString,
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: color,
                  // 等寬數字：倒數時各位數不左右跳動。
                  // 刻意不用 AppType.digits：Baloo 2 沒有 tabular figures，
                  // 倒數會左右抖
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 主按鈕（開始/暫停）：Material ripple + 圖示縮放切換
  Widget _mainButton(Color color) {
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
            width: 80,
            height: 80,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _isRunning ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(_isRunning),
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 兩側小按鈕（重設/跳過）：Material ripple
  Widget _sideButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFFFAF7F2),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: AppInk.soft),
        ),
      ),
    );
  }
}

// 計時進度圓環：淡色軌道 + 實色圓頭進度弧（從 12 點鐘方向順時針）
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
