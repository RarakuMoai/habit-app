import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_feedback.dart';
import '../utils/app_style.dart';
import '../utils/feature_flags.dart';
import '../utils/prefs_keys.dart';
import '../utils/tab_catalog.dart';
import '../utils/water_habit_link.dart';
import '../utils/weight_records.dart';
import '../widgets/app_waiting.dart';

// 功能開關頁：集中管理各頁籤的顯示開關
class FeatureSettingsPage extends StatefulWidget {
  const FeatureSettingsPage({super.key});

  @override
  State<FeatureSettingsPage> createState() => _FeatureSettingsPageState();
}

class _FeatureSettingsPageState extends State<FeatureSettingsPage> {
  bool _timerEnabled = true;
  bool _waterEnabled = false;
  bool _weightTrackingEnabled = false;
  bool _familyEnabled = false;
  List<String> _tabOrder = const [];
  bool _loaded = false;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _timerEnabled = _prefs!.getBool(PrefsKeys.timerEnabled) ?? true;
      _waterEnabled = _prefs!.getBool(PrefsKeys.waterEnabled) ?? false;
      _weightTrackingEnabled =
          _prefs!.getBool(PrefsKeys.weightTrackingEnabled) ?? false;
      _familyEnabled = _prefs!.getBool(PrefsKeys.familyEnabled) ?? false;
      _tabOrder = _prefs!.getStringList(PrefsKeys.tabOrder) ?? const <String>[];
      _loaded = true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
    // 即時廣播：MainPage 馬上重組頁籤，不必等退出設定頁才生效。
    bumpFeatureFlags();
  }

  // 功能開關列
  Widget _toggleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppSurfaces.divider),
        boxShadow: AppShadows.flat,
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppInk.strong,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppInk.soft),
        ),
        value: value,
        activeThumbColor: Colors.orange,
        activeTrackColor: Colors.orange.shade200,
        onChanged: (v) {
          playHaptic(HapticLevel.selection);
          onChanged(v);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // 目前「已啟用」的分頁，依使用者排序排好（給排序 UI 用）。
  List<TabMeta> _orderedEnabledMetas() {
    final enabled = <String>{
      TabIds.habit, // 習慣永遠在
      if (_timerEnabled) TabIds.timer,
      if (_waterEnabled) TabIds.water,
      if (_weightTrackingEnabled) TabIds.weight,
      if (_familyEnabled) TabIds.family,
      TabIds.wardrobe, // 固定分頁，永遠在
    };
    final ids = orderedTabIds(_tabOrder, enabled);
    return [for (final id in ids) kTabCatalog.firstWhere((m) => m.id == id)];
  }

  // 拖曳元件回傳「目前顯示中分頁的新順序」（id 字串）。
  Future<void> _applyOrder(List<String> shownOrder) async {
    // 新順序 = 顯示中的啟用分頁，後面接舊排序裡目前停用的 id（保留它們相對位置，
    // 重新啟用時不會無謂跳到最後）。
    final shown = shownOrder.toSet();
    final newOrder = <String>[
      ...shownOrder,
      for (final id in _tabOrder)
        if (!shown.contains(id)) id,
    ];
    setState(() => _tabOrder = newOrder);
    await _prefs?.setStringList(PrefsKeys.tabOrder, newOrder);
    bumpFeatureFlags(); // 即時套到底部列
  }

  // 排序區塊：用「真實底部列預覽」點選調整順序（標題列＋說明都在元件裡）。
  Widget _reorderSection() {
    final metas = _orderedEnabledMetas();
    // 只有一個分頁時沒得排，整段隱藏。
    if (metas.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BottomBarReorder(metas: metas, onReorder: _applyOrder),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            AppLocalizations.of(context).featureSettingsTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppInk.strong,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.featureSettingsTitle), centerTitle: true),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 底部分頁排序（拖曳調整順序）
                _reorderSection(),

                // 計時頁開關（專注、運動、節拍器、遊戲）
                _toggleTile(
                  icon: Icons.timer_outlined,
                  iconColor: Colors.red.shade400,
                  title: l10n.featureTimerTitle,
                  subtitle: l10n.featureTimerSubtitle,
                  value: _timerEnabled,
                  onChanged: (v) async {
                    setState(() => _timerEnabled = v);
                    await _saveBool(PrefsKeys.timerEnabled, v);
                  },
                ),

                // 喝水頁開關
                _toggleTile(
                  icon: Icons.water_drop_outlined,
                  iconColor: Colors.blue,
                  title: l10n.featureWaterTitle,
                  subtitle: l10n.featureWaterSubtitle,
                  value: _waterEnabled,
                  onChanged: (v) async {
                    if (_prefs != null) {
                      if (v) {
                        await WaterHabitLink.ensureHabit(_prefs!);
                      } else {
                        await WaterHabitLink.removeHabit(_prefs!);
                      }
                    }
                    await _saveBool(PrefsKeys.waterEnabled, v);
                    if (mounted) setState(() => _waterEnabled = v);
                  },
                ),

                // 體重紀錄開關
                _toggleTile(
                  icon: Icons.monitor_weight_outlined,
                  iconColor: Colors.green.shade600,
                  title: l10n.featureWeightTitle,
                  subtitle: l10n.featureWeightSubtitle,
                  value: _weightTrackingEnabled,
                  onChanged: (v) async {
                    setState(() => _weightTrackingEnabled = v);
                    await _saveBool(PrefsKeys.weightTrackingEnabled, v);
                    if (v && _prefs != null) {
                      await ensureWeightHabit(_prefs!);
                      await syncWeightHabitForDate(_prefs!);
                    }
                  },
                ),

                // 家庭模式開關
                _toggleTile(
                  icon: Icons.family_restroom,
                  iconColor: Colors.purple,
                  title: l10n.featureFamilyTitle,
                  subtitle: l10n.featureFamilySubtitle,
                  value: _familyEnabled,
                  onChanged: (v) async {
                    setState(() => _familyEnabled = v);
                    await _saveBool(PrefsKeys.familyEnabled, v);
                  },
                ),
              ],
            )
          : const AppPageWaiting(),
    );
  }
}

