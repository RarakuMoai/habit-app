// 全螢幕「桌面模式」宿主：手機放桌中央的對戰面。
//
// 職責：引擎生命週期、鎖亮屏、切背景自動暫停、音效/震動事件、
// 暫停霧面層、結束確認；實際面板交給 party_face / chess_face。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/sfx_service.dart';
import '../../../utils/wake_guard.dart';
import '../../../widgets/app_dialogs.dart';
import 'chess_face.dart';
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

  @override
  void initState() {
    super.initState();
    _engine = TableTimerEngine(widget.config)..onEvent = _handleEvent;
    WakeGuard.acquire('gameTable');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakeGuard.release('gameTable');
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌上情境手機不該離開這頁；真的被切走（來電、鎖屏）就自動暫停，
    // 回來看到暫停層自己按繼續，不會偷跑時間。
    if (state == AppLifecycleState.paused) _engine.pause();
  }

  // 時間驅動的提醒：MVP 先掛既有音效資產，專屬音效等美術階段換。
  void _handleEvent(TableTimerEvent event) {
    switch (event) {
      case TableTimerEvent.warn:
        playFeedback(SfxCue.cancel, haptic: HapticLevel.light);
      case TableTimerEvent.criticalTick:
        playHaptic(HapticLevel.medium);
      case TableTimerEvent.expire:
        playFeedback(SfxCue.complete, haptic: HapticLevel.medium);
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
    setState(() {
      _showSummary = false;
      _engine = TableTimerEngine(widget.config)..onEvent = _handleEvent;
    });
    old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: TableTheme.feltEdge,
        body: DecoratedBox(
          decoration: TableTheme.feltBackground(),
          child: ListenableBuilder(
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
                    )
                  else
                    PartyFace(key: ObjectKey(_engine), engine: _engine),
                  // 角落小鍵蓋在整面觸控區上方（吸收點擊，不觸發換人）。
                  // 棋鐘的控制在中央窄帶，這裡只給多人/自由模式。
                  // 注意 Stack 是 expand：一定要 Align 回頂部，不然 Row
                  // 會被撐滿整頁、按鈕垂直置中。
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _CornerButton(
                                icon: Icons.close_rounded,
                                onTap: _confirmExit,
                              ),
                              _CornerButton(
                                icon: Icons.pause_rounded,
                                onTap: _engine.phase == TablePhase.running
                                    ? _engine.pause
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
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
        ),
      ),
    );
  }
}

/// 角落半透明圓鍵（✕ / ⏸）。
class _CornerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CornerButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x2EF6ECDD),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                playHaptic(HapticLevel.selection);
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? TableTheme.inkFaint : TableTheme.inkStrong,
          ),
        ),
      ),
    );
  }
}

/// 暫停霧面層：模糊桌面 + 大顆繼續 + 次要操作。
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
          color: const Color(0xB31A120C),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.pause_circle_rounded,
                    size: 46,
                    color: TableTheme.inkSoft,
                  ),
                  const SizedBox(height: 12),
                  Text('暫停中', style: TableTheme.nameStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SeatDot(color: seat, size: 11),
                      const SizedBox(width: 7),
                      Text(
                        '輪到 ${engine.currentPlayer.name}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: TableTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _OverlayButton(
                    label: '繼續',
                    icon: Icons.play_arrow_rounded,
                    color: seat,
                    filled: true,
                    onTap: engine.resume,
                  ),
                  const SizedBox(height: 12),
                  _OverlayButton(
                    label: '回上一位',
                    icon: Icons.undo_rounded,
                    onTap: engine.canUndo ? engine.undo : null,
                  ),
                  const SizedBox(height: 12),
                  _OverlayButton(
                    label: '重開本回合',
                    icon: Icons.replay_rounded,
                    onTap: engine.restartTurn,
                  ),
                  const SizedBox(height: 12),
                  _OverlayButton(
                    label: '結束對局',
                    icon: Icons.stop_rounded,
                    color: TableTheme.overtime,
                    onTap: onExit,
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

class _OverlayButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool filled;
  final VoidCallback? onTap;

  const _OverlayButton({
    required this.label,
    required this.icon,
    this.color,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = color ?? TableTheme.inkSoft;
    final fg = filled
        ? const Color(0xFF241A12)
        : (enabled ? accent : TableTheme.inkFaint);
    return Material(
      color: filled ? accent : const Color(0x1AF6ECDD),
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : const BorderSide(color: TableTheme.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled
            ? () {
                playHaptic(HapticLevel.selection);
                onTap!();
              }
            : null,
        child: SizedBox(
          width: 230,
          height: filled ? 58 : 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: filled ? 26 : 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: filled ? 18 : 15.5,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 玩家座位色點（多處共用的最小元件）。
class _SeatDot extends StatelessWidget {
  final Color color;
  final double size;

  const _SeatDot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: size * 0.6,
          ),
        ],
      ),
    );
  }
}
