// Shared range checks for body-info inputs.
//
// Used by onboarding_page.dart and profile_edit_page.dart so the
// height/weight/birthday limits stay in one place. If a range ever
// needs adjusting, edit only this file.
//
// 範圍永遠以公制定義。UI 若在英制顯示，請先用 [UnitParse] 轉成公制
// 後再呼叫這裡的驗證器。

import 'units.dart';

class UserRanges {
  static const double heightMinCm = 80;
  static const double heightMaxCm = 230;

  static const double weightMinKg = 10;
  static const double weightMaxKg = 250;

  // Target weight uses the same envelope as current weight.
  static const double targetWeightMinKg = weightMinKg;
  static const double targetWeightMaxKg = weightMaxKg;

  // Jeanne Calment 122 是有紀錄上限，留點 buffer 給未驗證 outlier，
  // 仍能擋掉明顯 typo。
  static const int birthdayMaxAgeYears = 130;

  // BMI 合理區間（kg/m²）。寬到能容納極端瘦/胖的真實案例，
  // 主要只擋打錯字（例：身高體重對調、漏位數）。
  static const double bmiMin = 10;
  static const double bmiMax = 65;
}

class UserValidators {
  /// Returns an error message for [raw], or null when [raw] is acceptable.
  /// Empty input is treated as "not provided" (no error) — callers decide
  /// whether to require it.
  static String? height(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (v < UserRanges.heightMinCm || v > UserRanges.heightMaxCm) {
      return '請輸入 ${UserRanges.heightMinCm.toInt()}–${UserRanges.heightMaxCm.toInt()} cm'; // units-ok
    }
    return null;
  }

  static String? weight(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (v < UserRanges.weightMinKg || v > UserRanges.weightMaxKg) {
      return '請輸入 ${UserRanges.weightMinKg.toInt()}–${UserRanges.weightMaxKg.toInt()} kg'; // units-ok
    }
    return null;
  }

  /// Unit-aware weight check：raw 在 [system] 單位裡，內部轉公制驗證。
  static String? weightIn(String raw, UnitSystem system) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (system == UnitSystem.imperial) {
      final lbMin = UnitConvert.kgToLb(UserRanges.weightMinKg).round();
      final lbMax = UnitConvert.kgToLb(UserRanges.weightMaxKg).round();
      if (v < lbMin || v > lbMax) return '請輸入 $lbMin–$lbMax lb'; // units-ok
      return null;
    }
    return weight(raw);
  }

  /// Unit-aware target weight check.
  static String? targetWeightIn(String raw, UnitSystem system) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (system == UnitSystem.imperial) {
      final lbMin = UnitConvert.kgToLb(UserRanges.targetWeightMinKg).round();
      final lbMax = UnitConvert.kgToLb(UserRanges.targetWeightMaxKg).round();
      if (v < lbMin || v > lbMax) return '請輸入 $lbMin–$lbMax lb'; // units-ok
      return null;
    }
    return targetWeight(raw);
  }

  /// Unit-aware height check：imperial 模式直接驗 cm（呼叫端先用
  /// [UnitConvert.ftInToCm] 把 ft/in 合併成 cm 再傳入）。
  static String? heightCm(double? cm) {
    if (cm == null) return null;
    if (cm < UserRanges.heightMinCm || cm > UserRanges.heightMaxCm) {
      return '請輸入 ${UserRanges.heightMinCm.toInt()}–${UserRanges.heightMaxCm.toInt()} cm'; // units-ok
    }
    return null;
  }

  static String? targetWeight(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return '請輸入數字';
    if (v < UserRanges.targetWeightMinKg ||
        v > UserRanges.targetWeightMaxKg) {
      return '請輸入 ${UserRanges.targetWeightMinKg.toInt()}–${UserRanges.targetWeightMaxKg.toInt()} kg'; // units-ok
    }
    return null;
  }

  /// Combined plausibility check on (height, weight). Returns null when
  /// either input is missing/invalid or BMI lies inside [UserRanges.bmiMin,
  /// UserRanges.bmiMax]; otherwise returns an error message.
  ///
  /// Tolerant by design — only catches obvious typos (digit-swap, missing
  /// digit, swapped fields). Real edge cases like severe anorexia (BMI 12)
  /// or extreme obesity (BMI 60) still pass.
  static String? bmiPair(String rawHeight, String rawWeight) {
    final h = double.tryParse(rawHeight.trim());
    final w = double.tryParse(rawWeight.trim());
    if (h == null || w == null) return null;
    if (h <= 0) return null;
    final hM = h / 100;
    final bmi = w / (hM * hM);
    if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) {
      return '身高與體重的比例怪怪的，請再確認';
    }
    return null;
  }

  /// Birthday is constrained at the picker level (firstDate / lastDate),
  /// so this just defends against bad stored values.
  static String? birthday(DateTime? value) {
    if (value == null) return null;
    final now = DateTime.now();
    if (value.isAfter(now)) return '生日不能是未來日期';
    final maxBack = DateTime(
      now.year - UserRanges.birthdayMaxAgeYears,
      now.month,
      now.day,
    );
    if (value.isBefore(maxBack)) {
      return '請確認生日（超過 ${UserRanges.birthdayMaxAgeYears} 歲）';
    }
    return null;
  }
}
