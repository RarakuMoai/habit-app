// Codex 版「兔咪遊戲桌」入口。
//
// 快速狀態只顯示上次設定、骰子與開始；完整狀態用三步式設定。
// 兩種狀態都能直接開局，不要求使用者理解面板收合機制。
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
  static const double _compactHeight = 390;

  SharedPreferences? _prefs;
  TableTimerConfig _config = TableTimerConfig.fallback();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _config = TableStore.loadConfig(prefs);
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

  Future<void> _openDice() async {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DiceTrayPage(),
      ),
    );
  }

  void _showSetup() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    MascotPanelPrefs.requestCollapsed();
  }

  void _hideSetup() {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    MascotPanelPrefs.requestExpanded();
  }

  String get _summary =>
      '${_config.mode.label} · ${_config.activePlayers.length} 人 · '
      '${_config.timeSummary}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < _compactHeight;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: compact
              ? _CompactGameHome(
                  key: const ValueKey('game-compact'),
                  summary: _summary,
                  ready: _prefs != null,
                  onSetup: _showSetup,
                  onDice: _openDice,
                  onStart: _startGame,
                )
              : _buildFull(),
        );
      },
    );
  }

  Widget _buildFull() {
    final prefs = _prefs;
    if (prefs == null) {
      return const Center(child: CircularProgressIndicator(color: kGameAccent));
    }
    return Column(
      key: const ValueKey('game-full'),
      children: [
        Expanded(
          child: TableSetupPanel(
            prefs: prefs,
            onConfigChanged: (config) => setState(() => _config = config),
          ),
        ),
        _FullActionDock(
          summary: _summary,
          onDone: _hideSetup,
          onDice: _openDice,
          onStart: _startGame,
        ),
      ],
    );
  }
}

class _CompactGameHome extends StatelessWidget {
  final String summary;
  final bool ready;
  final VoidCallback onSetup;
  final VoidCallback onDice;
  final VoidCallback onStart;

  const _CompactGameHome({
    super.key,
    required this.summary,
    required this.ready,
    required this.onSetup,
    required this.onDice,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF6EC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Image.asset(
                        'assets/icon/tabs/game_timer.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '兔咪遊戲桌',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppInk.strong,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ready ? summary : '正在準備遊戲桌…',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: AppInk.soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: '調整玩法、人數和時間',
                      child: Tooltip(
                        message: '調整設定',
                        child: IconButton.filledTonal(
                          onPressed: onSetup,
                          icon: const Icon(Icons.tune_rounded),
                          iconSize: 23,
                          constraints: const BoxConstraints.tightFor(
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  enabled: ready,
                  label: '用目前設定開始遊戲',
                  child: FilledButton.icon(
                    onPressed: ready ? onStart : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                    label: const Text('開始遊戲'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(62),
                      backgroundColor: kGameAccent,
                      disabledBackgroundColor: AppSurfaces.divider,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        icon: Icons.casino_rounded,
                        label: '只骰骰子',
                        onTap: onDice,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SecondaryButton(
                        icon: Icons.tune_rounded,
                        label: '調整設定',
                        onTap: onSetup,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FullActionDock extends StatelessWidget {
  final String summary;
  final VoidCallback onDone;
  final VoidCallback onDice;
  final VoidCallback onStart;

  const _FullActionDock({
    required this.summary,
    required this.onDone,
    required this.onDice,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.card.withValues(alpha: 0.98),
        border: const Border(top: BorderSide(color: AppSurfaces.divider)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8D6E63).withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 19,
                    color: kGameAccentDark,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppInk.soft,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onDone,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                    ),
                    label: const Text('收好設定'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppInk.soft,
                      minimumSize: const Size(44, 44),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: _SecondaryButton(
                      icon: Icons.casino_rounded,
                      label: '骰子',
                      onTap: onDice,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '開始遊戲',
                      child: FilledButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow_rounded, size: 27),
                        label: const Text('開始遊戲'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: kGameAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(19),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label, maxLines: 1),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: kGameAccentDark,
          backgroundColor: const Color(0xFFF4F9F3),
          side: const BorderSide(color: Color(0xFFBBD6C5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
