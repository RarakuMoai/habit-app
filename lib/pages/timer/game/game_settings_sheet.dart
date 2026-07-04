import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/sfx_service.dart';
import '../../../widgets/hold_repeat_button.dart';
import 'game_clock.dart';
import 'game_widgets.dart';

/// 開啟遊戲計時設定底板（人數/命名排序/計時方式/倒數提示）。
/// 只在待機時可進；所有變更即改即存（controller mutator + persist）。
void showGameSettingsSheet(
  BuildContext context,
  GameClockController controller,
) {
  playFeedback(SfxCue.tap);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => GameSettingsSheet(controller: controller),
  );
}

/// 設定底板本體：改名輸入框、拖曳排序（含移動模式 jiggle 動畫）都是
/// 這顆 State 自己的事，跟計時卡片/全螢幕頁零耦合。
class GameSettingsSheet extends StatefulWidget {
  final GameClockController controller;

  const GameSettingsSheet({super.key, required this.controller});

  @override
  State<GameSettingsSheet> createState() => _GameSettingsSheetState();
}

class _GameSettingsSheetState extends State<GameSettingsSheet>
    with TickerProviderStateMixin {
  GameClockController get c => widget.controller;

  // 只在「正在改名的那一列」用一個 controller（點一下才變輸入框），
  // 其餘列是純文字＋拖曳，避免輸入框跟拖曳手勢打架。
  final TextEditingController _editCtrl = TextEditingController();
  int _editingIndex = -1;
  bool _moveMode = false;
  late final AnimationController _jiggle;

  @override
  void initState() {
    super.initState();
    _jiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _jiggle.dispose();
    super.dispose();
  }

  // 變更設定的統一出口：mutator 會自己刷新預覽並通知卡片，這裡補存檔＋
  // 重繪底板。
  void _apply(VoidCallback change) {
    change();
    c.persist();
    setState(() {});
  }

  void _beginEdit(int i) {
    setState(() {
      _editingIndex = i;
      _editCtrl.text = c.playerAt(i).name;
      _editCtrl.selection = TextSelection.collapsed(
        offset: _editCtrl.text.length,
      );
    });
  }

  void _endEdit() {
    if (_editingIndex < 0) return;
    setState(() => _editingIndex = -1);
    FocusScope.of(context).unfocus();
  }

  void _startMove() {
    _endEdit();
    if (_moveMode) return;
    setState(() => _moveMode = true);
    _jiggle.repeat();
    playHaptic(HapticLevel.selection);
  }

  void _finishMove() {
    if (!_moveMode) return;
    setState(() => _moveMode = false);
    _jiggle.stop();
    _jiggle.value = 0;
    playHaptic(HapticLevel.selection);
  }

  @override
  Widget build(BuildContext context) {
    const color = kGameAccent;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8DDD4),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _header(color),
                      const SizedBox(height: 16),
                      _sectionTitle(Icons.groups_rounded, color, '人數'),
                      const SizedBox(height: 8),
                      _stepperCard(
                        label: '玩家人數',
                        sub: '一起輪流計時的人數',
                        icon: Icons.groups_rounded,
                        color: color,
                        value: '${c.playerCount} 人',
                        onMinus: c.playerCount > kGameMinPlayers
                            ? () => _apply(
                                () => c.setPlayerCount(c.playerCount - 1),
                              )
                            : null,
                        onPlus: c.playerCount < kGameMaxPlayers
                            ? () => _apply(
                                () => c.setPlayerCount(c.playerCount + 1),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle(Icons.badge_rounded, color, '玩家與順序（拖曳排序）'),
                      const SizedBox(height: 8),
                      _nameReorderList(color),
                      const SizedBox(height: 16),
                      _sectionTitle(Icons.timer_rounded, color, '計時方式'),
                      const SizedBox(height: 8),
                      _modeChoices(color),
                      const SizedBox(height: 12),
                      _timePresetChips(color),
                      const SizedBox(height: 8),
                      if (c.mode == GameClockMode.turn)
                        _stepperCard(
                          label: '每回合秒數',
                          sub: '每次輪到都從這個秒數開始',
                          icon: Icons.timelapse_rounded,
                          color: color,
                          value: formatGameDuration(c.turnSeconds),
                          onMinus: c.turnSeconds > 5
                              ? () => _apply(
                                  () => c.setTurnSeconds(c.turnSeconds - 5),
                                )
                              : null,
                          onPlus: c.turnSeconds < 600
                              ? () => _apply(
                                  () => c.setTurnSeconds(c.turnSeconds + 5),
                                )
                              : null,
                        )
                      else ...[
                        _stepperCard(
                          label: '起始總時間',
                          sub: '每人一桶總時間，輪到才扣',
                          icon: Icons.hourglass_bottom_rounded,
                          color: color,
                          value: formatGameDuration(c.bankSeconds),
                          onMinus: c.bankSeconds > 30
                              ? () => _apply(
                                  () => c.setBankSeconds(c.bankSeconds - 30),
                                )
                              : null,
                          onPlus: c.bankSeconds < 3600
                              ? () => _apply(
                                  () => c.setBankSeconds(c.bankSeconds + 30),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _stepperCard(
                          label: '每手增秒',
                          sub: 'Fischer：走完一手加回幾秒（0=關）',
                          icon: Icons.add_alarm_rounded,
                          color: color,
                          value: c.increment == 0 ? '關' : '${c.increment} 秒',
                          onMinus: c.increment > 0
                              ? () => _apply(
                                  () => c.setIncrement(c.increment - 1),
                                )
                              : null,
                          onPlus: c.increment < 60
                              ? () => _apply(
                                  () => c.setIncrement(c.increment + 1),
                                )
                              : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _sectionTitle(
                        Icons.notifications_active_rounded,
                        color,
                        '倒數提示',
                      ),
                      const SizedBox(height: 8),
                      _switchTile(
                        icon: Icons.volume_up_rounded,
                        color: color,
                        label: '最後幾秒提示音',
                        sub: '接近時間用完時每秒提醒',
                        value: c.warnEnabled,
                        onChanged: (v) => _apply(() => c.setWarnEnabled(v)),
                      ),
                      const SizedBox(height: 8),
                      _stepperCard(
                        label: '提示秒數',
                        sub: '剩幾秒開始提示',
                        icon: Icons.alarm_rounded,
                        color: color,
                        value: '${c.warnSeconds} 秒',
                        enabled: c.warnEnabled,
                        onMinus: c.warnEnabled && c.warnSeconds > 3
                            ? () => _apply(
                                () => c.setWarnSeconds(c.warnSeconds - 1),
                              )
                            : null,
                        onPlus: c.warnEnabled && c.warnSeconds < 30
                            ? () => _apply(
                                () => c.setWarnSeconds(c.warnSeconds + 1),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: const Text(
                    '完成',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color color) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.casino_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '遊戲計時設定',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppInk.strong,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '桌遊與棋類的輪流計時',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppInk.soft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppInk.iconFaint),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ── 玩家命名 + 拖曳排序（ReorderableListView 負責索引，保留移動模式）──

  Widget _nameReorderList(Color color) {
    void reorder(int oldIndex, int newIndex) {
      if (oldIndex < newIndex) newIndex--;
      if (oldIndex == newIndex) return;
      _apply(() => c.movePlayer(oldIndex, newIndex));
      playHaptic(HapticLevel.selection);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: c.playerCount,
          onReorder: reorder,
          onReorderStart: (_) {
            _endEdit();
            if (!_moveMode) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _startMove());
            }
          },
          proxyDecorator: (child, index, animation) =>
              Material(color: Colors.transparent, child: child),
          itemBuilder: (_, i) {
            // 座位物件的 id 當 key：排序動畫跟著人走，不會跳格。
            final key = ValueKey('game_player_${c.playerAt(i).id}');
            if (_editingIndex == i) {
              return KeyedSubtree(
                key: key,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _playerEditField(i, color),
                ),
              );
            }
            final row = Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GameNameJiggle(
                animation: _jiggle,
                enabled: _moveMode,
                seed: c.playerAt(i).id,
                child: _playerRow(i, color),
              ),
            );
            return _GameNameDragListener(
              key: key,
              index: i,
              immediate: _moveMode,
              child: row,
            );
          },
        ),
        if (_moveMode) ...[
          const SizedBox(height: 2),
          _GameMoveDoneButton(onTap: _finishMove),
        ],
      ],
    );
  }

  // 一般玩家列：色點 + 名字 + 改名/移動提示圖示。
  Widget _playerRow(int index, Color color) {
    final dotColor = gamePlayerColor(index);
    final onTap = _moveMode ? null : () => _beginEdit(index);
    return Material(
      color: _moveMode
          ? color.withValues(alpha: 0.09)
          : const Color(0xFFFAF7F2),
      borderRadius: BorderRadius.circular(12),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _moveMode
                  ? color.withValues(alpha: 0.42)
                  : const Color(0xFFE8DDD4),
              width: _moveMode ? 1.3 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (_moveMode) ...[
                  const Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: AppInk.iconFaint,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.nameOf(index),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppInk.strong,
                    ),
                  ),
                ),
                if (!_moveMode) ...[
                  IconButton(
                    tooltip: '改名',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: AppInk.iconFaint,
                    ),
                    onPressed: onTap,
                  ),
                  IconButton(
                    tooltip: '移動',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    icon: const Icon(
                      Icons.open_with_rounded,
                      size: 18,
                      color: AppInk.iconFaint,
                    ),
                    onPressed: _startMove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 改名中的列：輸入框 + 完成鈕。
  Widget _playerEditField(int index, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gamePlayerColor(index),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _editCtrl,
            autofocus: true,
            maxLength: 8,
            textInputAction: TextInputAction.done,
            onChanged: (v) => _apply(() => c.renamePlayer(index, v)),
            onSubmitted: (_) => _endEdit(),
            onTapOutside: (_) => _endEdit(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppInk.strong,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: '玩家${index + 1}',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: AppInk.faint,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: color.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.check_rounded, color: color),
          onPressed: _endEdit,
        ),
      ],
    );
  }

  // 常用時間快選：一點即套，免得狂按加減鈕（細調仍走下方步進器）。
  Widget _timePresetChips(Color color) {
    final turn = c.mode == GameClockMode.turn;
    final presets = turn
        ? const [10, 30, 60, 120, 300]
        : const [60, 180, 300, 600, 1800];
    final current = turn ? c.turnSeconds : c.bankSeconds;
    Widget chip(int v) {
      final sel = v == current;
      return GestureDetector(
        onTap: () {
          playHaptic(HapticLevel.selection);
          _apply(() => turn ? c.setTurnSeconds(v) : c.setBankSeconds(v));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? color : const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: sel ? color : const Color(0xFFE8DDD4)),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            formatGameDuration(v),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: sel ? Colors.white : AppInk.soft,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final v in presets) chip(v)],
    );
  }

  Widget _modeChoices(Color color) {
    Widget tile(GameClockMode m, IconData icon, String title, String sub) {
      final sel = c.mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => _apply(() => c.setMode(m)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel
                  ? color.withValues(alpha: 0.12)
                  : const Color(0xFFFAF7F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel
                    ? color.withValues(alpha: 0.38)
                    : const Color(0xFFE8DDD4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: sel ? color : AppInk.soft),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: sel ? color : AppInk.strong,
                      ),
                    ),
                    if (sel) ...[
                      const Spacer(),
                      Icon(Icons.check_rounded, size: 16, color: color),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // IntrinsicHeight：在垂直捲動容器裡，Row 的高度本來無界，stretch 會撐爆；
    // 先用 IntrinsicHeight 把 Row 高度收斂成兩塊較高者，stretch 才能等高。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            GameClockMode.turn,
            Icons.timelapse_rounded,
            '每回合',
            '每次輪到都重置，適合桌遊',
          ),
          const SizedBox(width: 10),
          tile(
            GameClockMode.bank,
            Icons.hourglass_bottom_rounded,
            '棋鐘',
            '每人一桶總時間，適合下棋',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, Color color, String title) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppInk.strong,
          ),
        ),
      ],
    );
  }

  Widget _stepperCard({
    required String label,
    required String sub,
    required IconData icon,
    required Color color,
    required String value,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
    bool enabled = true,
  }) {
    Widget btn(IconData ic, VoidCallback? onTap) {
      final on = onTap != null;
      return HoldRepeatButton(
        onTrigger: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: on ? 0.14 : 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(ic, size: 18, color: on ? color : AppInk.faint),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8DDD4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppInk.strong,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppInk.soft,
                    ),
                  ),
                ],
              ),
            ),
            btn(Icons.remove_rounded, onMinus),
            SizedBox(
              width: 76,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.digits(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                ),
              ),
            ),
            btn(Icons.add_rounded, onPlus),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8DDD4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppInk.strong,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppInk.soft,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: color,
            onChanged: (v) {
              playHaptic(HapticLevel.selection);
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _GameMoveDoneButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GameMoveDoneButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade500, Colors.green.shade600],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '完成排序',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 移動模式的 jiggle 動畫：每列相位錯開，像 iOS 桌面編輯的抖動。
class _GameNameJiggle extends StatelessWidget {
  final Animation<double> animation;
  final bool enabled;
  final int seed;
  final Widget child;