// 「底部分頁順序」的點選排序。兩大設計目標：
// 1) 排版完全鏡像真實底部列（main.dart 的 _AdaptiveBottomNav）——一般手機
//    的 6 個分頁維持單排，只有每格不足共用門檻時才拆成上下兩排。
// 2) 互動改成「按鈕進排序、點選即移動」：點右上「排序」進入排序狀態，
//    點一個圖示把它選起來、再點目標位置就立刻移過去，不必長按也不必拖。
class _BottomBarReorder extends StatefulWidget {
  const _BottomBarReorder({required this.metas, required this.onReorder});

  final List<TabMeta> metas;
  // 回傳目前顯示中分頁的新順序（id 字串）。
  final ValueChanged<List<String>> onReorder;

  @override
  State<_BottomBarReorder> createState() => _BottomBarReorderState();
}

class _BottomBarReorderState extends State<_BottomBarReorder>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFFFF7043); // 與底部列選中色一致

  // 全 cell 共用的抖動驅動（一條 ticker，各 cell 用不同相位），同主頁手法。
  late final AnimationController _jiggle;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _jiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void dispose() {
    _jiggle.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() => _editMode = !_editMode);
    if (_editMode) {
      _jiggle.repeat();
    } else {
      _jiggle
        ..stop()
        ..value = 0;
    }
    playHaptic(HapticLevel.selection);
  }

  // 把 a、b 兩格「單純對調」位置——不玉突牽動其他分頁。
  void _swap(int a, int b) {
    if (a == b) return;
    final ids = widget.metas.map((m) => m.id).toList();
    final tmp = ids[a];
    ids[a] = ids[b];
    ids[b] = tmp;
    widget.onReorder(ids);
    playHaptic(HapticLevel.light);
  }

  // 標題列右上的「排序 / 完成」切換鈕（取代原本要長按才會動的設計）。
  Widget _editToggle() {
    final editing = _editMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleEdit,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: editing ? _accent : _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: editing ? _accent : _accent.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                editing ? Icons.check_rounded : Icons.swap_vert_rounded,
                size: 16,
                color: editing ? Colors.white : _accent,
              ),
              const SizedBox(width: 5),
              Text(
                editing
                    ? AppLocalizations.of(context).commonDone
                    : AppLocalizations.of(context).tabOrderEdit,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: editing ? Colors.white : _accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 依排序狀態給對應說明文字。
  String _hint() {
    final l10n = AppLocalizations.of(context);
    return _editMode ? l10n.tabOrderHintEditing : l10n.tabOrderHintIdle;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.metas.length;
    // 用真實底部導覽可用的螢幕寬度判斷，不被設定頁本身 24px 留白誤導。
    final isTwoRow = bottomNavUsesTwoRows(
      width: MediaQuery.sizeOf(context).width,
      itemCount: n,
    );
    final columnCount = isTwoRow ? (n / 2).ceil() : n;
    final rowCount = isTwoRow ? 2 : 1;
    final cellH = isTwoRow ? 52.0 : 62.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題列：左標題、右「排序 / 完成」切換鈕。
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context).tabOrderTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppInk.strong,
                ),
              ),
              const Spacer(),
              _editToggle(),
            ],
          ),
        ),
        // 說明：依排序狀態換句子，長度變了平滑撐開。
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topLeft,
            curve: Curves.easeOut,
            child: Text(
              _hint(),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppInk.soft,
              ),
            ),
          ),
        ),
        // 仿真底部列白卡（已移除原本無意義的 home indicator 橫槓）。
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, c) {
              final cellW = c.maxWidth / columnCount;
              return SizedBox(
                width: c.maxWidth,
                height: cellH * rowCount,
                child: Stack(
                  children: [
                    for (int i = 0; i < n; i++)
                      _positionedCell(
                        index: i,
                        cellW: cellW,
                        cellH: cellH,
                        maxWidth: c.maxWidth,
                        columnCount: columnCount,
                        isTwoRow: isTwoRow,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 算出第 i 個分頁在格線裡的位置；排序狀態下包上「即觸即拖」＋抖動，
  // 非排序狀態就是純預覽。
  Widget _positionedCell({
    required int index,
    required double cellW,
    required double cellH,
    required double maxWidth,
    required int columnCount,
    required bool isTwoRow,
  }) {
    final meta = widget.metas[index];
    // 鏡像真實底部列：前段（index < columnCount）在下排、後段在上排。
    final inBottomRow = !isTwoRow || index < columnCount;
    final row = isTwoRow ? (inBottomRow ? 1 : 0) : 0;
    final posInRow = inBottomRow ? index : index - columnCount;
    final rowLen = isTwoRow
        ? (inBottomRow ? columnCount : widget.metas.length - columnCount)
        : widget.metas.length;
    // 每排置中（與真實底部列 Row 的 mainAxisAlignment.center 一致）。
    final rowStartX = (maxWidth - rowLen * cellW) / 2;

    return AnimatedPositioned(
      key: ValueKey(meta.id),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: rowStartX + posInRow * cellW,
      top: row * cellH,
      width: cellW,
      height: cellH,
      child: _editMode
          ? _draggableCell(meta, index, cellW, cellH, isTwoRow)
          : _cellContent(meta, isTwoRow),
    );
  }

  // 排序狀態下的可拖曳格：DragTarget 接收別格拖過來、Draggable 讓自己被拖。
  // 用 Draggable（非 LongPress）＝摸到就能拖，不必按住；放開時與目標「對調」。
  Widget _draggableCell(
    TabMeta meta,
    int index,
    double cellW,
    double cellH,
    bool isTwoRow,
  ) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _swap(d.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          // 拖起來浮在指尖的樣子。
          feedback: _liftedCell(meta, cellW, cellH, isTwoRow),
          // 原位留個半透明殘影，提示「這格正在被拖」。
          childWhenDragging: Opacity(
            opacity: 0.25,
            child: _cellContent(meta, isTwoRow),
          ),
          child: _JiggleBox(
            animation: _jiggle,
            enabled: true,
            seed: meta.id.hashCode,
            child: _cellContent(meta, isTwoRow, highlighted: highlighted),
          ),
        );
      },
    );
  }

  // 單一分頁 cell 內容：icon + label，尺寸比照真實底部列（單排 22/11.5、兩排 20/10.5）。
  // highlighted = 有別格拖到它上面、放開就會對調，給個橘色膠囊預告；
  // lifted = 拖在指尖浮起的那張（膠囊 + 光暈陰影）。
  Widget _cellContent(
    TabMeta meta,
    bool isTwoRow, {
    bool highlighted = false,
    bool lifted = false,
  }) {
    final iconSize = isTwoRow ? 20.0 : 22.0;
    final fontSize = isTwoRow ? 10.5 : 11.5;
    final accented = highlighted || lifted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: accented
            ? _accent.withValues(alpha: lifted ? 0.16 : 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: accented
            ? Border.all(color: _accent.withValues(alpha: 0.45), width: 1.4)
            : null,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          TabGlyph(
            tabId: meta.id,
            fallbackIcon: meta.icon,
            fallbackColor: _accent,
            size: iconSize,
          ),
          const SizedBox(height: 3),
          Text(
            tabLabel(context, meta.id),
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: accented ? AppInk.strong : AppInk.soft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // 拖曳中浮在指尖的 cell：套同一份 cell 內容、放大一點凸顯。
  Widget _liftedCell(TabMeta meta, double w, double h, bool isTwoRow) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: w,
        height: h,
        child: Transform.scale(
          scale: 1.12,
          child: _cellContent(meta, isTwoRow, lifted: true),
        ),
      ),
    );
  }
}

// 排序模式下每個 cell 的「Q 版抖動」：監聽共用 controller，依 seed 給不同相位/方向，
// 看起來像 iOS 主畫面長按 App 那樣整列在輕輕晃。enabled=false 時直通不重繪。
// （參數與 home_page 的 _Jiggle 對齊，維持全 app 一致手感。）
class _JiggleBox extends StatelessWidget {
  const _JiggleBox({
    required this.animation,
    required this.enabled,
    required this.seed,
    required this.child,
  });

  final Animation<double> animation;
  final bool enabled;
  final int seed;
  final Widget child;

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
