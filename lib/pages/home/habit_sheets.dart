// 首頁的新增／編輯習慣 bottom sheet 與相關對話框。
// 這裡只負責互動 UI；習慣資料的實際變更由呼叫端透過 callback 處理。
import 'package:flutter/material.dart';

import '../../utils/input_formatters.dart';
import 'home_presets.dart';
import 'home_widgets.dart';

const Color _kWaterLinkedAccent = Color(0xFF42A5F5);
const Color _kWeightLinkedAccent = Color(0xFF7E57C2);

Color _linkedAccentForPreset(HomePreset preset) =>
    preset.name == '體重紀錄' ? _kWeightLinkedAccent : _kWaterLinkedAccent;

// ── 常用習慣子選單（可捲動清單 + 客製化設定）──
Future<Map<String, PresetConfig>?> showHabitPresetSheet(
  BuildContext context,
  List<HomePreset> available,
  Map<String, PresetConfig> initialSelected,
) {
  final tempSelected = <String, PresetConfig>{};
  for (final e in initialSelected.entries) {
    tempSelected[e.key] = PresetConfig(
      minutes: e.value.minutes,
      frequency: e.value.frequency,
      weeklyTarget: e.value.weeklyTarget,
    );
  }
  return showModalBottomSheet<Map<String, PresetConfig>>(
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
                  const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '常用習慣',
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
                  final config = tempSelected[p.name];
                  final hasCustom = p.defaultMinutes != null;
                  final linkedAccent = _linkedAccentForPreset(p);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: sel ? Colors.orange.shade50 : Colors.white,
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
                              tempSelected[p.name] = PresetConfig(
                                minutes: p.defaultMinutes ?? 0,
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
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (p.linkedSetting != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.link,
                                                size: 11,
                                                color: linkedAccent,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                p.linkedLabel!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: linkedAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (!sel && hasCustom)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            '可自訂時間${p.supportsFrequency ? "・可設頻率" : ""}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                      if (sel && hasCustom)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            '${config!.minutes > 0 ? "${config.minutes} 分鐘" : "未設時間"}${config.frequency == "weekly" ? "・每週 ${config.weeklyTarget} 次" : "・每日"}',
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
                                      color: sel
                                          ? Colors.orange
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
                          secondChild: sel && hasCustom && config != null
                              ? _presetCustomization(context, p, config, setS)
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

// ── 持續時間輸入對話框 ──
Future<int?> showMinutesDialog(BuildContext context, int current) async {
  final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('持續時間'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(
          suffixText: '分鐘',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        onSubmitted: (v) {
          final n = int.tryParse(v.trim());
          if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
        ),
        TextButton(
          onPressed: () {
            final n = int.tryParse(ctrl.text.trim());
            if (n != null && n > 0) Navigator.pop(ctx, n.clamp(1, 999));
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

// ── preset 自訂設定區（時間／頻率）──
Widget _presetCustomization(
  BuildContext context,
  HomePreset p,
  PresetConfig config,
  StateSetter setS,
) {
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
        // 分鐘調整
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 15, color: Colors.orange.shade500),
            const SizedBox(width: 10),
            AdjustBtn(
              icon: Icons.remove,
              enabled: config.minutes > 0,
              onTap: () => setS(
                () => config.minutes = config.minutes <= 5
                    ? 0
                    : config.minutes - 5,
              ),
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: () async {
                final result = await showMinutesDialog(context, config.minutes);
                if (result != null) setS(() => config.minutes = result);
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
                  config.minutes > 0 ? '${config.minutes}' : '--',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: config.minutes > 0
                        ? Colors.black87
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            Text(
              '分鐘',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 14),
            AdjustBtn(
              icon: Icons.add,
              enabled: config.minutes < 999,
              onTap: () => setS(
                () => config.minutes = config.minutes == 0
                    ? 5
                    : (config.minutes + 5).clamp(5, 999),
              ),
            ),
          ],
        ),
        if (p.supportsFrequency) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Colors.orange.shade100),
          ),
          // 頻率切換
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.repeat, size: 15, color: Colors.orange.shade500),
              const SizedBox(width: 10),
              FreqChip(
                label: '每日',
                selected: config.frequency == 'daily',
                onTap: () => setS(() => config.frequency = 'daily'),
              ),
              const SizedBox(width: 8),
              FreqChip(
                label: '每週',
                selected: config.frequency == 'weekly',
                onTap: () => setS(() => config.frequency = 'weekly'),
              ),
            ],
          ),
          // 每週目標次數（另起一行避免溢出）
          if (config.frequency == 'weekly')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '每週目標',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  AdjustBtn(
                    icon: Icons.remove,
                    enabled: config.weeklyTarget > 1,
                    onTap: () => setS(() => config.weeklyTarget--),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${config.weeklyTarget}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '次',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 10),
                  AdjustBtn(
                    icon: Icons.add,
                    enabled: config.weeklyTarget < 7,
                    onTap: () => setS(() => config.weeklyTarget++),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

// ── 編輯習慣 ──
Future<void> showEditHabitSheet(
  BuildContext context, {
  required Map<String, dynamic> habit,
  required void Function(String newName, String freq, int weeklyTarget) onSave,
}) async {
  final fullName = habit['name'] as String;

  final minuteMatch = RegExp(r'^(.*)\s+(\d+)\s+分鐘$').firstMatch(fullName);
  final initBase = minuteMatch != null ? minuteMatch.group(1)! : fullName;
  final initMinutes = minuteMatch != null
      ? int.parse(minuteMatch.group(2)!)
      : 0;
  final initFreq = (habit['frequency'] ?? 'daily') as String;
  final initWeekly = (habit['weeklyTarget'] as int?) ?? 3;

  final nameCtrl = TextEditingController(text: initBase);
  var freq = initFreq;
  var weeklyTarget = initWeekly;
  var minutes = initMinutes;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) {
        final baseName = clampHabitName(nameCtrl.text);
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
                onChanged: (_) => setS(() {}),
                maxLength: kHabitNameMaxLength,
                decoration: InputDecoration(
                  labelText: '習慣名稱',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.orange.shade400),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
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
                        final result = await showMinutesDialog(
                          context,
                          minutes,
                        );
                        if (result != null) setS(() => minutes = result);
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
                  onPressed: baseName.isEmpty
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          final newName = minutes > 0
                              ? '$baseName $minutes 分鐘'
                              : baseName;
                          onSave(newName, freq, weeklyTarget);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
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
        );
      },
    ),
  );
}

// ── 新增習慣 ──
Future<void> showAddHabitSheet(
  BuildContext context, {
  required List<HomePreset> available,
  required Future<void> Function(
    String customName,
    int customMinutes,
    String freq,
    int weeklyTarget,
    Map<String, PresetConfig> selected,
  )
  onConfirm,
}) async {
  final nameCtrl = TextEditingController();
  final selected = <String, PresetConfig>{};
  var freq = 'daily';
  var weeklyTarget = 3;
  var customMinutes = 0;
  var customExpanded = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (_, setS) {
        final customName = clampHabitName(nameCtrl.text);
        final total = (customName.isNotEmpty ? 1 : 0) + selected.length;
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
              const SizedBox(height: 12),
              // 常用習慣選取
              if (available.isNotEmpty)
                InkWell(
                  onTap: () async {
                    final result = await showHabitPresetSheet(
                      context,
                      available,
                      selected,
                    );
                    if (result != null) {
                      setS(() {
                        selected.clear();
                        selected.addAll(result);
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
                      color: selected.isEmpty
                          ? Colors.grey.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected.isEmpty
                            ? Colors.grey.shade300
                            : Colors.orange.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: selected.isEmpty
                              ? Colors.grey.shade500
                              : Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selected.isEmpty
                                ? '從常用習慣選取'
                                : '已選 ${selected.length} 個常用習慣',
                            style: TextStyle(
                              color: selected.isEmpty
                                  ? Colors.grey.shade600
                                  : Colors.orange.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(
                          selected.isEmpty
                              ? Icons.chevron_right
                              : Icons.check_circle,
                          size: 20,
                          color: selected.isEmpty
                              ? Colors.grey.shade400
                              : Colors.orange.shade600,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
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
                        ? (customName.isNotEmpty
                              ? Colors.deepOrange.shade50
                              : Colors.grey.shade100)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: customExpanded
                          ? (customName.isNotEmpty
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
                        color: customName.isNotEmpty
                            ? Colors.deepOrange.shade500
                            : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          customName.isNotEmpty ? customName : '自訂習慣',
                          style: TextStyle(
                            color: customName.isNotEmpty
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
              // 自訂習慣展開內容
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
                        maxLength: kHabitNameMaxLength,
                        decoration: InputDecoration(
                          hintText: '習慣名稱',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
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
                            color: customMinutes > 0
                                ? Colors.orange.shade300
                                : Colors.grey.shade300,
                            width: 1.5,
                          ),
                          color: customMinutes > 0
                              ? Colors.orange.shade50
                              : Colors.white,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: customMinutes > 0
                                  ? () => setS(
                                      () => customMinutes = customMinutes <= 5
                                          ? 0
                                          : customMinutes - 5,
                                    )
                                  : null,
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: customMinutes > 0
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade300,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: customMinutes > 0
                                  ? Colors.orange.shade200
                                  : Colors.grey.shade200,
                            ),
                            GestureDetector(
                              onTap: () async {
                                final result = await showMinutesDialog(
                                  context,
                                  customMinutes,
                                );
                                if (result != null) {
                                  setS(() => customMinutes = result);
                                }
                              },
                              child: Padding(
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
                                      customMinutes > 0
                                          ? '$customMinutes'
                                          : '--',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: customMinutes > 0
                                            ? Colors.black87
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '分鐘',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: customMinutes > 0
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
                              color: customMinutes > 0
                                  ? Colors.orange.shade200
                                  : Colors.grey.shade200,
                            ),
                            GestureDetector(
                              onTap: customMinutes < 999
                                  ? () => setS(
                                      () => customMinutes = customMinutes == 0
                                          ? 5
                                          : (customMinutes + 5).clamp(5, 999),
                                    )
                                  : null,
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: customMinutes < 999
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade300,
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: total == 0
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await onConfirm(
                            customName,
                            customMinutes,
                            freq,
                            weeklyTarget,
                            selected,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    total == 0 ? '請輸入或選擇習慣' : '新增 ($total 項)',
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
