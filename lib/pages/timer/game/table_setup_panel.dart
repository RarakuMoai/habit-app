// 「展開狀態」的完整設定面板：桌遊計時器的設定不再藏在彈出 sheet，
// 展開卡片本身就是設定頁——縮小快速用、展開完整設定。
//
// 所有改動即改即存（TableStore）並回報給入口卡（onConfigChanged），
// 縮小或開局前不需要任何確認步驟；桌遊開局前的調整沒有毀滅性操作。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/hold_repeat_button.dart';
import 'table_store.dart';
import 'table_timer_models.dart';
import 'table_timer_theme.dart';

class TableSetupPanel extends StatefulWidget {
  final SharedPreferences prefs;

  /// 設定有任何改動（含套用常用組合）就回報最新版，入口卡同步摘要。
  final ValueChanged<TableTimerConfig> onConfigChanged;

  /// 「只骰骰子」直達兔咪骰子屋（給的話，橫幅上出現骰子小鈕）。
  final VoidCallback? onDice;

  const TableSetupPanel({
    super.key,
    required this.prefs,
    required this.onConfigChanged,
    this.onDice,
  });

  @override
  State<TableSetupPanel> createState() => _TableSetupPanelState();
}

class _TableSetupPanelState extends State<TableSetupPanel> {
  late TableTimerConfig _config;
  late List<String> _roster;
  late List<TablePreset> _presets;

  static const _turnPresets = [30, 45, 60, 90, 120, 180, 300];
  static const _warnPresets = [5, 10, 15, 20, 30];
  static const _bankPresets = [60, 180, 300, 600, 900, 1800];
  static const _incrementPresets = [0, 2, 5, 10];

  @override
  void initState() {
    super.initState();
    _config = TableStore.loadConfig(widget.prefs);
    _roster = List.of(TableStore.loadRoster(widget.prefs));
    _presets = List.of(TableStore.loadPresets(widget.prefs));
  }

