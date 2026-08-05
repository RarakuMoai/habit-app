// 常用選項子選單：可捲動清單，每項可個別調整數值（名稱＋分數）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_style.dart';
import 'family_presets.dart';
import 'family_widgets.dart';

// 常用選項子選單：可捲動清單，每項可個別調整數值
Future<Map<String, int>?> showFamilyPresetSubSheet(
  BuildContext context,
  List<Preset> available,
  Map<String, int> initial, {
  // 預設文案不能寫在參數預設值（要編譯期常數），null 進來後才取 l10n。
  String? title,
  Color accentColor = Colors.orange,
  String badgePrefix = '+',
  String? dialogLabel,
  String? adjustDialogTitle,
}) {
  final l10n = AppLocalizations.of(context);
  title ??= l10n.ppsPresetHabits;
  dialogLabel ??= l10n.ppsPointsOnDone;
  adjustDialogTitle ??= l10n.ppsAdjustPoints;
  final selected = Map<String, int>.from(initial);
  return showModalBottomSheet<Map<String, int>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppSurfaces.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (selected.isNotEmpty)
                    Text(
                      l10n.ppsSelectedCount(selected.length),
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
                  final sel = selected.containsKey(p.name);
                  final pts = selected[p.name] ?? p.value;
                  return InkWell(
                    onTap: () => setS(() {
                      if (sel) {
                        selected.remove(p.name);
                      } else {
                        selected[p.name] = p.value;
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: sel
                            ? accentColor.withValues(alpha: 0.08)
                            : Colors.white,
                        border: Border(
                          bottom: BorderSide(color: AppSurfaces.fill),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(p.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: sel ? accentColor : AppInk.strong,
                              ),
                            ),
                          ),
                          // 積分徽章（點擊可調整）
                          GestureDetector(
                            onTap: () async {
                              if (!sel) {
                                setS(() => selected[p.name] = p.value);
                              }
                              final ctrl = TextEditingController(text: '$pts');
                              final newPts = await showDialog<int>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  title: Text('$adjustDialogTitle：${p.name}'),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) =>
                                        dismissFamilyNumberKeyboard(),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(
                                        kFamilyPointsMaxDigits,
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: dialogLabel,
                                      suffixIcon:
                                          const FamilyNumberKeyboardDoneButton(),
                                    ),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dCtx),
                                      child: Text(
                                        l10n.commonCancel,
                                        style: TextStyle(color: AppInk.soft),
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
                                setS(() => selected[p.name] = newPts);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: sel ? accentColor : AppSurfaces.fill,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$badgePrefix$pts',
                                    style: TextStyle(
                                      color: sel ? Colors.white : AppInk.soft,
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
                              color: sel ? accentColor : Colors.transparent,
                              border: Border.all(
                                color: sel ? accentColor : AppInk.faint,
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
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    selected.isEmpty
                        ? l10n.ppsConfirmNone
                        : l10n.ppsConfirmCount(selected.length),
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
