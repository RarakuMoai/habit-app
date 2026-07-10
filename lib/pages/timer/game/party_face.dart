// 多人桌遊／自由輪流對局面。
//
// 手機放在桌中央時，整面仍可點擊交棒；畫面同時用「現在輪到」、玩家
// 號碼、姓名與大字按鈕說清楚動作，不讓顏色成為唯一線索。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import 'table_timer_engine.dart';
import 'table_timer_theme.dart';

class PartyFace extends StatefulWidget {
  final TableTimerEngine engine;

  const PartyFace({super.key, required this.engine});

  @override
  State<PartyFace> createState() => _PartyFaceState();
}

class _PartyFaceState extends State<PartyFace> {
  DateTime? _lastPassAt;

  TableTimerEngine get engine => widget.engine;

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastPassAt;
    // 桌面整面都是按鈕，短暫防連點可避免兒童雙擊直接跳過一位。
    if (last != null && now.difference(last).inMilliseconds < 450) return;

    switch (engine.phase) {
      case TablePhase.ready:
        engine.start();
      case TablePhase.running:
        engine.advance();
      case TablePhase.paused:
      case TablePhase.finished:
        return;
    }
    _lastPassAt = now;
    playFeedback(SfxCue.gamePass);
  }

  String get _timeText {
    if (engine.isFree) return formatTableElapsed(engine.elapsedInTurn);
    if (engine.inOvertime) {
      return '+${formatTableElapsed(Duration(seconds: engine.overtimeSeconds))}';
    }
    return formatTableSeconds(
      engine.phase == TablePhase.ready
          ? engine.config.turnSeconds
          : engine.remainingSeconds,
    );
  }

  String get _semanticLabel {
    if (engine.phase == TablePhase.ready) {
      return '準備開始，第一位是 ${engine.currentPlayer.name}。啟用按鈕開始遊戲';
    }
    final time = engine.isFree
        ? '已用 $_timeText'
        : engine.inOvertime
        ? '已超時 $_timeText'
        : '剩下 $_timeText';
    return '現在輪到 ${engine.currentPlayer.name}，$time。'
        '完成後啟用按鈕，交給 ${engine.nextPlayer.name}';
  }

  @override
  Widget build(BuildContext context) {
    final ready = engine.phase == TablePhase.ready;
    final seat = TableTheme.seatColor(engine.currentPlayer.colorIndex);
    final accent = TableTheme.urgencyColor(engine.urgency, seat);

    return Semantics(
      container: true,
      button: true,
      label: _semanticLabel,
      onTap: _handleTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: SafeArea(
          child: Padding(
            // 上方留給 Stage 的「離開／暫停／骰子」工具列。
            padding: const EdgeInsets.fromLTRB(14, 66, 14, 12),
            child: LayoutBuilder(
              builder: (context, box) {
                final compact = box.maxHeight < 500;
                return Column(
                  children: [
                    _turnHeading(seat, ready, compact: compact),
                    SizedBox(height: compact ? 6 : 10),
                    Expanded(
                      child: Center(
                        child: _timerDial(
                          accent,
                          seat,
                          ready,
                          compact: compact,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    _playerOrderStrip(),
                    SizedBox(height: compact ? 6 : 10),
                    _handoffPrompt(accent, ready, compact: compact),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _turnHeading(Color seat, bool ready, {required bool compact}) {
    final playerNumber = engine.currentIndex + 1;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: ValueKey(engine.currentIndex),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: seat,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: seat.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              '$playerNumber',
              style: AppType.digits(
                fontSize: compact ? 17 : 19,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? '第一位準備好了嗎？' : '現在輪到',
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w800,
                    color: TableTheme.tableInkSoft,
                  ),
                ),
                Text(
                  engine.currentPlayer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 21 : 25,
                    fontWeight: FontWeight.w900,
                    color: TableTheme.tableInkStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerDial(
    Color accent,
    Color seat,
    bool ready, {
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(
          math.min(box.maxWidth * 0.86, box.maxHeight * 0.96),
          compact ? 250.0 : 340.0,
        );
        final safeSize = math.max(150.0, size);
        final progress = engine.isFree
            ? 1.0
            : ready
            ? 1.0
            : engine.ringProgress;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey('${engine.currentIndex}-${engine.inOvertime}'),
            width: safeSize,
            height: safeSize,
            padding: EdgeInsets.all(compact ? 14 : 18),
            decoration: BoxDecoration(
              color: AppSurfaces.card.withValues(alpha: 0.96),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.46),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.13),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
                const BoxShadow(
                  color: Color(0x168D6E63),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: compact ? 9 : 12,
                  strokeCap: StrokeCap.round,
                  color: engine.isFree ? seat.withValues(alpha: 0.42) : accent,
                  backgroundColor: AppSurfaces.divider,
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 22 : 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        engine.isFree
                            ? '這回合用了'
                            : engine.inOvertime
                            ? '已超時'
                            : ready
                            ? '每回合'
                            : '還有',
                        style: TextStyle(
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.w900,
                          color: engine.inOvertime
                              ? accent
                              : TableTheme.tableInkSoft,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _timeText,
                              maxLines: 1,
                              style: TableTheme.bigDigits(color: accent),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        engine.isFree
                            ? '自由計時'
                            : ready
                            ? '點一下開始'
                            : '專心想一想',
                        style: TextStyle(
                          fontSize: compact ? 13 : 15,
                          fontWeight: FontWeight.w800,
                          color: TableTheme.tableInkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _playerOrderStrip() {
    return Semantics(
      label: '玩家順序：${engine.players.map((p) => p.name).join('、')}',
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: engine.players.length,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (context, i) {
            final active = i == engine.currentIndex;
            final player = engine.players[i];
            final color = TableTheme.seatColor(player.colorIndex);
            return Container(
              constraints: const BoxConstraints(minWidth: 74),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: 0.12)
                    : AppSurfaces.card.withValues(alpha: 0.76),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active ? color : TableTheme.tableDivider,
                  width: active ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 23,
                    height: 23,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: AppType.digits(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Text(
                      active ? '現在・${player.name}' : player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                        color: TableTheme.tableInkStrong,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _handoffPrompt(Color accent, bool ready, {required bool compact}) {
    final next = engine.nextPlayer;
    final nextNumber = (engine.currentIndex + 1) % engine.players.length + 1;
    final label = ready
        ? '點一下，開始遊戲'
        : engine.inOvertime
        ? '時間到了，點一下交棒'
        : '完成了，點一下交棒';
    final helper = ready
        ? '由 ${engine.currentPlayer.name} 開始'
        : '下一位：$nextNumber 號 ${next.name}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      constraints: BoxConstraints(minHeight: compact ? 64 : 74),
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: compact ? 9 : 12),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.24),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            ready ? Icons.play_arrow_rounded : Icons.touch_app_rounded,
            size: compact ? 28 : 32,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 16 : 18,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF4FFF9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
