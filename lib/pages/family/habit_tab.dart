import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_style.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/sfx_service.dart';
import '../../widgets/app_waiting.dart';
import '../../widgets/habit_ui.dart';
import '../../widgets/water_bottle.dart';
import 'family_auth.dart';
import 'family_models.dart';
import 'family_presets.dart';
import 'family_store.dart';
import 'family_widgets.dart';
import 'preset_pick_sheet.dart';

/// 接喝水面板的習慣名稱。與首頁的 `waterHabitName` 一樣是用名稱當識別鍵
/// （見 docs/engineering_guardrails.md §i18n 刻意不遷第 1 類）——家長把習慣改成別的
/// 名字就不再連動，這是目前 preset 沒有穩定 id 的已知限制。
const String kFamilyWaterHabitName = '今日多喝水';

/// 喝水面板的預設每日目標杯數。
const int kFamilyWaterDefaultGoal = 8;

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
  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<ChildHabit> _habits = [];
  List<DeductionItem> _deductions = [];
  List<PointRecord> _records = [];
  final Set<String> _pendingHabitIds = {};
  final Set<String> _pendingRecordIds = {};
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
    final records = await loadRecords(_prefs!);
    if (!mounted) return;
    setState(() {
      // 只顯示此小孩的習慣與扣分項目
      _habits = habits.where((h) => h.childId == widget.child.id).toList();
      _deductions = deductions
          .where((d) => d.childId == widget.child.id)
          .toList();
      _records = records
          .where((record) => record.childId == widget.child.id)
          .toList();
      _loaded = true;
    });
  }

  // 判斷習慣今日是否完成（每日：今日打卡；每週：本週次數達標）
  bool _isDoneToday(ChildHabit habit) => switch (habit.frequency) {
    HabitFrequency.weekly => weeklyCount(habit) >= habit.weeklyTarget,
    HabitFrequency.repeatable => false,
    _ => habit.completedDate == todayStr(),
  };

  List<PointRecord> _repeatableCompletionsToday(ChildHabit habit) {
    return habitCompletionRecordsForDay(
      records: _records,
      habitId: habit.id,
      date: todayStr(),
    );
  }

  Map<String, PointRecord> get _reversalsByCompletionId =>
      habitReversalsByCompletionId(_records);

  List<PointRecord> _activeRepeatableCompletionsToday(ChildHabit habit) {
    final reversals = _reversalsByCompletionId;
    return _repeatableCompletionsToday(
      habit,
    ).where((record) => !reversals.containsKey(record.id)).toList();
  }

  String _recordTime(PointRecord record) {
    final parts = record.time.split(' ');
    return parts.length > 1 ? parts.last : record.time;
  }

  // 打卡：增加積分、標記日期
  // 每日：今日已打卡則跳過；每週：允許一日多次（上限 20 次/週）
  Future<void> _checkIn(ChildHabit habit) async {
    if (habit.frequency == HabitFrequency.repeatable) {
      await _recordRepeatableCompletion(habit);
      return;
    }
    final today = todayStr();
    if (habit.frequency == HabitFrequency.weekly) {
      if (weeklyCount(habit) >= 20) return; // 上限
    } else {
      if (habit.completedDate == today) return;
    }
    final prefs = _prefs!;

    final newPoints = await applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: habit.points,
      reason: _l10n.htReasonComplete(habit.name),
    );

    final allHabits = await loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      if (habit.frequency == HabitFrequency.weekly) {
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

  Future<void> _recordRepeatableCompletion(ChildHabit habit) async {
    if (!mounted || _pendingHabitIds.contains(habit.id)) return;
    setState(() => _pendingHabitIds.add(habit.id));

    final recordId = genId();
    try {
      final newPoints = await applyPoints(
        prefs: _prefs!,
        child: widget.child,
        delta: habit.points,
        reason: _l10n.htReasonComplete(habit.name),
        recordContext: PointRecordContext(
          id: recordId,
          kind: PointRecordKind.habitCompletion,
          sourceId: habit.id,
        ),
      );
      final allRecords = await loadRecords(_prefs!);
      if (!mounted) return;
      setState(() {
        widget.child.points = newPoints;
        _records = allRecords
            .where((record) => record.childId == widget.child.id)
            .toList();
      });
      widget.onPointsChanged();
      playFeedback(SfxCue.tap);

      PointRecord? completion;
      for (final record in _records) {
        if (record.id == recordId) {
          completion = record;
          break;
        }
      }
      if (completion == null || !mounted) return;
      final savedCompletion = completion;
      final sequence = _repeatableCompletionsToday(habit).length;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _l10n.htRepeatLogged(
              sequence,
              _recordTime(savedCompletion),
              savedCompletion.delta,
            ),
          ),
          action: SnackBarAction(
            label: _l10n.htUndoAction,
            onPressed: () =>
                unawaited(_cancelRepeatableCompletion(habit, savedCompletion)),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingHabitIds.remove(habit.id));
      }
    }
  }

  Future<void> _cancelRepeatableCompletion(
    ChildHabit habit,
    PointRecord completion,
  ) async {
    if (!mounted ||
        _pendingRecordIds.contains(completion.id) ||
        _reversalsByCompletionId.containsKey(completion.id)) {
      return;
    }
    setState(() => _pendingRecordIds.add(completion.id));

    try {
      final newPoints = await applyPoints(
        prefs: _prefs!,
        child: widget.child,
        delta: -completion.delta,
        reason: _l10n.htReasonUndo(habit.name),
        recordContext: PointRecordContext(
          kind: PointRecordKind.habitReversal,
          sourceId: habit.id,
          reversesRecordId: completion.id,
        ),
      );
      final allRecords = await loadRecords(_prefs!);
      if (!mounted) return;
      setState(() {
        widget.child.points = newPoints;
        _records = allRecords
            .where((record) => record.childId == widget.child.id)
            .toList();
      });
      widget.onPointsChanged();
      playFeedback(SfxCue.cancel);
    } finally {
      if (mounted) {
        setState(() => _pendingRecordIds.remove(completion.id));
      }
    }
  }

  /// 小孩的喝水面板。杯數不另外存——就是這個習慣今天未撤銷的完成紀錄筆數，
  /// 跟「記一次」共用同一套 PointRecord，所以時間、撤銷、積分全部一致。
  /// 只有「每日目標杯數」是這裡自己的設定（每個小孩一份）。
  Future<void> _showWaterPanel(ChildHabit habit) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final goalKey = PrefsKeys.familyWaterGoal(widget.child.id);
    var goal = prefs.getInt(goalKey) ?? kFamilyWaterDefaultGoal;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          final cups = _activeRepeatableCompletionsToday(habit);
          final completions = _repeatableCompletionsToday(habit);
          final reversals = _reversalsByCompletionId;
          final progress = goal <= 0
              ? 0.0
              : (cups.length / goal).clamp(0.0, 1.0);
          final reached = cups.length >= goal;

          Future<void> setGoal(int next) async {
            final v = next.clamp(1, 20);
            if (v == goal) return;
            await prefs.setInt(goalKey, v);
            setSheetState(() => goal = v);
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppSurfaces.dragHandle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _l10n.htWaterPanelTitle,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppInk.strong,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _l10n.commonClose,
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppInk.iconFaint,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 180,
                      child: WaterBottle(
                        progress: progress,
                        reached: reached,
                        bumpKey: cups.length,
                        panelOpenValue: 1,
                        paused: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _l10n.htWaterCups(cups.length, goal),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: reached
                            ? Colors.lightBlue.shade700
                            : AppInk.strong,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('family-water-drink'),
                        onPressed: _pendingHabitIds.contains(habit.id)
                            ? null
                            : () async {
                                await _recordRepeatableCompletion(habit);
                                if (sheetContext.mounted) setSheetState(() {});
                              },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: Colors.lightBlue.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.local_drink_rounded, size: 20),
                        label: Text(
                          _l10n.htWaterDrink,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 每日目標（每個小孩自己一份）
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _l10n.htWaterGoalLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppInk.strong,
                            ),
                          ),
                        ),
                        AdjustBtn(
                          icon: Icons.remove,
                          enabled: goal > 1,
                          onTap: () => setGoal(goal - 1),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '$goal ${_l10n.htWaterCupUnit}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        AdjustBtn(
                          icon: Icons.add,
                          enabled: goal < 20,
                          onTap: () => setGoal(goal + 1),
                        ),
                      ],
                    ),
                    if (completions.isNotEmpty) ...[
                      const Divider(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _l10n.htWaterTodayList,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppInk.soft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 逐杯的時間與撤銷：家長怕重複點，看得到才安心
                      for (var i = 0; i < completions.length; i++)
                        _waterCupRow(
                          habit: habit,
                          completion: completions[i],
                          sequence: completions.length - i,
                          reversal: reversals[completions[i].id],
                          onChanged: () {
                            if (sheetContext.mounted) setSheetState(() {});
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _waterCupRow({
    required ChildHabit habit,
    required PointRecord completion,
    required int sequence,
    required PointRecord? reversal,
    required VoidCallback onChanged,
  }) {
    final cancelled = reversal != null;
    final pending = _pendingRecordIds.contains(completion.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$sequence.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cancelled ? AppInk.faint : Colors.lightBlue.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _recordTime(completion),
              style: TextStyle(
                fontSize: 13,
                color: cancelled ? AppInk.faint : AppInk.strong,
                decoration: cancelled
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
          if (cancelled)
            Text(
              _l10n.htRepeatCancelledAt(_recordTime(reversal)),
              style: const TextStyle(
                fontSize: 11,
                color: AppInk.faint,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            TextButton(
              onPressed: pending
                  ? null
                  : () async {
                      await _cancelRepeatableCompletion(habit, completion);
                      onChanged();
                    },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _l10n.htCancelRecord,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showRepeatableHistory(ChildHabit habit) async {
    if (_repeatableCompletionsToday(habit).isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          final completions = _repeatableCompletionsToday(habit);
          final reversals = _reversalsByCompletionId;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppSurfaces.dragHandle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _l10n.htRepeatHistoryTitle(habit.name),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppInk.strong,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _l10n.commonClose,
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppInk.iconFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: completions.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (_, index) {
                          final completion = completions[index];
                          final reversal = reversals[completion.id];
                          final cancelled = reversal != null;
                          final sequence = completions.length - index;
                          final pending = _pendingRecordIds.contains(
                            completion.id,
                          );
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            leading: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: cancelled
                                    ? AppSurfaces.fill
                                    : Colors.orange.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$sequence',
                                style: AppType.digits(
                                  fontSize: 15,
                                  color: cancelled
                                      ? AppInk.faint
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            title: Text(
                              _l10n.htRepeatSequence(sequence),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cancelled ? AppInk.faint : AppInk.strong,
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                            subtitle: Text(
                              '${_recordTime(completion)} · '
                              '${_l10n.pmHabitPoints(completion.delta)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cancelled ? AppInk.faint : AppInk.soft,
                              ),
                            ),
                            trailing: cancelled
                                ? Text(
                                    _l10n.htRepeatCancelledAt(
                                      _recordTime(reversal),
                                    ),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppInk.faint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: pending
                                        ? null
                                        : () async {
                                            await _cancelRepeatableCompletion(
                                              habit,
                                              completion,
                                            );
                                            if (sheetContext.mounted) {
                                              setSheetState(() {});
                                            }
                                          },
                                    child: Text(_l10n.htCancelRecord),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 撤銷打卡：扣回積分並清除日期（每週習慣移除最後一筆今日紀錄）
  Future<void> _undoCheckIn(ChildHabit habit) async {
    if (!mounted) return;
    final today = todayStr();
    if (habit.frequency == HabitFrequency.weekly) {
      if (!habit.weeklyDates.contains(today)) return;
    } else {
      if (habit.completedDate != today) return;
    }

    final prefs = _prefs!;
    final newPoints = await applyPoints(
      prefs: prefs,
      child: widget.child,
      delta: -habit.points,
      reason: _l10n.htReasonUndo(habit.name),
    );

    final allHabits = await loadHabits(prefs);
    final idx = allHabits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      if (habit.frequency == HabitFrequency.weekly) {
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
  // 這裡的名稱只當「快速理由」的挑選標籤，選了之後會寫進積分紀錄的
  // reason 字串；不像 kHabitPresets 那樣拿去跟已存資料比對，所以可以翻譯。
  List<Preset> get _addPresets => [
    Preset(_l10n.htPresetChores, 10, '🏠'),
    Preset(_l10n.htPresetGoodBehavior, 10, '😊'),
    Preset(_l10n.htPresetExamProgress, 20, '📈'),
    Preset(_l10n.htPresetHelpedOthers, 10, '🤝'),
    Preset(_l10n.htPresetHomeworkOnTime, 15, '⏰'),
    Preset(_l10n.htPresetSelfStudy, 15, '📚'),
  ];

  Future<void> _giveSpecialPoints() async {
    if (!mounted) return;
    final ok = await verifyParentPinIfNeeded(
      context,
      title: _l10n.htPinSpecialPoints,
    );
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
                        color: AppSurfaces.dragHandle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _l10n.htSpecialPoints,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 加分 / 扣分 切換
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(_l10n.htAdd),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(_l10n.htDeduct),
                        icon: const Icon(Icons.remove_circle_outline),
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
                          _addPresets,
                          Map.from(selectedAddPresets),
                          title: _l10n.htQuickReasons,
                          accentColor: Colors.green.shade600,
                          dialogLabel: _l10n.htAddHowMany,
                          adjustDialogTitle: _l10n.htAdjustPoints,
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
                          title: _l10n.htDeductItems,
                          accentColor: Colors.red.shade600,
                          badgePrefix: '-',
                          dialogLabel: _l10n.htDeductHowMany,
                          adjustDialogTitle: _l10n.htAdjustPoints,
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
                            ? AppSurfaces.fill
                            : (isAdd
                                  ? Colors.green.shade50
                                  : Colors.red.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresets.isEmpty
                              ? AppSurfaces.divider
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
                                ? AppInk.soft
                                : (isAdd
                                      ? Colors.green.shade600
                                      : Colors.red.shade600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresets.isEmpty
                                  ? (isAdd
                                        ? _l10n.htPickQuickReason
                                        : _l10n.htPickDeductItem)
                                  : _l10n.htSelectedCount(
                                      selectedPresets.length,
                                    ),
                              style: TextStyle(
                                color: selectedPresets.isEmpty
                                    ? AppInk.soft
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
                                ? AppInk.faint
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
                      hintText: _l10n.htCustomReason,
                      filled: true,
                      fillColor: AppSurfaces.fill,
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
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => dismissFamilyNumberKeyboard(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          kFamilyPointsMaxDigits,
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: isAdd
                            ? _l10n.htCustomAddPoints
                            : _l10n.htCustomDeductPoints,
                        filled: true,
                        fillColor: AppSurfaces.fill,
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
                        suffixIcon: const FamilyNumberKeyboardDoneButton(),
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
                                      reason: _l10n.htReasonSpecial(entry.key),
                                    ),
                                  if (customReason.isNotEmpty && customPts > 0)
                                    (
                                      delta: sign * customPts,
                                      reason: _l10n.htReasonSpecial(
                                        customReason,
                                      ),
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
                                    _l10n.htPointsUpdated(
                                      widget.child.name,
                                      latestPts,
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAdd ? Colors.green : Colors.red,
                        disabledBackgroundColor: AppSurfaces.divider,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isAdd ? _l10n.htConfirmAdd : _l10n.htConfirmDeduct,
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
      return const AppPageWaiting();
    }

    final today = todayStr();
    final dailyHabits = _habits
        .where((h) => h.frequency == HabitFrequency.daily)
        .toList();
    final repeatableHabits = _habits
        .where((h) => h.frequency == HabitFrequency.repeatable)
        .toList();
    final weeklyHabits = _habits
        .where((h) => h.frequency == HabitFrequency.weekly)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 習慣區塊 ──
          if (_habits.isEmpty)
            _emptyHint(_l10n.htNoHabits)
          else ...[
            // 每日習慣
            if (dailyHabits.isNotEmpty) ...[
              HabitSectionHeader(
                label: _l10n.htDailyHabits,
                icon: Icons.wb_sunny_rounded,
                color: Colors.orange,
                done: dailyHabits.where(_isDoneToday).length,
                total: dailyHabits.length,
              ),
              _todayPointsHint(dailyHabits),
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
            if (repeatableHabits.isNotEmpty) ...[
              if (dailyHabits.isNotEmpty) const SizedBox(height: 18),
              HabitSectionHeader(
                label: _l10n.htRepeatableHabits,
                icon: Icons.repeat_rounded,
                color: Colors.deepOrange,
              ),
              _todayPointsHint(repeatableHabits),
              ...repeatableHabits.map((habit) {
                final completions = _repeatableCompletionsToday(habit);
                final activeCompletions = _activeRepeatableCompletionsToday(
                  habit,
                );
                return _HabitItem(
                  habit: habit,
                  doneToday: false,
                  weeklyCount: 0,
                  todayCount: activeCompletions.length,
                  historyCount: completions.length,
                  latestTodayTime: activeCompletions.isEmpty
                      ? null
                      : _recordTime(activeCompletions.first),
                  busy: _pendingHabitIds.contains(habit.id),
                  onCheckIn: () => _checkIn(habit),
                  onShowHistory: completions.isEmpty
                      ? null
                      : () => _showRepeatableHistory(habit),
                  onOpenWater: habit.name == kFamilyWaterHabitName
                      ? () => _showWaterPanel(habit)
                      : null,
                );
              }),
            ],
            // 每週習慣
            if (weeklyHabits.isNotEmpty) ...[
              if (dailyHabits.isNotEmpty || repeatableHabits.isNotEmpty)
                const SizedBox(height: 18),
              HabitSectionHeader(
                label: _l10n.htWeeklyHabits,
                icon: Icons.calendar_view_week_rounded,
                color: Colors.indigo,
                done: weeklyHabits
                    .where((h) => weeklyCount(h) >= h.weeklyTarget)
                    .length,
                total: weeklyHabits.length,
              ),
              _todayPointsHint(weeklyHabits),
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
            label: Text(_l10n.htSpecialPoints),
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
  Widget _todayPointsHint(List<ChildHabit> habits) {
    final today = todayStr();
    final todayPts = habits.fold<int>(0, (sum, habit) {
      return switch (habit.frequency) {
        HabitFrequency.weekly =>
          sum +
              habit.weeklyDates.where((date) => date == today).length *
                  habit.points,
        HabitFrequency.repeatable =>
          sum +
              _activeRepeatableCompletionsToday(
                habit,
              ).fold<int>(0, (points, record) => points + record.delta),
        _ => sum + (habit.completedDate == today ? habit.points : 0),
      };
    });
    if (todayPts <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.stars_rounded, size: 13, color: Colors.orange.shade400),
          const SizedBox(width: 4),
          Text(
            _l10n.htTodayEarned(todayPts),
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
    child: Text(text, style: TextStyle(color: AppInk.faint, fontSize: 13)),
  );
}

// 習慣列表項目（套用 home_page 風格）
class _HabitItem extends StatefulWidget {
  final ChildHabit habit;
  final bool doneToday;
  final int weeklyCount;
  final int todayCount;
  final int historyCount;
  final String? latestTodayTime;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback? onUndo;
  final VoidCallback? onShowHistory;

  /// 有值時，可多次習慣的主按鈕改成「喝水去」並打開喝水面板
  /// （目前只有「今日多喝水」會帶）。
  final VoidCallback? onOpenWater;

  const _HabitItem({
    required this.habit,
    required this.doneToday,
    required this.weeklyCount,
    required this.todayCount,
    this.historyCount = 0,
    this.latestTodayTime,
    this.busy = false,
    required this.onCheckIn,
    this.onUndo,
    this.onShowHistory,
    this.onOpenWater,
  });

  @override
  State<_HabitItem> createState() => _HabitItemState();
}

class _HabitItemState extends State<_HabitItem>
    with SingleTickerProviderStateMixin {
  AppLocalizations get _l10n => AppLocalizations.of(context);

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
    if (widget.habit.frequency == HabitFrequency.repeatable) {
      return _buildRepeatableCard();
    }
    if (widget.habit.frequency == HabitFrequency.weekly) {
      return _buildWeeklyCard();
    }
    return _buildDailyCard();
  }

  Widget _buildRepeatableCard() {
    final habit = widget.habit;
    final hasActiveRecords = widget.todayCount > 0;
    final hasHistory = widget.historyCount > 0;
    final summary = hasActiveRecords
        ? _l10n.htRepeatTodaySummary(
            widget.todayCount,
            widget.latestTodayTime ?? '',
          )
        : hasHistory
        ? _l10n.htRepeatOnlyCancelledToday
        : _l10n.htRepeatNoneToday;

    return Container(
      key: ValueKey('repeatable-habit-${habit.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppCardStyle.radius),
        border: AppCardStyle.hairline,
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListTile(
                minTileHeight: 82,
                onTap: widget.onShowHistory,
                contentPadding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                leading: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasActiveRecords
                        ? Colors.deepOrange.shade50
                        : AppSurfaces.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${widget.todayCount}',
                    style: AppType.digits(
                      fontSize: 18,
                      color: hasActiveRecords
                          ? Colors.deepOrange.shade700
                          : AppInk.faint,
                    ),
                  ),
                ),
                title: Text(
                  habit.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppInk.strong,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _l10n.htRepeatPerTime(habit.points),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.deepOrange.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: hasHistory ? AppInk.soft : AppInk.faint,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: hasHistory ? AppInk.soft : AppInk.faint,
                                fontWeight: hasHistory
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasHistory) ...[
                            const SizedBox(width: 1),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 14,
                              color: AppInk.iconFaint,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: FilledButton.icon(
                  key: ValueKey(
                    widget.onOpenWater != null
                        ? 'repeatable-water-${habit.id}'
                        : 'repeatable-add-${habit.id}',
                  ),
                  onPressed: widget.busy
                      ? null
                      : (widget.onOpenWater ?? widget.onCheckIn),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: widget.onOpenWater != null
                        ? Colors.lightBlue.shade50
                        : Colors.deepOrange.shade50,
                    foregroundColor: widget.onOpenWater != null
                        ? Colors.lightBlue.shade700
                        : Colors.deepOrange.shade700,
                    disabledBackgroundColor: AppSurfaces.fill,
                    disabledForegroundColor: AppInk.faint,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: widget.busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.onOpenWater != null
                              ? Icons.local_drink_rounded
                              : Icons.add_rounded,
                          size: 18,
                        ),
                  label: Text(
                    widget.onOpenWater != null
                        ? _l10n.htWaterGo
                        : _l10n.htLogOnce,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            splashColor: (done ? AppInk.faint : Colors.green).withValues(
              alpha: 0.12,
            ),
            highlightColor: (done ? AppInk.faint : Colors.green).withValues(
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
                              color: done ? null : AppSurfaces.fill,
                              border: done
                                  ? null
                                  : Border.all(
                                      color: AppSurfaces.divider,
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
                            color: done ? AppInk.faint : AppInk.strong,
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
                                      ? _l10n.htHabitPointsMinutes(
                                          habit.points,
                                          habit.minutes,
                                        )
                                      : _l10n.pmHabitPoints(habit.points),
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
                                      : AppInk.faint,
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
                          color: done ? AppInk.faint : AppInk.strong,
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
