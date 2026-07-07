// 「玩家與時間」設定 bottom sheet（app 本體的暖紙質感，非深色桌面）。
//
// 所有改動即改即存（TableStore），關掉 sheet 後入口卡重讀即可；
// 不做「取消還原」——桌遊開局前的調整沒有毀滅性操作。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import '../../../widgets/app_dialogs.dart';
import 'table_store.dart';
import 'table_timer_models.dart';
import 'table_timer_theme.dart';

/// 開啟設定 sheet；關閉後回傳最新設定（呼叫端直接 setState 換上）。
Future<TableTimerConfig> showTableSetupSheet(
  BuildContext context, {
  required SharedPreferences prefs,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TableSetupSheet(prefs: prefs),
  );
  return TableStore.loadConfig(prefs);
}

class _TableSetupSheet extends StatefulWidget {
  final SharedPreferences prefs;

  const _TableSetupSheet({required this.prefs});

  @override
  State<_TableSetupSheet> createState() => _TableSetupSheetState();
}

class _TableSetupSheetState extends State<_TableSetupSheet> {
  late TableTimerConfig _config;
  late List<String> _roster;

  static const _turnPresets = [30, 45, 60, 90, 120, 180, 300];
  static const _warnPresets = [5, 10, 15, 20];

  @override
  void initState() {
    super.initState();
    _config = TableStore.loadConfig(widget.prefs);
    _roster = List.of(TableStore.loadRoster(widget.prefs));
  }

  void _apply(TableTimerConfig next) {
    setState(() => _config = next);
    TableStore.saveConfig(widget.prefs, next);
  }

  void _saveRoster() {
    TableStore.saveRoster(widget.prefs, _roster);
  }

  // ── 玩家操作 ─────────────────────────────────────────────

  int _nextFreeColor() {
    final used = {for (final p in _config.players) p.colorIndex};
    for (var c = 0; c < TableTheme.seatColors.length; c++) {
      if (!used.contains(c)) return c;
    }
    return _config.players.length % TableTheme.seatColors.length;
  }

  void _addPlayer() {
    if (_config.players.length >= TableTimerConfig.maxPlayers) return;
    playFeedback(SfxCue.tap);
    final n = _config.players.length + 1;
    _apply(
      _config.copyWith(
        players: [
          ..._config.players,
          TablePlayer(name: '玩家 $n', colorIndex: _nextFreeColor()),
        ],
      ),
    );
  }

  void _removePlayer(int i) {
    if (_config.players.length <= TableTimerConfig.minPlayers) return;
    playFeedback(SfxCue.cancel);
    final next = List.of(_config.players)..removeAt(i);
    _apply(_config.copyWith(players: next));
  }

