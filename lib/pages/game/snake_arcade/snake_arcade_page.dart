// 三指彩蛋：菜園小蛇（大地圖貪食蛇）。
//
// 與二指骰子不同，這是「全螢幕」root overlay：遊戲盤放在視線較容易追蹤的
// 上方，兔咪縮成下方陪玩角落；全畫面滑動都能操作，不必用手遮住棋盤。
// 像素窗簾沿用同一套復古進出場儀式；關閉 overlay 即完整回到觸發前狀態。
//
// 版型：手機直式＝上 HUD＋正方形視窗＋下方兔咪操作台；橫式／平板橫向
// 改為棋盤在左、兔咪操作台在右。種子只由專用按鈕發射。
//
// 規則全部在 SnakeArcadeEngine；這個檔案只做輸入、鏡頭、演出與資料存取。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/mascot.dart';
import '../../../utils/mini_game_session.dart';
import '../../../utils/prefs_keys.dart';
import '../../../utils/sfx_service.dart';
import '../../../utils/usage_stats.dart';
import '../../../utils/wardrobe_catalog.dart';
import '../../../utils/wardrobe_store.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/mascot_scene.dart';
import '../../timer/game/table_timer_theme.dart'
    show kGameAccent, kGameAccentDark;
import 'snake_arcade_engine.dart';
import 'snake_arcade_painters.dart';
import 'snake_arcade_records.dart';

/// 同一個引擎節拍可能同時產生多個事件（例如最後一隻鼴鼠＝命中＋狩獵完成，
/// 撞牆但還有命＝死亡＋復活）。每批只選一個最高語意的音效，避免互相疊放。
@visibleForTesting
({SfxCue cue, HapticLevel haptic})? snakeArcadeFeedbackForEvents(
  Iterable<ArcadeEvent> events,
) {
  final set = events.toSet();
  if (set.contains(ArcadeEvent.revived)) {
    return (cue: SfxCue.snakeRevive, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.died)) {
    return (cue: SfxCue.snakeGameOver, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.huntFull)) {
    return (cue: SfxCue.snakeBonus, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.magnetFruitCollected)) {
    return (cue: SfxCue.snakeBonus, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.abilityOffered)) {
    return (cue: SfxCue.snakePower, haptic: HapticLevel.light);
  }
  if (set.contains(ArcadeEvent.huntStarted)) {
    return (cue: SfxCue.snakeHunt, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.laserStarted)) {
    return (cue: SfxCue.snakePower, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.laserShot)) {
    return (cue: SfxCue.snakeSeed, haptic: HapticLevel.light);
  }
  if (set.contains(ArcadeEvent.ateFiveFold)) {
    return (cue: SfxCue.snakePower, haptic: HapticLevel.medium);
  }
  if (set.contains(ArcadeEvent.ateGold)) {
    return (cue: SfxCue.snakeBonus, haptic: HapticLevel.light);
  }
  if (set.contains(ArcadeEvent.moleKilled)) {
    return (cue: SfxCue.snakeHit, haptic: HapticLevel.light);
  }
  if (set.contains(ArcadeEvent.shot)) {
    return (cue: SfxCue.snakeSeed, haptic: HapticLevel.selection);
  }
  if (set.contains(ArcadeEvent.ateCarrot)) {
    return (cue: SfxCue.snakeCollect, haptic: HapticLevel.selection);
  }
  if (set.contains(ArcadeEvent.started)) {
    return (cue: SfxCue.snakeStart, haptic: HapticLevel.selection);
  }
  if (set.contains(ArcadeEvent.huntWarnTick)) {
    return (cue: SfxCue.snakeWarning, haptic: HapticLevel.light);
  }
  return null;
}

const _cream = Color(0xFFF6F1E7);

/// 全螢幕彩蛋演出：像素窗簾蓋滿 → 換景成菜園 → 窗簾退去；
/// 關閉時反向播放，跑完才回呼 [onClosed] 讓 shell 移除 overlay entry。
class SnakeArcadeEgg extends StatefulWidget {
  const SnakeArcadeEgg({
    super.key,
    required this.onClosed,
    this.onCovered,
    this.engineBuilder,
    this.recordsClock,
  });

  final VoidCallback onClosed;

