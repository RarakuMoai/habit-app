import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import 'game_clock.dart';

// 卡片（對局大廳）與全螢幕對戰面共用的顯示元件。所有元件只吃
// [GameClockController]，在自己所在畫面的 context 下 build。
//
// 2026-07-04 UI 砍掉重做：遊戲計時器不再沿用番茄鐘的圓環語彙，改走
// 「棋鐘對戰面」——超大數字隔著桌子可讀、輪到誰整區染誰的顏色。

/// 遊戲計時器主色（跟專注番茄、運動青綠、節拍器紫明顯區分）。
const Color kGameAccent = Color(0xFF5B8DEF);

/// 決出勝負／完成時共用的慶祝色（狀態字、獲勝區、主鈕都靠它統一）。
const Color kGameFinishedGreen = Color(0xFF66BB6A);

/// 每回合模式超時的警示紅。
const Color kGameOvertimeRed = Color(0xFFEF5350);

/// 玩家配色（依座位順序套用，輪到誰畫面就染那個顏色）。
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

/// 點擊提示字（卡片與全螢幕同一套規則字）。
String gameTapHint(GameClockController c) {
  if (c.running) return '點一下換手';
  if (c.finished) return '點一下再來一局';
  if (c.started) return '點一下繼續';
  return '點一下開始';
}

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

/// 大廳的玩法摘要（每回合 30 秒 · 4 人／棋鐘 5 分 +2 秒/手 · 2 人）。
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

/// 玩家座位列：每位一張小卡（編號圓章 + 名字 +（可選）剩餘時間），
/// 輪到誰打亮、出局劃掉。待機時點某位＝指定先手。
/// 大廳用 [showTimes]=false（時間都是滿的，顯示只是噪音）。
class GamePlayersStrip extends StatelessWidget {
  final GameClockController controller;
  final bool showTimes;

  const GamePlayersStrip({
    super.key,
    required this.controller,
    this.showTimes = true,
  });

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
              SizedBox(width: w, child: _seatCard(i)),
          ],
        );
      },
    );
  }

  Widget _seatCard(int i) {
    final c = controller;
    final color = gamePlayerColor(i);
    final active = i == c.activeIndex && c.started && !c.finished;
    final winner = c.finished && i == c.winnerIndex;
    // 待機時「先手」沿用同一套打亮（讓大廳看得出誰先走）。
    final picked = !c.started && i == c.activeIndex;
    final highlighted = active || winner || picked;
    final highlightColor = winner ? kGameFinishedGreen : color;
    final out = c.playerAt(i).flagged;
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
                  if (showTimes) ...[
                    const SizedBox(height: 1),
                    Text(
                      out ? '時間到' : formatGameClock(c.playerAt(i).remaining),
                      style: AppType.digits(
                        fontWeight: FontWeight.w800,
                        color: highlighted ? highlightColor : AppInk.soft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全螢幕 2 人對戰的「半場」：一人一半，超大時間，輪到誰整半染誰的顏色。
/// 上半用 RotatedBox 轉 180° 面向對面玩家（由呼叫端包）。
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
    final picked = !c.started && index == c.activeIndex; // 待機：先手半場亮
    final out = p.flagged;
    final overtime = isActive && c.turnOvertime;
    final color = isWinner
        ? kGameFinishedGreen
        : overtime
        ? kGameOvertimeRed
        : gamePlayerColor(index);
    final lit = isActive || isWinner || picked;

    // 提示字：只出現在「點了有意義」的半場。
    String? hint;
    if (isWinner ||
        (c.finished && index == c.activeIndex && c.winnerIndex < 0)) {
      hint = '點一下再來一局';
    } else if (!c.started) {
      hint = picked ? '點一下開始' : null;
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
              ? color.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: lit
                ? color.withValues(alpha: 0.48)
                : const Color(0x14453229),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isWinner) ...[
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 22,
                        color: kGameFinishedGreen,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        c.nameOf(index),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: lit ? color : AppInk.soft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    out ? '出局' : formatGameClock(p.remaining),
                    maxLines: 1,
                    style: AppType.digits(
                      fontSize: 88,
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
                ),
                SizedBox(height: hint != null ? 2 : 0),
                if (hint != null)
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全螢幕 3 人以上的「大舞台」：目前玩家的名字＋超大時間佔滿視線焦點。
class GameStage extends StatelessWidget {
  final GameClockController controller;

  const GameStage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final color = gameStateColor(c);
    final overtime = c.turnOvertime;
    final title = c.finished ? gameStatusText(c) : c.nameOf(c.activeIndex);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.finished) ...[
              Icon(Icons.emoji_events_rounded, size: 30, color: color),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (!c.finished)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatGameClock(c.activePlayer.remaining),
              maxLines: 1,
              style: AppType.digits(
                fontSize: 110,
                fontWeight: FontWeight.w900,
                color: overtime ? kGameOvertimeRed : AppInk.strong,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          gameTapHint(c),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}
