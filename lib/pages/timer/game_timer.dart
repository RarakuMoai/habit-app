// 「遊戲」計時入口卡：桌遊計時器的收納盒。
//
// 定位（照重建任務書）：入口卡只做摘要與引導，完整遊玩體驗在 push 進去
// 的全螢幕桌面模式（TableStagePage）。縮小狀態（兔咪面板展開）只顯示
// 摘要一行＋展開引導，不承擔操作。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/mascot.dart';
import '../../utils/sfx_service.dart';
import 'game/table_setup_sheet.dart';
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

  Future<void> _openSetup() async {
    final prefs = _prefs;
    if (prefs == null) return;
    playFeedback(SfxCue.tap);
    final updated = await showTableSetupSheet(context, prefs: prefs);
    if (!mounted) return;
    setState(() => _config = updated);
  }

  Future<void> _startGame() async {
    final prefs = _prefs;
    if (prefs == null) return;
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TableStagePage(config: _config),
      ),
    );
  }

  String get _timeSummary {
    if (_config.mode == TableGameMode.free) return '自由計時';
    final s = _config.turnSeconds;
    if (s < 60) return '每回合 $s 秒';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '每回合 $m 分' : '每回合 $m 分 $r 秒';
  }

  String get _oneLineSummary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · $_timeSummary';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight < _compactHeight) return _buildCompact();
        return _buildFull();
      },
    );
  }

  // ── 完整入口卡 ───────────────────────────────────────────

  Widget _buildFull() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: kGameAccent.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.casino_rounded,
                      color: kGameAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '桌遊計時器',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        '放桌中央・輪到誰點誰',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _summaryCard(),
              const SizedBox(height: 16),
              _startButton(),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openSetup,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text(
                  '玩家與時間',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 摘要卡：模式、時間、玩家一覽。
  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _summaryChip(
                icon: switch (_config.mode) {
                  TableGameMode.party => Icons.groups_rounded,
                  TableGameMode.chess => Icons.swap_vert_rounded,
                  TableGameMode.free => Icons.all_inclusive_rounded,
                },
                label: _config.mode.label,
              ),
              const SizedBox(width: 8),
              _summaryChip(
                icon: Icons.timer_outlined,
                label: _timeSummary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final p in _config.activePlayers) _playerTag(p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kGameAccent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kGameAccent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppInk.strong,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerTag(TablePlayer p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: TableTheme.seatColor(p.colorIndex),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppInk.soft,
            ),
          ),
        ),
      ],
    );
  }

  /// 開始鈕：一小塊深色絨布桌——按下去就是進入對局世界的門。
  Widget _startButton() {
    final enabled = _prefs != null;
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3C2D21), Color(0xFF241A12)],
          ),
          borderRadius: BorderRadius.circular(29),
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
                size: 26,
                color: TableTheme.inkStrong,
              ),
              const SizedBox(width: 8),
              Text(
                '開始對局',
                style: TextStyle(
                  fontSize: 17,
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

  // ── 縮小狀態：只做摘要與引導 ──────────────────────────────

  Widget _buildCompact() {
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
                  color: kGameAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.casino_rounded,
                  color: kGameAccent,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '桌遊計時器',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _oneLineSummary,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppInk.soft,
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: kGameAccent,
                shape: const StadiumBorder(),
                elevation: 2,
                shadowColor: kGameAccent,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: MascotPanelPrefs.requestCollapsed,
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
                          '展開開始對局',
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
}
