import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';
import 'game_clock.dart';
import 'game_session.dart';
import 'game_settings_sheet.dart';
import 'game_widgets.dart';

/// 環桌對戰面：遊戲計時的本體，蓋滿整個 app（含底部分頁），
/// 手機平放桌子中央、大家一起用。
///
/// 2～8 人同一套版型：座位分成上下兩排，**上排整排旋轉 180° 面向對面的
/// 玩家**，每人一格自己的區。像實體棋鐘——待機時誰先點自己的區誰先走；
/// 進行中點自己的區＝換手（點別人的區只輕震，防誤觸）。中線控制列放
/// 退出／設定（待機）／上一位／暫停，兩邊玩家都搆得到。
///
/// 只依賴 [GameSession] 的公開 API；宿主卡片被移出 widget 樹時
/// （session dispose）會自己退場，不留殭屍參照。
class GameFullscreenPage extends StatefulWidget {
  final GameSession session;

  const GameFullscreenPage({super.key, required this.session});

  /// 進場淡入/退場淡出，蓋在 root navigator 上（含底部分頁）。
  static Route<void> route(GameSession session) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => GameFullscreenPage(session: session),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  @override
  State<GameFullscreenPage> createState() => _GameFullscreenPageState();
}

class _GameFullscreenPageState extends State<GameFullscreenPage> {
  GameSession get session => widget.session;
  GameClockController get c => session.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    session.addFullscreenCloser(_requestClose);
  }

  @override
  void dispose() {
    session.removeFullscreenCloser(_requestClose);
    if (!session.disposed) c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // session 被 dispose（宿主卡片移出樹）：下一幀自己退場。
  void _requestClose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _zoneTap(int i) => _showPausedOther(session.tapZone(i));

  // 搶鎖暫停了別的計時器：提示丟在這一頁（使用者看得到的畫面）上。
  void _showPausedOther(GameStartResult? result) {
    final msg = result?.pausedOtherMessage;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final n = c.playerCount;
    // 環桌座位：下排 0..bottom-1（正向），上排其餘（整排轉 180°）。
    // 旋轉會左右鏡射，座位順序自然變成「繞著桌子轉一圈」。
    final bottomCount = (n + 1) ~/ 2;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: RotatedBox(
                  quarterTurns: 2,
                  child: _zoneRow(bottomCount, n),
                ),
              ),
            ),
            _controlBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: _zoneRow(0, bottomCount),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneRow(int from, int to) {
    return Row(
      children: [
        for (var i = from; i < to; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GamePlayerZone(
                key: ValueKey('game_zone_$i'),
                controller: c,
                index: i,
                onTap: () => _zoneTap(i),
              ),
            ),
          ),
      ],
    );
  }

  // 中線控制列：退出／設定（待機才有；開局後要先重設）／上一位／暫停。
  Widget _controlBar() {
    final color = gameStateColor(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FsRoundButton(
            icon: Icons.close_rounded,
            color: AppInk.soft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 18),
          if (!c.started)
            _FsRoundButton(
              icon: Icons.tune_rounded,
              color: kGameAccent,
              onTap: () => showGameSettingsSheet(context, c),
            )
          else
            _FsRoundButton(
              icon: Icons.skip_previous_rounded,
              color: color,
              onTap: c.canUndo ? session.undo : null,
            ),
          const SizedBox(width: 18),
          _FsRoundButton(
            icon: c.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: color,
            onTap: c.finished
                ? null
                : c.running
                ? session.pause
                : () => _showPausedOther(session.start()),
          ),
        ],
      ),
    );
  }
}

// 對戰面的圓形控制鈕：白底浮凸，跟全 app 的按鈕語彙一致。
class _FsRoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _FsRoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Opacity(
      opacity: on ? 1 : 0.35,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: 24, color: on ? color : AppInk.faint),
          ),
        ),
      ),
    );
  }
}
