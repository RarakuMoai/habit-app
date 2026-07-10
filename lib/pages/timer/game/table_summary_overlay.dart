// 對局結算面：兔咪陪大家一起看看這局完成了多少回合。
//
// 每人一列：回合數、總思考、平均；平均最快的玩家給「⚡ 最快」（正向、
// 不點名最慢的）。資料吃引擎的 TurnStats，進行中沒結算的半截回合不計。
// 卡片延續 app 的暖紙與鼠尾草色，數據只做正向回顧，不排行輸贏。
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

  static const Color _amber = Color(0xFFE5A94A);
  static const Color _amberInk = Color(0xFF8A5C13);

  @override
  Widget build(BuildContext context) {
    final fastest = _fastestIndex;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: ColoredBox(
          color: const Color(0x66718F7B),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  decoration: BoxDecoration(
                    color: AppSurfaces.card,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x338D6E63),
                        blurRadius: 26,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 92,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Image.asset(
                              'assets/mascot/core/tumi_happy.png',
                              width: 104,
                              height: 104,
                              fit: BoxFit.contain,
                              semanticLabel: '開心的兔咪',
                            ),
                            const Positioned(
                              right: 70,
                              top: 4,
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: 26,
                                color: _amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '這局玩得真棒！',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '大家一起完成了 ${engine.settledTurns} 手',
                        style: AppType.digits(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppInk.soft,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: AppSurfaces.fill,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < engine.players.length; i++)
                              _playerRow(i, isFastest: i == fastest),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _button(
                        label: '再來一局',
                        icon: Icons.replay_rounded,
                        filled: true,
                        onTap: onRematch,
                      ),
                      const SizedBox(height: 8),
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
    final detail = stats.turns == 0
        ? '這局還沒輪到'
        : '${stats.turns} 手 · 共 ${formatTableElapsed(stats.totalThink)} · '
              '平均 ${formatTableElapsed(stats.averageThink)}';
    return Semantics(
      container: true,
      label:
          '${player.name}，$detail'
          '${isFastest ? '，平均思考最快' : ''}'
          '${engine.flagFallIndex == i ? '，時間到' : ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: seat, shape: BoxShape.circle),
              child: Text(
                '${i + 1}',
                style: AppType.digits(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: AppInk.strong,
                          ),
                        ),
                        if (isFastest)
                          _miniBadge(
                            '⚡ 最快',
                            _amberInk,
                            _amber.withValues(alpha: 0.16),
                          ),
                        if (engine.flagFallIndex == i)
                          _miniBadge(
                            '時間到',
                            AppInk.danger,
                            AppInk.danger.withValues(alpha: 0.10),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: AppType.digits(fontSize: 12.5, color: AppInk.soft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    final fg = filled ? Colors.white : AppInk.strong;
    final button = Material(
      color: filled ? _amber : AppSurfaces.fill,
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : const BorderSide(color: AppSurfaces.divider),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          playHaptic(HapticLevel.selection);
          onTap();
        },
        child: SizedBox(
          width: double.infinity,
          height: filled ? 58 : 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: filled ? 22 : 19, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: filled ? 16.5 : 15,
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
      label: label,
      child: Tooltip(message: label, child: button),
    );
  }
}
