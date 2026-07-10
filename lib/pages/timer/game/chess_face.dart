// 二人棋鐘：手機放在兩人中間，上半面旋轉給對座閱讀。
//
// 每一側同時用玩家編號、姓名、狀態文案與色彩表達輪次；整張大卡都是
// 交棒按鈕。開局遵循實體棋鐘直覺：按自己的區域，讓對方先走。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import 'table_timer_engine.dart';
import 'table_timer_theme.dart';

class ChessFace extends StatefulWidget {
  final TableTimerEngine engine;
  final VoidCallback onPause;
  final Future<void> Function() onExit;
  final VoidCallback onDice;

  const ChessFace({
    super.key,
    required this.engine,
    required this.onPause,
    required this.onExit,
    required this.onDice,
  });

  @override
  State<ChessFace> createState() => _ChessFaceState();
}

class _ChessFaceState extends State<ChessFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  DateTime? _lastTapAt;

  TableTimerEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _tapSide(int side) {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last).inMilliseconds < 320) return;

    switch (engine.phase) {
      case TablePhase.ready:
        engine.start(at: 1 - side);
      case TablePhase.running:
        if (engine.currentIndex != side) return;
        engine.advance();
      case TablePhase.paused:
      case TablePhase.finished:
        return;
    }
    _lastTapAt = now;
    playFeedback(SfxCue.gamePass);
  }

  @override
  Widget build(BuildContext context) {
    final ready = engine.phase == TablePhase.ready;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: RotatedBox(
              quarterTurns: 2,
              child: _playerHalf(side: 1, ready: ready),
            ),
          ),
          _controlBand(ready),
          Expanded(child: _playerHalf(side: 0, ready: ready)),
        ],
      ),
    );
  }

  Widget _playerHalf({required int side, required bool ready}) {
    final player = engine.players[side];
    final other = engine.players[1 - side];
    final seat = TableTheme.seatColor(player.colorIndex);
    final flagged =
        engine.phase == TablePhase.finished && engine.flagFallIndex == side;
    final active = !ready && engine.currentIndex == side;
    final tappable = ready || (engine.phase == TablePhase.running && active);
    final urgency = active && !flagged ? engine.urgency : 0;
    final accent = flagged
        ? TableTheme.overtime
        : TableTheme.urgencyColor(urgency, seat);
    final timeText = _timeFor(side, active: active, ready: ready);
    final status = switch ((ready, flagged, active)) {
      (_, true, _) => '時間到了',
      (true, _, _) => '按這裡，讓 ${other.name} 先走',
      (_, _, true) => engine.inOvertime ? '已超時 · 下完按這裡' : '輪到你 · 下完按這裡',
      _ => '等待 ${engine.currentPlayer.name}',
    };
    final semantic = switch ((ready, flagged, active)) {
      (_, true, _) => '${player.name}時間到，$timeText',
      (true, _, _) => '${player.name}的計時區。啟用後讓${other.name}先走',
      (_, _, true) => '現在輪到${player.name}，剩下$timeText。下完後啟用按鈕',
      _ => '${player.name}等待中，時間$timeText',
    };

    return Semantics(
      container: true,
      button: true,
      enabled: tappable,
      liveRegion: flagged,
      label: semantic,
      onTap: tappable ? () => _tapSide(side) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => _tapSide(side) : null,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, child) {
                final reduceMotion = MediaQuery.disableAnimationsOf(context);
                final pulse = reduceMotion ? 0.5 : _breath.value;
                return AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: flagged
                        ? const Color(0xFFFFECE8)
                        : active
                        ? Color.lerp(
                            AppSurfaces.card,
                            seat.withValues(alpha: 0.18),
                            0.55,
                          )
                        : AppSurfaces.card.withValues(
                            alpha: ready ? 0.94 : 0.78,
                          ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: tappable || flagged
                          ? accent.withValues(alpha: 0.78)
                          : TableTheme.tableDivider,
                      width: tappable || flagged ? 2.5 : 1.2,
                    ),
                    boxShadow: active || flagged
                        ? [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: 0.12 + pulse * 0.10,
                              ),
                              blurRadius: 22 + pulse * 8,
                              offset: const Offset(0, 7),
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Color(0x128D6E63),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                  ),
                  child: child,
                );
              },
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxHeight < 245;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 18,
                      compact ? 10 : 14,
                      compact ? 12 : 18,
                      compact ? 8 : 12,
                    ),
                    child: Column(
                      children: [
                        _playerHeading(
                          side: side,
                          seat: seat,
                          active: active,
                          compact: compact,
                        ),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                timeText,
                                maxLines: 1,
                                style: TableTheme.bigDigits(
                                  color: active || flagged
                                      ? accent
                                      : TableTheme.tableInkSoft,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _statusPill(
                          status,
                          accent: accent,
                          emphasized: tappable || flagged,
                          compact: compact,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _timeFor(int side, {required bool active, required bool ready}) {
    if (engine.isBank) {
      return formatTableElapsed(
        Duration(seconds: engine.bankDisplaySeconds(side)),
      );
    }
    if (active && engine.inOvertime) {
      return '+${formatTableElapsed(Duration(seconds: engine.overtimeSeconds))}';
    }
    if (active && !ready) {
      return formatTableSeconds(engine.remainingSeconds);
    }
    return formatTableSeconds(engine.config.turnSeconds);
  }

  Widget _playerHeading({
    required int side,
    required Color seat,
    required bool active,
    required bool compact,
  }) {
    final player = engine.players[side];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: compact ? 32 : 38,
          height: compact ? 32 : 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: seat, shape: BoxShape.circle),
          child: Text(
            '${side + 1}',
            style: AppType.digits(
              fontSize: compact ? 16 : 19,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                active ? '現在輪到' : '玩家 ${side + 1}',
                style: TextStyle(
                  fontSize: compact ? 12.5 : 14,
                  fontWeight: FontWeight.w800,
                  color: TableTheme.tableInkSoft,
                ),
              ),
              Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TableTheme.nameStyle(fontSize: compact ? 19 : 23),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusPill(
    String label, {
    required Color accent,
    required bool emphasized,
    required bool compact,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      constraints: BoxConstraints(minHeight: compact ? 42 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? accent.withValues(alpha: 0.13)
            : AppSurfaces.fill.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? accent.withValues(alpha: 0.48)
              : AppSurfaces.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            emphasized ? Icons.touch_app_rounded : Icons.hourglass_top_rounded,
            size: compact ? 18 : 20,
            color: emphasized ? accent : TableTheme.tableInkSoft,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 13 : 14.5,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: emphasized ? accent : TableTheme.tableInkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBand(bool ready) {
    final status = ready
        ? '誰先走？另一位先按自己的區域'
        : engine.phase == TablePhase.finished
        ? '${engine.players[engine.flagFallIndex!].name} 時間到'
        : '第 ${engine.turnCount} 手';
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: AppSurfaces.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: TableTheme.tableDivider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x148D6E63),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _toolButton(
            icon: Icons.close_rounded,
            label: '離開',
            onTap: () => unawaited(widget.onExit()),
          ),
          _toolButton(
            icon: Icons.pause_rounded,
            label: '暫停',
            onTap: engine.phase == TablePhase.running ? widget.onPause : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ready ? 12.5 : 14,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  color: engine.phase == TablePhase.finished
                      ? TableTheme.overtime
                      : TableTheme.tableInkStrong,
                ),
              ),
            ),
          ),
          _toolButton(
            icon: Icons.casino_rounded,
            label: '骰子',
            onTap: widget.onDice,
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: enabled
              ? const Color(0xFFEAF4EC)
              : AppSurfaces.fill.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled
                ? () {
                    playHaptic(HapticLevel.selection);
                    onTap();
                  }
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 58, minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 21,
                      color: enabled ? kGameAccentDark : AppInk.iconFaint,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
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
        ),
      ),
    );
  }
}
