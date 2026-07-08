// 「遊戲」計時入口卡：桌遊計時器的兩種面貌。
//
// 狀態定位（2026-07 UX 改版）：
// - 縮小（兔咪面板展開）＝快速面板：看目前設定、一鍵開局、需要才進設定。
// - 展開（兔咪面板收合）＝完整設定頁：玩家順位/時間/倒數提醒/常用組合
//   全部住在卡片裡（TableSetupPanel），底部固定「完成＋開始對局」。
// - 完整遊玩體驗在 push 進去的全螢幕桌面模式（TableStagePage）。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/sfx_service.dart';
import 'game/table_setup_panel.dart';
import 'game/table_stage_page.dart';
import 'game/table_store.dart';
import 'game/table_timer_models.dart';
import 'game/table_timer_theme.dart';

export 'game/table_timer_theme.dart' show kGameAccent;

class GameTimer extends StatefulWidget {
  const GameTimer({super.key});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer> {
  static const double _compactHeight = 280;

  SharedPreferences? _prefs;
  TableTimerConfig _config = TableTimerConfig.fallback();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _config = TableStore.loadConfig(p);
      });
    });
  }

  Future<void> _startGame() async {
    if (_prefs == null) return;
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TableStagePage(config: _config),
      ),
    );
  }

  /// 縮小狀態的「調整設定」：把卡片拉開＝進入完整設定頁。
  void _expandToSetup() {
    playFeedback(SfxCue.tap);
    MascotPanelPrefs.requestCollapsed();
  }

  /// 展開狀態的「完成」：設定收工，收回縮小的快速面板。
  void _collapseDone() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    MascotPanelPrefs.requestExpanded();
  }

  String get _oneLineSummary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · '
      '${_config.timeSummary}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight < _compactHeight) return _buildCompact();
        return _buildFull();
      },
    );
  }

  // ── 展開狀態：完整設定頁 ──────────────────────────────────

  Widget _buildFull() {
    final prefs = _prefs;
    if (prefs == null) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          child: TableSetupPanel(
            prefs: prefs,
            onConfigChanged: (c) => setState(() => _config = c),
          ),
        ),
        _footerBar(),
      ],
    );
  }

  /// 底部固定列：設定完成的兩個出口——收起、或直接開局。
  Widget _footerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppSurfaces.divider)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _doneButton()),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: _startButton(height: 54)),
        ],
      ),
    );
  }

  Widget _doneButton() {
    return Material(
      color: kGameAccent.withValues(alpha: 0.10),
      shape: StadiumBorder(
        side: BorderSide(color: kGameAccent.withValues(alpha: 0.30)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _collapseDone,
        child: const SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 20, color: kGameAccent),
              SizedBox(width: 6),
              Text(
                '完成',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: kGameAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 開始鈕：一小塊深色絨布桌——按下去就是進入對局世界的門。
  Widget _startButton({required double height, double fontSize = 16.5}) {
    final enabled = _prefs != null;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3C2D21), Color(0xFF241A12)],
          ),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: const Color(0x33F6ECDD)),
          boxShadow: AppShadows.card,
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? _startGame : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 24,
                color: TableTheme.inkStrong,
              ),
              const SizedBox(width: 6),
              Text(
                '開始對局',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: enabled ? TableTheme.inkStrong : TableTheme.inkFaint,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 縮小狀態：快速面板（看設定、直接開局）──────────────────

  Widget _buildCompact() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/tabs/game_timer.png',
                    width: 48,
                    height: 48,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '桌遊計時器',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _oneLineSummary,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _compactSetupButton(),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 168,
                    child: _startButton(height: 46, fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactSetupButton() {
    return Material(
      color: AppSurfaces.fill,
      shape: const StadiumBorder(side: BorderSide(color: AppSurfaces.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _expandToSetup,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 18, color: AppInk.soft),
                SizedBox(width: 6),
                Text(
                  '設定',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
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
