// 共用輸入格式化器（onboarding / 個人資料編輯共用）
import 'package:flutter/services.dart';

// 身高/體重欄位格式化：最多 3 位整數 + 1 位小數，且輸入超過上限時自動壓回上限
TextInputFormatter maxValueFormatter(int max) {
  final pattern = RegExp(r'^\d{0,3}(\.\d?)?$');
  return TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // 格式不符（多個小數點、超過 1 位小數、整數超過 3 位）→ 維持原值
    if (!pattern.hasMatch(text)) return oldValue;
    // 數值超過上限 → 壓回上限
    final v = double.tryParse(text);
    if (v != null && v > max) {
      final t = max.toString();
      return TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
    return newValue;
  });
}