  /// 開場窗簾第一次完全蓋住畫面時觸發。骰子彩蛋用這個時機卸載自己，
  /// 玩家只會看到連續換景，不會閃回原頁面。
  final VoidCallback? onCovered;

  /// 測試注入固定種子引擎用；正式彩蛋用時間種子。
  final SnakeArcadeEngine Function()? engineBuilder;

  /// 測試凍結排行榜時間用。
  final DateTime Function()? recordsClock;

  @override
  State<SnakeArcadeEgg> createState() => _SnakeArcadeEggState();
}

class _SnakeArcadeEggState extends State<SnakeArcadeEgg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _curtain;
  bool _panelVisible = false;
  bool _closing = false;
  int _curtainStep = 0;

  @override
  void initState() {
    super.initState();
    _curtain = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..addListener(_onCurtainTick);
    _openSequence();
  }

  @override
  void dispose() {
    _curtain.dispose();
    super.dispose();
  }

  void _onCurtainTick() {
    final step = (_curtain.value * 5).floor();
    if (step == _curtainStep) return;
    _curtainStep = step;
    playHaptic(HapticLevel.selection);
  }

  Future<void> _openSequence() async {
    playHaptic(HapticLevel.medium);
    try {
      await _curtain.forward().orCancel;
      if (!mounted) return;
      widget.onCovered?.call();
      setState(() => _panelVisible = true);
      playFeedback(SfxCue.snakePower, haptic: HapticLevel.light);
      await _curtain.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    playHaptic(HapticLevel.light);
    try {
      await _curtain.forward().orCancel;
      if (!mounted) return;
      setState(() => _panelVisible = false);
      unawaited(SfxService.instance.play(SfxCue.cancel));
      await _curtain.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 開場窗簾蓋滿前先擋住底下頁面的觸控。
          Listener(
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          if (_panelVisible)
            SnakeArcadePage(
              onClose: _close,
              engineBuilder: widget.engineBuilder,
              recordsClock: widget.recordsClock,
            ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _curtain,
              builder: (_, _) => CustomPaint(
                painter: ArcadePixelCurtainPainter(_curtain.value),
                isComplex: true,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SnakeArcadePage extends StatefulWidget {
  const SnakeArcadePage({
    super.key,
    required this.onClose,
    this.engineBuilder,
    this.recordsClock,
  });

  final VoidCallback onClose;
  final SnakeArcadeEngine Function()? engineBuilder;
  final DateTime Function()? recordsClock;

  @override
  State<SnakeArcadePage> createState() => _SnakeArcadePageState();
}

class _SnakeArcadePageState extends State<SnakeArcadePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late SnakeArcadeEngine _engine;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// 每幀 +1，只驅動棋盤／小地圖重畫，HUD 靠事件 setState。
  final ValueNotifier<int> _frame = ValueNotifier(0);

  double _cameraX = 0;
  double _cameraY = 0;
  double _pulse = 0;

  SharedPreferences? _prefs;
  SnakeArcadeRecords _records = SnakeArcadeRecords.empty();
  String _defaultName = '玩家';
  bool _resultRegistered = false;
  bool _resultQualifies = false;
  bool _showBoards = false;
  SnakeArcadeScore? _justRegistered;
  bool _finishRecorded = false;
  final TextEditingController _nameController = TextEditingController();

  // 手勢：全螢幕單指滑動轉向。射擊只走下方種子按鈕，避免點棋盤
  // 看物件或調整握姿時誤發。
  static const _swipeThreshold = 22.0;
  int? _activePointer;
  Offset? _origin;
  bool _swiped = false;

  DateTime get _now => widget.recordsClock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _engine = widget.engineBuilder?.call() ?? SnakeArcadeEngine();
    _snapCamera();
    WidgetsBinding.instance.addObserver(this);
    MiniGameSession.register(owner: this, onPause: _pauseGame);
    _ticker = createTicker(_onTick)..start();
    unawaited(_loadRecords());
    unawaited(UsageStats.bump(UsageEvents.snakeArcadeOpen));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MiniGameSession.unregister(this);
    _ticker.dispose();
    _frame.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pauseGame();
    }
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _records = SnakeArcadeRecords.load(prefs);
      final nickname = prefs.getString(PrefsKeys.userNickname)?.trim();
      _defaultName = _records.lastPlayerName.isNotEmpty
          ? _records.lastPlayerName
          : (nickname == null || nickname.isEmpty ? '玩家' : nickname);
    });
  }

  // ── 每幀：推進引擎、處理事件、鏡頭平滑跟隨 ─────────────

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTick).inMilliseconds;
    _lastTick = elapsed;
    if (dtMs <= 0) return;
    // 背景久了回前景 dt 會巨大；夾住避免一口氣快轉（引擎在暫停也不會跑，
    // 這裡只是保險）。
    _engine.advance(math.min(dtMs, 200));
    _handleEvents();
    _updateCamera(dtMs);
    _pulse = (elapsed.inMilliseconds % 900) / 900;
    _frame.value++;
  }

  void _updateCamera(int dtMs) {
    final targetX = clampCamera(
      _engine.head.x + 0.5 - kArcadeViewportCells / 2,
    );
    final targetY = clampCamera(
      _engine.head.y + 0.5 - kArcadeViewportCells / 2,
    );
    final t = math.min(1.0, dtMs / 1000 * 8);
    _cameraX += (targetX - _cameraX) * t;
    _cameraY += (targetY - _cameraY) * t;
  }

  void _snapCamera() {
    _cameraX = clampCamera(_engine.head.x + 0.5 - kArcadeViewportCells / 2);
    _cameraY = clampCamera(_engine.head.y + 0.5 - kArcadeViewportCells / 2);
  }

  void _handleEvents() {
    final events = _engine.takeEvents();
    if (events.isEmpty) return;
    final feedback = snakeArcadeFeedbackForEvents(events);
    if (feedback != null) {
      playFeedback(feedback.cue, haptic: feedback.haptic);
    }
    var needsSetState = false;
    for (final event in events) {
      switch (event) {
        case ArcadeEvent.started:
          needsSetState = true;
        case ArcadeEvent.ateCarrot:
          needsSetState = true;
        case ArcadeEvent.ateGold:
          needsSetState = true;
        case ArcadeEvent.ateFiveFold:
          needsSetState = true;
        case ArcadeEvent.carrotPulled:
        case ArcadeEvent.magnetFruitSpawned:
        case ArcadeEvent.magnetFruitCollected:
          needsSetState = true;
        case ArcadeEvent.abilityOffered:
          needsSetState = true;
        case ArcadeEvent.shot:
        case ArcadeEvent.laserStarted:
        case ArcadeEvent.laserShot:
        case ArcadeEvent.laserEnded:
        case ArcadeEvent.moleKilled:
          needsSetState = true;
        case ArcadeEvent.huntStarted:
          needsSetState = true;
        case ArcadeEvent.huntWarnTick:
        case ArcadeEvent.huntFull:
          needsSetState = true;
        case ArcadeEvent.huntEnded:
          if (feedback == null) playHaptic(HapticLevel.light);
          needsSetState = true;
        case ArcadeEvent.died:
          needsSetState = true;
        case ArcadeEvent.revived:
          _snapCamera();
          needsSetState = true;
        case ArcadeEvent.gameOver:
          _onGameOver();
          needsSetState = true;
      }
    }
    if (needsSetState && mounted) setState(() {});
  }

  void _onGameOver() {
    if (_finishRecorded) return;
    _finishRecorded = true;
    unawaited(UsageStats.bump(UsageEvents.snakeArcadeFinish));
    _resultQualifies = _records.qualifies(_engine.score, _now);
    _resultRegistered = false;
    _showBoards = !_resultQualifies;
    _justRegistered = null;
    _nameController.text = _defaultName;
  }

  // ── 輸入 ───────────────────────────────────────────────

  void _pointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _origin = event.position;
    _swiped = false;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _swiped) return;
    final origin = _origin;
    if (origin == null) return;
    final delta = event.position - origin;
    if (math.max(delta.dx.abs(), delta.dy.abs()) < _swipeThreshold) return;
    _swiped = true;
    final direction = delta.dx.abs() > delta.dy.abs()
        ? (delta.dx > 0 ? ArcadeDirection.right : ArcadeDirection.left)
        : (delta.dy > 0 ? ArcadeDirection.down : ArcadeDirection.up);
    final wasWaiting = _engine.phase == ArcadePhase.waiting;
    _engine.enqueueDirection(direction);
    if (wasWaiting && _engine.phase == ArcadePhase.running && mounted) {
      setState(() {});
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _origin = null;
    _swiped = false;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _origin = null;
    _swiped = false;
  }

  // ── 遊戲流程 ───────────────────────────────────────────

  void _pauseGame() {
    if (!_engine.pause()) return;
    if (mounted) setState(() {});
  }

  void _leavePause() {
    _engine.leavePause();
    playHaptic(HapticLevel.selection);
    setState(() {});
  }

  void _chooseAbility(int index) {
    _engine.chooseAbility(index);
    playFeedback(SfxCue.snakeCollect, haptic: HapticLevel.light);
    setState(() {});
  }

  void _shoot() {
    if (!_engine.shoot()) return;
    setState(() {});
  }

  bool get _hasActiveProgress {
    if (_engine.phase == ArcadePhase.gameOver) return false;
    if (_engine.phase == ArcadePhase.waiting &&
        _engine.waitReason == ArcadeWaitReason.newGame &&
        _engine.physicalCount == 0 &&
        _engine.score == 0) {
      return false;
    }
    return true;
  }

  Future<void> _requestExit() async {
    if (!_hasActiveProgress) {
      widget.onClose();
      return;
    }
    final pausedHere = _engine.pause();
    if (pausedHere && mounted) setState(() {});
    final leave = await showAppConfirmDialog(
      context,
      title: '離開菜園小蛇？',
      message: '這一局的進度不會保留。',
      confirmLabel: '離開遊戲',
      danger: true,
    );
    if (!mounted) return;
    if (leave) {
      widget.onClose();
      return;
    }
    if (pausedHere) {
      _engine.leavePause();
      setState(() {});
    }
  }

  Future<void> _requestRestart() async {
    if (!_hasActiveProgress) {
      _restart();
      return;
    }
    final restart = await showAppConfirmDialog(
      context,
      title: '重新開始？',
      message: '目前這一局的分數與能力會清除。',
      confirmLabel: '重新開始',
      danger: true,
    );
    if (!mounted || !restart) return;
    _restart();
  }

  void _restart() {
    _engine = widget.engineBuilder?.call() ?? SnakeArcadeEngine();
    _finishRecorded = false;
    _resultRegistered = false;
    _showBoards = false;
    _justRegistered = null;
    _snapCamera();
    playFeedback(SfxCue.snakeStart, haptic: HapticLevel.selection);
    setState(() {});
  }

  Future<void> _registerScore() async {
    if (_resultRegistered) return;
    _resultRegistered = true;
    final entry = _records.addEntry(
      name: _nameController.text,
      score: _engine.score,
      carrots: _engine.physicalCount,
      maxLength: _engine.maxLength,
      now: _now,
    );
    _justRegistered = entry;
    _defaultName = _records.lastPlayerName;
    playFeedback(SfxCue.complete, haptic: HapticLevel.medium);
    setState(() => _showBoards = true);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await _records.save(prefs);
  }

  void _skipRegister() {
    _resultRegistered = true;
    setState(() => _showBoards = true);
  }

  // ── 版面 ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phase = _engine.phase;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Material(
        key: const ValueKey('snake-arcade-page'),
        color: _cream,
        child: Listener(
          key: const ValueKey('snake-arcade-input'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (_, box) => _buildGameLayout(box),
                ),
              ),
              if (phase == ArcadePhase.choosingAbility)
                _AbilityOverlay(
                  abilities: _engine.offeredAbilities,
                  onPick: _chooseAbility,
                ),
              if (phase == ArcadePhase.paused)
                _PauseOverlay(
                  onResume: _leavePause,
                  onRestart: () => unawaited(_requestRestart()),
                  onExit: () => unawaited(_requestExit()),
                ),
              if (phase == ArcadePhase.gameOver) _buildResultOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameLayout(BoxConstraints box) {
    final sideBySide = box.maxWidth > box.maxHeight * 1.25;
    if (sideBySide) {
      final dockWidth = (box.maxWidth * 0.34).clamp(220.0, 310.0);
      final boardAreaWidth = box.maxWidth - dockWidth;
      final side = math.max(
        120.0,
        math.min(boardAreaWidth - 18, box.maxHeight - 58),
      );
      return Row(
        children: [
          SizedBox(
            width: boardAreaWidth,
            child: Column(
              children: [
                _buildHud(),
                Expanded(child: Center(child: _buildBoard(side))),
              ],
            ),
          ),
          SizedBox(
            width: dockWidth,
            child: _buildSideDock(compact: box.maxHeight < 440),
          ),
        ],
      );
    }

    final compact = box.maxWidth < 360 || box.maxHeight < 650;
    final dockFloor = compact ? 132.0 : 158.0;
    final side = math.max(
      120.0,
      math.min(box.maxWidth - 20, box.maxHeight - 56 - dockFloor),
    );
    return Column(
      children: [
        _buildHud(),
        _buildBoard(side),
        Expanded(child: _buildBottomDock(compact: compact)),
      ],
    );
  }

  Widget _buildHud() {
    final multiplier = _engine.scoreMultiplier;
    final multiplierLabel = multiplier == multiplier.roundToDouble()
        ? '×${multiplier.toInt()}'
        : '×$multiplier';
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            _HudChip(
              label: '分數',
              value: '${_engine.score}',
              key: const ValueKey('arcade-score-chip'),
            ),
            const SizedBox(width: 8),
            _HudChip(
              label: '速度${_engine.speedLevel}',
              value: multiplierLabel,
              key: const ValueKey('arcade-speed-chip'),
            ),
            const Spacer(),
            if (_engine.fiveFoldArmed)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: ArcadePalette.gold,
                  size: 20,
                ),
              ),
            if (_engine.passPoints > 0)
              _TinyBadge(
                label: '穿${_engine.passPoints}',
                color: kGameAccentDark,
              ),
            if (_engine.lives > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Row(
                  children: List.generate(
                    _engine.lives,
                    (_) => const Icon(
                      Icons.favorite_rounded,
                      color: ArcadePalette.carrot,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard(double side) {
    return SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ArcadePalette.fence, width: 2),
          boxShadow: AppShadows.flat,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (_, _, _) => CustomPaint(
                  key: const ValueKey('snake-arcade-board'),
                  painter: SnakeArcadeBoardPainter(
                    engine: _engine,
                    cameraX: _cameraX,
                    cameraY: _cameraY,
                    pulse: _pulse,
                  ),
                  isComplex: true,
                ),
              ),
              if (_engine.phase == ArcadePhase.waiting)
                _StartHint(reason: _engine.waitReason),
              if (_engine.huntActive) const _HuntBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDock({required bool compact}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Container(
        key: const ValueKey('arcade-mascot-dock'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: 8,
        ),
        decoration: _dockDecoration(),
        child: LayoutBuilder(
          builder: (_, box) {
            final showMap = box.maxWidth >= 560;
            return Row(
              children: [
                if (showMap) ...[
                  _buildMinimap(compact ? 66 : 78),
                  const SizedBox(width: 10),
                ],
                Expanded(child: _buildConsoleStatus()),
                SizedBox(width: compact ? 5 : 10),
                _buildGardenMascot(
                  width: compact ? 62 : 88,
                  height: compact ? 88 : 116,
                ),
                SizedBox(width: compact ? 4 : 8),
                _buildSeedButton(),
                SizedBox(width: compact ? 4 : 8),
                _buildDockActions(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSideDock({required bool compact}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
      child: Container(
        key: const ValueKey('arcade-mascot-dock'),
        padding: EdgeInsets.all(compact ? 8 : 12),
        decoration: _dockDecoration(),
        child: LayoutBuilder(
          builder: (_, box) {
            final mascotHeight = compact
                ? 76.0
                : math.min(186.0, box.maxHeight * 0.38);
            return Column(
              children: [
                _buildGardenMascot(
                  width: math.min(170, box.maxWidth),
                  height: mascotHeight,
                ),
                SizedBox(height: compact ? 3 : 10),
                _buildConsoleStatus(),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMinimap(compact ? 58 : 76),
                    const SizedBox(width: 8),
                    _buildSeedButton(),
                    const SizedBox(width: 8),
                    _buildDockActions(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  BoxDecoration _dockDecoration() => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFCF3), Color(0xFFE8EED7)],
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: ArcadePalette.fenceLight),
    boxShadow: AppShadows.flat,
  );

  Widget _buildMinimap(double dimension) {
    return SizedBox.square(
      dimension: dimension,
      child: ValueListenableBuilder<int>(
        valueListenable: _frame,
        builder: (_, _, _) => CustomPaint(
          key: const ValueKey('snake-arcade-minimap'),
          painter: SnakeArcadeMinimapPainter(
            engine: _engine,
            cameraX: _cameraX,
            cameraY: _cameraY,
          ),
        ),
      ),
    );
  }

  Widget _buildDockActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          key: const ValueKey('arcade-pause-button'),
          icon: Icons.pause_rounded,
          tooltip: '暫停',
          onPressed: _engine.phase == ArcadePhase.running ? _pauseGame : null,
        ),
        const SizedBox(height: 6),
        _RoundButton(
          key: const ValueKey('arcade-exit-button'),
          icon: Icons.close_rounded,
          tooltip: '離開遊戲',
          onPressed: () => unawaited(_requestExit()),
        ),
      ],
    );
  }

  Widget _buildGardenMascot({required double width, required double height}) {
    return SizedBox(
      key: const ValueKey('arcade-mascot'),
      width: width,
      height: height,
      child: ValueListenableBuilder<MascotState>(
        valueListenable: MascotPersona.current,
        builder: (_, state, _) => ValueListenableBuilder<String>(
          valueListenable: WardrobeStore.selectedOutfit,
          builder: (_, outfitId, _) => FittedBox(
            alignment: Alignment.bottomCenter,
            child: MascotStage(
              asset: skinnedMascotAsset(
                state.assetPath,
                outfitById(outfitId).skinKey,
              ),
              accent: kGameAccent,
              bubble: state.bubble,
              bubbleTick: state.bubbleTick,
              reactionTick: 0,
              onTap: () => MascotPersona.interact(MascotContext.tapReaction),
              onHeadPet: () => MascotPersona.interact(MascotContext.headPet),
              onEnergize: () => MascotPersona.interact(MascotContext.energize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleStatus() {
    final children = <Widget>[];
    if (_engine.huntActive) {
      children.add(
        _ConsoleBar(
          label: '狩獵 ${_engine.huntEaten}/${SnakeArcadeEngine.huntTargetKills}',
          trailing: '${(_engine.huntMsLeft / 1000).ceil()}s',
          progress: _engine.huntMsLeft / SnakeArcadeEngine.huntDurationMs,
          color: ArcadePalette.huntBody,
        ),
      );
    } else {
      children.add(
        _ConsoleBar(
          label: '下次能力',
          trailing: '${_engine.physicalCount}/${_engine.nextAbilityAt}',
          progress: _engine.nextAbilityAt == 0
              ? 0
              : _engine.physicalCount / _engine.nextAbilityAt,
          color: kGameAccent,
        ),
      );
    }
    children.add(const SizedBox(height: 8));
    children.add(
      Row(
        children: [
          Expanded(
            child: Text(
              _engine.molesUnlocked ? '按種子鈕趕走鼴鼠' : '收蘿蔔，長大一點',
              style: const TextStyle(
                color: AppInk.soft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildSeedButton() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (_, _, _) {
        final total = _engine.shootCooldownTotalMs;
        final progress = total == 0
            ? 1.0
            : 1 - _engine.shootCooldownLeftMs / total;
        final hunting = _engine.huntActive;
        final unlocked = _engine.molesUnlocked;
        final laser = _engine.laserActive;
        final label = hunting
            ? '狩獵中'
            : laser
            ? '雷射'
            : '種子';
        return SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 58,
                      child: CircularProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        strokeWidth: 4,
                        color: laser ? ArcadePalette.gold : kGameAccent,
                        backgroundColor: AppSurfaces.divider,
                      ),
                    ),
                    SizedBox.square(
                      dimension: 48,
                      child: Material(
                        color: unlocked && !hunting
                            ? (laser ? ArcadePalette.huntBody : kGameAccent)
                            : AppSurfaces.fill,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const ValueKey('arcade-seed-button'),
                          customBorder: const CircleBorder(),
                          onTap: _engine.canShoot ? _shoot : null,
                          child: Icon(
                            hunting
                                ? Icons.pets_rounded
                                : laser
                                ? Icons.bolt_rounded
                                : Icons.grain_rounded,
                            color: unlocked && !hunting
                                ? Colors.white
                                : AppInk.faint,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: AppInk.soft,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 結算與排行榜 ───────────────────────────────────────

  Widget _buildResultOverlay() {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return ColoredBox(
      color: const Color(0xB8453229),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + viewInsets),
          child: Container(
            key: const ValueKey('arcade-result-panel'),
            width: math.min(MediaQuery.sizeOf(context).width - 40, 340),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: AppSurfaces.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card,
            ),
            child: _showBoards ? _buildBoardsView() : _buildRegisterView(),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultHeader(engine: _engine, qualified: true),
        const SizedBox(height: 12),
        const Text(
          '進榜了！要用誰的名字記下來？',
          style: TextStyle(
            color: AppInk.strong,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('arcade-name-field'),
          controller: _nameController,
          maxLength: 12,
          decoration: const InputDecoration(
            counterText: '',
            isDense: true,
            border: OutlineInputBorder(),
            hintText: '署名',
          ),
        ),
        if (_records.recentNames.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in _records.recentNames)
                ActionChip(
                  key: ValueKey('arcade-name-chip-$name'),
                  label: Text(name),
                  onPressed: () {
                    _nameController.text = name;
                    playHaptic(HapticLevel.selection);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('arcade-register-button'),
          style: FilledButton.styleFrom(
            backgroundColor: kGameAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(42),
          ),
          onPressed: () => unawaited(_registerScore()),
          child: const Text('登錄成績'),
        ),
        TextButton(
          key: const ValueKey('arcade-skip-register-button'),
          onPressed: _skipRegister,
          child: const Text('先不登錄', style: TextStyle(color: AppInk.soft)),
        ),
      ],
    );
  }

  Widget _buildBoardsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultHeader(engine: _engine, qualified: _resultQualifies),
        const SizedBox(height: 12),
        _LeaderboardView(
          records: _records,
          now: _now,
          highlight: _justRegistered,
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('arcade-retry-button'),
          style: FilledButton.styleFrom(
            backgroundColor: kGameAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(42),
          ),
          onPressed: _restart,
          child: const Text('再來一局'),
        ),
        TextButton(
          key: const ValueKey('arcade-leave-button'),
          onPressed: widget.onClose,
          child: const Text('離開', style: TextStyle(color: AppInk.soft)),
        ),
      ],
    );
  }
}

// ── 小元件們 ─────────────────────────────────────────────

class _HudChip extends StatelessWidget {
  const _HudChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: kGameAccent.withValues(alpha: 0.20)),
        boxShadow: AppShadows.flat,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppInk.soft,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              value,
              style: AppType.digits(
                color: kGameAccentDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ConsoleBar extends StatelessWidget {
  const _ConsoleBar({
    required this.label,
    required this.trailing,
    required this.progress,
    required this.color,
  });

  final String label;
  final String trailing;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppInk.strong,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              trailing,
              style: AppType.digits(
                color: kGameAccentDark,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 7,
            color: color,
            backgroundColor: AppSurfaces.divider,
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: Material(
        color: AppSurfaces.card,
        shape: const CircleBorder(),
        child: IconButton(
          iconSize: 22,
          icon: Icon(icon, color: kGameAccentDark),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _StartHint extends StatelessWidget {
  const _StartHint({required this.reason});

  final ArcadeWaitReason reason;

  @override
  Widget build(BuildContext context) {
    final text = switch (reason) {
      ArcadeWaitReason.newGame => '滑動開始探索',
      ArcadeWaitReason.abilityPicked => '滑動繼續',
      ArcadeWaitReason.revived => '復活了，滑動繼續',
      ArcadeWaitReason.resumed => '滑動繼續',
    };
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6453229),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              text,
              key: const ValueKey('arcade-start-hint'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HuntBanner extends StatelessWidget {
  const _HuntBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ArcadePalette.huntHead.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Text(
                '狩獵時刻！用頭吃鼴鼠',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AbilityOverlay extends StatelessWidget {
  const _AbilityOverlay({required this.abilities, required this.onPick});

  final List<ArcadeAbility> abilities;
  final ValueChanged<int> onPick;

  static IconData _iconFor(ArcadeAbility ability) => switch (ability) {
    ArcadeAbility.extraLife => Icons.favorite_rounded,
    ArcadeAbility.speedUp => Icons.speed_rounded,
    ArcadeAbility.speedDown => Icons.slow_motion_video_rounded,
    ArcadeAbility.fiveFold => Icons.auto_awesome_rounded,
    ArcadeAbility.selfPass => Icons.blur_on_rounded,
    ArcadeAbility.hunt => Icons.flash_on_rounded,
    ArcadeAbility.carrotRain => Icons.grass_rounded,
    ArcadeAbility.rapidSeed => Icons.forward_rounded,
    ArcadeAbility.carrotMagnet => Icons.filter_center_focus_rounded,
    ArcadeAbility.laser => Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xB8453229),
      child: Center(
        child: Container(
          key: const ValueKey('arcade-ability-overlay'),
          width: math.min(MediaQuery.sizeOf(context).width - 40, 340),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: AppSurfaces.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '選一個能力',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppInk.strong,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < abilities.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Material(
                  color: AppSurfaces.fill,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('arcade-ability-option-$i'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onPick(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconFor(abilities[i]),
                            color: kGameAccent,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  abilities[i].label,
                                  style: const TextStyle(
                                    color: AppInk.strong,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  abilities[i].description,
                                  style: const TextStyle(
                                    color: AppInk.soft,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
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
              ],
              const SizedBox(height: 10),
              const Text(
                '選完再滑動一下才會繼續',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppInk.faint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onExit,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xB8453229),
      child: Center(
        child: Container(
          width: math.min(MediaQuery.sizeOf(context).width - 56, 260),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          decoration: BoxDecoration(
            color: AppSurfaces.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '已暫停',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppInk.strong,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '先喘口氣也可以。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppInk.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('arcade-resume-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: kGameAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(40),
                ),
                onPressed: onResume,
                child: const Text('繼續'),
              ),
              TextButton(
                key: const ValueKey('arcade-restart-button'),
                onPressed: onRestart,
                child: const Text(
                  '重新開始',
                  style: TextStyle(color: kGameAccentDark),
                ),
              ),
              TextButton(
                key: const ValueKey('arcade-pause-exit-button'),
                onPressed: onExit,
                child: const Text('離開遊戲', style: TextStyle(color: AppInk.soft)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.engine, required this.qualified});

  final SnakeArcadeEngine engine;
  final bool qualified;

  @override
  Widget build(BuildContext context) {
    final emotion = qualified ? MascotEmotion.popHappy : MascotEmotion.smile;
    final line = qualified ? '好快的蛇…我有看到。' : '呼…休息一下，再來嗎？';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Image.asset(emotion.assetPath, height: 64, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '結算',
                    style: TextStyle(
                      color: AppInk.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${engine.score}',
                    key: const ValueKey('arcade-final-score'),
                    style: AppType.digits(
                      color: kGameAccentDark,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    line,
                    style: const TextStyle(
                      color: AppInk.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ResultStat(label: '蘿蔔', value: '${engine.physicalCount}'),
            _ResultStat(label: '最長', value: '${engine.maxLength}'),
            _ResultStat(
              label: '獵怪',
              value: '${engine.huntKills + engine.shotKills}',
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppType.digits(
            color: AppInk.strong,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppInk.faint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LeaderboardView extends StatefulWidget {
  const _LeaderboardView({
    required this.records,
    required this.now,
    this.highlight,
  });

  final SnakeArcadeRecords records;
  final DateTime now;
  final SnakeArcadeScore? highlight;

  @override
  State<_LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<_LeaderboardView> {
  SnakeArcadeBoard _board = SnakeArcadeBoard.today;

  static const _labels = {
    SnakeArcadeBoard.today: '今日',
    SnakeArcadeBoard.week: '本週',
    SnakeArcadeBoard.allTime: '歷史',
  };

  @override
  Widget build(BuildContext context) {
    final entries = widget.records.board(_board, widget.now);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final kind in SnakeArcadeBoard.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  key: ValueKey('arcade-board-tab-${kind.name}'),
                  label: Text(_labels[kind]!),
                  selected: _board == kind,
                  selectedColor: kGameAccent.withValues(alpha: 0.16),
                  onSelected: (_) {
                    playHaptic(HapticLevel.selection);
                    setState(() => _board = kind);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '這個榜還空著，等第一筆成績。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppInk.faint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 218),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final highlighted = identical(entry, widget.highlight);
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? kGameAccent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: AppType.digits(
                            color: index < 3 ? kGameAccentDark : AppInk.faint,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: highlighted
                                ? kGameAccentDark
                                : AppInk.strong,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.score}',
                        style: AppType.digits(
                          color: kGameAccentDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
