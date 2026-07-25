// Shared range checks for body-info inputs.
//
// Used by onboarding_page.dart and profile_edit_page.dart so the
// height/weight/birthday limits stay in one place. If a range ever
// needs adjusting, edit only this file.
//
// 範圍永遠以公制定義。UI 若在英制顯示，請先用 [UnitParse] 轉成公制
// 後再呼叫這裡的驗證器。
//
// 錯誤訊息走 i18n：所有會回傳訊息的驗證器都收 [AppLocalizations]，
// 呼叫端用 AppLocalizations.of(context) 取得後傳入（測試用
// lookupAppLocalizations）。

import '../l10n/app_localizations.dart';
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

// 健康建議計算（onboarding 與個人資料編輯共用）
class HealthAdvice {
  /// 依身高的健康目標體重建議：BMI 18.5–24 為範圍、22 為建議值。
  ///
  /// 規則（兩頁統一）：身高在合理範圍才給建議；若同時填了合理範圍內的
  /// 體重、但身高體重比例明顯不合理（BMI 超出 [UserRanges.bmiMin]–
  /// [UserRanges.bmiMax]），回 null —— 先讓使用者修正輸入，不給可能
  /// 誤導的建議。體重缺漏或本身超出範圍時不做比例檢查（各自的欄位
  /// 錯誤會另外提示）。回傳值已轉成 [system] 單位。
  static ({int low, int high, int suggest, String unit})?
  targetWeightSuggestion({
    required double? heightCm,
    required double? weightKg,
    required UnitSystem system,
  }) {
    if (heightCm == null ||
        heightCm < UserRanges.heightMinCm ||
        heightCm > UserRanges.heightMaxCm) {
      return null;
    }
    final hM = heightCm / 100;
    if (weightKg != null &&
        weightKg >= UserRanges.weightMinKg &&
        weightKg <= UserRanges.weightMaxKg) {
      final bmi = weightKg / (hM * hM);
      if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) return null;
    }
    int disp(double kg) => system == UnitSystem.imperial
        ? UnitConvert.kgToLb(kg).round()
        : kg.round();
    return (
      low: disp(18.5 * hM * hM),
      high: disp(24 * hM * hM),
      suggest: disp(22 * hM * hM),
      unit: UnitFormat.weightLabel(system),
    );
  }
}

class UserValidators {
  /// Returns an error message for [raw], or null when [raw] is acceptable.
  /// Empty input is treated as "not provided" (no error) — callers decide
  /// whether to require it.
  static String? height(AppLocalizations l10n, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return l10n.valEnterNumber;
    if (v < UserRanges.heightMinCm || v > UserRanges.heightMaxCm) {
      return l10n.valRangeWithUnit(
        UserRanges.heightMinCm.toInt(),
        UserRanges.heightMaxCm.toInt(),
        UnitFormat.heightLabel(UnitSystem.metric),
      );
    }
    return null;
  }

  static String? weight(AppLocalizations l10n, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return l10n.valEnterNumber;
    if (v < UserRanges.weightMinKg || v > UserRanges.weightMaxKg) {
      return l10n.valRangeWithUnit(
        UserRanges.weightMinKg.toInt(),
        UserRanges.weightMaxKg.toInt(),
        UnitFormat.weightLabel(UnitSystem.metric),
      );
    }
    return null;
  }

  /// Unit-aware weight check：raw 在 [system] 單位裡，內部轉公制驗證。
  static String? weightIn(AppLocalizations l10n, String raw, UnitSystem system) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return l10n.valEnterNumber;
    if (system == UnitSystem.imperial) {
      final lbMin = UnitConvert.kgToLb(UserRanges.weightMinKg).round();
      final lbMax = UnitConvert.kgToLb(UserRanges.weightMaxKg).round();
      if (v < lbMin || v > lbMax) {
        return l10n.valRangeWithUnit(
          lbMin,
          lbMax,
          UnitFormat.weightLabel(UnitSystem.imperial),
        );
      }
      return null;
    }
    return weight(l10n, raw);
  }

  /// Unit-aware target weight check.
  static String? targetWeightIn(
    AppLocalizations l10n,
    String raw,
    UnitSystem system,
  ) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return l10n.valEnterNumber;
    if (system == UnitSystem.imperial) {
      final lbMin = UnitConvert.kgToLb(UserRanges.targetWeightMinKg).round();
      final lbMax = UnitConvert.kgToLb(UserRanges.targetWeightMaxKg).round();
      if (v < lbMin || v > lbMax) {
        return l10n.valRangeWithUnit(
          lbMin,
          lbMax,
          UnitFormat.weightLabel(UnitSystem.imperial),
        );
      }
      return null;
    }
    return targetWeight(l10n, raw);
  }

  /// Unit-aware height check：imperial 模式直接驗 cm（呼叫端先用
  /// [UnitConvert.ftInToCm] 把 ft/in 合併成 cm 再傳入）。
  static String? heightCm(AppLocalizations l10n, double? cm) {
    if (cm == null) return null;
    if (cm < UserRanges.heightMinCm || cm > UserRanges.heightMaxCm) {
      return l10n.valRangeWithUnit(
        UserRanges.heightMinCm.toInt(),
        UserRanges.heightMaxCm.toInt(),
        UnitFormat.heightLabel(UnitSystem.metric),
      );
    }
    return null;
  }

  static String? targetWeight(AppLocalizations l10n, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return l10n.valEnterNumber;
    if (v < UserRanges.targetWeightMinKg || v > UserRanges.targetWeightMaxKg) {
      return l10n.valRangeWithUnit(
        UserRanges.targetWeightMinKg.toInt(),
        UserRanges.targetWeightMaxKg.toInt(),
        UnitFormat.weightLabel(UnitSystem.metric),
      );
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
  static String? bmiPair(
    AppLocalizations l10n,
    String rawHeight,
    String rawWeight,
  ) {
    final h = double.tryParse(rawHeight.trim());
    final w = double.tryParse(rawWeight.trim());
    if (h == null || w == null) return null;
    if (h <= 0) return null;
    final hM = h / 100;
    final bmi = w / (hM * hM);
    if (bmi < UserRanges.bmiMin || bmi > UserRanges.bmiMax) {
      return l10n.valBmiImplausible;
    }
    return null;
  }

  /// Birthday is constrained at the picker level (firstDate / lastDate),
  /// so this just defends against bad stored values.
  static String? birthday(AppLocalizations l10n, DateTime? value) {
    if (value == null) return null;
    final now = DateTime.now();
    if (value.isAfter(now)) return l10n.valBirthdayFuture;
    final maxBack = DateTime(
      now.year - UserRanges.birthdayMaxAgeYears,
      now.month,
      now.day,
    );
    if (value.isBefore(maxBack)) {
      return l10n.valBirthdayTooOld(UserRanges.birthdayMaxAgeYears);
    }
    return null;
  }
}
