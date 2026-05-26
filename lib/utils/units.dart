// Unit system foundation.
//
// 內部一律以公制儲存（cm / kg / ml）。UI 顯示與輸入時透過這個模組
// 在公制 ↔ 使用者偏好之間轉換。要新增單位類別時只改這檔。
//
// 取捨：只支援 metric / imperial 兩套，imperial 用 ft+in / lb / fl oz；
// 不支援 stone、gallon 等較少數使用的單位。

import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem {
  metric,
  imperial;

  String get prefsValue => name; // 'metric' / 'imperial'

  static const String prefsKey = 'unit_system';

  static UnitSystem fromString(String? raw) {
    if (raw == 'imperial') return UnitSystem.imperial;
    return UnitSystem.metric;
  }

  /// 從 prefs 讀目前單位，沒設過就回退到 [detectDefault]。
  static UnitSystem load(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return detectDefault();
    return fromString(raw);
  }

  static Future<void> save(SharedPreferences prefs, UnitSystem v) =>
      prefs.setString(prefsKey, v.prefsValue);

  /// 用 device locale 猜預設：US / LR / MM 用 imperial，其餘用 metric。
  static UnitSystem detectDefault() {
    final locale = PlatformDispatcher.instance.locale;
    const imperialCountries = {'US', 'LR', 'MM'};
    if (locale.countryCode != null &&
        imperialCountries.contains(locale.countryCode)) {
      return UnitSystem.imperial;
    }
    return UnitSystem.metric;
  }
}

// ── 數字轉換 ──────────────────────────────────────────────────

const double _cmPerInch = 2.54;
const double _inchPerFoot = 12;
const double _kgPerLb = 0.45359237;
const double _mlPerFlOz = 29.5735;

class UnitConvert {
  /// cm → (ft, leftover-inches)。回傳整數 ft + 整數 in（四捨五入）。
  static (int ft, int inches) cmToFtIn(double cm) {
    final totalInches = (cm / _cmPerInch).round();
    final ft = totalInches ~/ _inchPerFoot;
    final inches = totalInches - ft * _inchPerFoot.toInt();
    return (ft, inches);
  }

  static double ftInToCm(int ft, int inches) =>
      (ft * _inchPerFoot + inches) * _cmPerInch;

  static double kgToLb(double kg) => kg / _kgPerLb;
  static double lbToKg(double lb) => lb * _kgPerLb;

  static double mlToFlOz(double ml) => ml / _mlPerFlOz;
  static double flOzToMl(double oz) => oz * _mlPerFlOz;
}

// ── 顯示格式 ──────────────────────────────────────────────────
//
// 所有 format 入參都是公制（cm / kg / ml）；依目前 [UnitSystem] 出字串。

class UnitFormat {
  /// 173 cm → "173 cm"（metric）/ "5'8\""（imperial）
  static String height(double cm, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      final (ft, inches) = UnitConvert.cmToFtIn(cm);
      return "$ft'$inches\"";
    }
    return '${cm.toStringAsFixed(cm == cm.roundToDouble() ? 0 : 1)} cm';
  }

  /// 70 kg → "70 kg" / "154 lb"
  static String weight(double kg, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      return '${UnitConvert.kgToLb(kg).round()} lb';
    }
    final isInt = kg == kg.roundToDouble();
    return '${kg.toStringAsFixed(isInt ? 0 : 1)} kg';
  }

  /// 250 ml → "250 ml" / "8 oz"
  static String volume(int ml, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      return '${UnitConvert.mlToFlOz(ml.toDouble()).round()} oz';
    }
    return '$ml ml';
  }

  static String volumeLabel(UnitSystem system) =>
      system == UnitSystem.imperial ? 'oz' : 'ml';

  static String weightLabel(UnitSystem system) =>
      system == UnitSystem.imperial ? 'lb' : 'kg';

  static String heightLabel(UnitSystem system) =>
      system == UnitSystem.imperial ? 'ft / in' : 'cm';
}

// ── 輸入解析 ──────────────────────────────────────────────────
//
// 把使用者輸入（在當下單位裡）轉成公制基準值；失敗回 null。

class UnitParse {
  /// metric 模式：raw 是 cm；imperial 模式：raw 不用，請走 [ftInToCm]。
  static double? heightCm(String raw, UnitSystem system) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    if (system == UnitSystem.imperial) return null; // 走兩格輸入
    return v;
  }

  static double? weightKg(String raw, UnitSystem system) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    if (system == UnitSystem.imperial) return UnitConvert.lbToKg(v);
    return v;
  }

  static double? volumeMl(String raw, UnitSystem system) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    if (system == UnitSystem.imperial) return UnitConvert.flOzToMl(v);
    return v;
  }
}
