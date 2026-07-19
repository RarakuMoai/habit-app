// 「遊戲」計時入口卡：遊戲桌的準備畫面與底部設定選單。
//
// 狀態定位（2026-07 UX 改版）：
// - 預設＝與專注／運動／節拍器一致的準備畫面：看設定、一鍵開局。
// - 點右上「設定」後，從下方展開與其他計時工具一致的完整設定選單。
// - 完整遊玩體驗在 push 進去的全螢幕桌面模式（TableStagePage）。
// - 不開對局也能「只骰骰子」：直達兔咪骰子屋（DiceTrayPage）。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/timer_mode_frame.dart';
import '../../widgets/timer_ring_painter.dart';
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

  /// 從下方展開完整設定；一般調整即時儲存，關閉後由準備畫面顯示新摘要。
  Future<void> _openSettingsSheet() async {
    final prefs = _prefs;
    if (prefs == null) return;
    playFeedback(SfxCue.tap);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: kGameAccent.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 把手列與其他三個設定面板同款；關閉鈕收進面板標題卡右側，
                // 與專注／運動／節拍器「標題列右側關閉」同一個位置語彙。
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8DDD4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Expanded(
                  child: TableSetupPanel(
                    prefs: prefs,
                    onConfigChanged: (c) {
                      if (mounted) setState(() => _config = c);
                    },
                    onDice: _openDice,
                    onDone: () => Navigator.pop(sheetContext),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppSurfaces.divider)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kGameAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: const Text(
                        '完成',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _oneLineSummary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · '
      '${_config.timeSummary}';

  @override
  Widget build(BuildContext context) {
    return _buildReady();
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
        // 與其他模式同構的「左低頻／右高頻」滿排：左「玩家」進設定調人，
        // 右「骰子」是不開局也常用的工具。
        leading: TimerSecondaryAction(
          icon: Icons.groups_rounded,
          label: '玩家',
          onTap: _prefs == null ? null : _openSettingsSheet,
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
      topAction: TimerSettingsAction(
        color: kGameAccent,
        onTap: _prefs == null ? null : _openSettingsSheet,
      ),
    );
  }

  Widget _tableHero(double size) {
    final icon = switch (_config.mode) {
      TableGameMode.party => Icons.rotate_right_rounded,
      TableGameMode.chess => Icons.grid_view_rounded,
      TableGameMode.free => Icons.all_inclusive_rounded,
    };
    // 與專注／運動同一個圓環盤面（外徑、刻度、內盤畫法一致），
    // 遊戲桌沒有進度概念，progress 固定 0 只呈現盤面。
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kGameAccent.withValues(alpha: 0.16),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: CustomPaint(
          painter: const TimerRingPainter(progress: 0, color: kGameAccent),
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: kGameAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 28, color: kGameAccent),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '遊戲桌',
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

  // 下方摘要區：與專注方案／運動類別同款的白底膠囊（玩法／玩家／時間），
  // 點任一顆直接開設定選單，不再是純顯示的一條卡。
  Widget _configBar() {
    return SizedBox(
      height: 52,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _configChip(
                  Icons.videogame_asset_rounded,
                  '玩法',
                  _config.mode.label,
                ),
                const SizedBox(width: 8),
                _configChip(
                  Icons.groups_rounded,
                  '玩家',
                  '${_config.activePlayers.length} 人',
                ),
                const SizedBox(width: 8),
                _configChip(Icons.timer_outlined, '時間', _config.timeSummary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _configChip(IconData icon, String label, String value) {
    return GestureDetector(
      onTap: _prefs == null ? null : _openSettingsSheet,
      child: Container(
        constraints: const BoxConstraints(minWidth: 76, maxWidth: 108),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: AppCardStyle.hairline,
          boxShadow: AppShadows.flat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: kGameAccent),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
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
      ),
    );
  }
}
