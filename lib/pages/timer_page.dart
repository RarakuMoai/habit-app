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

  // 番茄紅橘 / 嫩綠 / 湖水綠：比 Material 原色再暖一階，貼整體插畫調性
  Color get _phaseColor => switch (_phase) {
    _Phase.focus => const Color(0xFFFF7043),
    _Phase.shortBreak => const Color(0xFF66BB6A),
    _Phase.longBreak => const Color(0xFF26A69A),
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
    final ringSize = (h - 305).clamp(140.0, 238.0);
    return Column(
      children: [
        const SizedBox(height: 10),
        _phaseChip(color),
        if (_longBreakEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 10),
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
        const SizedBox(height: 12),
        _buildPresetRow(),
        const SizedBox(height: 14),
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
                  if (_longBreakEnabled)
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
          horizontal: small ? 14 : 20,
          vertical: small ? 6 : 8,
        ),
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
            fontSize: small ? 13 : 16,
          ),
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
        ),
        SizedBox(width: gap),
        _mainButton(color, size: compact ? 62 : 78),
        SizedBox(width: gap),
        _sideButton(
          icon: Icons.skip_next_rounded,
          onTap: _skipPhase,
          size: compact ? 44 : 54,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: hasAny
            ? const Color(0xFFFF7043).withValues(alpha: 0.08)
            : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(hasAny ? '🍅' : '🌱', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          hasAny
              ? Text(
                  '今日 ×$_todayTomatoes · 專注 $_todayFocusMin 分鐘',
                  style: AppType.digits(
                    fontSize: 13.5,
                    color: const Color(0xFFE25A33),
                  ),
                )
              : const Text(
                  '今天還沒種下番茄，按下開始吧',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppInk.soft,
                    fontWeight: FontWeight.w500,
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

  // 循環指示：小番茄（實心帶葉子 = 本輪已完成），比抽象圓點更有味道
  Widget _buildCycleDots() {
    final filled = _cycleCount.clamp(0, _longBreakEvery);
    const tomato = Color(0xFFE8604C);
    const leaf = Color(0xFF7CB163);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_longBreakEvery, (i) {
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
      (p) => p.focus == _focusMin && p.brk == _shortMin,
    );
    return Opacity(
      opacity: _isRunning ? 0.45 : 1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final p in _presets) ...[
            _presetChip(
              name: p.label,
              detail: '${p.focus}·${p.brk}',
              selected:
                  !isCustom && p.focus == _focusMin && p.brk == _shortMin,
              onTap: () => _applyPreset(p.focus, p.brk),
            ),
            const SizedBox(width: 8),
          ],
          _presetChip(
            name: '自訂',
            detail: isCustom ? '$_focusMin·$_shortMin' : '自由配',
            selected: isCustom,
            onTap: _openSettingsSheet,
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: selected ? null : AppCardStyle.hairline,
          boxShadow: selected ? null : AppShadows.flat,
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

  // 環內副標：執行中報結束時刻，暫停/待機給情境短語
  String _ringSubtitle() {
    final end = _endTime;
    if (_isRunning && end != null) {
      final hh = end.hour.toString().padLeft(2, '0');
      final mm = end.minute.toString().padLeft(2, '0');
      return '～$hh:$mm';
    }
    if (_secondsLeft < _phaseTotal) return '已暫停';
    return switch (_phase) {
      _Phase.focus => '第 ${(_cycleCount % _longBreakEvery) + 1} 顆番茄',
      _Phase.shortBreak => '喘口氣',
      _Phase.longBreak => '好好放鬆',
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
            painter: _RingPainter(progress: p, color: color),
            child: child,
          ),
          child: Container(
            margin: EdgeInsets.all(size * 0.082),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // 暖白面 + 極淡髮絲圈，跟卡片語彙一致
              color: Color(0xFFFFFDF9),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x0A46342B)),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeString,
                    style: TextStyle(
                      fontSize: size * 0.205,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.05,
                      // 等寬數字：倒數時各位數不左右跳動。
                      // 刻意不用 AppType.digits：Baloo 2 沒有 tabular figures，
                      // 倒數會左右抖
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: size * 0.02),
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
  }) {
    return DecoratedBox(
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
    );
  }
}

// 計時進度圓環：淡色軌道 + 實色圓頭進度弧（12 點鐘方向順時針）+
// 弧端白心旋鈕（同首頁進度列的亮點語彙）
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(8.0, size.width * 0.047);
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.13);
    canvas.drawCircle(center, radius, track);

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final sweep = 2 * math.pi * p;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );

    // 弧端旋鈕：白心 + accent 描邊 + 柔光，倒數的「現在」更有存在感
    final angle = -math.pi / 2 + sweep;
    final knob = center +
        Offset(math.cos(angle) * radius, math.sin(angle) * radius);
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
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
