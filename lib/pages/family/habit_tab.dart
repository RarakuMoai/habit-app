import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_feedback.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/habit_ui.dart';
import 'family_auth.dart';
import 'family_models.dart';
import 'family_presets.dart';
import 'family_store.dart';
import 'preset_pick_sheet.dart';

// ── 習慣打卡 Tab ──

class HabitTab extends StatefulWidget {
  final ChildData child;
  final VoidCallback onPointsChanged; // 積分異動後通知父層更新 AppBar

  const HabitTab({
    super.key,
    required this.child,
    required this.onPointsChanged,
  });

  @override
  State<HabitTab> createState() => _HabitTabState();
}

class _HabitTabState extends State<HabitTab> {
  List<ChildHabit> _habits = [];
  List<DeductionItem> _deductions = [];
  bool _loaded = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 重新載入習慣與扣分項目
  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final habits = await loadHabits(_prefs!);
    final deductions = await loadDeductions(_prefs!);
    setState(() {
      // 只顯示此小孩的習慣與扣分項目
      _habits = habits.where((h) => h.childId == widget.child.id).toList();
      _deductions = deductions
          .where((d) => d.childId == widget.child.id)
          .toList();
      _loaded = true;
    });
  }

  // 判斷習慣今日是否完成（每日：今日打卡；每週：本週次數達標）
  bool _isDoneToday(ChildHabit habit) => habit.frequency == 'weekly'
      ? weeklyCount(habit) >= habit.weeklyTarget
      : habit.completedDate == todayStr();

  // 打卡：增加積分、標記日期
  // 每日：今日已打卡則跳過；每週：允許一日多次（上限 20 次/週）
  Future<void> _checkIn(ChildHabit habit) async {
    final today = todayStr();
    if (habit.frequency == 'weekly') {
      if (weeklyCount(habit) >= 20) return; // 上限
    } else {
      if (habit.completedDate == today) return;
    }
    final prefs = _prefs!;

    final newPoints = await applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: habit.points,
      reason: '完成習慣：${habit.name}',
    );

    final allHabits = await loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      if (habit.frequency == 'weekly') {
        allHabits[idx].weeklyDates.add(today);
        habit.weeklyDates.add(today);
      } else {
        allHabits[idx].completedDate = today;
        habit.completedDate = today;
      }
      await saveHabits(prefs, allHabits);
    }

    // 音效＋震動回饋（對齊習慣頁慣例）：
    // 達標（每日打卡 / 每週湊滿次數）→ success；每週累加未達標 → tap
    playFeedback(_isDoneToday(habit) ? SfxCue.success : SfxCue.tap);

    setState(() => widget.child.points = newPoints);
    widget.onPointsChanged();
  }

  // 撤銷打卡：扣回積分並清除日期（每週習慣移除最後一筆今日紀錄）
  Future<void> _undoCheckIn(ChildHabit habit) async {
    if (!mounted) return;
    final today = todayStr();
    if (habit.frequency == 'weekly') {
      if (!habit.weeklyDates.contains(today)) return;
    } else {
      if (habit.completedDate != today) return;
    }

    final prefs = _prefs!;
    final newPoints = await applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -habit.points,
      reason: '撤銷完成：${habit.name}',
    );

    final allHabits = await loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      if (habit.frequency == 'weekly') {
        // 移除最後一筆今日紀錄（多次打卡只撤銷一次）
        final lastIdx = allHabits[idx].weeklyDates.lastIndexOf(today);
        if (lastIdx != -1) {
          allHabits[idx].weeklyDates.removeAt(lastIdx);
        }
        final localIdx = habit.weeklyDates.lastIndexOf(today);
        if (localIdx != -1) {
          habit.weeklyDates.removeAt(localIdx);
        }
      } else {
        allHabits[idx].completedDate = '';
        habit.completedDate = '';
      }
      await saveHabits(prefs, allHabits);
    }

    playFeedback(SfxCue.cancel);

    setState(() => widget.child.points = newPoints);
    widget.onPointsChanged();
  }

  // ── 特殊積分（需家長密碼）──
  static const _kAddPresets = [
    Preset('幫忙做家事', 10, '🏠'),
    Preset('表現良好', 10, '😊'),
    Preset('考試進步', 20, '📈'),
    Preset('幫助別人', 10, '🤝'),
    Preset('準時完成作業', 15, '⏰'),
    Preset('主動學習', 15, '📚'),
  ];

  Future<void> _giveSpecialPoints() async {
    if (!mounted) return;
    final ok = await verifyParentPinIfNeeded(context, title: '請輸入家長密碼以給予特殊積分');
    if (!ok || !mounted) return;

    var isAdd = true;
    final reasonCtrl = TextEditingController();
    final pointCtrl = TextEditingController();
    final selectedAddPresets = <String, int>{};
    final selectedDeductItems = <String, int>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) {
          final customReason = reasonCtrl.text.trim();
          final customPts = int.tryParse(pointCtrl.text.trim()) ?? 0;
          final hasCustom = customReason.isNotEmpty;
          final selectedPresets = isAdd
              ? selectedAddPresets
              : selectedDeductItems;
          final canConfirm =
              selectedPresets.isNotEmpty || (hasCustom && customPts > 0);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '特殊積分',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  // 加分 / 扣分 切換
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('加分'),
                        icon: Icon(Icons.add_circle_outline),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('扣分'),
                        icon: Icon(Icons.remove_circle_outline),
                      ),
                    ],
                    selected: {isAdd},
                    onSelectionChanged: (s) => setS(() {
                      isAdd = s.first;
                      selectedAddPresets.clear();
                      selectedDeductItems.clear();
                      reasonCtrl.clear();
                      pointCtrl.clear();
                    }),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: isAdd
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      selectedForegroundColor: isAdd
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 快速理由 / 扣分項目 子選單按鈕
                  InkWell(
                    onTap: () async {
                      if (isAdd) {
                        final result = await showFamilyPresetSubSheet(
                          context,
                          _kAddPresets.toList(),
                          Map.from(selectedAddPresets),
                          title: '快速理由',
                          accentColor: Colors.green.shade600,
                          dialogLabel: '加幾分',
                          adjustDialogTitle: '調整分數',
                        );
                        if (result != null) {
                          setS(() {
                            selectedAddPresets.clear();
                            selectedAddPresets.addAll(result);
                          });
                        }
                      } else {
                        if (_deductions.isEmpty) return;
                        final result = await showFamilyPresetSubSheet(
                          context,
                          _deductions
                              .map((d) => Preset(d.name, d.points))
                              .toList(),
                          Map.from(selectedDeductItems),
                          title: '扣分項目',
                          accentColor: Colors.red.shade600,
                          badgePrefix: '-',
                          dialogLabel: '扣幾分',
                          adjustDialogTitle: '調整分數',
                        );
                        if (result != null) {
                          setS(() {
                            selectedDeductItems.clear();
                            selectedDeductItems.addAll(result);
                          });
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selectedPresets.isEmpty
                            ? Colors.grey.shade50
                            : (isAdd
                                  ? Colors.green.shade50
                                  : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresets.isEmpty
                              ? Colors.grey.shade300
                              : (isAdd
                                    ? Colors.green.shade300
                                    : Colors.red.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade500
                                : (isAdd
                                      ? Colors.green.shade600
                                      : Colors.red.shade600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresets.isEmpty
                                  ? (isAdd ? '從快速理由選取' : '從扣分項目選取')
                                  : '已選 ${selectedPresets.length} 項',
                              style: TextStyle(
                                color: selectedPresets.isEmpty
                                    ? Colors.grey.shade600
                                    : (isAdd
                                          ? Colors.green.shade700
                                          : Colors.red.shade700),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            selectedPresets.isEmpty
                                ? Icons.chevron_right
                                : Icons.check_circle,
                            size: 20,
                            color: selectedPresets.isEmpty
                                ? Colors.grey.shade400
                                : (isAdd
                                      ? Colors.green.shade600
                                      : Colors.red.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 自訂原因
                  TextField(
                    controller: reasonCtrl,
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      hintText: isAdd ? '自訂原因...' : '自訂原因...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),

                  // 自訂分數（有輸入原因才顯示）
                  if (hasCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointCtrl,
                      onChanged: (_) => setS(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        labelText: isAdd ? '自訂加分數' : '自訂扣分數',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          isAdd
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          size: 18,
                          color: isAdd ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 確認按鈕
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () async {
                              Navigator.pop(ctx);
                              final presets = isAdd
                                  ? selectedAddPresets
                                  : selectedDeductItems;
                              final customReason = reasonCtrl.text.trim();
                              final customPts =
                                  int.tryParse(pointCtrl.text.trim()) ?? 0;
                              final sign = isAdd ? 1 : -1;
                              // 多筆異動整批套用（讀寫各一次，順序同逐筆）
                              final latestPts = await applyPointsBatch(
                                prefs: _prefs!,
                                child: widget.child,
                                entries: [
                                  for (final entry in presets.entries)
                                    (
                                      delta: sign * entry.value,
                                      reason: '特殊積分：${entry.key}',
                                    ),
                                  if (customReason.isNotEmpty && customPts > 0)
                                    (
                                      delta: sign * customPts,
                                      reason: '特殊積分：$customReason',
                                    ),
                                ],
                              );
                              playFeedback(SfxCue.success);
                              setState(() => widget.child.points = latestPts);
                              widget.onPointsChanged();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已更新 ${widget.child.name} 的積分，目前共 $latestPts 分',
                                  ),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdd ? Colors.green : Colors.red,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isAdd ? '確認加分' : '確認扣分',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = todayStr();
    final dailyHabits = _habits.where((h) => h.frequency == 'daily').toList();
    final weeklyHabits = _habits.where((h) => h.frequency == 'weekly').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 習慣區塊 ──
          if (_habits.isEmpty)
            _emptyHint('尚無習慣，請家長至家長管理新增')
          else ...[
            // 每日習慣
            if (dailyHabits.isNotEmpty) ...[
              HabitSectionHeader(
                label: '每日習慣',
                icon: Icons.wb_sunny_rounded,
                color: Colors.orange,
                done: dailyHabits.where(_isDoneToday).length,
                total: dailyHabits.length,
              ),
              _todayPointsHint(dailyHabits, isWeekly: false),
              ...dailyHabits.map(
                (habit) => _HabitItem(
                  habit: habit,
                  doneToday: _isDoneToday(habit),
                  weeklyCount: weeklyCount(habit),
                  todayCount: habit.weeklyDates.where((d) => d == today).length,
                  onCheckIn: () => _checkIn(habit),
                  onUndo: () => _undoCheckIn(habit),
                ),
              ),
            ],
            // 每週習慣
            if (weeklyHabits.isNotEmpty) ...[
              if (dailyHabits.isNotEmpty) const SizedBox(height: 18),
              HabitSectionHeader(
                label: '每週習慣',
                icon: Icons.calendar_view_week_rounded,
                color: Colors.indigo,
                done: weeklyHabits
                    .where((h) => weeklyCount(h) >= h.weeklyTarget)
                    .length,
                total: weeklyHabits.length,
              ),
              _todayPointsHint(weeklyHabits, isWeekly: true),
              ...weeklyHabits.map(
                (habit) => _HabitItem(
                  habit: habit,
                  doneToday: _isDoneToday(habit),
                  weeklyCount: weeklyCount(habit),
                  todayCount: habit.weeklyDates.where((d) => d == today).length,
                  onCheckIn: () => _checkIn(habit),
                  onUndo: () => _undoCheckIn(habit),
                ),
              ),
            ],
          ],

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _giveSpecialPoints,
            icon: const Icon(Icons.star_outline, size: 16),
            label: const Text('特殊積分'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple,
              side: BorderSide(color: Colors.purple.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // 今日已獲得分數提示（只在有得分時顯示）
  Widget _todayPointsHint(List<ChildHabit> habits, {required bool isWeekly}) {
    final today = todayStr();
    int todayPts;
    if (isWeekly) {
      // 每週習慣：每筆今日 weeklyDates 都計分（支援多次）
      todayPts = habits.fold<int>(0, (sum, h) {
        final todayCount = h.weeklyDates.where((d) => d == today).length;
        return sum + todayCount * h.points;
      });
    } else {
      todayPts = habits
          .where((h) => h.completedDate == today)
          .fold<int>(0, (sum, h) => sum + h.points);
    }
    if (todayPts <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.stars_rounded, size: 13, color: Colors.orange.shade400),
          const SizedBox(width: 4),
          Text(
            '今日已獲得 +$todayPts 分',
            style: TextStyle(
              fontSize: 11,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    ),
  );
}

// 習慣列表項目（套用 home_page 風格）
class _HabitItem extends StatefulWidget {
  final ChildHabit habit;
  final bool doneToday;
  final int weeklyCount;
  final int todayCount;
  final VoidCallback onCheckIn;
  final VoidCallback? onUndo;

  const _HabitItem({
    required this.habit,
    required this.doneToday,
    required this.weeklyCount,
    required this.todayCount,
    required this.onCheckIn,
    this.onUndo,
  });

  @override
  State<_HabitItem> createState() => _HabitItemState();
}

class _HabitItemState extends State<_HabitItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.78), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.78, end: 1.18), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleDailyTap() {
    _ctrl.forward(from: 0);
    if (widget.doneToday) {
      widget.onUndo?.call();
    } else {
      widget.onCheckIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.habit.frequency == 'weekly') return _buildWeeklyCard();
    return _buildDailyCard();
  }

  Widget _buildDailyCard() {
    final done = widget.doneToday;
    final habit = widget.habit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done ? const Color(0xFFF1F8E9) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.orange.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          // 整張卡都可點擊打卡（不只左邊小圓圈），ripple 回饋
          child: InkWell(
            onTap: _handleDailyTap,
            splashColor: (done ? Colors.grey : Colors.green).withValues(
              alpha: 0.12,
            ),
            highlightColor: (done ? Colors.grey : Colors.green).withValues(
              alpha: 0.06,
            ),
            child: IntrinsicHeight(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 66),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 5,
                      color: done
                          ? Colors.green.shade400
                          : Colors.orange.shade400,
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        leading: ScaleTransition(
                          scale: _scale,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              gradient: done
                                  ? LinearGradient(
                                      colors: [
                                        Colors.green.shade400,
                                        Colors.green.shade500,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: done ? null : Colors.grey.shade50,
                              border: done
                                  ? null
                                  : Border.all(
                                      color: Colors.grey.shade300,
                                      width: 1.8,
                                    ),
                              shape: BoxShape.circle,
                              boxShadow: done
                                  ? [
                                      BoxShadow(
                                        color: Colors.green.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: done
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                        title: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: done ? Colors.grey.shade400 : Colors.black87,
                          ),
                          child: Text(
                            habit.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        subtitle: done
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  habit.minutes > 0
                                      ? '+${habit.points} 分 · ${habit.minutes} 分鐘'
                                      : '+${habit.points} 分',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        trailing: done
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 11,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '+${habit.points}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyCard() {
    final done = widget.doneToday;
    final habit = widget.habit;
    final inProgress = widget.weeklyCount > 0 && !done;
    final todayCount = widget.todayCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: done
            ? const Color(0xFFF1F8E9)
            : inProgress
            ? const Color(0xFFF3F2FB)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: done ? 0 : 1.5,
        shadowColor: Colors.indigo.withValues(alpha: 0.18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 66),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左邊條
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 5,
                    color: done
                        ? Colors.green.shade400
                        : Colors.indigo.shade300,
                  ),
                  // ⊖ n ⊕ 計數區
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WeeklyAdjustBtn(
                            size: 30,
                            icon: Icons.remove_rounded,
                            onTap: todayCount > 0
                                ? () {
                                    widget.onUndo?.call();
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          ScaleTransition(
                            scale: _scale,
                            child: SizedBox(
                              width: 24,
                              child: Text(
                                '$todayCount',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: todayCount > 0
                                      ? Colors.indigo.shade700
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          WeeklyAdjustBtn(
                            size: 30,
                            icon: Icons.add_rounded,
                            onTap: widget.weeklyCount < 20
                                ? () {
                                    _ctrl.forward(from: 0);
                                    widget.onCheckIn();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 名稱
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: done ? Colors.grey.shade400 : Colors.black87,
                        ),
                        child: Text(
                          habit.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  // 本週 N/M 膠囊
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.green.shade100
                            : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            done ? Icons.check_rounded : Icons.flag_rounded,
                            size: 11,
                            color: done
                                ? Colors.green.shade700
                                : Colors.indigo.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${widget.weeklyCount}/${habit.weeklyTarget}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: done
                                  ? Colors.green.shade700
                                  : Colors.indigo.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
