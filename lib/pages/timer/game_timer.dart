import 'package:flutter/material.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import 'game/game_clock.dart';
import 'game/game_fullscreen_page.dart';
import 'game/game_session.dart';
import 'game/game_settings_sheet.dart';
import 'game/game_widgets.dart';

export 'game/game_widgets.dart' show kGameAccent;

/// 桌遊／下棋輪流計時器（計時頁的「遊戲」分頁卡片）。
///
/// 2026-07-04 UI 重做：卡片不再放和番茄鐘同款的圓環，而是「對局大廳」——
/// 玩法摘要＋玩家席次（點選指定先手）＋大顆開始鈕；開局自動進全螢幕對戰面
/// （2 人棋鐘分半／3 人以上大舞台，見 game/game_fullscreen_page.dart）。
/// 對局中退回卡片時顯示即時實況與控制。
///
/// 邏輯在 [GameClockController]、副作用接線在 [GameSession]；跟其他三個
/// 計時器一樣常駐在計時頁的 IndexedStack，被別的計時器搶鎖或切到背景時
/// 由 session 自動暫停（保留戰局）。
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

  void _afterStart(GameStartResult? result) {
    if (result == null || !mounted) return;
    final msg = result.pausedOtherMessage;
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
    // 開新局才自動進全螢幕；暫停後按繼續不強迫跳轉。
    if (result.freshStart) _enterFullscreen();
  }

  /// 全螢幕對戰面：蓋滿整個 app（含底部分頁）。開著的期間這張卡片整個
  /// 被蓋住，build 回空殼別白工重繪；BGM 靜音進退場交給 session。
  Future<void> _enterFullscreen() async {
    if (_fullscreenOpen) return;
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

  // 計時區低於這個高度（＝兔咪面板展開、空間被壓縮）就不硬塞，改顯示展開
  // 引導。大廳一次要呈現摘要＋席次＋開始鈕，需要完整高度才好用。
  static const double _kMinFullHeight = 380;

  @override
  Widget build(BuildContext context) {
    if (!_c.loaded) return const SizedBox.shrink();
    if (_fullscreenOpen) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight < _kMinFullHeight) {
          return _compactPrompt();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Stack(
            children: [
              _c.started ? _liveView() : _lobbyView(),
              if (!_c.started)
                Positioned(top: 0, right: 0, child: _settingsEntry())
              else
                Positioned(top: 0, right: 0, child: _fullscreenEntry()),
            ],
          ),
        );
      },
    );
  }

  // ── 對局大廳（待機）──

  Widget _lobbyView() {
    return Column(
      children: [
        const SizedBox(height: 44), // 留給右上設定鈕
        _setupCard(),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                GamePlayersStrip(controller: _c, showTimes: false),
                const SizedBox(height: 8),
                const Text(
                  '點選玩家可指定先手',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppInk.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _startButton(),
        const SizedBox(height: 4),
      ],
    );
  }

  // 玩法摘要卡：一眼看懂本局規則，點了直接進設定。
  Widget _setupCard() {
    const color = kGameAccent;
    final turn = _c.mode == GameClockMode.turn;
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showGameSettingsSheet(context, _c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  turn
                      ? Icons.timelapse_rounded
                      : Icons.hourglass_bottom_rounded,
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn ? '每回合計時' : '棋鐘（總時間）',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      gameSetupSummary(_c),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppInk.soft,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppInk.iconFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _startButton() {
    const color = kGameAccent;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: color,
        shape: const StadiumBorder(),
        elevation: 3,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _afterStart(_session.start()),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '開始對局',
                style: TextStyle(
                  fontSize: 17,
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

  // ── 對局實況（已開局，從全螢幕退回時的卡片視圖）──

  Widget _liveView() {
    final color = gameStateColor(_c);
    return Column(
      children: [
        const SizedBox(height: 44), // 留給右上全螢幕鈕
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gameStatusText(_c),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                if (_c.finished)
                  Icon(
                    Icons.emoji_events_rounded,
                    size: 56,
                    color: kGameFinishedGreen,
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatGameClock(_c.activePlayer.remaining),
                      maxLines: 1,
                      style: AppType.digits(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: _c.turnOvertime
                            ? kGameOvertimeRed
                            : AppInk.strong,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        GamePlayersStrip(controller: _c),
        const SizedBox(height: 12),
        _controlsRow(),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _controlsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _sideButton(
          icon: Icons.replay_rounded,
          label: '重設',
          onTap: _session.reset,
          faded: !_c.started,
        ),
        const SizedBox(width: 22),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mainButton(),
            const SizedBox(height: _sideLabelGap + _sideLabelHeight),
          ],
        ),
        const SizedBox(width: 22),
        _sideButton(
          icon: Icons.skip_next_rounded,
          label: '下一位',
          onTap: _session.pass,
          faded: !_c.running,
        ),
      ],
    );
  }

  Widget _mainButton() {
    final color = gameStateColor(_c);
    final icon = _c.finished
        ? Icons.replay_rounded
        : _c.running
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    const size = 76.0;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (_c.finished) {
              _session.reset();
            } else if (_c.running) {
              _session.pause();
            } else {
              _afterStart(_session.start());
            }
          },
          child: Icon(icon, size: size * 0.46, color: Colors.white),
        ),
      ),
    );
  }

  static const double _sideLabelGap = 5;
  static const double _sideLabelHeight = 15;

  Widget _sideButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool faded,
  }) {
    const size = 52.0;
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 1,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: faded ? null : onTap,
                child: Icon(icon, size: 24, color: AppInk.soft),
              ),
            ),
          ),
          const SizedBox(height: _sideLabelGap),
          SizedBox(
            height: _sideLabelHeight,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 右上入口（待機＝設定；開局後＝回全螢幕）──

  Widget _settingsEntry() {
    return Material(
      color: kGameAccent,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: kGameAccent.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showGameSettingsSheet(context, _c),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '遊戲設定',
                style: TextStyle(
                  fontSize: 13,
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

  Widget _fullscreenEntry() {
    final color = gameStateColor(_c);
    return Material(
      color: color,
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _enterFullscreen,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fullscreen_rounded, size: 18, color: Colors.white),
              SizedBox(width: 5),
              Text(
                '全螢幕',
                style: TextStyle(
                  fontSize: 13,
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

  // ── 收合（兔咪面板展開）狀態：引導使用者展開面板 ──

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
