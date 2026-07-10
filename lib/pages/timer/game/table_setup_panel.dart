// Codex 版桌遊開局面板。
//
// 設計重點不是把所有選項攤在同一層，而是先回答三件事：
// 「怎麼玩、幾個人、多久」。玩家名字、提醒與棋鐘加秒仍保留，
// 但放在自然的次層，讓孩子與長輩第一次打開也能直接開始。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import 'table_store.dart';
import 'table_timer_models.dart';
import 'table_timer_theme.dart';

class TableSetupPanel extends StatefulWidget {
  final SharedPreferences prefs;
  final ValueChanged<TableTimerConfig> onConfigChanged;

  const TableSetupPanel({
    super.key,
    required this.prefs,
    required this.onConfigChanged,
  });

  @override
  State<TableSetupPanel> createState() => _TableSetupPanelState();
}

class _TableSetupPanelState extends State<TableSetupPanel> {
  static const _turnChoices = [30, 60, 90, 180];
  static const _bankChoices = [180, 300, 600, 900];
  static const _warnChoices = [5, 10, 15, 20, 30];
  static const _incrementChoices = [0, 2, 5, 10];

  late TableTimerConfig _config;
  late List<String> _roster;
  late List<TablePreset> _presets;

  @override
  void initState() {
    super.initState();
    _config = TableStore.loadConfig(widget.prefs);
    _roster = List.of(TableStore.loadRoster(widget.prefs));
    _presets = List.of(TableStore.loadPresets(widget.prefs));
  }

  void _apply(TableTimerConfig next) {
    final fixed = next.clampWarn();
    setState(() => _config = fixed);
    unawaited(TableStore.saveConfig(widget.prefs, fixed));
    widget.onConfigChanged(fixed);
  }

  void _setMode(TableGameMode mode) {
    if (_config.mode == mode) return;
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    _apply(_config.copyWith(mode: mode));
  }

  void _setPlayerCount(int count) {
    final wanted = count.clamp(
      TableTimerConfig.minPlayers,
      TableTimerConfig.maxPlayers,
    );
    if (wanted == _config.players.length) return;
    final players = List<TablePlayer>.of(_config.players);
    while (players.length < wanted) {
      final index = players.length;
      players.add(TablePlayer(name: '玩家 ${index + 1}', colorIndex: index));
    }
    while (players.length > wanted) {
      players.removeLast();
    }
    playHaptic(HapticLevel.selection);
    _apply(_config.copyWith(players: players));
  }