  void _movePlayer(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _config.players.length) return;
    playHaptic(HapticLevel.selection);
    final next = List.of(_config.players);
    final p = next.removeAt(i);
    next.insert(j, p);
    _apply(_config.copyWith(players: next));
  }

  Future<void> _renamePlayer(int i) async {
    final player = _config.players[i];
    final controller = TextEditingController(text: player.name);
    var addToRoster = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('玩家名字'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 12,
                decoration: const InputDecoration(hintText: '輸入名字'),
              ),
              if (_roster.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  '從常用玩家帶入',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppInk.soft,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in _roster)
                      _pickChip(
                        name,
                        onTap: () => setDialog(() => controller.text = name),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setDialog(() => addToRoster = !addToRoster),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      addToRoster
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: addToRoster ? kGameAccent : AppInk.iconFaint,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '同時存入常用玩家',
                      style: TextStyle(fontSize: 13.5, color: AppInk.soft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            dialogCancelAction(ctx, onPressed: () => Navigator.pop(ctx, false)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true || name.isEmpty) return;

    final next = List.of(_config.players);
    next[i] = player.copyWith(name: name);
    _apply(_config.copyWith(players: next));
    if (addToRoster && !_roster.contains(name)) {
      setState(() => _roster.add(name));
      _saveRoster();
    }
  }

  Future<void> _addRosterName() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增常用玩家'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '輸入名字'),
        ),
        actions: [
          dialogCancelAction(ctx, onPressed: () => Navigator.pop(ctx, false)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('新增'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true || name.isEmpty || _roster.contains(name)) return;
    setState(() => _roster.add(name));
    _saveRoster();
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chess = _config.mode == TableGameMode.chess;
    final free = _config.mode == TableGameMode.free;
    final maxH = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppSurfaces.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '玩家與時間',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppInk.strong,
              ),
            ),
            const SizedBox(height: 14),
            _modeSwitch(),
            const SizedBox(height: 18),
            _sectionTitle(chess ? '玩家（棋鐘用前兩位）' : '玩家'),
            const SizedBox(height: 8),
            for (var i = 0; i < _config.players.length; i++)
              _playerRow(i, dimmed: chess && i >= 2),
            if (!chess && _config.players.length < TableTimerConfig.maxPlayers)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: _addPlayer,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    '新增玩家',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (!free) ...[
              const SizedBox(height: 14),
              _sectionTitle('每回合時間'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _turnPresets)
                    _valueChip(
                      _turnLabel(s),
                      selected: _config.turnSeconds == s,
                      onTap: () => _apply(_config.copyWith(turnSeconds: s)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _stepperRow(),
              const SizedBox(height: 14),
              _sectionTitle('倒數提醒'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _warnPresets)
                    _valueChip(
                      '剩 $s 秒',
                      selected: _config.warnSeconds == s,
                      onTap: () => _apply(_config.copyWith(warnSeconds: s)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _apply(
                  _config.copyWith(autoAdvance: !_config.autoAdvance),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '超時自動換下一位',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppInk.strong,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '關閉時超時會亮紅等待，點一下才換人',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppInk.soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _config.autoAdvance,
                        activeTrackColor: kGameAccent,
                        onChanged: (v) =>
                            _apply(_config.copyWith(autoAdvance: v)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _sectionTitle('常用玩家'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _roster)
                  _rosterChip(name),
                _pickChip('＋ 新增', onTap: _addRosterName, accent: true),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '改玩家名字時可以一鍵帶入常用玩家',
              style: TextStyle(fontSize: 12, color: AppInk.faint),
            ),
          ],
        ),
      ),
    );
  }

  String _turnLabel(int s) => s >= 60 && s % 60 == 0 ? '${s ~/ 60} 分' : '$s 秒';

  Widget _modeSwitch() {
    Widget seg(TableGameMode mode, IconData icon) {
      final sel = _config.mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (sel) return;
            playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
            _apply(_config.copyWith(mode: mode));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? kGameAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: sel ? Colors.white : AppInk.soft,
                ),
                const SizedBox(height: 3),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppSurfaces.fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppSurfaces.divider),
      ),
      child: Row(
        children: [
          seg(TableGameMode.party, Icons.groups_rounded),
          seg(TableGameMode.chess, Icons.swap_vert_rounded),
          seg(TableGameMode.free, Icons.all_inclusive_rounded),
        ],
      ),
    );
  }

  Widget _playerRow(int i, {required bool dimmed}) {
    final p = _config.players[i];
    final canRemove = _config.players.length > TableTimerConfig.minPlayers;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          decoration: BoxDecoration(
            color: AppSurfaces.fill,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: TableTheme.seatColor(p.colorIndex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: dimmed ? null : () => _renamePlayer(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppInk.strong,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: AppInk.iconFaint,
                        ),
                        if (dimmed) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '不上場',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppInk.faint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _rowIcon(
                Icons.keyboard_arrow_up_rounded,
                enabled: i > 0,
                onTap: () => _movePlayer(i, -1),
              ),
              _rowIcon(
                Icons.keyboard_arrow_down_rounded,
                enabled: i < _config.players.length - 1,
                onTap: () => _movePlayer(i, 1),
              ),
              _rowIcon(
                Icons.close_rounded,
                enabled: canRemove,
                danger: true,
                onTap: () => _removePlayer(i),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowIcon(
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 20,
        color: !enabled
            ? AppSurfaces.divider
            : (danger ? AppInk.danger : AppInk.soft),
      ),
    );
  }

  Widget _stepperRow() {
    return Row(
      children: [
        const Text(
          '自訂',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppInk.soft,
          ),
        ),
        const Spacer(),
        _stepBtn(Icons.remove_rounded, () {
          final v = (_config.turnSeconds - 5).clamp(
            TableTimerConfig.minTurnSeconds,
            TableTimerConfig.maxTurnSeconds,
          );
          _apply(_config.copyWith(turnSeconds: v));
        }),
        SizedBox(
          width: 86,
          child: Center(
            child: Text(
              _turnSecondsText(),
              style: AppType.digits(fontSize: 17, color: AppInk.strong),
            ),
          ),
        ),
        _stepBtn(Icons.add_rounded, () {
          final v = (_config.turnSeconds + 5).clamp(
            TableTimerConfig.minTurnSeconds,
            TableTimerConfig.maxTurnSeconds,
          );
          _apply(_config.copyWith(turnSeconds: v));
        }),
      ],
    );
  }

  String _turnSecondsText() {
    final s = _config.turnSeconds;
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '$m 分' : '$m 分 $r 秒';
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppSurfaces.fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          playHaptic(HapticLevel.selection);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppInk.strong),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: AppInk.soft,
    ),
  );

  Widget _valueChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        playHaptic(HapticLevel.selection);
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGameAccent : AppSurfaces.fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kGameAccent : AppSurfaces.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppInk.soft,
          ),
        ),
      ),
    );
  }

  Widget _pickChip(String label, {required VoidCallback onTap, bool accent = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: accent ? kGameAccent.withValues(alpha: 0.10) : AppSurfaces.fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent
                ? kGameAccent.withValues(alpha: 0.35)
                : AppSurfaces.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: accent ? kGameAccent : AppInk.strong,
          ),
        ),
      ),
    );
  }

  Widget _rosterChip(String name) {
    return Container(
      padding: const EdgeInsets.only(left: 13, right: 6, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppSurfaces.fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppSurfaces.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppInk.strong,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () {
              playFeedback(SfxCue.cancel);
              setState(() => _roster.remove(name));
              _saveRoster();
            },
            icon: const Icon(
              Icons.close_rounded,
              size: 15,
              color: AppInk.iconFaint,
            ),
          ),
        ],
      ),
    );
  }
}
