// 二人棋鐘面：上下分割，上半 180° 翻轉面向對座。
//
// 實體棋鐘慣例：點「自己（正在走時間）那側」＝停自己的鐘、啟動對方；
// 點對方那側無效（防干擾）。開局前點任一側 = 啟動「對面」的鐘
// （跟按下實體棋鐘側鈕一樣直覺）。
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

  TableTimerEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _tapSide(int side) {
    switch (engine.phase) {
      case TablePhase.ready:
        // 按自己那側 = 啟動對方的鐘
        engine.start(at: 1 - side);
      case TablePhase.running:
        if (engine.currentIndex != side) return; // 對方按了不算
        engine.advance();
      case TablePhase.paused:
      case TablePhase.finished:
        return; // 旗倒後鐘停了，點側邊沒有意義
    }
    playFeedback(SfxCue.gamePass); // 棋鐘喀噠
  }

  @override
  Widget build(BuildContext context) {
    final ready = engine.phase == TablePhase.ready;
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: RotatedBox(quarterTurns: 2, child: _half(1, ready))),
          _middleBand(ready),
          Expanded(child: _half(0, ready)),
        ],
      ),
    );
  }

  /// 一側棋鐘半面。[side] 0 = 下（本位）、1 = 上（對座）。
  Widget _half(int side, bool ready) {
    final player = engine.players[side];
    final seat = TableTheme.seatColor(player.colorIndex);
    // 旗倒側：終局後亮紅停在 0:00
    final flagged =
        engine.phase == TablePhase.finished && engine.flagFallIndex == side;
    final active = (!ready && engine.currentIndex == side) || flagged;
    final urgency = active && !flagged ? engine.urgency : 0;
    final accent = flagged
        ? TableTheme.overtime
        : TableTheme.urgencyColor(urgency, seat);

    final String timeText;
    if (engine.isBank) {
      // 總時間制：兩側各自顯示自己的時間庫（m:ss）
      timeText = formatTableElapsed(
        Duration(seconds: engine.bankDisplaySeconds(side)),
      );
    } else if (active && engine.inOvertime) {
      timeText =
          '+${formatTableElapsed(Duration(seconds: engine.overtimeSeconds))}';
    } else if (active) {
      timeText = formatTableSeconds(engine.remainingSeconds);
    } else {
      timeText = formatTableSeconds(engine.config.turnSeconds);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapSide(side),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: active ? TableTheme.panel : const Color(0xFF241A12),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.75)
                      : TableTheme.hairline,
                  width: active ? 2.4 : 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: accent.withValues(
                            alpha: 0.22 + 0.18 * _breath.value,
                          ),
                          blurRadius: 30 + 10 * _breath.value,
                        ),
                      ]
                    : null,
              ),
              child: child,
            );
          },
          child: Opacity(
            opacity: active || ready ? 1.0 : 0.42,
            child: LayoutBuilder(
              builder: (context, box) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: seat,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TableTheme.nameStyle(fontSize: 21),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: box.maxHeight * 0.44,
                      child: FittedBox(
                        child: Text(
                          timeText,
                          maxLines: 1,
                          style: TableTheme.bigDigits(
                            color: active ? accent : TableTheme.inkSoft,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 20,
                      child: flagged || (active && engine.inOvertime)
                          ? Text(
                              flagged ? '時間到' : '超時',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                                color: accent,
                              ),
                            )
                          : (active
                                ? const Text(
                                    '輪到你 · 走完點這裡',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: TableTheme.inkFaint,
                                    ),
                                  )
                                : null),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 中央窄帶：暫停 / 手數 / 結束（雙向都看得懂的置中排法）。
  Widget _middleBand(bool ready) {
    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _bandButton(icon: Icons.close_rounded, onTap: () => widget.onExit()),
          const SizedBox(width: 26),
          if (ready)
            const Text(
              '點自己那側開始',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: TableTheme.inkFaint,
              ),
            )
          else if (engine.phase == TablePhase.finished)
            Text(
              '${engine.players[engine.flagFallIndex!].name} 時間到',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: TableTheme.overtime,
              ),
            )
          else
            Text(
              '第 ${engine.turnCount} 手',
              style: AppType.digits(fontSize: 14, color: TableTheme.inkSoft),
            ),
          const SizedBox(width: 26),
          _bandButton(
            icon: Icons.pause_rounded,
            onTap: engine.phase == TablePhase.running ? widget.onPause : null,
          ),
          const SizedBox(width: 26),
          _bandButton(icon: Icons.casino_rounded, onTap: widget.onDice),
        ],
      ),
    );
  }

  Widget _bandButton({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: const Color(0x2EF6ECDD),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                playHaptic(HapticLevel.selection);
                onTap();
              },
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? TableTheme.inkFaint : TableTheme.inkStrong,
          ),
        ),
      ),
    );
  }
}
