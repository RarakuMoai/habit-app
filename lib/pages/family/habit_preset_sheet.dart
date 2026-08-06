// 常用習慣選取 sheet：勾選並可個別調整積分／時間／頻率
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import '../../widgets/sheet_drag_handle.dart';
import 'family_models.dart';
import 'family_presets.dart';
import 'family_widgets.dart';

Widget _buildFamilyPresetCustomization(
  BuildContext context,
  Preset p,
  HabitPresetCfg cfg,
  StateSetter setS,
) {
  final l10n = AppLocalizations.of(context);
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orange.shade100),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 15, color: Colors.orange.shade500),
            const SizedBox(width: 10),
            AdjustBtn(
              icon: Icons.remove,
              enabled: cfg.minutes > 0,
              onTap: () => setS(
                () => cfg.minutes = cfg.minutes <= 5 ? 0 : cfg.minutes - 5,
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: () async {
                final result = await showFamilyMinutesDialog(
                  context,
                  cfg.minutes,
                );
                if (result != null) setS(() => cfg.minutes = result);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.orange.shade300,
                      width: 1.5,
                    ),
                  ),
                ),
                child: Text(
                  cfg.minutes > 0 ? '${cfg.minutes}' : '--',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cfg.minutes > 0 ? AppInk.strong : AppInk.faint,
                  ),
                ),
              ),
            ),
            Text(
              l10n.fwMinutes,
              style: TextStyle(fontSize: 13, color: AppInk.soft),
            ),
            const SizedBox(width: 14),
            AdjustBtn(
              icon: Icons.add,
              enabled: cfg.minutes < 999,
              onTap: () => setS(
                () => cfg.minutes = cfg.minutes == 0
                    ? 5
                    : (cfg.minutes + 5).clamp(5, 999),
              ),
            ),
          ],
        ),
        if (p.supportsFrequency) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Colors.orange.shade100),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Icon(Icons.repeat, size: 15, color: Colors.orange.shade500),
              FreqChip(
                label: l10n.hsDaily,
                selected: cfg.frequency == HabitFrequency.daily,
                onTap: () => setS(() => cfg.frequency = HabitFrequency.daily),
              ),
              FreqChip(
                label: l10n.hsRepeatable,
                selected: cfg.frequency == HabitFrequency.repeatable,
                onTap: () =>
                    setS(() => cfg.frequency = HabitFrequency.repeatable),
              ),
              FreqChip(
                label: l10n.hsWeekly,
                selected: cfg.frequency == HabitFrequency.weekly,
                onTap: () => setS(() => cfg.frequency = HabitFrequency.weekly),
              ),
            ],
          ),
          if (cfg.frequency == HabitFrequency.weekly)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.hpsWeeklyTarget,
                    style: TextStyle(fontSize: 12, color: AppInk.soft),
                  ),
                  const SizedBox(width: 12),
                  AdjustBtn(
                    icon: Icons.remove,
                    enabled: cfg.weeklyTarget > 1,
                    onTap: () => setS(() => cfg.weeklyTarget--),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${cfg.weeklyTarget}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    l10n.hpsTimes,
                    style: TextStyle(fontSize: 13, color: AppInk.soft),
                  ),
                  const SizedBox(width: 10),
                  AdjustBtn(
                    icon: Icons.add,
                    enabled: cfg.weeklyTarget < 7,
                    onTap: () => setS(() => cfg.weeklyTarget++),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

Future<Map<String, HabitPresetCfg>?> showHabitPresetSheet(
  BuildContext context,
  List<Preset> available,
  Map<String, HabitPresetCfg> initial,
) {
  final l10n = AppLocalizations.of(context);
  final tempSelected = <String, HabitPresetCfg>{
    for (final e in initial.entries)
      e.key: HabitPresetCfg(
        points: e.value.points,
        minutes: e.value.minutes,
        frequency: e.value.frequency,
        weeklyTarget: e.value.weeklyTarget,
      ),
  };
  return showModalBottomSheet<Map<String, HabitPresetCfg>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: SheetDragHandle(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.hpsPresetTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (tempSelected.isNotEmpty)
                    Text(
                      l10n.ppsSelectedCount(tempSelected.length),
                      style: TextStyle(fontSize: 12, color: AppInk.soft),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final p = available[i];
                  final sel = tempSelected.containsKey(p.name);
                  final cfg = tempSelected[p.name];
                  final hasCustom = p.defaultMinutes > 0 || p.supportsFrequency;
                  final pts = cfg?.points ?? p.value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: sel ? Colors.orange.shade50 : Colors.white,
                      border: Border(
                        bottom: BorderSide(color: AppSurfaces.fill),
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setS(() {
                            if (sel) {
                              tempSelected.remove(p.name);
                            } else {
                              tempSelected[p.name] = HabitPresetCfg(
                                points: p.value,
                                minutes: p.defaultMinutes,
                              );
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  p.emoji,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: sel
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: sel
                                              ? Colors.orange.shade800
                                              : AppInk.strong,
                                        ),
                                      ),
                                      if (!sel && hasCustom)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            p.supportsFrequency
                                                ? l10n.hpsCustomizableFreq
                                                : l10n.hpsCustomizable,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppInk.soft,
                                            ),
                                          ),
                                        ),
                                      if (sel && hasCustom && cfg != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            '${cfg.minutes > 0 ? l10n.hpsMinutesSet(cfg.minutes) : l10n.hpsNoDuration}'
                                            '${switch (cfg.frequency) {
                                              HabitFrequency.weekly => l10n.hpsFreqWeekly(cfg.weeklyTarget),
                                              HabitFrequency.repeatable => l10n.hpsFreqRepeatable,
                                              _ => l10n.hpsFreqDaily,
                                            }}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // 積分徽章（家庭模式特有）
                                GestureDetector(
                                  onTap: () async {
                                    if (!sel) {
                                      setS(
                                        () => tempSelected[p.name] =
                                            HabitPresetCfg(
                                              points: p.value,
                                              minutes: p.defaultMinutes,
                                            ),
                                      );
                                    }
                                    final ctrl = TextEditingController(
                                      text: '$pts',
                                    );
                                    final newPts = await showDialog<int>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: Text(
                                          l10n.ppsAdjustPointsFor(p.name),
                                        ),
                                        content: TextField(
                                          controller: ctrl,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) =>
                                              dismissFamilyNumberKeyboard(),
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(
                                              kFamilyPointsMaxDigits,
                                            ),
                                          ],
                                          decoration: InputDecoration(
                                            labelText: l10n.ppsPointsOnDone,
                                            suffixIcon:
                                                const FamilyNumberKeyboardDoneButton(),
                                          ),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dCtx),
                                            child: Text(
                                              l10n.commonCancel,
                                              style: TextStyle(
                                                color: AppInk.soft,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dCtx,
                                              int.tryParse(ctrl.text) ?? pts,
                                            ),
                                            child: Text(l10n.commonConfirm),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (newPts != null && newPts > 0) {
                                      setS(() {
                                        if (tempSelected.containsKey(p.name)) {
                                          tempSelected[p.name]!.points = newPts;
                                        } else {
                                          tempSelected[p.name] = HabitPresetCfg(
                                            points: newPts,
                                            minutes: p.defaultMinutes,
                                          );
                                        }
                                      });
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? Colors.orange
                                          : AppSurfaces.fill,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '+$pts',
                                          style: TextStyle(
                                            color: sel
                                                ? Colors.white
                                                : AppInk.soft,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (sel) ...[
                                          const SizedBox(width: 3),
                                          const Icon(
                                            Icons.edit,
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: sel
                                        ? Colors.orange
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: sel ? Colors.orange : AppInk.faint,
                                      width: 2,
                                    ),
                                  ),
                                  child: sel
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox(
                            width: double.infinity,
                            height: 0,
                          ),
                          secondChild: sel && hasCustom && cfg != null
                              ? _buildFamilyPresetCustomization(
                                  context,
                                  p,
                                  cfg,
                                  setS,
                                )
                              : const SizedBox(
                                  width: double.infinity,
                                  height: 0,
                                ),
                          crossFadeState: (sel && hasCustom)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 220),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, tempSelected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    tempSelected.isEmpty
                        ? l10n.ppsConfirmNone
                        : l10n.ppsConfirmCount(tempSelected.length),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
