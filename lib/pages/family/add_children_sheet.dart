// 新增小孩 bottom sheet 與頭像選擇對話框

import 'package:flutter/material.dart';

import '../../utils/app_style.dart';

// ── 小孩頭像選項 ──
const List<String> _kChildAvatars = [
  '🐼',
  '🦁',
  '🐸',
  '🦊',
  '🐨',
  '🐯',
  '🐻',
  '🐰',
  '🦄',
  '🐙',
  '🦋',
  '🐢',
  '🦕',
  '🐬',
  '🦅',
  '🐧',
  '🐺',
  '🐮',
  '🐹',
  '🐱',
  '🌟',
  '🌈',
  '🚀',
  '⚡',
];

// 新增小孩時的暫存資料（名字 + 頭像）
class ChildInput {
  String name = '';
  String avatar = '🐼';
}

// 新增小孩 bottom sheet（支援一次新增多位）
Future<String?> showAvatarPickerDialog(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('選擇頭像'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 280,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _kChildAvatars.length,
          itemBuilder: (_, i) {
            final emoji = _kChildAvatars[i];
            final selected = emoji == current;
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, emoji),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.blue.shade100 : AppSurfaces.fill,
                  border: selected
                      ? Border.all(color: Colors.blue.shade400, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('取消', style: TextStyle(color: AppInk.soft)),
        ),
      ],
    ),
  );
}

Future<List<ChildInput>?> showAddChildrenSheet(BuildContext context) async {
  final inputs = <ChildInput>[ChildInput()];
  return showModalBottomSheet<List<ChildInput>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '新增小孩',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...inputs.asMap().entries.map((e) {
              final i = e.key;
              final input = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picked = await showAvatarPickerDialog(
                          ctx,
                          input.avatar,
                        );
                        if (picked != null) setS(() => input.avatar = picked);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppSurfaces.fill,
                        ),
                        child: Center(
                          child: Text(
                            input.avatar,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        autofocus: i == 0,
                        textInputAction: TextInputAction.next,
                        onChanged: (v) => input.name = v,
                        decoration: InputDecoration(
                          hintText: inputs.length > 1
                              ? '小孩名字 ${i + 1}'
                              : '小孩名字',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (inputs.length > 1) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setS(() => inputs.removeAt(i)),
                        child: Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red.shade300,
                          size: 22,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setS(() => inputs.add(ChildInput())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('再加一位'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(color: AppInk.soft)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final valid = inputs
                        .where((inp) => inp.name.trim().isNotEmpty)
                        .toList();
                    Navigator.pop(ctx, valid.isEmpty ? null : valid);
                  },
                  child: const Text('新增'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