  void _apply(TableTimerConfig next) {
    // 每回合時間變短時把倒數提醒一起夾回（warn 必須 < 每回合時間）
    final fixed = next.clampWarn();
    setState(() => _config = fixed);
    TableStore.saveConfig(widget.prefs, fixed);
    widget.onConfigChanged(fixed);
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

  void _reorderPlayer(int oldIndex, int newIndex) {
    // ReorderableListView 的 newIndex 是「移除前」的位置，往後移要 -1。
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    playHaptic(HapticLevel.selection);
    final next = List.of(_config.players);
    final p = next.removeAt(oldIndex);
    next.insert(newIndex, p);
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

  // ── 常用組合 ─────────────────────────────────────────────

  void _savePresets() {
    TableStore.savePresets(widget.prefs, _presets);
  }

  bool _isActivePreset(TablePreset preset) =>
      preset.config.encode() == _config.encode();

  Future<String?> _askPresetName({
    required String title,
    required String initial,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initial);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '組合名稱'),
        ),
        actions: [
          dialogCancelAction(ctx, onPressed: () => Navigator.pop(ctx, false)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true || name.isEmpty) return null;
    return name;
  }

  Future<void> _saveCurrentAsPreset() async {
    if (_presets.length >= TablePreset.maxCount) return;
    final name = await _askPresetName(
      title: '儲存常用組合',
      initial: TablePreset.defaultName(_config),
      confirmLabel: '儲存',
    );
    if (name == null) return;
    playFeedback(SfxCue.success);
    setState(() => _presets.add(TablePreset(name: name, config: _config)));
    _savePresets();
  }

  void _applyPreset(TablePreset preset) {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    _apply(preset.config);
  }

  Future<void> _renamePreset(TablePreset preset) async {
    final name = await _askPresetName(
      title: '常用組合改名',
      initial: preset.name,
      confirmLabel: '確定',
    );
    if (name == null) return;
    final i = _presets.indexOf(preset);
    if (i < 0) return;
    setState(() {
      _presets[i] = TablePreset(name: name, config: preset.config);
    });
    _savePresets();
  }

  /// 長按或點 ⋯：改名 / 刪除 選單。
  Future<void> _managePreset(TablePreset preset) async {
    playHaptic(HapticLevel.selection);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppSurfaces.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppSurfaces.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                TablePreset.defaultName(preset.config),
                style: const TextStyle(fontSize: 12.5, color: AppInk.soft),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppInk.soft),
                title: const Text(
                  '改名',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppInk.danger,
                ),
                title: const Text(
                  '刪除這組',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppInk.danger,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _renamePreset(preset);
      case 'delete':
        playFeedback(SfxCue.cancel);
        setState(() => _presets.remove(preset));
        _savePresets();
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

    // 水平留白由各區自己包（_padded）：常用組合列要「全出血」，
    // 卡片才能自然滑出頁緣、不會在頁邊被硬切（SE 撞邊問題）。
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
      children: [
        _padded([
          _header(),
          const SizedBox(height: 10),
          _matchSummary(),
          const SizedBox(height: 16),
          _sectionTitle('常用組合', caption: '把玩家＋模式＋時間存成一組，下次一鍵套用'),
          const SizedBox(height: 8),
        ]),
        _presetStrip(),
        _padded([
          const SizedBox(height: 20),
          _sectionTitle('玩法'),
          const SizedBox(height: 8),
          _modeSwitch(),
          const SizedBox(height: 6),
          Text(switch (_config.mode) {
            TableGameMode.party => '放桌子中央，輪到誰就點一下換下一位',
            TableGameMode.chess => '兩人對坐，點自己那側交棒給對方',
            TableGameMode.free => '不倒數沒壓力，只記錄輪到誰、想了多久',
          }, style: const TextStyle(fontSize: 12, color: AppInk.soft)),
          const SizedBox(height: 20),
          _sectionTitle(
            '出場順位',
            caption: chess ? '由上到下排序，棋鐘由前兩位上場' : '由上到下輪流出場，按住 ≡ 拖曳調整',
          ),
          const SizedBox(height: 8),
          _playerList(chess: chess),
          if (!chess && _config.players.length < TableTimerConfig.maxPlayers)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addPlayer,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  '新增玩家',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          if (chess) ...[
            const SizedBox(height: 12),
            _sectionTitle('計時制'),
            const SizedBox(height: 8),
            _timingSwitch(),
          ],
          if (!free && !_config.usesBank) ...[
            const SizedBox(height: 20),
            _sectionTitle('每回合時間'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _turnPresets)
                  _valueChip(
                    _secondsText(s),
                    selected: _config.turnSeconds == s,
                    onTap: () => _apply(_config.copyWith(turnSeconds: s)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _stepperRow(
              text: _secondsText(_config.turnSeconds),
              onMinus: _config.turnSeconds > TableTimerConfig.minTurnSeconds
                  ? () => _apply(
                      _config.copyWith(
                        turnSeconds: (_config.turnSeconds - 5).clamp(
                          TableTimerConfig.minTurnSeconds,
                          TableTimerConfig.maxTurnSeconds,
                        ),
                      ),
                    )
                  : null,
              onPlus: _config.turnSeconds < TableTimerConfig.maxTurnSeconds
                  ? () => _apply(
                      _config.copyWith(
                        turnSeconds: (_config.turnSeconds + 5).clamp(
                          TableTimerConfig.minTurnSeconds,
                          TableTimerConfig.maxTurnSeconds,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
          if (_config.usesBank) ...[
            const SizedBox(height: 20),
            _sectionTitle('每人總時間'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _bankPresets)
                  _valueChip(
                    _secondsText(s),
                    selected: _config.bankSeconds == s,
                    onTap: () => _apply(_config.copyWith(bankSeconds: s)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _stepperRow(
              text: _secondsText(_config.bankSeconds),
              onMinus: _config.bankSeconds > TableTimerConfig.minBankSeconds
                  ? () => _apply(
                      _config.copyWith(
                        bankSeconds: (_config.bankSeconds - 30).clamp(
                          TableTimerConfig.minBankSeconds,
                          TableTimerConfig.maxBankSeconds,
                        ),
                      ),
                    )
                  : null,
              onPlus: _config.bankSeconds < TableTimerConfig.maxBankSeconds
                  ? () => _apply(
                      _config.copyWith(
                        bankSeconds: (_config.bankSeconds + 30).clamp(
                          TableTimerConfig.minBankSeconds,
                          TableTimerConfig.maxBankSeconds,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            _sectionTitle('每手加秒（Fischer）', caption: '時間用盡＝旗倒直接分勝負；走完一手可加回幾秒'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _incrementPresets)
                  _valueChip(
                    s == 0 ? '不加秒' : '＋$s 秒',
                    selected: _config.incrementSeconds == s,
                    onTap: () => _apply(_config.copyWith(incrementSeconds: s)),
                  ),
              ],
            ),
          ],
          if (!free) ...[
            const SizedBox(height: 20),
            _sectionTitle(
              '倒數提醒',
              caption: _config.usesBank
                  ? '剩幾秒開始提醒（要比每人總時間短）'
                  : '剩幾秒開始提醒（要比每回合時間短）',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _warnPresets)
                  if (s <= _config.warnCap)
                    _valueChip(
                      '剩 $s 秒',
                      selected: _config.warnSeconds == s,
                      onTap: () => _apply(_config.copyWith(warnSeconds: s)),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            _stepperRow(
              text: '剩 ${_config.warnSeconds} 秒',
              onMinus: _config.warnSeconds > TableTimerConfig.minWarnSeconds
                  ? () => _apply(
                      _config.copyWith(warnSeconds: _config.warnSeconds - 1),
                    )
                  : null,
              onPlus: _config.warnSeconds < _config.warnCap
                  ? () => _apply(
                      _config.copyWith(warnSeconds: _config.warnSeconds + 1),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            if (!_config.usesBank)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    _apply(_config.copyWith(autoAdvance: !_config.autoAdvance)),
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
          const SizedBox(height: 20),
          _sectionTitle('常用玩家', caption: '改玩家名字時可以一鍵帶入'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _roster) _rosterChip(name),
              _pickChip('＋ 新增', onTap: _addRosterName, accent: true),
            ],
          ),
        ]),
      ],
    );
  }

  /// 區段內容的水平留白（常用組合列以外都走這裡）。
  Widget _padded(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  /// 頁首：貼紙 icon＋名稱＋隨設定即時更新的一句話摘要。
  /// 兔咪邀請橫幅：設定頁不是表單，是兔咪招呼大家上桌。
  /// （展開狀態兔咪面板收合、本尊不在場，這裡由邀請差分補上兔咪感。）
  Widget _header() {
    return Semantics(
      container: true,
      label: '兔咪遊戲桌設定',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E8), Color(0xFFEAF6EC)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kGameAccent.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '兔咪遊戲桌',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '兔咪會幫忙記住每個人的回合，想好再換下一位。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppInk.soft,
                    ),
                  ),
                  if (widget.onDice != null) ...[
                    const SizedBox(height: 8),
                    _diceChip(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            ExcludeSemantics(
              child: Image.asset(
                'assets/mascot/core/tumi_invite.png',
                width: 84,
                height: 84,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 橫幅上的「只骰骰子」小鈕：不開對局也能用骰盤。
  Widget _diceChip() {
    return Material(
      color: AppSurfaces.card.withValues(alpha: 0.85),
      shape: StadiumBorder(
        side: BorderSide(color: kGameAccent.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: widget.onDice,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.casino_rounded, size: 16, color: kGameAccentDark),
              SizedBox(width: 5),
              Text(
                '只骰骰子',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: kGameAccentDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 開局前摘要：把最影響對局的三件事先亮出來，讓設定頁不是只是一串控制。
  Widget _matchSummary() {
    final activePlayers = _config.activePlayers;
    final seat = TableTheme.seatColor(activePlayers.first.colorIndex);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kGameAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGameAccent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sports_esports_rounded,
                size: 18,
                color: kGameAccent,
              ),
              const SizedBox(width: 7),
              const Text(
                '本局摘要',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const Spacer(),
              _summaryPill(
                icon: _modeIcon(_config.mode),
                label: _config.mode.label,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 420 ? 3 : 2;
              final spacing = 8.0;
              final width = (box.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _summaryTile(
                    width: width,
                    icon: Icons.people_alt_rounded,
                    label: '${activePlayers.length} 人出場',
                    value: _playersSummary,
                    accent: seat,
                  ),
                  _summaryTile(
                    width: width,
                    icon: _config.usesBank
                        ? Icons.hourglass_bottom_rounded
                        : Icons.timelapse_rounded,
                    label: _config.usesBank ? '時間庫' : '回合時間',
                    value: _config.timeSummary,
                  ),
                  _summaryTile(
                    width: width,
                    icon: _config.mode == TableGameMode.free
                        ? Icons.all_inclusive_rounded
                        : Icons.notifications_active_rounded,
                    label: _config.mode == TableGameMode.free ? '節奏' : '提醒',
                    value: _warnSummary,
                    accent: _config.mode == TableGameMode.free
                        ? AppInk.soft
                        : TableTheme.warnInk,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppSurfaces.card.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGameAccent.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: kGameAccent),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: AppInk.strong,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    Color accent = kGameAccent,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
          color: AppSurfaces.card.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppSurfaces.divider.withValues(alpha: 0.82),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppInk.soft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _playersSummary {
    final players = _config.activePlayers;
    final names = players.take(3).map((p) => p.name).join('、');
    if (players.length <= 3) return names;
    return '$names 等 ${players.length} 人';
  }

  String get _warnSummary {
    if (_config.mode == TableGameMode.free) return '不倒數，只記時間';
    final warn = '剩 ${_config.warnSeconds} 秒';
    if (_config.usesBank) return '$warn 旗倒';
    return _config.autoAdvance ? '$warn 自動換人' : '$warn 手動換人';
  }

  // ── 常用組合列 ───────────────────────────────────────────

  /// 橫向卡片列（全出血，自帶 20 水平 padding，卡片滑得出頁緣）：
  /// 每張卡＝一組快照（點卡套用、⋯ 或長按管理），尾端固定「儲存目前設定」。
  Widget _presetStrip() {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final preset in _presets) ...[
            _presetCard(preset),
            const SizedBox(width: 8),
          ],
          if (_presets.length < TablePreset.maxCount) _savePresetCard(),
        ],
      ),
    );
  }

  /// 副標的一行摘要：模式小圖示＋「N 人 · 時間」（比全文字短，不易截斷）。
  Widget _presetDetail(TableTimerConfig c, {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_modeIcon(c.mode), size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${c.activePlayers.length} 人 · ${c.timeSummary}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 卡片：淡染表選中（「使用中」細字），不做整塊實色——
  /// 頁面上唯一的實色 CTA 留給「開始對局」。
  Widget _presetCard(TablePreset preset) {
    final active = _isActivePreset(preset);
    return GestureDetector(
      onTap: () => _applyPreset(preset),
      onLongPress: () => _managePreset(preset),
      child: Container(
        constraints: const BoxConstraints(minWidth: 136, maxWidth: 216),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: active
              ? kGameAccent.withValues(alpha: 0.10)
              : AppSurfaces.fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? kGameAccent.withValues(alpha: 0.55)
                : AppSurfaces.divider,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.bookmark_rounded,
                        size: 14,
                        color: kGameAccent,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          preset.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: AppInk.strong,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 5),
                        const Text(
                          '使用中',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: kGameAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  _presetDetail(
                    preset.config,
                    color: active ? AppInk.soft : AppInk.faint,
                  ),
                ],
              ),
            ),
            // 管理入口（改名/刪除）；長按整卡也會開同一個選單
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _managePreset(preset),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Icon(
                  Icons.more_vert_rounded,
                  size: 16,
                  color: AppInk.iconFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savePresetCard() {
    return GestureDetector(
      onTap: _saveCurrentAsPreset,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: kGameAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGameAccent.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 17,
              color: kGameAccent,
            ),
            SizedBox(width: 6),
            Text(
              '儲存目前設定',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: kGameAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 出場順位 ─────────────────────────────────────────────

  Widget _playerList({required bool chess}) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderStart: (_) => playHaptic(HapticLevel.selection),
      onReorder: _reorderPlayer,
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.03, child: child),
      ),
      children: [
        // key 綁玩家實體（不能綁 index）：拖曳排序時 framework 靠 key
        // 追蹤「同一列」，綁 index 會讓動畫與 proxy 對錯人。
        for (var i = 0; i < _config.players.length; i++)
          _playerRow(
            i,
            key: ObjectKey(_config.players[i]),
            dimmed: chess && i >= 2,
          ),
      ],
    );
  }

  Widget _playerRow(int i, {required Key key, required bool dimmed}) {
    final p = _config.players[i];
    final canRemove = _config.players.length > TableTimerConfig.minPlayers;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppSurfaces.fill,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // 順位徽章：座位色底＋序號，「由上到下」一眼可讀
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TableTheme.seatColor(p.colorIndex),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: dimmed ? null : () => _renamePlayer(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
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
                            '本局輪空',
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
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: AppInk.iconFaint,
                  ),
                ),
              ),
              // 移除鈕走低調灰（每列一顆紅 ✕ 會讓整區充滿警示噪音）
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: canRemove ? () => _removePlayer(i) : null,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: canRemove ? AppInk.iconFaint : AppSurfaces.divider,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 模式/計時制 ──────────────────────────────────────────

  IconData _modeIcon(TableGameMode mode) => switch (mode) {
    TableGameMode.party => Icons.groups_rounded,
    TableGameMode.chess => Icons.swap_vert_rounded,
    TableGameMode.free => Icons.all_inclusive_rounded,
  };

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
                Icon(icon, size: 20, color: sel ? Colors.white : AppInk.soft),
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

  /// 棋鐘計時制：每回合制 / 總時間制（時間庫＋Fischer）。
  Widget _timingSwitch() {
    Widget seg({
      required bool bank,
      required IconData icon,
      required String label,
    }) {
      final sel = _config.chessUseBank == bank;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (sel) return;
            playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
            _apply(_config.copyWith(chessUseBank: bank));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: sel ? kGameAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: sel ? Colors.white : AppInk.soft),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
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
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppSurfaces.divider),
      ),
      child: Row(
        children: [
          seg(bank: false, icon: Icons.timelapse_rounded, label: '每回合制'),
          seg(bank: true, icon: Icons.hourglass_bottom_rounded, label: '總時間制'),
        ],
      ),
    );
  }

  // ── 小元件 ───────────────────────────────────────────────

  String _secondsText(int s) {
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '$m 分' : '$m 分 $r 秒';
  }

  /// 自訂步進列：點一下 ±step、按住連發；到極值自動停用。
  Widget _stepperRow({
    required String text,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) {
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
        _stepBtn(Icons.remove_rounded, onTrigger: onMinus),
        SizedBox(
          width: 96,
          child: Center(
            child: Text(
              text,
              style: AppType.digits(fontSize: 17, color: AppInk.strong),
            ),
          ),
        ),
        _stepBtn(Icons.add_rounded, onTrigger: onPlus),
      ],
    );
  }

  Widget _stepBtn(IconData icon, {VoidCallback? onTrigger}) {
    final active = onTrigger != null;
    return HoldRepeatButton(
      onTrigger: onTrigger,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? kGameAccent.withValues(alpha: 0.10)
              : AppSurfaces.fill,
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 19,
            color: active ? kGameAccent : AppInk.iconFaint,
          ),
        ),
      ),
    );
  }

  /// 區段標題：右側拉漸隱細線收尾（全 app 規範），caption 用次要墨色。
  Widget _sectionTitle(String text, {String? caption}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppInk.soft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kGameAccent.withValues(alpha: 0.25),
                    kGameAccent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      if (caption != null) ...[
        const SizedBox(height: 2),
        Text(caption, style: const TextStyle(fontSize: 12, color: AppInk.soft)),
      ],
    ],
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

  Widget _pickChip(
    String label, {
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: accent
              ? kGameAccent.withValues(alpha: 0.10)
              : AppSurfaces.fill,
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
