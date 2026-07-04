import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../widgets/timer_ring_painter.dart';
import 'game_clock.dart';

// 卡片與全螢幕頁共用的顯示元件。所有元件只吃 [GameClockController]，
// 在「自己所在畫面」的 context 下 build——舊版全螢幕頁借用被蓋住那張卡的
// context 導致 MediaQuery 抓錯來源的問題從結構上消失。

/// 遊戲計時器主色（跟專注番茄、運動青綠、節拍器紫明顯區分）。
const Color kGameAccent = Color(0xFF5B8DEF);

/// 決出勝負／完成時共用的慶祝色（狀態膠囊、主鈕、圓環、玩家卡都靠它統一）。
const Color kGameFinishedGreen = Color(0xFF66BB6A);

/// 每回合模式超時的警示紅。
const Color kGameOvertimeRed = Color(0xFFEF5350);

/// 玩家配色（依座位順序套用，輪到誰圓環就染成那個顏色）。
const List<Color> kGamePlayerColors = [
  Color(0xFFEF6F6C), // 紅
  Color(0xFF5B8DEF), // 藍
  Color(0xFF66BB6A), // 綠
  Color(0xFFFFB300), // 琥珀
  Color(0xFFAB7DF6), // 紫
  Color(0xFF26C6DA), // 青
  Color(0xFFFF8A65), // 橙
  Color(0xFFEC407A), // 粉
];

Color gamePlayerColor(int i) => kGamePlayerColors[i % kGamePlayerColors.length];

/// 目前狀態的主題色：勝負綠 > 超時紅 > 輪到誰的玩家色。
Color gameStateColor(GameClockController c) => c.finished
    ? kGameFinishedGreen
    : c.turnOvertime
    ? kGameOvertimeRed
    : gamePlayerColor(c.activeIndex);

/// 圓環中央與全螢幕的操作提示字。
String gameRingHint(GameClockController c) {
  if (c.running) return '點一下換手';
  if (c.finished) return '點一下再來';
  if (c.started) return '點一下繼續';
  return '點一下開始';
}

/// 收合（兔咪面板展開）時的一行摘要。
String gameCompactSummary(GameClockController c) {
  if (c.finished) {
    return c.winnerIndex >= 0 ? '${c.nameOf(c.winnerIndex)} 獲勝' : '平手';
  }
  if (c.started) {
    final time = formatGameClock(c.activePlayer.remaining);
    if (c.turnOvertime) return '${c.nameOf(c.activeIndex)} 超時 $time';
    return '${c.nameOf(c.activeIndex)} ${c.running ? '進行中' : '暫停中'} · $time';
  }
  if (c.mode == GameClockMode.turn) {
    return '每回合 ${formatGameDuration(c.turnSeconds)} · ${c.playerCount} 人';
  }
  final inc = c.increment > 0 ? ' · +${c.increment} 秒/手' : '';
  return '棋鐘 ${formatGameDuration(c.bankSeconds)}$inc · ${c.playerCount} 人';
}

/// 狀態膠囊：待機顯示玩法摘要、進行顯示「誰的回合」、結束顯示勝負。
class GameStatusChip extends StatelessWidget {
  final GameClockController controller;

  const GameStatusChip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final color = gameStateColor(c);
    final String text;
    final IconData icon;
    if (c.finished) {
      icon = Icons.emoji_events_rounded;
      text = c.winnerIndex >= 0 ? '${c.nameOf(c.winnerIndex)} 獲勝' : '平手';
    } else if (c.turnOvertime) {
      icon = Icons.warning_amber_rounded;
      text =
          '${c.nameOf(c.activeIndex)} 超時 ${formatGameClock(c.activePlayer.remaining)}';
    } else if (c.started) {
      icon = c.running ? Icons.play_arrow_rounded : Icons.pause_rounded;
      text = c.running
          ? '${c.nameOf(c.activeIndex)} 的回合'
          : '${c.nameOf(c.activeIndex)} 暫停中';
    } else {
      icon = c.mode == GameClockMode.turn
          ? Icons.timelapse_rounded
          : Icons.hourglass_bottom_rounded;
      text = c.mode == GameClockMode.turn
          ? '每回合 ${formatGameDuration(c.turnSeconds)} · ${c.playerCount} 人'
          : '棋鐘 ${formatGameDuration(c.bankSeconds)}'
                '${c.increment > 0 ? ' +${c.increment} 秒/手' : ''} · ${c.playerCount} 人';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: ConstrainedBox(
        key: ValueKey('$text${c.running}'),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 56,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 大圓環：平滑進度 + 中央玩家名/剩餘時間/操作提示。
/// [onTap] 傳 null 時不攔截點擊（全螢幕頁由整頁的手勢層接手）。
class GameRing extends StatelessWidget {
  final GameClockController controller;
  final double size;
  final VoidCallback? onTap;

  const GameRing({
    super.key,
    required this.controller,
    required this.size,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final overtime = c.turnOvertime;
    final ringColor = gameStateColor(c);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: c.ringProgress,
            builder: (context, t, child) => CustomPaint(
              painter: TimerRingPainter(progress: t, color: ringColor),
              child: child,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.nameOf(c.activeIndex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: size * 0.085,
                      fontWeight: FontWeight.w800,
                      color: ringColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatGameClock(c.activePlayer.remaining),
                    style: AppType.digits(
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w900,
                      color: overtime ? kGameOvertimeRed : AppInk.strong,
                    ),
                  ),
                  SizedBox(height: size * 0.02),
                  Text(
                    gameRingHint(c),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppInk.faint,
                    ),
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

/// 玩家列：每位一張小卡（編號圓章 + 名字 + 剩餘時間），輪到誰打亮、出局劃掉。
/// 待機時點某位＝指定先手。最多兩排自動排版，永不橫向溢出。
class GamePlayersStrip extends StatelessWidget {
  final GameClockController controller;

  const GamePlayersStrip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final count = controller.playerCount;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 340 && count <= 4
            ? math.min(count, 2)
            : count <= 4
            ? count
            : (count / 2).ceil();
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(width: w, child: _playerCard(i)),
          ],
        );
      },
    );
  }

  Widget _playerCard(int i) {
    final c = controller;
    final color = gamePlayerColor(i);
    final active = i == c.activeIndex && c.started && !c.finished;
    final winner = c.finished && i == c.winnerIndex;
    // 贏家沿用「輪到誰」的同一套暈影樣式，只是改用慶祝綠，跟狀態膠囊/主鈕一致。
    final highlighted = active || winner;
    final highlightColor = winner ? kGameFinishedGreen : color;
    final out = c.playerAt(i).flagged;
    // 玩家代幣：編號圓章（像桌遊玩家標記），出局轉灰。
    final token = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: out ? AppInk.faint : color,
        boxShadow: out
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: out
          ? const Icon(Icons.close_rounded, size: 14, color: Colors.white)
          : Text(
              '${i + 1}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
    );
    return GestureDetector(
      onTap: c.started
          ? null
          : () {
              c.pickFirstPlayer(i);
              playHaptic(HapticLevel.selection);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? highlightColor.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? highlightColor.withValues(alpha: 0.50)
                : const Color(0x0F46342B),
            width: highlighted ? 1.5 : 1,
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: highlightColor.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Row(
          children: [
            token,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.nameOf(i),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: out ? AppInk.faint : AppInk.strong,
                      decoration: out ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    out ? '時間到' : formatGameClock(c.playerAt(i).remaining),
                    style: AppType.digits(
                      fontWeight: FontWeight.w800,
                      color: highlighted ? highlightColor : AppInk.soft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
