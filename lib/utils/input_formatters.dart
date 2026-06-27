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

// 自動補小數點：使用者極可能漏打小數點時幫忙補上。
//
// 規則（刻意保守，只在「極高機率」才動）：[text] 是純整數、超出合理上限
// [max]，但除以 10 後落在 (0, max] 內，就把最後一位當成小數位。
// 例：max=75（體脂）時 "365" → "36.5"；max=250（體重 kg）時 "705" → "70.5"。
// 其餘情況一律原樣回傳——本來就在範圍內的合法數字絕不會被改動。
String autoDecimalForRange(String text, num max) {
  if (text.isEmpty || text.contains('.')) return text;
  final n = int.tryParse(text);
  if (n == null || n <= max) return text; // 空 / 非整數 / 已在範圍內 → 不動
  final scaled = n / 10;
  if (scaled > 0 && scaled <= max) {
    final cut = text.length - 1;
    return '${text.substring(0, cut)}.${text.substring(cut)}';
  }
  return text;
}

// 身體數據數字欄位（公制：身高 cm / 體重 kg）專用格式化，內含自動補小數。
//
// 取代「maxValueFormatter + 另外補小數」：刻意允許整數「暫時」多打一位，
// 好讓 [autoDecimalForRange] 把漏打的小數點補回去——
//   身高打 1708 → 170.8、體重打 705 → 70.5。
//
// 規則：最多 4 位整數（過渡）或 3 位整數 + 1 位小數。補得回合理範圍的就
// 直接補上小數；補不回的 4 位純整數一定超出身體數據上限，直接擋下（維持
// 原值，不留怪數字）；3 位以內的越界值放行，交給驗證器顯示紅字。
// 英制欄位（lb/ft 都是整數）請改用 [maxValueFormatter]。
TextInputFormatter bodyMetricFormatter(num max) {
  final pattern = RegExp(r'^\d{0,4}(\.\d?)?$');
  return TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!pattern.hasMatch(text)) return oldValue;
    final fixed = autoDecimalForRange(text, max);
    if (fixed != text) {
      return TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: fixed.length),
      );
    }
    // 補不了的 4 位純整數一定超出身體數據上限 → 擋下
    if (!text.contains('.') && text.length >= 4) return oldValue;
    return newValue;
  });
}

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
