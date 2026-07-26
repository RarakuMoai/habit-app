// 對局結算面：兔咪陪大家一起看看這局完成了多少回合。
//
// 每人一列：回合數、總思考、平均；平均最快的玩家給「⚡ 最快」（正向、
// 不點名最慢的）。資料吃引擎的 TurnStats，進行中沒結算的半截回合不計。
// 卡片走 app 本體的暖紙質感（同暫停層），數據只做正向回顧、不排輸贏。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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

  static const Color _amber = Color(0xFFE9A94E);
  static const Color _amberInk = Color(0xFFA8741F);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fastest = _fastestIndex;
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
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                      // 兔咪一起慶祝（特效照慣例 Flutter 端疊小星星）
                      SizedBox(
                        height: 96,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Image.asset(
                              'assets/mascot/core/tumi_happy.png',
                              width: 104,
                              height: 104,
                              fit: BoxFit.contain,
                              semanticLabel: l10n.sumHappyMascotSemantics,
                            ),
                            const Positioned(
                              right: 74,
                              top: 2,
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                                color: _amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.sumGameOver,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.sumPlayedHands(engine.settledTurns),
                        style: AppType.digits(
                          fontSize: 13.5,
                          color: AppInk.soft,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: AppSurfaces.fill,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < engine.players.length; i++)
                              _playerRow(l10n, i, isFastest: i == fastest),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _button(
                        label: l10n.sumPlayAgain,
                        icon: Icons.replay_rounded,
                        filled: true,
                        onTap: onRematch,
                      ),
                      const SizedBox(height: 8),
                      _button(
                        label: l10n.stgLeave,
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

  Widget _playerRow(AppLocalizations l10n, int i, {required bool isFastest}) {
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
            decoration: BoxDecoration(color: seat, shape: BoxShape.circle),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppInk.strong,
                    ),
                  ),
                ),
                if (isFastest) ...[
                  const SizedBox(width: 6),
                  _miniBadge(
                    l10n.sumFastest,
                    _amberInk,
                    _amber.withValues(alpha: 0.16),
                  ),
                ],
                if (engine.flagFallIndex == i) ...[
                  const SizedBox(width: 6),
                  _miniBadge(
                    l10n.gameTimeUp,
                    AppInk.danger,
                    AppInk.danger.withValues(alpha: 0.10),
                  ),
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
                    : l10n.sumHandsAndTime(
                        stats.turns,
                        formatTableElapsed(stats.totalThink),
                      ),
                style: AppType.digits(fontSize: 14, color: AppInk.strong),
              ),
              const SizedBox(height: 1),
              Text(
                stats.turns == 0
                    ? l10n.sumNotPlayed
                    : l10n.sumAverage(formatTableElapsed(stats.averageThink)),
                style: AppType.digits(fontSize: 11.5, color: AppInk.faint),
              ),
            ],
          ),
        ],
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
    // filled 用暖琥珀（跟獎盃同語調）：對局層的 CTA 走暖色，
    // 藍色留給 app 內設定頁的 CTA，深色桌上不出現冷色大塊。
    final fg = filled ? Colors.white : AppInk.strong;
    return Material(
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
          height: filled ? 52 : 46,
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
  }
}
