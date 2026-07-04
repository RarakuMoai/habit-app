import 'package:flutter/material.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/sfx_service.dart';
import 'game/game_clock.dart';
import 'game/game_fullscreen_page.dart';
import 'game/game_session.dart';
import 'game/game_widgets.dart';

export 'game/game_widgets.dart' show kGameAccent;

/// 桌遊／下棋輪流計時器（計時頁的「遊戲」分頁）。
///
/// 2026-07-04 體驗重做：這張卡片**只是入口**——圖示＋玩法摘要＋玩家色點＋
/// 大顆「進入對戰」。遊戲本體（設定、開局、換手）100% 活在全螢幕的
/// 環桌對戰面（game/game_fullscreen_page.dart），不再有卡片裡的半殘操作面。
/// 對局進行中退回卡片時顯示實況一行＋回到對戰。
///
/// 邏輯在 [GameClockController]、副作用接線在 [GameSession]；被別的計時器
/// 搶鎖或切到背景時由 session 自動暫停（保留戰局）。
class GameTimer extends StatefulWidget {
  const GameTimer({super.key});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer> {
  late final GameSession _session;
  GameClockController get _c => _session.controller;
  bool _fullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    _session = GameSession();
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _session.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 進入全螢幕對戰面。開著的期間這張卡片整個被蓋住，build 回空殼別白工
  /// 重繪；BGM 靜音進退場交給 session。
  Future<void> _enterFullscreen() async {
    if (_fullscreenOpen) return;
    playFeedback(SfxCue.tap, haptic: HapticLevel.medium);
    setState(() => _fullscreenOpen = true);
    _session.onFullscreenEntered();
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(GameFullscreenPage.route(_session));
    // 卡片已被移出樹（session 也 dispose 了）就不用收尾，BGM 還原在
    // session.dispose 裡處理過。
    if (!mounted) return;
    setState(() => _fullscreenOpen = false);
    _session.onFullscreenExited();
  }

  // ── UI ──

  // 低於這個高度（兔咪面板展開、空間被壓縮）改顯示展開引導。
  static const double _kMinFullHeight = 300;

  @override
  Widget build(BuildContext context) {
    if (!_c.loaded) return const SizedBox.shrink();
    if (_fullscreenOpen) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight < _kMinFullHeight) {
          return _compactPrompt();
        }
        return _launcher();
      },
    );
  }

  // 入口卡：遊戲的「門面」。待機給玩法摘要＋玩家預覽；進行中給實況。
  Widget _launcher() {
    final started = _c.started;
    final color = started ? gameStateColor(_c) : kGameAccent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.casino_rounded, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              '遊戲計時器',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppInk.strong,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              started ? gameStatusText(_c) : '桌遊、下棋的輪流計時',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: started ? color : AppInk.soft,
              ),
            ),
            const SizedBox(height: 16),
            if (started && !_c.finished)
              Text(
                formatGameClock(_c.activePlayer.remaining),
                style: AppType.digits(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: _c.turnOvertime ? kGameOvertimeRed : AppInk.strong,
                ),
              )
            else if (_c.finished)
              const Icon(
                Icons.emoji_events_rounded,
                size: 44,
                color: kGameFinishedGreen,
              )
            else ...[
              GameSeatDots(controller: _c),
              const SizedBox(height: 6),
              Text(
                gameSetupSummary(_c),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppInk.faint,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _enterButton(color, started),
            if (started) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _session.reset,
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text(
                  '重設對局',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(foregroundColor: AppInk.soft),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _enterButton(Color color, bool started) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: color,
        shape: const StadiumBorder(),
        elevation: 3,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _enterFullscreen,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                started
                    ? Icons.fullscreen_rounded
                    : Icons.sports_esports_rounded,
                size: 24,
                color: Colors.white,
              ),
              const SizedBox(width: 7),
              Text(
                started ? '回到對戰' : '進入對戰',
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 收合（兔咪面板展開）狀態：空間不夠，引導使用者展開面板。
  Widget _compactPrompt() {
    const accent = kGameAccent;
    final sub = gameCompactSummary(_c);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.casino_rounded,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '遊戲計時器',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppInk.soft,
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: accent,
                shape: const StadiumBorder(),
                elevation: 2,
                shadowColor: accent.withValues(alpha: 0.4),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _expandPanel,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '展開使用',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 收起兔咪面板（openValue→0）讓計時區展開到完整高度。
  void _expandPanel() {
    playHaptic(HapticLevel.light);
    MascotPanelPrefs.requestCollapsed();
  }
}
