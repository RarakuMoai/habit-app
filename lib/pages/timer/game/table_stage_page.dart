// 全螢幕「桌面模式」宿主：手機放桌中央的對戰面。
//
// 職責：引擎生命週期、鎖亮屏、切背景自動暫停、音效/震動事件、
// 暫停霧面層、結束確認；實際面板交給 party_face / chess_face。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import '../../../utils/wake_guard.dart';
import '../../../widgets/app_dialogs.dart';
import 'chess_face.dart';
import 'dice_tray.dart';
import 'party_face.dart';
import 'table_summary_overlay.dart';
import 'table_timer_engine.dart';
import 'table_timer_models.dart';
import 'table_timer_theme.dart';

class TableStagePage extends StatefulWidget {
  final TableTimerConfig config;

  const TableStagePage({super.key, required this.config});

  @override
  State<TableStagePage> createState() => _TableStagePageState();
}

class _TableStagePageState extends State<TableStagePage>
    with WidgetsBindingObserver {
  late TableTimerEngine _engine;

  /// 結束確認後顯示結算面（沒真的玩就直接離開，不秀）。
  bool _showSummary = false;

  /// 骰盤 overlay（擲骰時計時照跑——骰你的、算你的時間）。
  bool _showDiceTray = false;

  @override
  void initState() {
    super.initState();
    _engine = TableTimerEngine(widget.config)..onEvent = _handleEvent;
    _engine.addListener(_syncWakeGuard);
    WakeGuard.acquire('gameTable');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.removeListener(_syncWakeGuard);
    WakeGuard.release('gameTable');
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌上情境手機不該離開這頁；真的被切走（來電、鎖屏）就自動暫停，
    // 回來看到暫停層自己按繼續，不會偷跑時間。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _engine.pause();
    }
  }

  void _syncWakeGuard() {
    if (_engine.phase == TablePhase.paused ||
        _engine.phase == TablePhase.finished) {
      WakeGuard.release('gameTable');
    } else {
      WakeGuard.acquire('gameTable');
    }
  }

  // 時間驅動的提醒：桌遊專屬音效（木質 tick／沉鑼，2026-07 生成）。
  void _handleEvent(TableTimerEvent event) {
    switch (event) {
      case TableTimerEvent.warn:
        playFeedback(SfxCue.gameWarn, haptic: HapticLevel.light);
      case TableTimerEvent.criticalTick:
        playFeedback(SfxCue.gameWarn, haptic: HapticLevel.medium);
      case TableTimerEvent.expire:
        playFeedback(SfxCue.gameFlag, haptic: HapticLevel.medium);
      case TableTimerEvent.autoAdvance:
        break; // expire 已給回饋，自動換人不再疊加
    }
  }

  Future<void> _confirmExit() async {
    if (_engine.phase == TablePhase.ready || _showSummary) {
      Navigator.of(context).pop();
      return;
    }
    // 旗倒終局：勝負已定，不再問「要不要結束」，直接進結算
    if (_engine.phase == TablePhase.finished) {
      setState(() => _showSummary = true);
      return;
    }
    _engine.pause();
    final leave = await showAppConfirmDialog(
      context,
      title: '結束對局？',
      message: '結束後會顯示本局小結。',
      confirmLabel: '結束對局',
      danger: true,
    );
    if (!mounted) return;
    if (!leave) return; // 停在暫停層，讓桌上的人自己按「繼續」
    if (_engine.settledTurns > 0) {
      playFeedback(SfxCue.complete, haptic: HapticLevel.medium);
      setState(() => _showSummary = true);
    } else {
      Navigator.of(context).pop(); // 一手都沒走完，沒東西好結算
    }
  }

  /// 再來一局：同一份設定換一顆全新引擎，回到 ready。
  void _rematch() {
    final old = _engine;
    old.removeListener(_syncWakeGuard);
    setState(() {
      _showSummary = false;
      _engine = TableTimerEngine(widget.config)..onEvent = _handleEvent;
      _engine.addListener(_syncWakeGuard);
    });
    WakeGuard.acquire('gameTable');
    old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showDiceTray) {
          setState(() => _showDiceTray = false);
        } else {
          _confirmExit();
        }
      },
      child: Scaffold(
        backgroundColor: TableTheme.feltEdge,
        body: DecoratedBox(
          decoration: TableTheme.feltBackground(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: Image(
                  image: AssetImage(
                    'assets/scenes/game/game_family_table_bg.png',
                  ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              DecoratedBox(decoration: TableTheme.feltWarmLight()),
              DecoratedBox(decoration: TableTheme.feltVignette()),
              ListenableBuilder(
                listenable: _engine,
                builder: (context, _) {
                  final chess = widget.config.mode == TableGameMode.chess;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // key 綁引擎：再來一局換新引擎時整張面重建，
                      // 面板內部掛在舊引擎上的 listener 才不會殘留。
                      if (chess)
                        ChessFace(
                          key: ObjectKey(_engine),
                          engine: _engine,
                          onPause: _engine.pause,
                          onExit: _confirmExit,
                          onDice: () => setState(() => _showDiceTray = true),
                        )
                      else
                        PartyFace(key: ObjectKey(_engine), engine: _engine),
                      // 清楚標字的控制蓋在整面交棒區上方，避免兒童或長者
                      // 猜測純 icon；棋鐘的控制留在中央帶。
                      if (!chess)
                        SafeArea(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  _StageActionButton(
                                    icon: Icons.close_rounded,
                                    label: '離開',
                                    onTap: _confirmExit,
                                  ),
                                  const Spacer(),
                                  _StageActionButton(
                                    icon: Icons.pause_rounded,
                                    label: '暫停',
                                    onTap: _engine.phase == TablePhase.running
                                        ? _engine.pause
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  _StageActionButton(
                                    icon: Icons.casino_rounded,
                                    label: '骰子',
                                    onTap: () =>
                                        setState(() => _showDiceTray = true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_showDiceTray)
                        DiceTrayOverlay(
                          onClose: () => setState(() => _showDiceTray = false),
                        ),
                      if (_engine.phase == TablePhase.paused && !_showSummary)
                        _PauseOverlay(engine: _engine, onExit: _confirmExit),
                      if (_showSummary)
                        TableSummaryOverlay(
                          engine: _engine,
                          onRematch: _rematch,
                          onLeave: () => Navigator.of(context).pop(),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 對局工具鈕：文字＋圖示、至少 48px，並提供完整輔助說明。
class _StageActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _StageActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final button = Material(
      color: enabled
          ? AppSurfaces.card.withValues(alpha: 0.94)
          : AppSurfaces.fill.withValues(alpha: 0.82),
      shape: StadiumBorder(
        side: BorderSide(
          color: enabled ? TableTheme.tableDivider : AppSurfaces.divider,
        ),
      ),
      elevation: enabled ? 1 : 0,
      shadowColor: const Color(0x338D6E63),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled
            ? () {
                playHaptic(HapticLevel.selection);
                onTap!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: enabled ? TableTheme.tableInkStrong : AppInk.iconFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: enabled
                        ? TableTheme.tableInkStrong
                        : AppInk.iconFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(message: label, child: button),
    );
  }
}

/// 暫停霧面層：兔咪陪大家歇一下，所有修正操作都用完整文字表達。
class _PauseOverlay extends StatelessWidget {
  final TableTimerEngine engine;
  final Future<void> Function() onExit;

  const _PauseOverlay({required this.engine, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final seat = TableTheme.seatColor(engine.currentPlayer.colorIndex);
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: ColoredBox(
          color: const Color(0x665E8B79),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  decoration: BoxDecoration(
                    color: AppSurfaces.card,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x338D6E63),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 82,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Image.asset(
                              'assets/mascot/core/tumi_sleep.png',
                              width: 92,
                              height: 92,
                              fit: BoxFit.contain,
                              semanticLabel: '兔咪陪你休息一下',
                            ),
                            Positioned(
                              right: 2,
                              top: 0,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: seat.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.pause_rounded,
                                  size: 22,
                                  color: seat,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '先休息一下',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: seat,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '輪到 ${engine.currentPlayer.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppInk.strong,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '時間已經停住，準備好再繼續就可以了。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14.5, color: AppInk.soft),
                      ),
                      const SizedBox(height: 18),
                      _cardButton(
                        label: '繼續這一局',
                        icon: Icons.play_arrow_rounded,
                        background: seat,
                        foreground: Colors.white,
                        height: 54,
                        fontSize: 17,
                        onTap: engine.resume,
                      ),
                      const SizedBox(height: 10),
                      _cardButton(
                        label: '回到上一位',
                        icon: Icons.undo_rounded,
                        height: 50,
                        onTap: engine.canUndo ? engine.undo : null,
                      ),
                      const SizedBox(height: 8),
                      _cardButton(
                        label: '這回合重新計時',
                        icon: Icons.replay_rounded,
                        height: 50,
                        onTap: engine.restartTurn,
                      ),
                      const SizedBox(height: 4),
                      _cardButton(
                        label: '結束這一局',
                        icon: Icons.stop_rounded,
                        foreground: AppInk.danger,
                        flat: true,
                        onTap: onExit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 暖紙卡上的按鈕：filled（background 有值）／tonal／flat 三態共用。
  Widget _cardButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    Color? background,
    Color? foreground,
    bool flat = false,
    double height = 48,
    double fontSize = 14.5,
  }) {
    final enabled = onTap != null;
    final fg = !enabled ? AppInk.iconFaint : (foreground ?? AppInk.strong);
    final button = Material(
      color: background ?? (flat ? Colors.transparent : AppSurfaces.fill),
      shape: StadiumBorder(
        side: background != null || flat
            ? BorderSide.none
            : const BorderSide(color: AppSurfaces.divider),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled
            ? () {
                playHaptic(HapticLevel.selection);
                onTap();
              }
            : null,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: fontSize + 4, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(message: label, child: button),
    );
  }
}
