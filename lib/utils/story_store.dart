// 回憶本的狀態單一真相來源（SSOT）。
//
// 已解鎖的事件（含解鎖日期）、「未讀」集合、「待揭曉」佇列都集中在這裡，用
// ValueNotifier 對外廣播：衣櫃的「回憶」分區、繪本閱讀器、全螢幕揭曉都讀這裡，
// 避免各自讀 prefs 不同步。
//
// 純資料層：只負責「解鎖 / 標記已讀 / 待揭曉佇列 / 持久化」，不直接碰 UI。
// 事件「自己來」的觸發判定放 [StoryEvents]，由 app 既有時刻（連勝、登入、
// 節日…）呼叫；解鎖成功會排進 [StoryStore.pendingReveal]，由 MainPage 監聽
// 並播放全螢幕揭曉（story_reveal_page.dart），看完才 [StoryStore.consumeReveal]。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';
import 'story_catalog.dart';

/// 一筆已解鎖紀錄：哪個事件、何時解鎖（繪本上印日期用）。
class StoryUnlock {
  final String id;
  final DateTime date;
  const StoryUnlock(this.id, this.date);
}

class StoryStore {
  StoryStore._();

  /// 已解鎖事件，依解鎖時間排序（舊→新，像一本書）。
  static final ValueNotifier<List<StoryUnlock>> unlocked =
      ValueNotifier<List<StoryUnlock>>([]);

  /// 未讀事件 id：控制未來「書發亮」。MVP 不顯示，但先記著免得日後要遷移。
  static final ValueNotifier<Set<String>> unread = ValueNotifier<Set<String>>(
    {},
  );

  /// 已解鎖但還沒播過全螢幕揭曉的事件 id（先進先出）。
  /// 持久化：揭曉看到一半關 app，下次啟動會補播，不會漏掉事件。
  static final ValueNotifier<List<String>> pendingReveal =
      ValueNotifier<List<String>>([]);

  static bool _loaded = false;
  static bool get loaded => _loaded;

  /// 載入持久化狀態（冪等，可重複呼叫；資料清空後 restart 會重讀到空＝歸零）。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = _decode(prefs.getString(PrefsKeys.storyUnlocked));
    final unlockedIds = {for (final u in decoded) u.id};
    final rawUnread = (prefs.getStringList(PrefsKeys.storyUnread) ?? const [])
        .toSet();
    final cleanedUnread = rawUnread.where(unlockedIds.contains).toSet();
    final rawPending =
        prefs.getStringList(PrefsKeys.storyPendingReveal) ?? const [];
    final cleanedPending = rawPending.where(unlockedIds.contains).toList();
    unlocked.value = decoded;
    unread.value = cleanedUnread;
    pendingReveal.value = cleanedPending;
    _loaded = true;
    if (cleanedUnread.length != rawUnread.length ||
        cleanedPending.length != rawPending.length) {
      await _persist();
    }
  }

  static List<StoryUnlock> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return [
        for (final m in list)
          if (storyEventExists(m['id'] as String))
            StoryUnlock(
              m['id'] as String,
              DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.storyUnlocked,
      jsonEncode([
        for (final u in unlocked.value)
          {'id': u.id, 'date': u.date.toIso8601String()},
      ]),
    );
    await prefs.setStringList(PrefsKeys.storyUnread, unread.value.toList());
    await prefs.setStringList(
      PrefsKeys.storyPendingReveal,
      pendingReveal.value,
    );
  }

  static bool isUnlocked(String id) => unlocked.value.any((u) => u.id == id);

  static bool get hasUnread => unread.value.isNotEmpty;

  /// 解鎖一個事件。已解鎖 → no-op 回 false；新解鎖 → 加入、標未讀、
  /// 排進待揭曉佇列，回 true。
  static Future<bool> unlock(String id) async {
    if (!_loaded) await load();
    if (!storyEventExists(id) || isUnlocked(id)) return false;
    unlocked.value = [...unlocked.value, StoryUnlock(id, DateTime.now())];
    unread.value = {...unread.value, id};
    pendingReveal.value = [...pendingReveal.value, id];
    await _persist();
    return true;
  }

  /// 全螢幕揭曉播完後呼叫：移出待揭曉佇列並清未讀（已經看過內容了）。
  static Future<void> consumeReveal(String id) async {
    if (!pendingReveal.value.contains(id) && !unread.value.contains(id)) {
      return;
    }
    pendingReveal.value = [
      for (final p in pendingReveal.value)
        if (p != id) p,
    ];
    unread.value = {...unread.value}..remove(id);
    await _persist();
  }

  /// 翻到某頁時清掉未讀（未來控制「書發亮」熄滅）。
  static Future<void> markRead(String id) async {
    if (!unread.value.contains(id)) return;
    unread.value = {...unread.value}..remove(id);
    await _persist();
  }

  /// 清空全部回憶（dev 測試用：同時清記憶體與 prefs）。
  static Future<void> clear() async {
    unlocked.value = [];
    unread.value = {};
    pendingReveal.value = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.storyUnlocked);
    await prefs.remove(PrefsKeys.storyUnread);
    await prefs.remove(PrefsKeys.storyPendingReveal);
  }
}

