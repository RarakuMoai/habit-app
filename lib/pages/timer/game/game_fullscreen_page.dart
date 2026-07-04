import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import 'game_clock.dart';
import 'game_session.dart';
import 'game_widgets.dart';

/// 全螢幕對戰面：蓋滿整個 app（含底部分頁），把裝置放在桌上大家一起用。
///
/// - 2 人＝棋鐘式上下分半：上半旋轉 180° 面向對面玩家，**點自己那半＝換手**
///   （不用搶同一顆鈕、也不會誤觸對方），中間一條控制列（退出/上一位/暫停）。
/// - 3 人以上＝大舞台：目前玩家名字＋超大時間佔滿焦點，點畫面任一處換手，
///   底下座位列看順序與剩餘時間。
///
/// 只依賴 [GameSession] 的公開 API：監聽 controller 重繪、呼叫意圖方法，
/// 跟卡片畫面共用同一個資料來源。宿主卡片被移出 widget 樹時（session
/// dispose）會自己退場，不留殭屍參照。
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

  // 分半模式點某一半：進行中只有「輪到的那一半」能換手（點對面＝輕震提示，
  // 防止誤觸幫別人走棋）；暫停/待機/勝負則點哪裡都是繼續/開始/再來一局。
  void _zoneTap(int i) {
    if (c.running) {
      if (i == c.activeIndex) {
        session.pass();
      } else {
        playHaptic(HapticLevel.light);
      }
      return;
    }
    _showPausedOther(session.tapAnywhere());
  }

  // 大舞台（3 人以上）：點畫面任一處＝換手/繼續/再來一局。
  void _stageTap() => _showPausedOther(session.tapAnywhere());

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
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(child: c.playerCount == 2 ? _duel() : _stage()),
    );
  }

  // ── 2 人：棋鐘分半 ──

  Widget _duel() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            // 面向對面的玩家：整半場轉 180°，傳裝置/放桌上都直接可讀。
            child: RotatedBox(
              quarterTurns: 2,
              child: GamePlayerZone(
                key: const ValueKey('game_zone_1'),
                controller: c,
                index: 1,
                onTap: () => _zoneTap(1),
              ),
            ),
          ),
        ),
        _duelControlBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: GamePlayerZone(
              key: const ValueKey('game_zone_0'),
              controller: c,
              index: 0,
              onTap: () => _zoneTap(0),
            ),
          ),
        ),
      ],
    );
  }

  // 中線控制列：退出／上一位／暫停。不旋轉（兩邊玩家都搆得到）。
  Widget _duelControlBar() {
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
          const SizedBox(width: 20),
          _FsRoundButton(
            icon: Icons.skip_previous_rounded,
            color: color,
            onTap: c.canUndo ? session.undo : null,
          ),
          const SizedBox(width: 20),
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

  // ── 3 人以上：大舞台＋座位列 ──

  Widget _stage() {
    return Stack(
      children: [
        GestureDetector(
          key: const ValueKey('game_stage'),
          behavior: HitTestBehavior.opaque,
          onTap: _stageTap,
          child: Column(
            children: [
              const SizedBox(height: 56), // 留給左上退出鈕
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GameStage(controller: c),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GamePlayersStrip(controller: c),
              ),
              const SizedBox(height: 96), // 留給底部上一位/暫停列
            ],
          ),
        ),
        Positioned(
          top: 4,
          left: 12,
          child: _FsRoundButton(
            icon: Icons.close_rounded,
            color: AppInk.soft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FsRoundButton(
                icon: Icons.skip_previous_rounded,
                color: gameStateColor(c),
                onTap: c.canUndo ? session.undo : null,
              ),
              const SizedBox(width: 28),
              _FsRoundButton(
                icon: c.running
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: gameStateColor(c),
                big: true,
                onTap: c.finished
                    ? null
                    : c.running
                    ? session.pause
                    : () => _showPausedOther(session.start()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 全螢幕頁專用的圓形控制鈕：白底浮凸，跟卡片的側鈕/主鈕同一套視覺語言。
class _FsRoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool big;

  const _FsRoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final size = big ? 76.0 : 52.0;
    return Opacity(
      opacity: on ? 1 : 0.35,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: big ? 3 : 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(
              icon,
              size: big ? 34 : 24,
              color: on ? color : AppInk.faint,
            ),
          ),
        ),
      ),
    );
  }
}