  void _movePlayer(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _config.players.length) return;
    final players = List<TablePlayer>.of(_config.players);
    final player = players.removeAt(index);
    players.insert(target, player);
    playHaptic(HapticLevel.selection);
    _apply(_config.copyWith(players: players));
  }

  Future<void> _renamePlayer(int index) async {
    final player = _config.players[index];
    final controller = TextEditingController(text: player.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('第 ${index + 1} 位玩家叫什麼？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '玩家名字',
                  hintText: '例如：奶奶、小安',
                  prefixIcon: Icon(Icons.face_rounded),
                ),
                onSubmitted: (value) =>
                    Navigator.of(dialogContext).pop(value.trim()),
              ),
              if (_roster.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '常用名字',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppInk.soft,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in _roster)
                      ActionChip(
                        label: Text(name),
                        onPressed: () => controller.text = name,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;

    final players = List<TablePlayer>.of(_config.players);
    players[index] = player.copyWith(name: result);
    if (!_roster.contains(result) && !result.startsWith('玩家 ')) {
      _roster.add(result);
      unawaited(TableStore.saveRoster(widget.prefs, _roster));
    }
    playFeedback(SfxCue.success, haptic: HapticLevel.selection);
    _apply(_config.copyWith(players: players));
  }

  Future<void> _saveFavorite() async {
    if (_presets.length >= TablePreset.maxCount) return;
    final controller = TextEditingController(
      text: switch (_config.mode) {
        TableGameMode.party => '家庭桌遊',
        TableGameMode.chess => '雙人對弈',
        TableGameMode.free => '輕鬆輪流',
      },
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('收藏這組玩法'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '幫它取個名字',
            prefixIcon: Icon(Icons.favorite_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('收藏'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final next = [..._presets, TablePreset(name: name, config: _config)];
    setState(() => _presets = next);
    unawaited(TableStore.savePresets(widget.prefs, next));
    playFeedback(SfxCue.success, haptic: HapticLevel.medium);
  }

  void _applyFavorite(TablePreset preset) {
    playFeedback(SfxCue.tap, haptic: HapticLevel.selection);
    _apply(preset.config);
  }

  Future<void> _removeFavorite(TablePreset preset) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('移除「${preset.name}」？'),
        content: const Text('只會移除收藏，不會影響目前的設定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除', style: TextStyle(color: AppInk.danger)),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() => _presets.remove(preset));
    unawaited(TableStore.savePresets(widget.prefs, _presets));
    playFeedback(SfxCue.cancel, haptic: HapticLevel.selection);
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _config.activePlayers.length;
    return ListView(
      key: const PageStorageKey('codex-game-setup'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _welcomeCard(),
        if (_presets.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader(
            number: null,
            title: '常用玩法',
            subtitle: '點一下就準備好；長按可以移除',
          ),
          const SizedBox(height: 10),
          _favoriteStrip(),
        ],
        const SizedBox(height: 22),
        _sectionHeader(number: 1, title: '今天怎麼玩？', subtitle: '選最接近的玩法就好'),
        const SizedBox(height: 10),
        _modeChoices(),
        const SizedBox(height: 24),
        _sectionHeader(
          number: 2,
          title: _config.mode == TableGameMode.chess ? '哪兩位對弈？' : '今天有幾位玩家？',
          subtitle: _config.mode == TableGameMode.chess
              ? '棋鐘固定兩位，點名字可以修改'
              : '輪到的順序會照下面排列',
        ),
        const SizedBox(height: 10),
        if (_config.mode != TableGameMode.chess) ...[
          _playerCountControl(activeCount),
          const SizedBox(height: 12),
        ],
        _playerCards(),
        const SizedBox(height: 24),
        _sectionHeader(
          number: 3,
          title: _config.mode == TableGameMode.free ? '不用趕，慢慢玩' : '想留多少時間？',
          subtitle: _config.mode == TableGameMode.free
              ? '只記錄每個人想了多久，不會倒數'
              : '先選一個舒服的速度，遊戲中仍可暫停',
        ),
        const SizedBox(height: 10),
        _timeChoices(),
        const SizedBox(height: 18),
        _advancedCard(),
        const SizedBox(height: 14),
        _saveFavoriteButton(),
      ],
    );
  }

  Widget _welcomeCard() {
    return Semantics(
      container: true,
      label: '兔咪遊戲桌，三步就能開始',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E8), Color(0xFFEAF6EC)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE9DDC9)),
          boxShadow: AppShadows.flat,
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
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '選玩法、人數和時間，準備好就一起玩！',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppInk.soft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_config.mode.label} · $activeCountText · ${_config.timeSummary}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: kGameAccentDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Image.asset(
                'assets/mascot/core/tumi_invite.png',
                width: 88,
                height: 88,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get activeCountText => '${_config.activePlayers.length} 人';

  Widget _sectionHeader({
    required int? number,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (number != null) ...[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: kGameAccent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppType.digits(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: AppInk.soft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeChoices() {
    return Column(
      children: [
        _modeCard(
          mode: TableGameMode.party,
          icon: Icons.groups_rounded,
          title: '大家輪流',
          description: '桌遊、牌卡、說故事',
          badge: '2–6 人',
          color: const Color(0xFF67A77F),
        ),
        const SizedBox(height: 10),
        _modeCard(
          mode: TableGameMode.chess,
          icon: Icons.swap_vert_rounded,
          title: '雙人對弈',
          description: '下棋、將棋、策略對戰',
          badge: '2 人',
          color: const Color(0xFF6F8FD6),
        ),
        const SizedBox(height: 10),
        _modeCard(
          mode: TableGameMode.free,
          icon: Icons.all_inclusive_rounded,
          title: '輕鬆輪流',
          description: '不倒數，只記錄輪到誰',
          badge: '無壓力',
          color: const Color(0xFFD58B68),
        ),
      ],
    );
  }

  Widget _modeCard({
    required TableGameMode mode,
    required IconData icon,
    required String title,
    required String description,
    required String badge,
    required Color color,
  }) {
    final selected = _config.mode == mode;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title，$description，$badge',
      child: Material(
        color: selected ? color.withValues(alpha: 0.13) : AppSurfaces.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _setMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? color : AppSurfaces.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 0.20 : 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.16)
                        : AppSurfaces.fill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    selected ? '已選' : badge,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: selected ? color : AppInk.soft,
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

  Widget _playerCountControl(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE9D9)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count 位玩家',
              textAlign: TextAlign.center,
              style: AppType.digits(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppInk.strong,
              ),
            ),
          ),
          _roundStepButton(
            icon: Icons.remove_rounded,
            tooltip: '減少一位玩家',
            onTap: count > TableTimerConfig.minPlayers
                ? () => _setPlayerCount(count - 1)
                : null,
          ),
          const SizedBox(width: 8),
          _roundStepButton(
            icon: Icons.add_rounded,
            tooltip: '增加一位玩家',
            onTap: count < TableTimerConfig.maxPlayers
                ? () => _setPlayerCount(count + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _roundStepButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled ? kGameAccent : AppSurfaces.fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 52,
              child: Icon(
                icon,
                size: 27,
                color: enabled ? Colors.white : AppInk.iconFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerCards() {
    final count = _config.mode == TableGameMode.chess
        ? 2
        : _config.players.length;
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          _playerCard(i, canMove: _config.mode != TableGameMode.chess),
          if (i != count - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _playerCard(int index, {required bool canMove}) {
    final player = _config.players[index];
    final color = TableTheme.seatColor(player.colorIndex);
    return Semantics(
      container: true,
      label: '第 ${index + 1} 位，${player.name}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                '${index + 1}',
                style: AppType.digits(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
            ),
            if (canMove) ...[
              _smallIconButton(
                icon: Icons.arrow_upward_rounded,
                label: '把 ${player.name} 往前移',
                onTap: index > 0 ? () => _movePlayer(index, -1) : null,
              ),
              _smallIconButton(
                icon: Icons.arrow_downward_rounded,
                label: '把 ${player.name} 往後移',
                onTap: index < _config.players.length - 1
                    ? () => _movePlayer(index, 1)
                    : null,
              ),
            ],
            _smallIconButton(
              icon: Icons.edit_rounded,
              label: '修改 ${player.name} 的名字',
              onTap: () => _renamePlayer(index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallIconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 44, height: 48),
          onPressed: onTap,
          icon: Icon(icon, size: 21),
          color: AppInk.soft,
          disabledColor: AppInk.iconFaint,
        ),
      ),
    );
  }

  Widget _timeChoices() {
    if (_config.mode == TableGameMode.free) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF2D8C5)),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.self_improvement_rounded,
              size: 38,
              color: Color(0xFFD58B68),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '兔咪會幫忙記住每個人的回合，想好再換下一位。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: AppInk.strong,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_config.mode == TableGameMode.chess) ...[
          _timingModeSwitch(),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final seconds
                in _config.usesBank ? _bankChoices : _turnChoices)
              _timeCard(
                seconds,
                selected:
                    (_config.usesBank
                        ? _config.bankSeconds
                        : _config.turnSeconds) ==
                    seconds,
                onTap: () => _apply(
                  _config.usesBank
                      ? _config.copyWith(bankSeconds: seconds)
                      : _config.copyWith(turnSeconds: seconds),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _timingModeSwitch() {
    return SegmentedButton<bool>(
      expandedInsets: EdgeInsets.zero,
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.hourglass_top_rounded),
          label: Text('每回合'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.timer_rounded),
          label: Text('每人總時間'),
        ),
      ],
      selected: {_config.chessUseBank},
      showSelectedIcon: false,
      onSelectionChanged: (value) =>
          _apply(_config.copyWith(chessUseBank: value.first)),
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.fromHeight(52)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _timeCard(
    int seconds, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final label = _secondsText(seconds);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? kGameAccent.withValues(alpha: 0.14)
            : AppSurfaces.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            playHaptic(HapticLevel.selection);
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 146,
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? kGameAccent : AppSurfaces.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.timer_outlined,
                  size: 22,
                  color: selected ? kGameAccentDark : AppInk.soft,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: selected ? kGameAccentDark : AppInk.strong,
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

  Widget _advancedCard() {
    final free = _config.mode == TableGameMode.free;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppSurfaces.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // ListView 會用 PageStorage 保存 double 捲動位置；若這裡沒有自己
          // 的 key，ExpansionTile 可能讀到同一份資料並把 double 當 bool。
          key: const PageStorageKey('codex-game-advanced'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          leading: const Icon(Icons.tune_rounded, color: kGameAccentDark),
          title: const Text(
            '更多設定',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppInk.strong,
            ),
          ),
          subtitle: Text(
            free ? '目前不需調整倒數' : '提醒、超時與棋鐘加秒',
            style: const TextStyle(fontSize: 12.5, color: AppInk.soft),
          ),
          children: free ? [_freeAdvancedNote()] : _timedAdvancedChildren(),
        ),
      ),
    );
  }

  Widget _freeAdvancedNote() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '自由輪流不會催促玩家；開局後仍可暫停、回上一位或重新開始回合。',
        style: TextStyle(fontSize: 13.5, height: 1.4, color: AppInk.soft),
      ),
    );
  }

  List<Widget> _timedAdvancedChildren() {
    final visibleWarnChoices = <int>{
      _config.warnSeconds,
      for (final seconds in _warnChoices)
        if (seconds <= _config.warnCap) seconds,
    }.toList()..sort();
    return [
      const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '剩幾秒開始提醒？',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppInk.strong,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in visibleWarnChoices)
              ChoiceChip(
                label: Text('剩 $seconds 秒'),
                selected: _config.warnSeconds == seconds,
                onSelected: (_) =>
                    _apply(_config.copyWith(warnSeconds: seconds)),
              ),
          ],
        ),
      ),
      if (_config.usesBank) ...[
        const SizedBox(height: 18),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '走完一手加秒',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppInk.strong,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seconds in _incrementChoices)
                ChoiceChip(
                  label: Text(seconds == 0 ? '不加秒' : '＋$seconds 秒'),
                  selected: _config.incrementSeconds == seconds,
                  onSelected: (_) =>
                      _apply(_config.copyWith(incrementSeconds: seconds)),
                ),
            ],
          ),
        ),
      ] else ...[
        const SizedBox(height: 12),
        Semantics(
          toggled: _config.autoAdvance,
          label: '時間到自動換下一位',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '時間到自動換下一位',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              '關閉時會停在紅色提醒，等你手動換人',
              style: TextStyle(fontSize: 12.5, color: AppInk.soft),
            ),
            activeTrackColor: kGameAccent,
            value: _config.autoAdvance,
            onChanged: (value) => _apply(_config.copyWith(autoAdvance: value)),
          ),
        ),
      ],
    ];
  }

  Widget _favoriteStrip() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = _presets[index];
          final active = preset.config.encode() == _config.encode();
          return Semantics(
            button: true,
            selected: active,
            label: '常用玩法 ${preset.name}，${preset.config.timeSummary}',
            hint: '長按可以移除',
            child: Material(
              color: active
                  ? kGameAccent.withValues(alpha: 0.14)
                  : AppSurfaces.fill,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _applyFavorite(preset),
                onLongPress: () => _removeFavorite(preset),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 144,
                    maxWidth: 210,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? kGameAccent : AppSurfaces.divider,
                      width: active ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppInk.strong,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${preset.config.activePlayers.length} 人 · ${preset.config.timeSummary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppInk.soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _saveFavoriteButton() {
    final enabled = _presets.length < TablePreset.maxCount;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '收藏目前的玩法設定',
      child: OutlinedButton.icon(
        onPressed: enabled ? _saveFavorite : null,
        icon: const Icon(Icons.favorite_border_rounded),
        label: Text(enabled ? '收藏這組玩法' : '常用玩法已收藏滿'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: kGameAccentDark,
          side: const BorderSide(color: Color(0xFFBBD6C5)),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  static String _secondsText(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '$minutes 分鐘' : '$minutes 分 $rest 秒';
  }
}
