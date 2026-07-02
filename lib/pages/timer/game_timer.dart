import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/audio_settings_service.dart';
import '../../utils/bgm_service.dart';
import '../../utils/mascot.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/sfx_service.dart';
import '../../utils/timer_mutex.dart';
import '../../utils/wake_guard.dart';
import '../../widgets/hold_repeat_button.dart';
import '../../widgets/timer_ring_painter.dart';

// 遊戲計時器主色（跟專注番茄、運動青綠、節拍器紫明顯區分）。
const Color kGameAccent = Color(0xFF5B8DEF);

// 決出勝負／完成時共用的慶祝色（狀態膠囊、主鈕、圓環、玩家卡都靠它統一）。
const Color _kFinishedGreen = Color(0xFF66BB6A);

// 計時模式：每回合（每位玩家每輪都重置秒數）／棋鐘（每人一桶累計時間）。
enum _GameMode { turn, bank }

const int _kMinPlayers = 2;
const int _kMaxPlayers = 8;

// 「上一位」還原用的戰局快照：每次真的換手（手動下一位／棋鐘時間到自動換手）
// 前存一份，回上一步就整包蓋回去，兩種模式都通用，不用個別反推增秒/超時邏輯。
class _GameSnapshot {
  final int active;
  final List<double> remaining;
  final List<bool> flagged;
  final int winner;

  _GameSnapshot(this.active, List<double> remaining, List<bool> flagged, this.winner)
    : remaining = List.of(remaining),
      flagged = List.of(flagged);
}

// 玩家配色（依座位順序套用，輪到誰圓環就染成那個顏色）。
const List<Color> _playerColors = [
  Color(0xFFEF6F6C), // 紅
  Color(0xFF5B8DEF), // 藍
  Color(0xFF66BB6A), // 綠
  Color(0xFFFFB300), // 琥珀
  Color(0xFFAB7DF6), // 紫
  Color(0xFF26C6DA), // 青
  Color(0xFFFF8A65), // 橙
  Color(0xFFEC407A), // 粉
];

/// 桌遊／下棋輪流計時器：可設人數（2–8）、玩家命名與順序、每回合秒數或棋鐘
/// 累計（含 Fischer 每手增秒），有平滑動畫圓環、最後幾秒提示音。
///
/// 跟其他三個計時器一樣常駐在計時頁的 IndexedStack；別的計時器「按開始」透過
/// [TimerMutex] 搶鎖時會自動暫停（保留戰局）。切到背景也暫停（前景工具）。
class GameTimer extends StatefulWidget {
  const GameTimer({super.key});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── 設定（持久化）──
  int _count = 2;
  final List<String> _names = List.filled(_kMaxPlayers, '', growable: true);
  final List<int> _playerIds = List.generate(_kMaxPlayers, (i) => i);
  _GameMode _mode = _GameMode.turn;
  int _turnSeconds = 30; // 每回合模式：每輪秒數
  int _bankSeconds = 300; // 棋鐘模式：每人起始總秒數
  int _increment = 0; // 棋鐘模式：每完成一手加幾秒（Fischer）
  bool _warnEnabled = true;
  int _warnSeconds = 5;
  bool _loaded = false;

  // ── 戰局狀態 ──
  bool _started = false; // 已開局（有戰局，可暫停／繼續）
  bool _running = false; // 計時跑動中
  int _active = 0; // 目前輪到的玩家 index
  final List<double> _remaining = List.filled(_kMaxPlayers, 0); // 各玩家剩餘秒數
  final List<bool> _flagged = List.filled(_kMaxPlayers, false); // 棋鐘：時間到出局
  int _winner = -1; // 棋鐘決出勝負時的玩家 index；-1=未決
  final List<_GameSnapshot> _history = []; // 「上一位」還原堆疊

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  // 圓環進度（每幀更新走 ValueListenable，不每幀 setState；數字只在跨秒時 setState）
  final ValueNotifier<double> _ringT = ValueNotifier<double>(1);
  late final AnimationController _nameJiggle;
  bool _nameMoveMode = false;

