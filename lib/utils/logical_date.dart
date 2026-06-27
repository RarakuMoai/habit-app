// 邏輯日（可往後挪的換日線）。
//
// 使用者常常 1–2 點才睡，午夜換日會把「睡前最後一次紀錄」算到隔天。
// 這裡提供可設定的「一天從幾點開始」(dayStartHour)：算紀錄日前先把
// 時間往回退 dayStartHour 小時，再取日曆日。例：設 4 點，凌晨 1 點記錄
// → 退成前一天 21 點 → 仍算「昨天」。
//
// ⚠️ 範圍限定：只用於「習慣 / 喝水 / 體重」的紀錄日。金幣發獎的判重
// 刻意維持純日曆午夜（見 [CoinService]），否則使用者只要在午夜前後
// 來回切這個設定，就能讓「今天」字串跳動而重複領獎。

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

abstract final class LogicalDate {
  /// 預設凌晨 4:00 換日（涵蓋多數夜貓族的睡前紀錄）。
  static const int defaultHour = 4;
  static const int minHour = 0;

  /// 上限 6 點：再晚就會把整個早上算成前一天，超出「夜貓補登」的合理範圍。
  static const int maxHour = 6;

  /// 目前換日時間（小時）的全 app 廣播。[load] / [save] 都會同步它；
  /// 需要「設定改了立即生效」的常駐頁 addListener 並 setState 即可。
  static final ValueNotifier<int> notifier = ValueNotifier<int>(defaultHour);

  static int _clamp(int hour) => hour.clamp(minHour, maxHour);

  /// 從 prefs 讀目前換日時間，沒設過回退到 [defaultHour]。會同步 [notifier]。
  static int load(SharedPreferences prefs) {
    final v = _clamp(prefs.getInt(PrefsKeys.dayStartHour) ?? defaultHour);
    notifier.value = v;
    return v;
  }

  static Future<void> save(SharedPreferences prefs, int hour) {
    final v = _clamp(hour);
    notifier.value = v;
    return prefs.setInt(PrefsKeys.dayStartHour, v);
  }

  /// 從 prefs 讀換日時間，但「不」動 [notifier]（背景/工具呼叫用）。
  static int hourOf(SharedPreferences prefs) =>
      _clamp(prefs.getInt(PrefsKeys.dayStartHour) ?? defaultHour);

  /// 用目前換日設定算「今天」的 yyyy-MM-dd（[now] 供測試注入）。
  static String today(SharedPreferences prefs, {DateTime? now}) =>
      stringFor(now ?? DateTime.now(), hourOf(prefs));

  /// 純函式：把 [at] 依 [dayStartHour] 換算成邏輯日的 yyyy-MM-dd 字串。
  static String stringFor(DateTime at, int dayStartHour) =>
      _fmt(at.subtract(Duration(hours: _clamp(dayStartHour))));

  /// 純函式：把 [at] 換算成「邏輯日的零點」DateTime（給跨日天數運算用）。
  static DateTime dayOf(DateTime at, int dayStartHour) {
    final shifted = at.subtract(Duration(hours: _clamp(dayStartHour)));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
