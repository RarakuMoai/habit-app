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
          // 後備漸層：CG 還沒解碼完成的第一幀也不會閃白
          decoration: TableTheme.feltBackground(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // AI 生成絨布桌 CG＋保底暗角（光影特效照慣例 Flutter 端疊）
              const RepaintBoundary(
                child: Image(
                  image: AssetImage(TableTheme.feltAsset),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                      // 骰子鈕：party/free 放右下角（棋鐘在中央帶）
                      if (!chess)
                        SafeArea(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              child: _CornerButton(
                                icon: Icons.casino_rounded,
                                onTap: () =>
                                    setState(() => _showDiceTray = true),
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

/// 暫停霧面層：模糊桌面上蓋一張 app 本體的暖紙卡片——
/// 對局中的「休息角落」，把兔咪世界的溫度帶進深色桌面。
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
          color: const Color(0x8C1A120C),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 330),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  decoration: BoxDecoration(
                    color: AppSurfaces.card,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59120B06),
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: seat.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.pause_rounded, size: 30, color: seat),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '暫停中',
                        style: TextStyle(
                          fontSize: 20,
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
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppInk.strong,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '喝口水休息一下，回來再繼續',
                        style: TextStyle(fontSize: 12.5, color: AppInk.soft),
                      ),
                      const SizedBox(height: 18),
                      _cardButton(
                        label: '繼續',
                        icon: Icons.play_arrow_rounded,
                        background: seat,
                        foreground: Colors.white,
                        height: 54,
                        fontSize: 17,
                        onTap: engine.resume,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _cardButton(
                              label: '回上一位',
                              icon: Icons.undo_rounded,
                              onTap: engine.canUndo ? engine.undo : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _cardButton(
                              label: '重開回合',
                              icon: Icons.replay_rounded,
                              onTap: engine.restartTurn,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _cardButton(
                        label: '結束對局',
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
    double height = 46,
    double fontSize = 14.5,
  }) {
    final enabled = onTap != null;
    final fg = !enabled ? AppInk.iconFaint : (foreground ?? AppInk.strong);
    return Material(
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
  }
}
