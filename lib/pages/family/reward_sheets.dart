// 新增／編輯獎勵 bottom sheet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../widgets/sheet_drag_handle.dart';
import 'family_models.dart';
import 'family_presets.dart';
import 'family_store.dart';
import 'family_widgets.dart';
import 'reward_preset_sheet.dart';

// ── 新增獎勵 ──
Future<void> showAddRewardSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required List<ChildData> children,
  required List<RewardItem> existingRewards,
  required Future<void> Function() onSaved,
}) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController();
  final pointCtrl = TextEditingController();
  final selectedIds = Set<String>.from(children.map((c) => c.id));
  final selectedPresetCfgs = <String, RewardPresetCfg>{};

  final existingNames = existingRewards.map((r) => r.name).toSet();
  final available = kRewardPresets
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
          child: PinnedHandleSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.rsAddTitle,
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
                      selectedColor: Colors.purple.shade100,
                      checkmarkColor: Colors.purple,
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

                // 從常用獎勵選取 按鈕
                if (available.isNotEmpty) ...[
                  InkWell(
                    onTap: () async {
                      final result = await showRewardPresetSheet(
                        context,
                        available,
                        Map.from(selectedPresetCfgs),
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
                            : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPresetCfgs.isEmpty
                              ? AppSurfaces.divider
                              : Colors.purple.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: selectedPresetCfgs.isEmpty
                                ? AppInk.soft
                                : Colors.purple.shade600,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedPresetCfgs.isEmpty
                                  ? l10n.rsPickPreset
                                  : l10n.rsPickedPresets(
                                      selectedPresetCfgs.length,
                                    ),
                              style: TextStyle(
                                color: selectedPresetCfgs.isEmpty
                                    ? AppInk.soft
                                    : Colors.purple.shade700,
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
                                : Colors.purple.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 自訂獎勵名稱
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.rsCustomNameHint,
                    filled: true,
                    fillColor: AppSurfaces.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.card_giftcard_outlined,
                      size: 18,
                    ),
                  ),
                ),

                // 自訂積分（有輸入名稱才顯示）
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
                      labelText: l10n.rsPointsCost,
                      filled: true,
                      fillColor: AppSurfaces.fill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.stars_outlined, size: 18),
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
                            final rewards = await loadRewards(prefs);
                            for (final e in selectedPresetCfgs.entries) {
                              final rewardName = e.value.minutes > 0
                                  ? l10n.rsNameMinutes(e.key, e.value.minutes)
                                  : e.key;
                              rewards.add(
                                RewardItem(
                                  id: genId(),
                                  name: rewardName,
                                  pointsCost: e.value.points,
                                  minutes: e.value.minutes,
                                  childIds: selectedIds.toList(),
                                ),
                              );
                            }
                            if (customName.isNotEmpty) {
                              final customPts =
                                  int.tryParse(pointCtrl.text.trim()) ?? 0;
                              rewards.add(
                                RewardItem(
                                  id: genId(),
                                  name: customName,
                                  pointsCost: customPts,
                                  childIds: selectedIds.toList(),
                                ),
                              );
                            }
                            await saveRewards(prefs, rewards);
                            await onSaved();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      disabledBackgroundColor: AppSurfaces.divider,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      total == 0 ? l10n.rsPickOrType : l10n.hsAddCount(total),
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

// ── 編輯獎勵 ──
Future<void> showEditRewardSheet(
  BuildContext context, {
  required SharedPreferences prefs,
  required RewardItem reward,
  required List<ChildData> children,
  required Future<void> Function() onSaved,
}) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController(text: reward.name);
  final pointCtrl = TextEditingController(text: reward.pointsCost.toString());
  final selectedIds = Set<String>.from(reward.childIds);

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
        final canSave = name.isNotEmpty && pts > 0 && selectedIds.isNotEmpty;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: PinnedHandleSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.rsEditTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.hsApplyToChildren,
                  style: TextStyle(fontSize: 12, color: AppInk.soft),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: children.map((c) {
                    final sel = selectedIds.contains(c.id);
                    return FilterChip(
                      label: Text(c.name),
                      selected: sel,
                      selectedColor: Colors.purple.shade100,
                      checkmarkColor: Colors.purple,
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
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.rsNameLabel,
                    filled: true,
                    fillColor: AppSurfaces.fill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.card_giftcard_outlined,
                      size: 18,
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
                    labelText: l10n.rsPointsCost,
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSave
                        ? () async {
                            Navigator.pop(ctx);
                            final rewards = await loadRewards(prefs);
                            final idx = rewards.indexWhere(
                              (r) => r.id == reward.id,
                            );
                            if (idx != -1) {
                              rewards[idx] = RewardItem(
                                id: reward.id,
                                name: name,
                                pointsCost: pts,
                                minutes: reward.minutes,
                                childIds: selectedIds.toList(),
                              );
                            }
                            await saveRewards(prefs, rewards);
                            await onSaved();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
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
