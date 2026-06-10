// 新增／編輯習慣 bottom sheet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_models.dart';
import 'family_presets.dart';
import 'family_store.dart';
import 'family_widgets.dart';
import 'habit_preset_sheet.dart';

// ── 新增習慣 ──
Future<void> showAddHabitSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required List<ChildData> children,
  required List<ChildHabit> existingHabits,
  required Future<void> Function() onSaved,
}) async {
  final nameCtrl = TextEditingController();
  final pointCtrl = TextEditingController(text: '10');
  final selectedIds = Set<String>.from(children.map((c) => c.id));
  final selectedPresetCfgs = <String, HabitPresetCfg>{};
  var freq = 'daily';
  var weeklyTarget = 3;
  var minutes = 0;
  var customExpanded = false;

  final existingNames = existingHabits.map((h) => h.name).toSet();
  final available = kHabitPresets
      .where((p) => !existingNames.contains(p.name))
      .toList();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) {
        final customName = nameCtrl.text.trim();
        final total =
            (customName.isNotEmpty ? 1 : 0) + selectedPresetCfgs.length;
        final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
        final hasCustom = customName.isNotEmpty;
        final canAdd =
            (hasCustom || selectedPresetCfgs.isNotEmpty) &&
            (!hasCustom || pts > 0) &&
            selectedIds.isNotEmpty;

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
                  '新增習慣',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),

                // 套用小孩
                Text(
                  '套用小孩',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: children.map((c) {
                    final sel = selectedIds.contains(c.id);
                    return FilterChip(
                      label: Text(c.name),
                      selected: sel,
                      selectedColor: Colors.orange.shade100,
                      checkmarkColor: Colors.orange,
                      onSelected: (v) => setS(() {
                        if (v) {
                          selectedIds.add(c.id);
                        } else {
                          selectedIds.remove(c.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // 從常用習慣選取 按鈕
                if (available.isNotEmpty) ...[
                  InkWell(
                    onTap: () async {
                      final result = await showHabitPresetSheet(
                        context,
                        available,
                        selectedPresetCfgs,
                      );
                      if (result != null) {
                        setS(() {
                          selectedPresetCfgs.clear();
                          selectedPresetCfgs.addAll(result);
                        });
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
                        color: selectedPresetCfgs.isEmpty
                            ? Colors.grey.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresetCfgs.isEmpty
                              ? Colors.grey.shade300
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresetCfgs.isEmpty
                                ? Colors.grey.shade500
                                : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresetCfgs.isEmpty
                                  ? '從常用習慣選取'
                                  : '已選 ${selectedPresetCfgs.length} 個常用習慣',
                              style: TextStyle(
                                color: selectedPresetCfgs.isEmpty
                                    ? Colors.grey.shade600
                                    : Colors.orange.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            selectedPresetCfgs.isEmpty
                                ? Icons.chevron_right
                                : Icons.check_circle,
                            size: 20,
                            color: selectedPresetCfgs.isEmpty
                                ? Colors.grey.shade400
                                : Colors.orange.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 自訂習慣 toggle
                InkWell(
                  onTap: () => setS(() => customExpanded = !customExpanded),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: customExpanded
                          ? (hasCustom
                                ? Colors.deepOrange.shade50
                                : Colors.grey.shade100)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: customExpanded
                            ? (hasCustom
                                  ? Colors.deepOrange.shade300
                                  : Colors.grey.shade300)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 18,
                          color: hasCustom
                              ? Colors.deepOrange.shade500
                              : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasCustom ? customName : '自訂習慣',
                            style: TextStyle(
                              color: hasCustom
                                  ? Colors.deepOrange.shade700
                                  : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(
                          customExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          onChanged: (_) => setS(() {}),
                          maxLength: 20,
                          decoration: InputDecoration(
                            hintText: '習慣名稱',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.orange.shade400,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: pointCtrl,
                          onChanged: (_) => setS(() {}),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: InputDecoration(
                            hintText: '完成可得分數',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.orange.shade400,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            prefixIcon: const Icon(
                              Icons.star_outline,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '頻率',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            FreqChip(
                              label: '每日',
                              selected: freq == 'daily',
                              onTap: () => setS(() => freq = 'daily'),
                            ),
                            const SizedBox(width: 8),
                            FreqChip(
                              label: '每週',
                              selected: freq == 'weekly',
                              onTap: () => setS(() => freq = 'weekly'),
                            ),
                            if (freq == 'weekly') ...[
                              const SizedBox(width: 16),
                              AdjustBtn(
                                icon: Icons.remove,
                                enabled: weeklyTarget > 1,
                                onTap: () => setS(() => weeklyTarget--),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$weeklyTarget',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '  次',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AdjustBtn(
                                icon: Icons.add,
                                enabled: weeklyTarget < 7,
                                onTap: () => setS(() => weeklyTarget++),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '持續時間（選填）',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: minutes > 0
                                  ? Colors.orange.shade300
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            color: minutes > 0
                                ? Colors.orange.shade50
                                : Colors.white,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: minutes > 0
                                    ? () => setS(
                                        () => minutes = minutes <= 5
                                            ? 0
                                            : minutes - 5,
                                      )
                                    : null,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.remove,
                                    size: 18,
                                    color: minutes > 0
                                        ? Colors.orange.shade700
                                        : Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: minutes > 0
                                    ? Colors.orange.shade200
                                    : Colors.grey.shade200,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      minutes > 0 ? '$minutes' : '--',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: minutes > 0
                                            ? Colors.black87
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '分鐘',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: minutes > 0
                                            ? Colors.grey.shade600
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: minutes > 0
                                    ? Colors.orange.shade200
                                    : Colors.grey.shade200,
                              ),
                              GestureDetector(
                                onTap: () => setS(
                                  () => minutes = minutes == 0
                                      ? 5
                                      : (minutes + 5).clamp(5, 999),
                                ),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.add,
                                    size: 18,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: customExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
                const SizedBox(height: 20),

                // 新增按鈕
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canAdd
                        ? () async {
                            Navigator.pop(ctx);
                            final habits = await loadHabits(prefs);
                            // 常用習慣（各自積分/時間/頻率）
                            for (final e in selectedPresetCfgs.entries) {
                              for (final childId in selectedIds) {
                                habits.add(
                                  ChildHabit(
                                    id: genId(),
                                    childId: childId,
                                    name: e.key,
                                    points: e.value.points,
                                    frequency: e.value.frequency,
                                    weeklyTarget: e.value.weeklyTarget,
                                    minutes: e.value.minutes,
                                  ),
                                );
                              }
                            }
                            // 自訂習慣
                            if (customName.isNotEmpty) {
                              final customPts =
                                  int.tryParse(pointCtrl.text.trim()) ?? 10;
                              for (final childId in selectedIds) {
                                habits.add(
                                  ChildHabit(
                                    id: genId(),
                                    childId: childId,
                                    name: customName,
                                    points: customPts,
                                    frequency: freq,
                                    weeklyTarget: weeklyTarget,
                                    minutes: minutes,
                                  ),
                                );
                              }
                            }
                            await saveHabits(prefs, habits);
                            await onSaved();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      total == 0 ? '請選擇或輸入習慣' : '新增 ($total 項)',
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

// ── 編輯習慣 ──
Future<void> showEditHabitSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required ChildHabit habit,
  required Future<void> Function() onSaved,
}) async {
  final nameCtrl = TextEditingController(text: habit.name);
  final pointCtrl = TextEditingController(text: habit.points.toString());
  var freq = habit.frequency;
  var weeklyTarget = habit.weeklyTarget;
  var minutes = habit.minutes;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) {
        final name = nameCtrl.text.trim();
        final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
        final canSave = name.isNotEmpty && pts > 0;
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
                  '編輯習慣',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: '習慣名稱',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pointCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: '完成可得分數',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.stars_outlined, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '頻率',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    FreqChip(
                      label: '每日',
                      selected: freq == 'daily',
                      onTap: () => setS(() => freq = 'daily'),
                    ),
                    const SizedBox(width: 8),
                    FreqChip(
                      label: '每週',
                      selected: freq == 'weekly',
                      onTap: () => setS(() => freq = 'weekly'),
                    ),
                    if (freq == 'weekly') ...[
                      const SizedBox(width: 16),
                      AdjustBtn(
                        icon: Icons.remove,
                        enabled: weeklyTarget > 1,
                        onTap: () => setS(() => weeklyTarget--),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$weeklyTarget',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '  次',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AdjustBtn(
                        icon: Icons.add,
                        enabled: weeklyTarget < 7,
                        onTap: () => setS(() => weeklyTarget++),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '持續時間（選填）',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: minutes > 0
                          ? Colors.orange.shade300
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    color: minutes > 0 ? Colors.orange.shade50 : Colors.white,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: minutes > 0
                            ? () => setS(
                                () => minutes = minutes <= 5 ? 0 : minutes - 5,
                              )
                            : null,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.remove,
                            size: 18,
                            color: minutes > 0
                                ? Colors.orange.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: minutes > 0
                            ? Colors.orange.shade200
                            : Colors.grey.shade200,
                      ),
                      GestureDetector(
                        onTap: () async {
                          final r = await showFamilyMinutesDialog(
                            context,
                            minutes,
                          );
                          if (r != null) setS(() => minutes = r);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                minutes > 0 ? '$minutes' : '--',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: minutes > 0
                                      ? Colors.black87
                                      : Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '分鐘',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: minutes > 0
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: minutes > 0
                            ? Colors.orange.shade200
                            : Colors.grey.shade200,
                      ),
                      GestureDetector(
                        onTap: minutes < 999
                            ? () => setS(
                                () => minutes = minutes == 0
                                    ? 5
                                    : (minutes + 5).clamp(5, 999),
                              )
                            : null,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.add,
                            size: 18,
                            color: minutes < 999
                                ? Colors.orange.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSave
                        ? () async {
                            Navigator.pop(ctx);
                            final habits = await loadHabits(prefs);
                            final idx = habits.indexWhere(
                              (h) => h.id == habit.id,
                            );
                            if (idx != -1) {
                              habits[idx] = ChildHabit(
                                id: habit.id,
                                childId: habit.childId,
                                name: name,
                                points: pts,
                                completedDate: habit.completedDate,
                                frequency: freq,
                                weeklyTarget: weeklyTarget,
                                weeklyDates: habit.weeklyDates,
                                minutes: minutes,
                              );
                            }
                            await saveHabits(prefs, habits);
                            await onSaved();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '儲存',
                      style: TextStyle(color: Colors.white),
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