  const _GameNameJiggle({
    required this.animation,
    required this.enabled,
    required this.seed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final direction = seed.isEven ? 1.0 : -1.0;
    final phaseOffset = (seed.abs() % 100) / 100 * math.pi * 2;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        if (!enabled) return child!;
        final phase = animation.value * math.pi * 2 + phaseOffset;
        final sway = math.sin(phase);
        final bounce = math.sin(phase + math.pi / 2);
        final squash = math.sin(phase + math.pi);
        return Transform.translate(
          offset: Offset(direction * sway * 0.5, bounce * 0.9),
          child: Transform.rotate(
            angle: direction * sway * 0.014,
            child: Transform.scale(
              scaleX: 1 + squash * 0.005,
              scaleY: 1 - squash * 0.0035,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

const Duration _kGameDragHoldDelay = Duration(seconds: 1);

// 長按 1 秒才進入拖曳（移動模式下直接拖），避免跟點按改名打架。
class _GameNameDragListener extends ReorderableDragStartListener {
  final bool immediate;

  const _GameNameDragListener({
    super.key,
    required super.child,
    required super.index,
    required this.immediate,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return immediate
        ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
        : DelayedMultiDragGestureRecognizer(
            delay: _kGameDragHoldDelay,
            debugOwner: this,
          );
  }
}
