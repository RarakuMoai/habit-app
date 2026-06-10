// 常用獎勵選取 sheet：勾選並可個別調整積分／時間
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'family_presets.dart';
import 'family_widgets.dart';

Widget _buildRewardPresetCustomization(
  BuildContext context,
  Preset p,
  RewardPresetCfg cfg,
  StateSetter setS,
) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.purple.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.purple.shade100),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.timer_outlined, size: 15, color: Colors.purple.shade400),
        const SizedBox(width: 10),
        AdjustBtn(
          icon: Icons.remove,
          enabled: cfg.minutes > 0,
          onTap: () =>
              setS(() => cfg.minutes = cfg.minutes <= 5 ? 0 : cfg.minutes - 5),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () async {
            final result = await showFamilyMinutesDialog(context, cfg.minutes);
            if (result != null) setS(() => cfg.minutes = result);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.purple.shade300, width: 1.5),
              ),
            ),
            child: Text(
              cfg.minutes > 0 ? '${cfg.minutes}' : '--',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cfg.minutes > 0 ? Colors.black87 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
        Text('分鐘', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
  );
}

Future<Map<String, RewardPresetCfg>?> showRewardPresetSheet(
  BuildContext context,
  List<Preset> available,
  Map<String, RewardPresetCfg> initial,
) {
  final tempSelected = <String, RewardPresetCfg>{
    for (final e in initial.entries)
      e.key: RewardPresetCfg(points: e.value.points, minutes: e.value.minutes),
  };
  return showModalBottomSheet<Map<String, RewardPresetCfg>>(
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
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.purple.shade600,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '常用獎勵',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (tempSelected.isNotEmpty)
                    Text(
                      '${tempSelected.length} 項已選',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
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
                  final hasCustom = p.supportsFrequency;
                  final pts = cfg?.points ?? p.value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: sel ? Colors.purple.shade50 : Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100),
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setS(() {
                            if (sel) {
                              tempSelected.remove(p.name);
                            } else {
                              tempSelected[p.name] = RewardPresetCfg(
                                points: p.value,
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
                                        sel &&
                                                hasCustom &&
                                                cfg != null &&
                                                cfg.minutes > 0
                                            ? '${p.name} ${cfg.minutes} 分鐘'
                                            : p.name,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: sel
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: sel
                                              ? Colors.purple.shade800
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (!sel && hasCustom)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            '可自訂時間',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // 積分徽章（點擊可調整）
                                GestureDetector(
                                  onTap: () async {
                                    if (!sel) {
                                      setS(
                                        () => tempSelected[p.name] =
                                            RewardPresetCfg(points: p.value),
                                      );
                                    }
                                    final ctrl = TextEditingController(
                                      text: '$pts',
                                    );
                                    final newPts = await showDialog<int>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: Text('調整積分：${p.name}'),
                                        content: TextField(
                                          controller: ctrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(4),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: '所需積分',
                                          ),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dCtx),
                                            child: Text(
                                              '取消',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dCtx,
                                              int.tryParse(ctrl.text) ?? pts,
                                            ),
                                            child: const Text('確認'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (newPts != null && newPts > 0) {
                                      setS(() {
                                        if (tempSelected.containsKey(p.name)) {
                                          tempSelected[p.name]!.points = newPts;
                                        } else {
                                          tempSelected[p.name] =
                                              RewardPresetCfg(points: newPts);
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
                                          ? Colors.purple.shade600
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$pts',
                                          style: TextStyle(
                                            color: sel
                                                ? Colors.white
                                                : Colors.grey.shade600,
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
                                        ? Colors.purple.shade600
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: sel
                                          ? Colors.purple.shade600
                                          : Colors.grey.shade300,
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
                              ? _buildRewardPresetCustomization(
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
                    backgroundColor: Colors.purple.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    tempSelected.isEmpty
                        ? '確認（未選取）'
                        : '確認選取 (${tempSelected.length} 項)',
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
