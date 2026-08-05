// 新增／編輯扣分項目 bottom sheet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import 'family_models.dart';
import 'family_presets.dart';
import 'family_store.dart';
import 'family_widgets.dart';
import 'preset_pick_sheet.dart';

int _deductionPresetPoints(String name) {
  for (final p in kDeductionPresets) {
    if (p.name == name) return p.value;
  }
  return 5;
}

// ── 新增扣分項目 ──
Future<void> showAddDeductionSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required List<ChildData> children,
  required List<DeductionItem> existingDeductions,
  required Future<void> Function() onSaved,
}) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController();
  final pointCtrl = TextEditingController(text: '5');
  final selectedIds = Set<String>.from(children.map((c) => c.id));
  final selectedPresets = <String>{};
  final selectedPresetPts = <String, int>{};

  final existingNames = existingDeductions.map((d) => d.name).toSet();
  final available = kDeductionPresets
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
        final total = (customName.isNotEmpty ? 1 : 0) + selectedPresets.length;
        final pts = int.tryParse(pointCtrl.text.trim()) ?? 0;
        final hasCustom = customName.isNotEmpty;
        final canAdd =
            (hasCustom || selectedPresets.isNotEmpty) &&
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
                  l10n.dsAddTitle,
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
                      selectedColor: Colors.red.shade100,
                      checkmarkColor: Colors.red,
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

                // 從常用項目選取 按鈕
                if (available.isNotEmpty) ...[
                  InkWell(
                    onTap: () async {
                      final result = await showFamilyPresetSubSheet(
                        context,
                        available,
                        Map.fromEntries(
                          selectedPresets.map(
                            (n) => MapEntry(
                              n,
                              selectedPresetPts[n] ?? _deductionPresetPoints(n),
                            ),
                          ),
                        ),
                        title: l10n.dsPresetTitle,
                        accentColor: Colors.red.shade600,
                        badgePrefix: '-',
                        dialogLabel: l10n.htDeductHowMany,
                      );
                      if (result != null) {
                        setS(() {
                          selectedPresets.clear();
                          selectedPresetPts.clear();
                          selectedPresets.addAll(result.keys);
                          selectedPresetPts.addAll(result);
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
                        color: selectedPresets.isEmpty
                            ? AppSurfaces.fill
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresets.isEmpty
                              ? AppSurfaces.divider
                              : Colors.red.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresets.isEmpty
                                ? AppInk.soft
                                : Colors.red.shade600,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresets.isEmpty
                                  ? l10n.dsPickPreset
                                  : l10n.dsPickedPresets(
                                      selectedPresets.length,
                                    ),
                              style: TextStyle(
                                color: selectedPresets.isEmpty
                                    ? AppInk.soft
                                    : Colors.red.shade700,
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
                                : Colors.red.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 自訂名稱
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.dsCustomNameHint,
                    filled: true,
                    fillColor: AppSurfaces.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ),

                // 自訂扣分（有輸入名稱才顯示）
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
                      LengthLimitingTextInputFormatter(kFamilyPointsMaxDigits),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.dsCustomPoints,
                      filled: true,
                      fillColor: AppSurfaces.fill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                      ),
                      suffixIcon: const FamilyNumberKeyboardDoneButton(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // 新增按鈕
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canAdd
                        ? () async {
                            Navigator.pop(ctx);
                            final deductions = await loadDeductions(prefs);
                            for (final presetName in selectedPresets) {
                              final deductPts =
                                  selectedPresetPts[presetName] ??
                                  _deductionPresetPoints(presetName);
                              for (final childId in selectedIds) {
                                deductions.add(
                                  DeductionItem(
                                    id: genId(),
                                    childId: childId,
                                    name: presetName,
                                    points: deductPts,
                                  ),
                                );
                              }
                            }
                            if (customName.isNotEmpty) {
                              final customPts =
                                  int.tryParse(pointCtrl.text.trim()) ?? 5;
                              for (final childId in selectedIds) {
                                deductions.add(
                                  DeductionItem(
                                    id: genId(),
                                    childId: childId,
                                    name: customName,
                                    points: customPts,
                                  ),
                                );
                              }
                            }
                            await saveDeductions(prefs, deductions);
                            await onSaved();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: AppSurfaces.divider,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      total == 0 ? l10n.dsPickOrType : l10n.hsAddCount(total),
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

// ── 編輯扣分項目 ──
Future<void> showEditDeductionSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required DeductionItem item,
  required Future<void> Function() onSaved,
}) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController(text: item.name);
  final pointCtrl = TextEditingController(text: item.points.toString());

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
                l10n.dsEditTitle,
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
                  labelText: l10n.dsNameLabel,
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
                  labelText: l10n.htDeductHowMany,
                  filled: true,
                  fillColor: AppSurfaces.fill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.remove_circle_outline, size: 18),
                  suffixIcon: const FamilyNumberKeyboardDoneButton(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSave
                      ? () async {
                          Navigator.pop(ctx);
                          final deductions = await loadDeductions(prefs);
                          final idx = deductions.indexWhere(
                            (d) => d.id == item.id,
                          );
                          if (idx != -1) {
                            deductions[idx] = DeductionItem(
                              id: item.id,
                              childId: item.childId,
                              name: name,
                              points: pts,
                            );
                          }
                          await saveDeductions(prefs, deductions);
                          await onSaved();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
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
        );
      },
    ),
  );
}
