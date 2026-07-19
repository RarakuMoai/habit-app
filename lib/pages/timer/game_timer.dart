// 「遊戲」計時入口卡：兔咪遊戲桌的兩種面貌。
//
// 狀態定位（2026-07 UX 改版）：
// - 預設＝與專注／運動／節拍器一致的準備畫面：看設定、一鍵開局。
// - 點「設定」才進完整設定頁；設定狀態不再綁兔咪面板高度，鍵盤或版面改變
//   都不會銷毀正在編輯的 TableSetupPanel。
// - 完整遊玩體驗在 push 進去的全螢幕桌面模式（TableStagePage）。
// - 不開對局也能「只骰骰子」：直達兔咪骰子屋（DiceTrayPage）。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/timer_mode_frame.dart';
import 'game/dice_tray.dart';
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
  SharedPreferences? _prefs;
  TableTimerConfig _config = TableTimerConfig.fallback();
  bool _showSetup = false;

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

  /// 不開對局、只想骰骰子：直達兔咪骰子屋。
  Future<void> _openDice() async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DiceTrayPage(),
      ),
    );
  }

  /// 進入完整設定頁，同時收起兔咪面板騰出足夠空間。
  void _expandToSetup() {
    playFeedback(SfxCue.tap);
    setState(() => _showSetup = true);
    MascotPanelPrefs.requestCollapsed();
  }

  void _finishSetup() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    setState(() => _showSetup = false);
  }

  String get _oneLineSummary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · '
      '${_config.timeSummary}';

  @override
  Widget build(BuildContext context) {
    return _showSetup ? _buildSetup() : _buildReady();
  }

  // ── 完整設定頁 ───────────────────────────────────────────

  Widget _buildSetup() {
    final prefs = _prefs;
    if (prefs == null) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          child: TableSetupPanel(
            prefs: prefs,
            onConfigChanged: (c) => setState(() => _config = c),
            onDice: _openDice,
            onDone: _finishSetup,
          ),
        ),
        _footerBar(),
      ],
    );
  }

  // ── 共用準備畫面 ─────────────────────────────────────────

  Widget _buildReady() {
    return TimerModeFrame(
      heroBuilder: (context, size) => _tableHero(size),
      status: const TimerStatusPill(
        stateKey: 'ready',
        color: kGameAccent,
        icon: Icons.groups_rounded,
        label: '準備開局',
      ),
      progress: _playerDots(),
      controls: TimerControlCluster(
        accent: kGameAccent,
        primaryIcon: Icons.play_arrow_rounded,
        onPrimary: _prefs == null ? null : _startGame,
        leading: TimerSecondaryAction(
          icon: Icons.tune_rounded,
          label: '設定',
          onTap: _expandToSetup,
        ),
        trailing: TimerSecondaryAction(
          icon: Icons.casino_rounded,
          label: '骰子',
          onTap: _openDice,
        ),
      ),
      statusLine: Text(
        _oneLineSummary,
        style: const TextStyle(
          color: AppInk.soft,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      quickPicker: _configBar(),
    );
  }

  Widget _tableHero(double size) {
    final icon = switch (_config.mode) {
      TableGameMode.party => Icons.rotate_right_rounded,
      TableGameMode.chess => Icons.grid_view_rounded,
      TableGameMode.free => Icons.all_inclusive_rounded,
    };
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8E8), Color(0xFFE5F2E8)],
          ),
          border: Border.all(color: kGameAccent.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: kGameAccent.withValues(alpha: 0.18),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.035),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: kGameAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: kGameAccent),
                ),
                const SizedBox(height: 9),
                const Text(
                  '兔咪遊戲桌',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_config.activePlayers.length} 位玩家',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kGameAccentDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerDots() {
    final count = _config.activePlayers.length;
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TableTheme.seatColor(
                  _config.activePlayers[i].colorIndex,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _configBar() {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.flat,
      ),
      child: Row(
        children: [
          Expanded(
            child: _configFact(
              Icons.videogame_asset_rounded,
              '玩法',
              _config.mode.label,
            ),
          ),
          const VerticalDivider(
            width: 12,
            indent: 10,
            endIndent: 10,
            color: AppSurfaces.divider,
          ),
          Expanded(
            child: _configFact(
              Icons.groups_rounded,
              '玩家',
              '${_config.activePlayers.length} 人',
            ),
          ),
          const VerticalDivider(
            width: 12,
            indent: 10,
            endIndent: 10,
            color: AppSurfaces.divider,
          ),
          Expanded(
            child: _configFact(Icons.timer_outlined, '時間', _config.timeSummary),
          ),
        ],
      ),
    );
  }

  Widget _configFact(IconData icon, String label, String value) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: kGameAccent),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppInk.soft,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 底部固定列只留真正會推進流程的「開始對局」。
  Widget _footerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppSurfaces.divider)),
      ),
      child: _startButton(height: 54),
    );
  }

  /// 開始鈕：頁面唯一的實色 CTA（遊戲主色）。
  /// 原「深色絨布門」在暖奶油底上讀成死黑色塊，2026-07-08 截圖自查後撤掉。
  Widget _startButton({required double height, double fontSize = 16.5}) {
    final enabled = _prefs != null;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: height,
        decoration: BoxDecoration(
          color: enabled ? kGameAccent : AppSurfaces.fill,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: kGameAccent.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? _startGame : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 24,
                color: enabled ? Colors.white : AppInk.iconFaint,
              ),
              const SizedBox(width: 6),
              Text(
                '開始對局',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: enabled ? Colors.white : AppInk.iconFaint,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