  // ── 全螢幕面對面模式 ──
  // 開局後推到全螢幕頁：畫面任一處＝換手，方便傳裝置給下一位。全螢幕頁是
  // 另一個 route，不會被這裡的 setState 連動，所以每次戰局狀態變動都把這顆
  // 世代計數器 +1，讓它當監聽觸發器重繪；圓環動畫仍共用 _ringT，逐幀更新
  // 不用經過它。
  final ValueNotifier<int> _matchGen = ValueNotifier<int>(0);
  bool _fullscreenOpen = false;
  bool _bgmWasMuted = false; // 進全螢幕前音樂是否已經是靜音，退出時還原

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TimerMutex.register(ActiveTimer.game, _pauseForOther);
    _ticker = createTicker(_onTick);
    _nameJiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _loadPrefs();
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _nameJiggle.dispose();
    _ringT.dispose();
    _matchGen.dispose();
    WakeGuard.release('game');
    TimerMutex.unregister(ActiveTimer.game);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前景工具：切到背景就暫停（保留戰局），不在背景空轉 ticker。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_running) _pause(feedback: false);
    }
  }

  // ── 載入 / 持久化 ──

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _count = (p.getInt(PrefsKeys.gameTimerPlayerCount) ?? 2).clamp(
        _kMinPlayers,
        _kMaxPlayers,
      );
      final stored = p.getStringList(PrefsKeys.gameTimerNames) ?? const [];
      for (var i = 0; i < _kMaxPlayers; i++) {
        _names[i] = i < stored.length ? stored[i] : '';
      }
      _mode = p.getString(PrefsKeys.gameTimerMode) == 'bank'
          ? _GameMode.bank
          : _GameMode.turn;
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
      _warnSeconds = (p.getInt(PrefsKeys.gameTimerWarnSeconds) ?? 5).clamp(
        3,
        30,
      );
      _initPreview();
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(PrefsKeys.gameTimerPlayerCount, _count);
    await p.setStringList(PrefsKeys.gameTimerNames, _names.toList());
    await p.setString(
      PrefsKeys.gameTimerMode,
      _mode == _GameMode.bank ? 'bank' : 'turn',
    );
    await p.setInt(PrefsKeys.gameTimerTurnSeconds, _turnSeconds);
    await p.setInt(PrefsKeys.gameTimerBankSeconds, _bankSeconds);
    await p.setInt(PrefsKeys.gameTimerIncrement, _increment);
    await p.setBool(PrefsKeys.gameTimerWarnEnabled, _warnEnabled);
    await p.setInt(PrefsKeys.gameTimerWarnSeconds, _warnSeconds);
  }

  // 待機預覽：每人滿格、無人出局、輪到首位。
  void _initPreview() {
    final full = (_mode == _GameMode.turn ? _turnSeconds : _bankSeconds)
        .toDouble();
    for (var i = 0; i < _kMaxPlayers; i++) {
      _remaining[i] = full;
      _flagged[i] = false;
    }
    if (_active >= _count) _active = 0;
    _winner = -1;
    _ringT.value = 1;
  }

  // ── 衍生 ──

  bool get _finished => _started && _winner >= 0;
  int get _fullSeconds => _mode == _GameMode.turn ? _turnSeconds : _bankSeconds;
  Color get _activeColor => _playerColors[_active % _playerColors.length];
  bool get _turnOvertime =>
      _mode == _GameMode.turn && _started && _remaining[_active] < 0;

  String _name(int i) =>
      _names[i].trim().isEmpty ? '玩家${i + 1}' : _names[i].trim();

  double _progressFor(int i) {
    if (_flagged[i]) return 0;
    final r = _remaining[i];
    if (r <= 0) return 0;
    return (r / _fullSeconds).clamp(0.0, 1.0);
  }

  // 秒數 → M:SS（負值＝超時，前面加 +）
  static String _clock(double s) {
    final neg = s < 0;
    final t = s.abs().ceil();
    final core = '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    return neg ? '+$core' : core;
  }

  // 設定面板用的友善時長（5 秒 / 1 分 30 秒）
  static String _human(int s) {
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final ss = s % 60;
    return ss == 0 ? '$m 分' : '$m 分 $ss 秒';
  }

  String _compactSummary() {
    if (_finished) {
      return _winner >= 0 ? '${_name(_winner)} 獲勝' : '平手';
    }
    if (_started) {
      final time = _clock(_remaining[_active]);
      if (_turnOvertime) return '${_name(_active)} 超時 $time';
      return '${_name(_active)} ${_running ? '進行中' : '暫停中'} · $time';
    }
    if (_mode == _GameMode.turn) {
      return '每回合 ${_human(_turnSeconds)} · $_count 人';
    }
    final inc = _increment > 0 ? ' · +$_increment 秒/手' : '';
    return '棋鐘 ${_human(_bankSeconds)}$inc · $_count 人';
  }

  // ── 啟停 / 換手 ──

  // [feedbackContext]：搶鎖提示 SnackBar 要往「目前看得到的那個畫面」丟。全螢幕
  // 頁蓋在這顆 State 的 context 之上時，直接用 context 會把提示丟到被蓋住、
  // 使用者看不到的那層，所以全螢幕頁的繼續鈕會傳自己的 context 進來覆寫。
  void _start({BuildContext? feedbackContext}) {
    if (_running || _finished) return;
    final freshStart = !_started;
    final paused = TimerMutex.acquire(ActiveTimer.game);
    if (paused != null && mounted) {
      ScaffoldMessenger.of(feedbackContext ?? context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(paused.pausedMessage)));
    }
    if (freshStart) {
      // 新開局：各玩家裝滿、清出局、輪到目前選的首位。
      final full = _fullSeconds.toDouble();
      for (var i = 0; i < _kMaxPlayers; i++) {
        _remaining[i] = full;
        _flagged[i] = false;
      }
      if (_active >= _count) _active = 0;
      _winner = -1;
      _started = true;
      _history.clear();
    }
    _running = true;
    _lastElapsed = Duration.zero;
    _ringT.value = _progressFor(_active);
    _ticker?.start();
    WakeGuard.acquire('game'); // 對局進行中：大家盯著螢幕沒人在點，別自動鎖屏
    setState(() {});
    _matchGen.value++;
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    // 開新局才自動進全螢幕；暫停後在一般畫面按繼續不強迫跳轉。
    if (freshStart) _enterFullscreen();
  }

  void _pause({bool feedback = true}) {
    if (!_running) return;
    _running = false;
    _ticker?.stop();
    WakeGuard.release('game');
    TimerMutex.release(ActiveTimer.game);
    if (mounted) setState(() {});
    _matchGen.value++;
    if (feedback) playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
  }

  // 被別的計時器搶鎖：暫停保留戰局，不發音效。
  void _pauseForOther() => _pause(feedback: false);

  void _reset() {
    _ticker?.stop();
    _running = false;
    _started = false;
    _history.clear();
    WakeGuard.release('game');
    TimerMutex.release(ActiveTimer.game);
    setState(_initPreview);
    _matchGen.value++;
    playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
  }

  // 上一位：回到「換手前」那一刻，處理玩家傳裝置時碰錯（誤觸下一位、棋鐘誤判
  // 時間到）的特殊狀況。沒有歷史紀錄時輕震動提示，不報錯不出聲。
  void _prevPlayer() {
    if (_history.isEmpty) {
      playHaptic(HapticLevel.light);
      return;
    }
    final snap = _history.removeLast();
    setState(() {
      _active = snap.active;
      for (var i = 0; i < _kMaxPlayers; i++) {
        _remaining[i] = snap.remaining[i];
        _flagged[i] = snap.flagged[i];
      }
      _winner = snap.winner;
      _ringT.value = _progressFor(_active);
    });
    _matchGen.value++;
    playFeedback(SfxCue.cancel, haptic: HapticLevel.selection);
  }

  // 全螢幕面對面模式：蓋滿整個 app（含底部分頁），畫面任一處＝換手，
  // 方便桌遊/棋類傳裝置給下一位。進場先把音樂靜音（大家在看棋盤，音樂較干擾），
  // 退場照原本狀態還原，不動使用者原本「有沒有開音樂」的設定。
  Future<void> _enterFullscreen() async {
    if (_fullscreenOpen) return;
    // 蓋著全螢幕頁時，下面這顆卡片整個看不到；setState 讓 build() 立刻切成
    // 空殼，別再每次換手/跳秒都白工地重繪整套圓環＋玩家列。
    setState(() => _fullscreenOpen = true);
    _bgmWasMuted = AudioSettingsService.musicMuted.value;
    if (!_bgmWasMuted) unawaited(BgmService.instance.setMuted(true));
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => _GameFullscreenPage(state: this),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted) setState(() => _fullscreenOpen = false);
    if (!_bgmWasMuted) unawaited(BgmService.instance.setMuted(false));
  }

  void _setNameMoveMode(bool value) {
    if (_nameMoveMode == value) return;
    _nameMoveMode = value;
    if (value) {
      _nameJiggle.repeat();
    } else {
      _nameJiggle.stop();
      _nameJiggle.value = 0;
    }
  }

  // 換手（點圓環或「下一位」）：棋鐘先給剛走的玩家加增秒，再輪到下一位未出局者。
  // 換手前存一份快照給「上一位」用；音效改用較醒目的 gameTurn 鈴聲，
  // 提醒下一位可以動了（不是普通操作 tap 音）。
  void _pass() {
    if (!_running) return;
    _pushHistory();
    if (_mode == _GameMode.bank &&
        _increment > 0 &&
        !_flagged[_active] &&
        _remaining[_active] > 0) {
      _remaining[_active] += _increment;
    }
    _advance();
    setState(() {});
    _matchGen.value++;
    playFeedback(SfxCue.gameTurn, haptic: HapticLevel.medium);
  }

  void _pushHistory() {
    _history.add(_GameSnapshot(_active, _remaining, _flagged, _winner));
    if (_history.length > 100) _history.removeAt(0);
  }

  // 輪到下一位「未出局」玩家；每回合模式幫新的一手裝滿秒數。
  void _advance() {
    var n = _active;
    for (var step = 0; step < _count; step++) {
      n = (n + 1) % _count;
      if (!_flagged[n]) break;
    }
    _active = n;
    if (_mode == _GameMode.turn) _remaining[_active] = _turnSeconds.toDouble();
    _ringT.value = _progressFor(_active);
  }

  void _onTimeUp(int i) {
    playFeedback(SfxCue.complete, haptic: HapticLevel.medium);
    if (_mode == _GameMode.bank) {
      _pushHistory();
      _remaining[i] = 0;
      _flagged[i] = true;
      final alive = [
        for (var k = 0; k < _count; k++)
          if (!_flagged[k]) k,
      ];
      if (alive.length <= 1) {
        _winner = alive.isEmpty ? -1 : alive.first;
        _running = false;
        _ticker?.stop();
        WakeGuard.release('game');
        TimerMutex.release(ActiveTimer.game);
        playFeedback(SfxCue.success);
      } else {
        _advance();
      }
    }
    // 每回合模式：時間到不換手，進入「超時」往上數，等使用者按下一位。
    if (mounted) setState(() {});
    _matchGen.value++;
  }

  // 每幀：扣目前玩家的時間，平滑更新圓環；跨整秒才 setState 刷新數字＋提示音。
  void _onTick(Duration elapsed) {
    if (!_running || !_started) return;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    final i = _active;
    final before = _remaining[i];
    final after = before - dt;
    _remaining[i] = after;
    _ringT.value = _progressFor(i);

    if (before > 0 && after <= 0) {
      _onTimeUp(i);
      return;
    }
    // 跨整秒：刷新顯示，並在最後幾秒滴答提示。
    if (after.ceil() != before.ceil()) {
      if (_warnEnabled && after > 0 && after.ceil() <= _warnSeconds) {
        playFeedback(SfxCue.tap, haptic: HapticLevel.light);
      }
      if (mounted) setState(() {});
      _matchGen.value++;
    }
  }

  // ── UI ──

  // 計時區低於這個高度（＝兔咪面板展開、空間被壓縮）就不硬塞，改顯示展開引導。
  // 遊戲計時器一次要呈現圓環＋多位玩家＋控制，需要完整高度才好用。
  static const double _kMinFullHeight = 380;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    // 全螢幕頁蓋在上面時這張卡片整個看不到；回空殼別讓圓環/玩家列每次換手
    // 或跳秒都白工地重繪一份沒人看得到的畫面。
    if (_fullscreenOpen) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxHeight < _kMinFullHeight) {
          return _compactPrompt();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 30), // 留給右上設定鈕
                  _statusChip(),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, rc) {
                          final size = math
                              .min(rc.maxWidth, rc.maxHeight)
                              .clamp(120.0, 250.0)
                              .toDouble();
                          return _ring(size);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _playersStrip(),
                  const SizedBox(height: 12),
                  _controlsRow(),
                  const SizedBox(height: 4),
                ],
              ),
              if (!_started)
                Positioned(top: 0, right: 0, child: _settingsEntry())
              else
                Positioned(top: 0, right: 0, child: _fullscreenEntry()),
            ],
          ),
        );
      },
    );
  }

  // 收合（兔咪面板展開）狀態：空間不夠擺整套遊戲計時，引導使用者展開面板。
  // 用 FittedBox 包住，再矮也不會爆版。
  Widget _compactPrompt() {
    const accent = kGameAccent;
    final sub = _compactSummary();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.casino_rounded,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '遊戲計時器',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppInk.soft,
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: accent,
                shape: const StadiumBorder(),
                elevation: 2,
                shadowColor: accent.withValues(alpha: 0.4),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _expandPanel,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '展開使用',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 收起兔咪面板（openValue→0）讓計時區展開到完整高度。
  void _expandPanel() {
    playHaptic(HapticLevel.light);
    MascotPanelPrefs.requestCollapsed();
  }

  // 狀態膠囊：待機顯示玩法摘要、進行顯示「誰的回合」、結束顯示勝負。
  Widget _statusChip() {
    final color = _finished
        ? _kFinishedGreen
        : _turnOvertime
        ? const Color(0xFFEF5350)
        : _activeColor;
    final String text;
    final IconData icon;
    if (_finished) {
      icon = Icons.emoji_events_rounded;
      text = _winner >= 0 ? '${_name(_winner)} 獲勝' : '平手';
    } else if (_turnOvertime) {
      icon = Icons.warning_amber_rounded;
      text = '${_name(_active)} 超時 ${_clock(_remaining[_active])}';
    } else if (_started) {
      icon = _running ? Icons.play_arrow_rounded : Icons.pause_rounded;
      text = _running ? '${_name(_active)} 的回合' : '${_name(_active)} 暫停中';
    } else {
      icon = _mode == _GameMode.turn
          ? Icons.timelapse_rounded
          : Icons.hourglass_bottom_rounded;
      text = _mode == _GameMode.turn
          ? '每回合 ${_human(_turnSeconds)} · $_count 人'
          : '棋鐘 ${_human(_bankSeconds)}${_increment > 0 ? ' +$_increment 秒/手' : ''} · $_count 人';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: ConstrainedBox(
        key: ValueKey('$text$_running'),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 56,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ringHint() {
    if (_running) return '點一下換手';
    if (_finished) return '點一下再來';
    if (_started) return '點一下繼續';
    return '點一下開始';
  }

  // 圓環／全螢幕頁共用同一套點擊規則：進行中＝換手、結束＝再來一局、
  // 待機或暫停＝開始或繼續。抽成共用方法，避免兩處各寫一份、以後改規則
  // 漏掉其中一邊。[feedbackContext] 給 _start() 決定搶鎖提示要丟去哪個畫面。
  void _dispatchTap(BuildContext feedbackContext) {
    if (_running) {
      _pass();
    } else if (_finished) {
      _reset();
    } else {
      _start(feedbackContext: feedbackContext);
    }
  }

  // 大圓環：平滑進度 + 中央玩家名與剩餘時間。整塊可點：進行中＝換手、
  // 待機＝開始、結束＝再來一局。
  Widget _ring(double size) {
    final overtime = _mode == _GameMode.turn && _remaining[_active] < 0;
    return GestureDetector(
      onTap: () => _dispatchTap(context),
      child: SizedBox(
        width: size,
        height: size,
        child: ValueListenableBuilder<double>(
          valueListenable: _ringT,
          builder: (context, t, _) {
            final ringColor = _finished
                ? _kFinishedGreen
                : overtime
                ? const Color(0xFFEF5350)
                : _activeColor;
            return CustomPaint(
              painter: TimerRingPainter(progress: t, color: ringColor),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _name(_active),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: size * 0.085,
                        fontWeight: FontWeight.w800,
                        color: ringColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _clock(_remaining[_active]),
                      style: AppType.digits(
                        fontSize: size * 0.22,
                        fontWeight: FontWeight.w900,
                        color: overtime
                            ? const Color(0xFFEF5350)
                            : AppInk.strong,
                      ),
                    ),
                    SizedBox(height: size * 0.02),
                    Text(
                      _ringHint(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppInk.faint,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 玩家列：每位一張小卡（顏色點 + 名字 + 剩餘時間），輪到誰打亮、出局劃掉。
  // 待機時點某位＝指定先手。最多兩排自動排版，永不橫向溢出。
  Widget _playersStrip() {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 340 && _count <= 4
            ? math.min(_count, 2)
            : _count <= 4
            ? _count
            : (_count / 2).ceil();
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < _count; i++)
              SizedBox(width: w, child: _playerCard(i)),
          ],
        );
      },
    );
  }

  Widget _playerCard(int i) {
    final color = _playerColors[i % _playerColors.length];
    final active = i == _active && _started && !_finished;
    final winner = _finished && i == _winner;
    // 贏家沿用「輪到誰」的同一套暈影樣式，只是改用慶祝綠，跟狀態膠囊/主鈕一致。
    final highlighted = active || winner;
    final highlightColor = winner ? _kFinishedGreen : color;
    final out = _flagged[i];
    // 玩家代幣：編號圓章（像桌遊玩家標記），出局轉灰。輪到誰整張卡用該色暈影 pop。
    final token = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: out ? AppInk.faint : color,
        boxShadow: out
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: out
          ? const Icon(Icons.close_rounded, size: 14, color: Colors.white)
          : Text(
              '${i + 1}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
    );
    return GestureDetector(
      onTap: _started
          ? null
          : () {
              setState(() => _active = i);
              playHaptic(HapticLevel.selection);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? highlightColor.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? highlightColor.withValues(alpha: 0.50)
                : const Color(0x0F46342B),
            width: highlighted ? 1.5 : 1,
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: highlightColor.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Row(
          children: [
            token,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(i),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: out ? AppInk.faint : AppInk.strong,
                      decoration: out ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    out ? '時間到' : _clock(_remaining[i]),
                    style: AppType.digits(
                      fontWeight: FontWeight.w800,
                      color: highlighted ? highlightColor : AppInk.soft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _sideButton(
          icon: Icons.replay_rounded,
          label: '重設',
          onTap: _reset,
          faded: !_started,
        ),
        const SizedBox(width: 22),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mainButton(),
            const SizedBox(height: _sideLabelGap + _sideLabelHeight),
          ],
        ),
        const SizedBox(width: 22),
        _sideButton(
          icon: Icons.skip_next_rounded,
          label: '下一位',
          onTap: _pass,
          faded: !_running,
        ),
      ],
    );
  }

  Widget _mainButton() {
    final color = _finished ? _kFinishedGreen : _activeColor;
    final icon = _finished
        ? Icons.replay_rounded
        : _running
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    const size = 76.0;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (_finished) {
              _reset();
            } else if (_running) {
              _pause();
            } else {
              _start();
            }
          },
          child: Icon(icon, size: size * 0.46, color: Colors.white),
        ),
      ),
    );
  }

  static const double _sideLabelGap = 5;
  static const double _sideLabelHeight = 15;

  Widget _sideButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool faded,
  }) {
    const size = 52.0;
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 1,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: faded ? null : onTap,
                child: Icon(icon, size: 24, color: AppInk.soft),
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

  // 明顯的設定入口（待機才出現；開局後要先重設）
  Widget _settingsEntry() {
    return Material(
      color: kGameAccent,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: kGameAccent.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _openSettings,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '遊戲設定',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 回全螢幕入口（開局後出現，跟設定鈕互斥同一個位置）：離開全螢幕後想再傳
  // 裝置面對面玩，不用重設整局就能再進去。
  Widget _fullscreenEntry() {
    final color = _finished ? _kFinishedGreen : _activeColor;
    return Material(
      color: color,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _enterFullscreen,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fullscreen_rounded, size: 18, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '全螢幕',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 設定底板 ──
  void _openSettings() {
    playFeedback(SfxCue.tap);
    // 只在「正在改名的那一列」用一個 controller（點一下才變輸入框），
    // 其餘列是純文字＋長按拖曳，避免輸入框跟拖曳手勢打架。關閉時釋放。
    final editCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _settingsSheet(ctx, editCtrl),
    ).whenComplete(() {
      editCtrl.dispose();
      _setNameMoveMode(false);
    });
  }

  Widget _settingsSheet(BuildContext sheetCtx, TextEditingController editCtrl) {
    const color = kGameAccent;
    // 目前正在改名的列（-1＝沒有）。宣告在 StatefulBuilder 外 → 跨 setSheet 保留。
    var editingIndex = -1;
    return StatefulBuilder(
      builder: (ctx, setSheet) {
        void apply(VoidCallback change) {
          setState(() {
            change();
            _initPreview();
          });
          setSheet(() {});
          _persist();
        }

        void beginEdit(int i) {
          editingIndex = i;
          editCtrl.text = _names[i];
          editCtrl.selection = TextSelection.collapsed(
            offset: editCtrl.text.length,
          );
          setSheet(() {});
        }

        void endEdit() {
          if (editingIndex < 0) return;
          editingIndex = -1;
          FocusScope.of(ctx).unfocus();
          setSheet(() {});
        }

        void startNameMove() {
          endEdit();
          if (_nameMoveMode) return;
          setState(() => _setNameMoveMode(true));
          setSheet(() {});
          playHaptic(HapticLevel.selection);
        }

        void finishNameMove() {
          if (!_nameMoveMode) return;
          setState(() => _setNameMoveMode(false));
          setSheet(() {});
          playHaptic(HapticLevel.selection);
        }

        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
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
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
                          _sheetHeader(ctx, color),
                          const SizedBox(height: 16),
                          _sectionTitle(Icons.groups_rounded, color, '人數'),
                          const SizedBox(height: 8),
                          _stepperCard(
                            label: '玩家人數',
                            sub: '一起輪流計時的人數',
                            icon: Icons.groups_rounded,
                            color: color,
                            value: '$_count 人',
                            onMinus: _count > _kMinPlayers
                                ? () => apply(() => _count--)
                                : null,
                            onPlus: _count < _kMaxPlayers
                                ? () => apply(() => _count++)
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(
                            Icons.badge_rounded,
                            color,
                            '玩家與順序（拖曳排序）',
                          ),
                          const SizedBox(height: 8),
                          _nameReorderList(
                            color: color,
                            editingIndex: editingIndex,
                            editCtrl: editCtrl,
                            apply: apply,
                            onBeginEdit: beginEdit,
                            onEndEdit: endEdit,
                            onStartMove: startNameMove,
                            onFinishMove: finishNameMove,
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(Icons.timer_rounded, color, '計時方式'),
                          const SizedBox(height: 8),
                          _modeChoices(apply, color),
                          const SizedBox(height: 12),
                          if (_mode == _GameMode.turn)
                            _stepperCard(
                              label: '每回合秒數',
                              sub: '每次輪到都從這個秒數開始',
                              icon: Icons.timelapse_rounded,
                              color: color,
                              value: _human(_turnSeconds),
                              onMinus: _turnSeconds > 5
                                  ? () => apply(
                                      () => _turnSeconds = (_turnSeconds - 5)
                                          .clamp(5, 600),
                                    )
                                  : null,
                              onPlus: _turnSeconds < 600
                                  ? () => apply(
                                      () => _turnSeconds = (_turnSeconds + 5)
                                          .clamp(5, 600),
                                    )
                                  : null,
                            )
                          else ...[
                            _stepperCard(
                              label: '起始總時間',
                              sub: '每人一桶總時間，輪到才扣',
                              icon: Icons.hourglass_bottom_rounded,
                              color: color,
                              value: _human(_bankSeconds),
                              onMinus: _bankSeconds > 30
                                  ? () => apply(
                                      () => _bankSeconds = (_bankSeconds - 30)
                                          .clamp(30, 3600),
                                    )
                                  : null,
                              onPlus: _bankSeconds < 3600
                                  ? () => apply(
                                      () => _bankSeconds = (_bankSeconds + 30)
                                          .clamp(30, 3600),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            _stepperCard(
                              label: '每手增秒',
                              sub: 'Fischer：走完一手加回幾秒（0=關）',
                              icon: Icons.add_alarm_rounded,
                              color: color,
                              value: _increment == 0 ? '關' : '$_increment 秒',
                              onMinus: _increment > 0
                                  ? () => apply(() => _increment--)
                                  : null,
                              onPlus: _increment < 60
                                  ? () => apply(() => _increment++)
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 16),
                          _sectionTitle(
                            Icons.notifications_active_rounded,
                            color,
                            '倒數提示',
                          ),
                          const SizedBox(height: 8),
                          _switchTile(
                            icon: Icons.volume_up_rounded,
                            color: color,
                            label: '最後幾秒提示音',
                            sub: '接近時間用完時每秒提醒',
                            value: _warnEnabled,
                            onChanged: (v) => apply(() => _warnEnabled = v),
                          ),
                          const SizedBox(height: 8),
                          _stepperCard(
                            label: '提示秒數',
                            sub: '剩幾秒開始提示',
                            icon: Icons.alarm_rounded,
                            color: color,
                            value: '$_warnSeconds 秒',
                            enabled: _warnEnabled,
                            onMinus: _warnEnabled && _warnSeconds > 3
                                ? () => apply(() => _warnSeconds--)
                                : null,
                            onPlus: _warnEnabled && _warnSeconds < 30
                                ? () => apply(() => _warnSeconds++)
                                : null,
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
                        backgroundColor: color,
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
  }

  Widget _sheetHeader(BuildContext ctx, Color color) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.casino_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '遊戲計時設定',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '桌遊與棋類的輪流計時',
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
          icon: const Icon(Icons.close_rounded, color: AppInk.iconFaint),
          onPressed: () => Navigator.pop(ctx),
        ),
      ],
    );
  }

  // 命名 + 拖曳排序：照音樂盒播放清單使用 ReorderableListView。
  // 原本手刻 LongPressDraggable + DragTarget 容易出現 drop index 算錯、排序跳動；
  // 這裡讓 Flutter 的 reorderable 清單負責索引，並保留「移動模式」與完成 bar。
  Widget _nameReorderList({
    required Color color,
    required int editingIndex,
    required TextEditingController editCtrl,
    required void Function(VoidCallback) apply,
    required void Function(int) onBeginEdit,
    required VoidCallback onEndEdit,
    required VoidCallback onStartMove,
    required VoidCallback onFinishMove,
  }) {
    void reorder(int oldIndex, int newIndex) {
      if (oldIndex < newIndex) newIndex--;
      if (oldIndex == newIndex) return;
      apply(() {
        final activeId = _playerIds[_active];
        final name = _names.removeAt(oldIndex);
        final id = _playerIds.removeAt(oldIndex);
        _names.insert(newIndex, name);
        _playerIds.insert(newIndex, id);
        final nextActive = _playerIds.indexOf(activeId);
        _active = nextActive >= 0 && nextActive < _count ? nextActive : 0;
      });
      playHaptic(HapticLevel.selection);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: _count,
          onReorder: reorder,
          onReorderStart: (_) {
            onEndEdit();
            if (!_nameMoveMode) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => onStartMove(),
              );
            }
          },
          proxyDecorator: (child, index, animation) =>
              Material(color: Colors.transparent, child: child),
          itemBuilder: (_, i) {
            final playerId = _playerIds[i];
            final key = ValueKey('game_player_$playerId');
            if (editingIndex == i) {
              return KeyedSubtree(
                key: key,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _playerEditField(i, color, editCtrl, apply, onEndEdit),
                ),
              );
            }
            final row = Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GameNameJiggle(
                animation: _nameJiggle,
                enabled: _nameMoveMode,
                seed: playerId,
                child: _playerRow(
                  i,
                  color,
                  moveMode: _nameMoveMode,
                  onTap: _nameMoveMode ? null : () => onBeginEdit(i),
                  onMove: onStartMove,
                ),
              ),
            );
            return _GameNameDragListener(
              key: key,
              index: i,
              immediate: _nameMoveMode,
              child: row,
            );
          },
        ),
        if (_nameMoveMode) ...[
          const SizedBox(height: 2),
          _GameMoveDoneButton(onTap: onFinishMove),
        ],
      ],
    );
  }

  // 一般玩家列：色點 + 名字 + 改名/移動提示圖示。
  Widget _playerRow(
    int index,
    Color color, {
    required bool moveMode,
    VoidCallback? onTap,
    required VoidCallback onMove,
  }) {
    final dotColor = _playerColors[index % _playerColors.length];
    return Material(
      color: moveMode ? color.withValues(alpha: 0.09) : const Color(0xFFFAF7F2),
      borderRadius: BorderRadius.circular(12),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: moveMode
                  ? color.withValues(alpha: 0.42)
                  : const Color(0xFFE8DDD4),
              width: moveMode ? 1.3 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (moveMode) ...[
                  const Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: AppInk.iconFaint,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _name(index),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppInk.strong,
                    ),
                  ),
                ),
                if (!moveMode) ...[
                  IconButton(
                    tooltip: '改名',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: AppInk.iconFaint,
                    ),
                    onPressed: onTap,
                  ),
                  IconButton(
                    tooltip: '移動',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(
                      Icons.open_with_rounded,
                      size: 18,
                      color: AppInk.iconFaint,
                    ),
                    onPressed: onMove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 改名中的列：輸入框 + 完成鈕。
  Widget _playerEditField(
    int index,
    Color color,
    TextEditingController editCtrl,
    void Function(VoidCallback) apply,
    VoidCallback onEndEdit,
  ) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _playerColors[index % _playerColors.length],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: editCtrl,
            autofocus: true,
            maxLength: 8,
            textInputAction: TextInputAction.done,
            onChanged: (v) => apply(() => _names[index] = v),
            onSubmitted: (_) => onEndEdit(),
            onTapOutside: (_) => onEndEdit(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppInk.strong,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: '玩家${index + 1}',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: AppInk.faint,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: color.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.check_rounded, color: color),
          onPressed: onEndEdit,
        ),
      ],
    );
  }

  Widget _modeChoices(void Function(VoidCallback) apply, Color color) {
    Widget tile(_GameMode m, IconData icon, String title, String sub) {
      final sel = _mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => apply(() => _mode = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel
                  ? color.withValues(alpha: 0.12)
                  : const Color(0xFFFAF7F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel
                    ? color.withValues(alpha: 0.38)
                    : const Color(0xFFE8DDD4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: sel ? color : AppInk.soft),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: sel ? color : AppInk.strong,
                      ),
                    ),
                    if (sel) ...[
                      const Spacer(),
                      Icon(Icons.check_rounded, size: 16, color: color),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // IntrinsicHeight：在垂直捲動容器裡，Row 的高度本來無界，stretch 會撐爆；
    // 先用 IntrinsicHeight 把 Row 高度收斂成兩塊較高者，stretch 才能等高。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(_GameMode.turn, Icons.timelapse_rounded, '每回合', '每次輪到都重置，適合桌遊'),
          const SizedBox(width: 10),
          tile(
            _GameMode.bank,
            Icons.hourglass_bottom_rounded,
            '棋鐘',
            '每人一桶總時間，適合下棋',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, Color color, String title) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
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

  Widget _stepperCard({
    required String label,
    required String sub,
    required IconData icon,
    required Color color,
    required String value,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
    bool enabled = true,
  }) {
    Widget btn(IconData ic, VoidCallback? onTap) {
      final on = onTap != null;
      return HoldRepeatButton(
        onTrigger: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: on ? 0.14 : 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(ic, size: 18, color: on ? color : AppInk.faint),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8DDD4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppInk.strong,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppInk.soft,
                    ),
                  ),
                ],
              ),
            ),
            btn(Icons.remove_rounded, onMinus),
            SizedBox(
              width: 76,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.digits(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                ),
              ),
            ),
            btn(Icons.add_rounded, onPlus),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8DDD4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: color,
            onChanged: (v) {
              playHaptic(HapticLevel.selection);
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _GameMoveDoneButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GameMoveDoneButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade500, Colors.green.shade600],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '完成排序',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameNameJiggle extends StatelessWidget {
  final Animation<double> animation;
  final bool enabled;
  final int seed;
  final Widget child;

  const _GameNameJiggle({
    required this.animation,
    required this.enabled,
    required this.seed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final direction = seed.isEven ? 1.0 : -1.0;
    final phaseOffset = (seed.abs() % 100) / 100 * math.pi * 2;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        if (!enabled) return child!;
        final phase = animation.value * math.pi * 2 + phaseOffset;
        final sway = math.sin(phase);
        final bounce = math.sin(phase + math.pi / 2);
        final squash = math.sin(phase + math.pi);
        return Transform.translate(
          offset: Offset(direction * sway * 0.5, bounce * 0.9),
          child: Transform.rotate(
            angle: direction * sway * 0.014,
            child: Transform.scale(
              scaleX: 1 + squash * 0.005,
              scaleY: 1 - squash * 0.0035,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

const Duration _kGameDragHoldDelay = Duration(seconds: 1);

class _GameNameDragListener extends ReorderableDragStartListener {
  final bool immediate;

  const _GameNameDragListener({
    super.key,
    required super.child,
    required super.index,
    required this.immediate,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return immediate
        ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
        : DelayedMultiDragGestureRecognizer(
            delay: _kGameDragHoldDelay,
            debugOwner: this,
          );
  }
}

/// 全螢幕面對面對局頁：桌遊/棋類傳裝置給下一位時，畫面任一處都能換手。
/// 直接讀寫 [_GameTimerState] 的私有成員（同一個檔案，Dart privacy 是 library
/// 層級不是 class 層級，這裡合法也刻意這樣做）——換手/暫停/上一位都是原本
/// 那顆計時器在跑，全螢幕頁只是換一種「大、好戳、傳著玩」的殼。
class _GameFullscreenPage extends StatefulWidget {
  final _GameTimerState state;

  const _GameFullscreenPage({required this.state});

  @override
  State<_GameFullscreenPage> createState() => _GameFullscreenPageState();
}

class _GameFullscreenPageState extends State<_GameFullscreenPage> {
  _GameTimerState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s._matchGen.addListener(_onMatchChanged);
  }

  @override
  void dispose() {
    s._matchGen.removeListener(_onMatchChanged);
    super.dispose();
  }

  void _onMatchChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final color = s._finished ? _kFinishedGreen : s._activeColor;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 圓環本身的 GestureDetector 被下面的 IgnorePointer 蓋掉，改由
              // 這層整頁接手，跟 _ring() 共用同一套 _dispatchTap 規則，畫面
              // 任一處點下去效果都一樣；傳 context 讓搶鎖提示丟在這一頁上。
              onTap: () => s._dispatchTap(context),
              child: Column(
                children: [
                  const SizedBox(height: 56), // 留給左上退出鈕
                  s._statusChip(),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final size = (math.min(c.maxWidth, c.maxHeight) * 0.82)
                              .clamp(200.0, 340.0)
                              .toDouble();
                          return IgnorePointer(child: s._ring(size));
                        },
                      ),
                    ),
                  ),
                  s._playersStrip(),
                  const SizedBox(height: 96), // 留給底部退出/上一位/暫停列
                ],
              ),
            ),
            Positioned(
              top: 4,
              left: 12,
              child: _FsRoundButton(
                icon: Icons.close_rounded,
                color: AppInk.soft,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FsRoundButton(
                    icon: Icons.skip_previous_rounded,
                    color: color,
                    onTap: s._history.isEmpty ? null : s._prevPlayer,
                  ),
                  const SizedBox(width: 28),
                  _FsRoundButton(
                    icon: s._running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: color,
                    big: true,
                    onTap: s._finished
                        ? null
                        : s._running
                        ? s._pause
                        : () => s._start(feedbackContext: context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 全螢幕頁專用的圓形控制鈕：白底浮凸，跟一般畫面的 _sideButton/主鈕同一套
// 視覺語言，只是尺寸配合全螢幕操作距離放大一階。
class _FsRoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool big;

  const _FsRoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final size = big ? 76.0 : 56.0;
    return Opacity(
      opacity: on ? 1 : 0.35,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: big ? 3 : 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: big ? 34 : 24, color: on ? color : AppInk.faint),
          ),
        ),
      ),
    );
  }
}
