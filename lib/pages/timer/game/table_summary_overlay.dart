// 對局結算面：結束對局後蓋在絨布桌上的小結。
//
// 每人一列：回合數、總思考、平均；平均最快的玩家給 ⚡（正向、不點名
// 最慢的）。資料吃引擎的 TurnStats，進行中沒結算的半截回合不計。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import 'table_timer_engine.dart';
import 'table_timer_theme.dart';

class TableSummaryOverlay extends StatelessWidget {
  final TableTimerEngine engine;
  final VoidCallback onRematch;
  final VoidCallback onLeave;

  const TableSummaryOverlay({
    super.key,
    required this.engine,
    required this.onRematch,
    required this.onLeave,
  });

  /// 平均最快的玩家 index（至少走過一手才有資格；沒人走過回 -1）。
  int get _fastestIndex {
    var best = -1;
    Duration? bestAvg;
    for (var i = 0; i < engine.stats.length; i++) {
      final s = engine.stats[i];
      if (s.turns == 0) continue;
      final avg = s.averageThink;
      if (bestAvg == null || avg < bestAvg) {
        bestAvg = avg;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final fastest = _fastestIndex;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: ColoredBox(
          color: const Color(0xB31A120C),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 42,
                        color: TableTheme.warn,
                      ),
                      const SizedBox(height: 10),
                      Text('對局結束', style: TableTheme.nameStyle(fontSize: 24)),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${engine.settledTurns} 手',
                        style: AppType.digits(
                          fontSize: 14,
                          color: TableTheme.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: TableTheme.panel.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: TableTheme.hairline),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Column(
                          children: [
                            for (var i = 0; i < engine.players.length; i++)
                              _playerRow(i, isFastest: i == fastest),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _button(
                        label: '再來一局',
                        icon: Icons.replay_rounded,
                        filled: true,
                        onTap: onRematch,
                      ),
                      const SizedBox(height: 12),
                      _button(
                        label: '離開',
                        icon: Icons.logout_rounded,
                        onTap: onLeave,
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

  Widget _playerRow(int i, {required bool isFastest}) {
    final player = engine.players[i];
    final stats = engine.stats[i];
    final seat = TableTheme.seatColor(player.colorIndex);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: seat,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: seat.withValues(alpha: 0.5), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: TableTheme.inkStrong,
                    ),
                  ),
                ),
                if (isFastest) ...[
                  const SizedBox(width: 6),
                  const Text('⚡', style: TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.turns == 0
                    ? '－'
                    : '${stats.turns} 手 · ${formatTableElapsed(stats.totalThink)}',
                style: AppType.digits(
                  fontSize: 14.5,
                  color: TableTheme.inkStrong,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                stats.turns == 0
                    ? '沒輪到'
                    : '平均 ${formatTableElapsed(stats.averageThink)}',
                style: AppType.digits(
                  fontSize: 11.5,
                  color: TableTheme.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    final fg = filled ? const Color(0xFF241A12) : TableTheme.inkSoft;
    return Material(
      color: filled ? TableTheme.warn : const Color(0x1AF6ECDD),
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : const BorderSide(color: TableTheme.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          playHaptic(HapticLevel.selection);
          onTap();
        },
        child: SizedBox(
          width: 230,
          height: filled ? 56 : 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: filled ? 24 : 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: filled ? 17 : 15.5,
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
