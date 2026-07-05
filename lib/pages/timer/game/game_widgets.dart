import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';
import 'game_clock.dart';

// 遊戲計時器的共用顯示元件。
//
// 2026-07-04 體驗重做：卡片只是入口，遊戲本體 100% 活在全螢幕「環桌對戰面」
// ——所有人數都是分半 grid（上排旋轉 180° 面向對面玩家），每人一格自己的區，
// 像實體棋鐘一樣「誰先點誰先走」。

/// 遊戲計時器主色（跟專注番茄、運動青綠、節拍器紫明顯區分）。
const Color kGameAccent = Color(0xFF5B8DEF);

/// 決出勝負／完成時共用的慶祝色。
const Color kGameFinishedGreen = Color(0xFF66BB6A);

/// 每回合模式超時的警示紅。
const Color kGameOvertimeRed = Color(0xFFEF5350);

/// 玩家配色（依座位順序套用，輪到誰那一格就染誰的顏色）。
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

/// 一行狀態文字：誰的回合／暫停／超時／勝負；待機時給玩法摘要。
String gameStatusText(GameClockController c) {
  if (c.finished) {
    return c.winnerIndex >= 0 ? '${c.nameOf(c.winnerIndex)} 獲勝' : '平手';
  }
  if (c.turnOvertime) {
    return '${c.nameOf(c.activeIndex)} 超時 '
        '${formatGameClock(c.activePlayer.remaining)}';
  }
  if (c.started) {
    return c.running
        ? '${c.nameOf(c.activeIndex)} 的回合'
        : '${c.nameOf(c.activeIndex)} 暫停中';
  }
  return gameSetupSummary(c);
}

/// 玩法摘要（每回合 30 秒 · 4 人／棋鐘 5 分 +2 秒/手 · 2 人）。
String gameSetupSummary(GameClockController c) {
  if (c.mode == GameClockMode.turn) {
    return '每回合 ${formatGameDuration(c.turnSeconds)} · ${c.playerCount} 人';
  }
  final inc = c.increment > 0 ? ' +${c.increment} 秒/手' : '';
  return '棋鐘 ${formatGameDuration(c.bankSeconds)}$inc · ${c.playerCount} 人';
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
  return gameSetupSummary(c);
}

/// 入口卡的玩家預覽：一排編號色章（幾個人、什麼顏色，一眼看懂）。
class GameSeatDots extends StatelessWidget {
  final GameClockController controller;

  const GameSeatDots({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < controller.playerCount; i++)
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gamePlayerColor(i),
              boxShadow: [
                BoxShadow(
                  color: gamePlayerColor(i).withValues(alpha: 0.35),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// 對戰面的一格：一位玩家的專屬區。超大時間、輪到誰整格染誰的顏色。
/// 待機時每格都是「點一下由你開始」——像實體棋鐘，誰先點誰先走。
class GamePlayerZone extends StatelessWidget {
  final GameClockController controller;
  final int index;
  final VoidCallback onTap;

  const GamePlayerZone({
    super.key,
    required this.controller,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.playerAt(index);
    final isActive = c.started && !c.finished && index == c.activeIndex;
    final isWinner = c.finished && index == c.winnerIndex;
    final out = p.flagged;
    final overtime = isActive && c.turnOvertime;
    final color = isWinner
        ? kGameFinishedGreen
        : overtime
        ? kGameOvertimeRed
        : gamePlayerColor(index);
    final lit = isActive || isWinner;

    String? hint;
    if (c.finished) {
      if (isWinner || c.winnerIndex < 0) hint = '點一下再來一局';
    } else if (!c.started) {
      hint = '點一下由你開始';
    } else if (isActive) {
      hint = c.running ? '點一下換手' : '點一下繼續';
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: lit
              ? color.withValues(alpha: 0.15)
              : out
              ? const Color(0xFFF3EEE8)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: lit ? color.withValues(alpha: 0.5) : const Color(0x14453229),
            width: lit ? 2 : 1,
          ),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : AppShadows.flat,
        ),
        child: Center(
          // 內容隨格子等比撐大（不只縮小）：2 人時半個螢幕的格子要配超大數字，
          // 桌面隔遠可讀；8 人的窄格則自動縮到剛好。字級只是比例基準。
          // 視覺層級：輪到的人最大、等待中縮小讓位、待機中等（每格都是開始鈕）。
          child: FractionallySizedBox(
            widthFactor: lit ? 0.84 : (c.started ? 0.58 : 0.72),
            heightFactor: lit ? 0.7 : (c.started ? 0.48 : 0.6),
            child: FittedBox(
              // 預設 contain：等比放大到塞滿 84%×70% 的格內空間
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWinner) ...[
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 20,
                          color: kGameFinishedGreen,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        c.nameOf(index),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: out ? AppInk.faint : gamePlayerColor(index),
                          decoration: out ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    out ? '出局' : formatGameClock(p.remaining),
                    style: AppType.digits(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: out
                          ? AppInk.faint
                          : overtime
                          ? kGameOvertimeRed
                          : lit
                          ? AppInk.strong
                          : AppInk.soft,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: (lit ? color : AppInk.faint).withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
