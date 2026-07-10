// 「遊戲」計時入口卡：兔咪遊戲桌的兩種面貌。
//
// 狀態定位（2026-07 UX 改版）：
// - 縮小（兔咪面板展開）＝快速面板：看目前設定、一鍵開局、需要才進設定。
// - 展開（兔咪面板收合）＝完整設定頁：玩家順位/時間/倒數提醒/常用組合
//   全部住在卡片裡（TableSetupPanel），底部固定「完成＋開始對局」。
// - 完整遊玩體驗在 push 進去的全螢幕桌面模式（TableStagePage）。
// - 不開對局也能「只骰骰子」：直達兔咪骰子屋（DiceTrayPage）。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/sfx_service.dart';
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
  // 完整設定頁需要的最小高度：Pro Max「面板展開」時內容區約 320，
  // 一定要落在門檻之下（否則設定頁被塞進小空間硬剪斷）；
  // 各機型「面板收合」後至少 ~410。
  static const double _compactHeight = 380;

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
        // 判斷縮小門檻時把鍵盤高度加回來：鍵盤彈出會把卡片壓過門檻，
        // 若因此切成縮小卡，設定頁 state（連同輸入對話框按確定後的
        // 存檔）會整個被銷毀——「常用玩家存不進去、改名無效、畫面
        // 捲回頂部」全是這條路（2026-07-10 修）。Scaffold 已吃掉
        // viewInsets，直接讀 View 原始值；且必須在 LayoutBuilder 的
        // builder 裡讀——GameTimer 是 const 建構，鍵盤出現時只有
        // 這個 builder 會因約束變化重跑，外層 build 不會。
        final view = View.of(context);
        final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
        if (box.maxHeight + keyboard < _compactHeight) return _buildCompact();
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
            onDice: _openDice,
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

  /// 完成鈕：中性 tonal——footer 只留一顆彩色 CTA（開始對局）。
  Widget _doneButton() {
    return Material(
      color: AppSurfaces.fill,
      shape: const StadiumBorder(side: BorderSide(color: AppSurfaces.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _collapseDone,
        child: const SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 20, color: AppInk.soft),
              SizedBox(width: 6),
              Text(
                '完成',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ],
          ),
        ),
      ),
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
                        '兔咪遊戲桌',
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
                  _compactChipButton(
                    icon: Icons.tune_rounded,
                    label: '設定',
                    onTap: _expandToSetup,
                  ),
                  const SizedBox(width: 8),
                  _compactChipButton(
                    icon: Icons.casino_rounded,
                    label: '骰子',
                    onTap: _openDice,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 160,
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

  Widget _compactChipButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppSurfaces.fill,
      shape: const StadiumBorder(side: BorderSide(color: AppSurfaces.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppInk.soft),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
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
