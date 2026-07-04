import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_style.dart';
import 'game_clock.dart';
import 'game_session.dart';
import 'game_widgets.dart';

/// 全螢幕面對面對局頁：蓋滿整個 app（含底部分頁），畫面任一處＝換手，
/// 方便桌遊/棋類傳裝置給下一位。
///
/// 只依賴 [GameSession] 的公開 API：監聽 controller 重繪、呼叫意圖方法，
/// 跟卡片畫面天生同步（同一個資料來源），不再有舊版偷讀私有 State +
/// 手動世代計數器的同步問題。宿主卡片被移出 widget 樹時（session dispose）
/// 會自己退場，不留殭屍參照。
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

  void _tapAnywhere() {
    final result = session.tapAnywhere();
    _showPausedOther(result);
  }

  void _resume() => _showPausedOther(session.start());

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
    final color = gameStateColor(c);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 圓環不自己收點擊（onTap: null），整頁由這層統一接手，
              // 畫面任一處點下去效果都一樣（換手/再來/繼續）。
              onTap: _tapAnywhere,
              child: Column(
                children: [
                  const SizedBox(height: 56), // 留給左上退出鈕
                  GameStatusChip(controller: c),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final size =
                              (math.min(box.maxWidth, box.maxHeight) * 0.82)
                                  .clamp(200.0, 340.0)
                                  .toDouble();
                          return GameRing(controller: c, size: size);
                        },
                      ),
                    ),
                  ),
                  GamePlayersStrip(controller: c),
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
                    color: color,
                    onTap: c.canUndo ? session.undo : null,
                  ),
                  const SizedBox(width: 28),
                  _FsRoundButton(
                    icon: c.running
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: color,
                    big: true,
                    onTap: c.finished
                        ? null
                        : c.running
                        ? session.pause
                        : _resume,
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

// 全螢幕頁專用的圓形控制鈕：白底浮凸，跟一般畫面的側鈕/主鈕同一套視覺語言，
// 只是尺寸配合全螢幕操作距離放大一階。
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
    final size = big ? 76.0 : 56.0;
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
