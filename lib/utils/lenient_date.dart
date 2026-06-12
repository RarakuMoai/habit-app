// 寬鬆日期解析：使用者手動輸入日期時，不應該被格式卡住。
// 純 Dart、無 Flutter 依賴，方便單元測試（test/lenient_date_test.dart）。

/// 接受的格式：
///   有分隔符（- / . 年月，可夾空白）：2000-1-1、2000-01-01、2000/1/1、
///   2000.1.1、2000年1月1日、" 2000 - 1 - 1 "
///   無分隔符：剛好 8 碼數字（20000101）
///
/// 解析不出、歧義（2000-12、7 碼數字）、月日超界、
/// 或不是真實日期（2/30）回 null。
DateTime? parseLenientDate(String input) {
  final t = input.trim();
  // 有分隔符：年月之間、月日之間都要有，避免 2000-12 被猜成 2000-1-2
  final m =
      RegExp(
        r'^(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?$',
      ).firstMatch(t) ??
      RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(t);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  // DateTime 會自動進位（2026-2-30 → 2026-3-2），round-trip 驗證真實性
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}
