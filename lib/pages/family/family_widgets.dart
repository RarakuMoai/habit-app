// 育兒模式共用小元件：持續時間對話框、調整按鈕、頻率 Chip
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 持續時間（分鐘）輸入對話框
Future<int?> showFamilyMinutesDialog(BuildContext context, int current) async {
  final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('持續時間'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
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

// 調整按鈕（＋ / −）
class AdjustBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const AdjustBtn({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? Colors.white : Colors.grey.shade100,
        border: Border.all(
          color: enabled ? Colors.orange.shade300 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          splashColor: Colors.orange.withValues(alpha: 0.18),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? Colors.orange.shade700 : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

// 頻率切換 Chip（每日 / 每週）
class FreqChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FreqChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? Colors.orange : Colors.grey.shade300,
          width: 1.5,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.orange.withValues(alpha: 0.18),
          highlightColor: Colors.orange.withValues(alpha: 0.08),
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
