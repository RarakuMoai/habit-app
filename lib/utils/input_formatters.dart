// 共用輸入格式化器（onboarding / 個人資料編輯共用）
import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

// 習慣名稱長度上限（與各輸入框的 maxLength 一致）
const int kHabitNameMaxLength = 20;

// TextField 的 maxLength 對 CJK 輸入法走「組字結束才截斷」，iOS 上部分
// 輸入路徑會漏截，所以儲存前再硬截一次。用 characters 以字位（grapheme）
// 為單位，避免把 emoji 砍成半個。
String clampHabitName(String raw) =>
    raw.trim().characters.take(kHabitNameMaxLength).toString();

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