/// 事件「自己來」的觸發判定：由 app 既有時刻呼叫，命中門檻就解鎖（冪等）。
///
/// 目前的接線位置（新增觸發時記得補到這張表）：
/// - [onFirstHabitCreated]：home_page 新增習慣後 + _load 補發（已有習慣的舊資料）
/// - [onFirstAllDone]：home_page toggleHabit 的「當日全完成」分支
/// - [onHabitStreak]：home_page 跨日結算後
/// - [onLoginStreak]：main.dart MainPage 領每日登入獎勵後
/// - [onComeback]：home_page _load 讀到 lastOpen 之後（覆寫前）
/// - [onSeasonDay]：main.dart MainPage 啟動 + 回前景時（真實日曆日）
class StoryEvents {
  StoryEvents._();

  /// 測試注入用：覆寫觸發判定掃描的目錄（正式一律 null＝storyCatalog）。
  @visibleForTesting
  static List<StoryEventSpec>? debugCatalog;

  static List<StoryEventSpec> get _catalog => debugCatalog ?? storyCatalog;

  static Future<String?> _unlockFirstWhere(
    bool Function(StoryEventSpec event) test,
  ) async {
    for (final e in _catalog) {
      if (test(e) && await StoryStore.unlock(e.id)) return e.id;
    }
    return null;
  }

  /// 第一次建立習慣後呼叫。回傳這次新解鎖的事件 id，已解鎖過則 null。
  static Future<String?> onFirstHabitCreated() {
    return _unlockFirstWhere((e) => e.trigger == StoryTrigger.firstHabit);
  }

  /// 第一次每日習慣全部完成後呼叫。回傳這次新解鎖的事件 id，已解鎖過則 null。
  static Future<String?> onFirstAllDone() {
    return _unlockFirstWhere((e) => e.trigger == StoryTrigger.firstAllDone);
  }

  /// 習慣連勝更新後呼叫（home_page 日切處）。回傳這次新解鎖的事件 id，沒有則 null。
  static Future<String?> onHabitStreak(int streak) async {
    return _unlockFirstWhere(
      (e) => e.trigger == StoryTrigger.habitStreak && streak >= e.threshold,
    );
  }

  /// 連續登入天數更新後呼叫。回傳這次新解鎖的事件 id，沒有則 null。
  static Future<String?> onLoginStreak(int streak) {
    return _unlockFirstWhere(
      (e) => e.trigger == StoryTrigger.loginStreak && streak >= e.threshold,
    );
  }

  /// 久違回來後呼叫。daysAway 是距離上次打開 app 的天數。
  static Future<String?> onComeback(int daysAway) {
    return _unlockFirstWhere(
      (e) => e.trigger == StoryTrigger.comeback && daysAway >= e.threshold,
    );
  }

  /// 節日檢查：app 啟動 / 回前景時用「真實日曆日」呼叫（節日不跟換日設定走）。
  /// 視窗可能重疊（例：跨年＋新年），所以把命中的全部解鎖，回傳新解鎖的 id 們。
  static Future<List<String>> onSeasonDay(DateTime date) async {
    final hits = <String>[];
    for (final e in _catalog) {
      if (e.trigger != StoryTrigger.season) continue;
      if (!(e.season?.contains(date) ?? false)) continue;
      if (await StoryStore.unlock(e.id)) hits.add(e.id);
    }
    return hits;
  }
}
