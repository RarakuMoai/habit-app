// 回憶本的狀態單一真相來源（SSOT）。
//
// 已解鎖的事件（含解鎖日期）與「未讀」集合都集中在這裡，用 ValueNotifier
// 對外廣播：衣櫃的「回憶」分區、繪本閱讀器都讀這裡，避免各自讀 prefs 不同步。
//
// 純資料層：只負責「解鎖 / 標記已讀 / 持久化」，不直接碰 UI。事件「自己來」的
// 觸發判定放 [StoryEvents]，由 app 既有時刻（連勝、登入里程碑…）呼叫。

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
  static final ValueNotifier<Set<String>> unread =
      ValueNotifier<Set<String>>({});

  static bool _loaded = false;
  static bool get loaded => _loaded;

  /// 載入持久化狀態（冪等，可重複呼叫；資料清空後 restart 會重讀到空＝歸零）。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    unlocked.value = _decode(prefs.getString(PrefsKeys.storyUnlocked));
    unread.value =
        (prefs.getStringList(PrefsKeys.storyUnread) ?? const []).toSet();
    _loaded = true;
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
  }

  static bool isUnlocked(String id) => unlocked.value.any((u) => u.id == id);

  static bool get hasUnread => unread.value.isNotEmpty;

  /// 解鎖一個事件。已解鎖 → no-op 回 false；新解鎖 → 加入並標未讀，回 true。
  static Future<bool> unlock(String id) async {
    if (!_loaded) await load();
    if (!storyEventExists(id) || isUnlocked(id)) return false;
    unlocked.value = [...unlocked.value, StoryUnlock(id, DateTime.now())];
    unread.value = {...unread.value, id};
    await _persist();
    return true;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.storyUnlocked);
    await prefs.remove(PrefsKeys.storyUnread);
  }
}

/// 事件「自己來」的觸發判定：由 app 既有時刻呼叫，命中門檻就解鎖（冪等）。
class StoryEvents {
  StoryEvents._();

  /// 習慣連勝更新後呼叫（home_page 日切處）。回傳這次新解鎖的事件 id，沒有則 null。
  static Future<String?> onHabitStreak(int streak) async {
    for (final e in storyCatalog) {
      if (e.trigger == StoryTrigger.habitStreak && streak >= e.threshold) {
        if (await StoryStore.unlock(e.id)) return e.id;
      }
    }
    return null;
  }
}
