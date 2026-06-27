import 'package:flutter/foundation.dart';

// 功能開關（計時 / 喝水 / 體重 / 衣櫃 / 家庭頁籤）反應式廣播。
//
// 背景：開關存進 SharedPreferences 後，常駐的 MainPage 原本只在「完全退出
// 設定頁」時靠 onSettingsReturn 回呼鏈重讀重組頁籤。那條鏈穿過兩層 push/pop
// 的 await + 回呼，時序一沒對上就會「開了沒反應、要再摸一下才生效」。
//
// 改法：開關一存就 bump 這個 revision，MainPage 監聽到立刻重讀 prefs 重組，
// 不再依賴退出時機（與 UnitSystem.notifier / parentSession 同一套反應式做法）。
final ValueNotifier<int> featureFlagsRevision = ValueNotifier<int>(0);

/// 存完任一功能開關後呼叫，廣播一次讓 MainPage 即時套用。
void bumpFeatureFlags() => featureFlagsRevision.value++;

/// 開發者工具總開關（設定頁的「開發者測試」入口、模擬分頁、場景時段覆寫…）。
///
/// 目前 **release 也暫時開啟**，讓自己用的 prod / dev 兩個版本都看得到開發者測試。
///
/// ⚠️ 正式對外發布前，把這行改回 `kDebugMode`（或 `false`），正式使用者就看不到任何
///    開發者工具。`grep kDevToolsEnabled lib/` 可一次找出所有相關位置。
const bool kDevToolsEnabled = true; // RELEASE-BEFORE-PUBLISH: 上架前改回 kDebugMode
