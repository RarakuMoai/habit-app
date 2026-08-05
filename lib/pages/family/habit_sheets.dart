// 新增／編輯習慣 bottom sheet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
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
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController();
  final pointCtrl = TextEditingController(text: '10');
  final selectedIds = Set<String>.from(children.map((c) => c.id));
  final selectedPresetCfgs = <String, HabitPresetCfg>{};
  var freq = HabitFrequency.daily;
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
                      color: AppSurfaces.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.hsAddTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),

                // 套用小孩
                Text(
                  l10n.hsApplyToChildren,
                  style: TextStyle(fontSize: 12, color: AppInk.soft),
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
                            ? AppSurfaces.fill
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresetCfgs.isEmpty
                              ? AppSurfaces.divider
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresetCfgs.isEmpty
                                ? AppInk.soft
                                : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresetCfgs.isEmpty
                                  ? l10n.hsPickPreset
                                  : l10n.hsPickedPresets(
                                      selectedPresetCfgs.length,
                                    ),
                              style: TextStyle(
                                color: selectedPresetCfgs.isEmpty
                                    ? AppInk.soft
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
                                ? AppInk.faint
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
                                : AppSurfaces.fill)
                          : AppSurfaces.fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: customExpanded
                            ? (hasCustom
                                  ? Colors.deepOrange.shade300
                                  : AppSurfaces.divider)
                            : AppSurfaces.divider,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 18,
                          color: hasCustom
                              ? Colors.deepOrange.shade500
                              : AppInk.soft,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasCustom ? customName : l10n.hsCustomHabit,
                            style: TextStyle(
                              color: hasCustom
                                  ? Colors.deepOrange.shade700
                                  : AppInk.soft,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(
                          customExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: AppInk.faint,
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
                      color: AppSurfaces.fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppSurfaces.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          onChanged: (_) => setS(() {}),
                          maxLength: 20,
                          decoration: InputDecoration(
                            hintText: l10n.hsNameHint,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppSurfaces.divider,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppSurfaces.divider,
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
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => dismissFamilyNumberKeyboard(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                              kFamilyPointsMaxDigits,
                            ),
                          ],
                          decoration: InputDecoration(
                            hintText: l10n.hsPointsHint,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppSurfaces.divider,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppSurfaces.divider,
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
                            suffixIcon: const FamilyNumberKeyboardDoneButton(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.hsFrequency,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppInk.soft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FreqChip(
                              label: l10n.hsDaily,
                              selected: freq == HabitFrequency.daily,
                              onTap: () =>
                                  setS(() => freq = HabitFrequency.daily),
                            ),
                            FreqChip(
                              label: l10n.hsRepeatable,
                              selected: freq == HabitFrequency.repeatable,
                              onTap: () =>
                                  setS(() => freq = HabitFrequency.repeatable),
                            ),
                            FreqChip(
                              label: l10n.hsWeekly,
                              selected: freq == HabitFrequency.weekly,
                              onTap: () =>
                                  setS(() => freq = HabitFrequency.weekly),
                            ),
                          ],
                        ),
                        if (freq == HabitFrequency.repeatable)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 2),
                            child: Text(
                              l10n.hsRepeatableHint,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (freq == HabitFrequency.weekly)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                  l10n.hsTimesSuffix,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppInk.soft,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AdjustBtn(
                                  icon: Icons.add,
                                  enabled: weeklyTarget < 7,
                                  onTap: () => setS(() => weeklyTarget++),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.hsDurationOptional,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppInk.soft,
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
                                  : AppSurfaces.divider,
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
                                        : AppSurfaces.divider,
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: minutes > 0
                                    ? Colors.orange.shade200
                                    : AppSurfaces.divider,
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
                                            ? AppInk.strong
                                            : AppInk.faint,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.fwMinutes,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: minutes > 0
                                            ? AppInk.soft
                                            : AppInk.faint,
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
                                    : AppSurfaces.divider,
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
                      disabledBackgroundColor: AppSurfaces.divider,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      total == 0 ? l10n.hsPickOrType : l10n.hsAddCount(total),
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
  final l10n = AppLocalizations.of(context);
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
                      color: AppSurfaces.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.hsEditTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.hsNameHint,
                    filled: true,
                    fillColor: AppSurfaces.fill,
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
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(kFamilyPointsMaxDigits),
                  ],
                  onChanged: (_) => setS(() {}),
                  onSubmitted: (_) => dismissFamilyNumberKeyboard(),
                  decoration: InputDecoration(
                    labelText: l10n.hsPointsHint,
                    filled: true,
                    fillColor: AppSurfaces.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.stars_outlined, size: 18),
                    suffixIcon: const FamilyNumberKeyboardDoneButton(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.hsFrequency,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppInk.soft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FreqChip(
                      label: l10n.hsDaily,
                      selected: freq == HabitFrequency.daily,
                      onTap: () => setS(() => freq = HabitFrequency.daily),
                    ),
                    FreqChip(
                      label: l10n.hsRepeatable,
                      selected: freq == HabitFrequency.repeatable,
                      onTap: () => setS(() => freq = HabitFrequency.repeatable),
                    ),
                    FreqChip(
                      label: l10n.hsWeekly,
                      selected: freq == HabitFrequency.weekly,
                      onTap: () => setS(() => freq = HabitFrequency.weekly),
                    ),
                  ],
                ),
                if (freq == HabitFrequency.repeatable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      l10n.hsRepeatableHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (freq == HabitFrequency.weekly)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          l10n.hsTimesSuffix,
                          style: TextStyle(fontSize: 13, color: AppInk.soft),
                        ),
                        const SizedBox(width: 8),
                        AdjustBtn(
                          icon: Icons.add,
                          enabled: weeklyTarget < 7,
                          onTap: () => setS(() => weeklyTarget++),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  l10n.hsDurationOptional,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppInk.soft,
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
                          : AppSurfaces.divider,
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
                                : AppSurfaces.divider,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: minutes > 0
                            ? Colors.orange.shade200
                            : AppSurfaces.divider,
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
                                      ? AppInk.strong
                                      : AppInk.faint,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.fwMinutes,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: minutes > 0
                                      ? AppInk.soft
                                      : AppInk.faint,
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
                            : AppSurfaces.divider,
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
                                : AppSurfaces.divider,
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
                      disabledBackgroundColor: AppSurfaces.divider,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      l10n.commonSave,
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
