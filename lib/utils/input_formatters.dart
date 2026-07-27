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

// ── 兔咪名字：用「顯示寬度」限長，不用字元數 ──────────────────
//
// 名字會嵌進很多系統文案（「{name}的夥伴檔案」、「{name}造型」…），限長的
// 目的是防破版，所以該數的是「佔多寬」而不是「幾個字」。CJK 是全寬（一個字
// 約等於兩個拉丁字元），所以中文 6 字與英文 12 字元的視覺寬度相同。
//
// 12 這個數字的依據（2026-07-26 實測 iPhone SE 320pt 寬）：最吃緊的
// 「{name}的夥伴檔案」AppBar 標題可容納中文 11 字，12 半寬單位留了將近
// 一倍的邊際。詳見 docs/i18n_migration.md。
const int kMascotNameMaxUnits = 12;

// 全寬（East Asian Wide／Fullwidth）字位的主要 Unicode 區段。
// 沒用完整的 EAW 屬性表——這幾段涵蓋中日韓與 emoji，夠這個用途。
bool _isWideChar(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.runes.first;
  return (c >= 0x1100 && c <= 0x115F) || // 韓文字母 Jamo
      (c >= 0x2E80 && c <= 0x303F) || // CJK 部首、符號與標點
      (c >= 0x3040 && c <= 0x33FF) || // 平假名、片假名、注音、相容字
      (c >= 0x3400 && c <= 0x4DBF) || // CJK 擴充 A
      (c >= 0x4E00 && c <= 0x9FFF) || // CJK 統一漢字
      (c >= 0xA960 && c <= 0xA97F) || // 韓文字母擴充 A
      (c >= 0xAC00 && c <= 0xD7A3) || // 韓文音節
      (c >= 0xF900 && c <= 0xFAFF) || // CJK 相容漢字
      (c >= 0xFE30 && c <= 0xFE4F) || // CJK 相容形式
      (c >= 0xFF00 && c <= 0xFF60) || // 全寬 ASCII
      (c >= 0xFFE0 && c <= 0xFFE6) || // 全寬符號
      (c >= 0x1F300 && c <= 0x1FAFF) || // emoji
      (c >= 0x20000 && c <= 0x3FFFD); // CJK 擴充 B 以後
}

/// 字串的顯示寬度，單位是「半寬字元」：全寬字位算 2、其餘算 1。
int displayWidth(String s) =>
    s.characters.fold(0, (sum, ch) => sum + (_isWideChar(ch) ? 2 : 1));

/// 依顯示寬度截斷（以字位為單位，不會把 emoji 砍成半個）。
String clampToDisplayWidth(String raw, int maxUnits) {
  var used = 0;
  final out = StringBuffer();
  for (final ch in raw.characters) {
    final w = _isWideChar(ch) ? 2 : 1;
    if (used + w > maxUnits) break;
    used += w;
    out.write(ch);
  }
  return out.toString();
}

/// 兔咪名字輸入用：擋在 [maxUnits] 個半寬單位內。
///
/// 用 formatter 而不是 TextField 的 maxLength，因為 maxLength 只能數字元，
/// 對「中文 6 字／英文 12 字元」這種依語言不同的上限做不到；而且 formatter
/// 連混打（「小雲Cloud」）也算得對。
class DisplayWidthLimitingFormatter extends TextInputFormatter {
  final int maxUnits;

  const DisplayWidthLimitingFormatter(this.maxUnits);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (displayWidth(newValue.text) <= maxUnits) return newValue;
    final clamped = clampToDisplayWidth(newValue.text, maxUnits);
    // 超出就退回上一個合法狀態的長度，游標收到尾端。
    return TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
  }
}

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
