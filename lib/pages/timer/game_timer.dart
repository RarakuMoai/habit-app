import 'dart:math' as math;

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

/// 桌遊／下棋輪流計時器（計時頁的「遊戲」分頁卡片）：可設人數（2–8）、
/// 玩家命名與順序、每回合秒數或棋鐘累計（含 Fischer 每手增秒）。
///
/// 這裡只是薄殼 UI：戰局邏輯在 [GameClockController]（game/game_clock.dart）、
/// 副作用接線在 [GameSession]（game/game_session.dart）。跟其他三個計時器
/// 一樣常駐在計時頁的 IndexedStack；別的計時器「按開始」搶鎖時 session 會
/// 自動暫停（保留戰局），切到背景也暫停（前景工具）。
class GameTimer extends StatefulWidget {
  const GameTimer({super.key});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer> with TickerProviderStateMixin {
  late final GameSession _session;
  GameClockController get _c => _session.controller;
  bool _fullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    _session = GameSession(vsync: this);
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

  // 開始/換手/再來一局的統一入口；開始成功時處理「搶鎖提示」與
  // 「新開局自動進全螢幕」兩個卡片端的後續動作。
  void _tap() => _afterStart(_session.tapAnywhere());

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

  /// 全螢幕面對面模式：蓋滿整個 app（含底部分頁）。開著的期間這張卡片
  /// 整個被蓋住，build 回空殼別白工重繪；BGM 靜音進退場交給 session。
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
  // 引導。遊戲計時器一次要呈現圓環＋多位玩家＋控制，需要完整高度才好用。
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
              Column(
                children: [
                  const SizedBox(height: 30), // 留給右上設定鈕
                  GameStatusChip(controller: _c),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, rc) {
                          final size = math
                              .min(rc.maxWidth, rc.maxHeight)
                              .clamp(120.0, 250.0)
                              .toDouble();
                          return GameRing(
                            controller: _c,
                            size: size,
                            onTap: _tap,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GamePlayersStrip(controller: _c),
                  const SizedBox(height: 12),
                  _controlsRow(),
                  const SizedBox(height: 4),
                ],
              ),
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

  // 收合（兔咪面板展開）狀態：空間不夠擺整套遊戲計時，引導使用者展開面板。
  // 用 FittedBox 包住，再矮也不會爆版。
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
    final color = _c.finished
        ? kGameFinishedGreen
        : gamePlayerColor(_c.activeIndex);
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

  // 明顯的設定入口（待機才出現；開局後要先重設）
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

  // 回全螢幕入口（開局後出現，跟設定鈕互斥同一個位置）：離開全螢幕後想再
  // 傳裝置面對面玩，不用重設整局就能再進去。
  Widget _fullscreenEntry() {
    final color = _c.finished
        ? kGameFinishedGreen
        : gamePlayerColor(_c.activeIndex);
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
}
