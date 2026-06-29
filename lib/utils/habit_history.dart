// 習慣的逐日完成歷史 + 刪除墓碑（補打勾 / 統計的單一資料源）。
//
// 設計：每日習慣每個邏輯日一個 key（[PrefsKeys.habitDoneDay]），值是當天
// 「已完成的習慣 id」清單。打勾/取消當下寫入，跨日不清除 → 過去的紀錄會
// 一直保留，之後可做統計與補打勾。每週習慣的逐日紀錄仍在習慣物件的
// `weeklyDates`（多重集語意），這裡只負責每日習慣，整併延後。
//
// 習慣以「穩定 id」對應，不靠會被使用者改動的名字；刪除時寫一筆墓碑，
// 讓補打勾仍能顯示已刪掉但當時存在的條目。
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

abstract final class HabitHistory {
  static final Random _rand = Random();

  /// 產生穩定且幾乎不會碰撞的習慣 id（含隨機尾碼，避免同一輪迴圈撞號）。
  static String newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final suffix = _rand.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 'h${ts}_$suffix';
  }

  // ── 逐日完成集合 ─────────────────────────────────────────

  /// 某邏輯日（yyyy-MM-dd）已完成的每日習慣 id。
  static List<String> doneIdsOn(SharedPreferences prefs, String date) {
    final raw = prefs.getString(PrefsKeys.habitDoneDay(date));
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// 覆寫某天的完成集合；空集合直接移除 key（不留空殼）。
  static Future<void> setDoneIdsOn(
    SharedPreferences prefs,
    String date,
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) {
      await prefs.remove(PrefsKeys.habitDoneDay(date));
    } else {
      await prefs.setString(PrefsKeys.habitDoneDay(date), jsonEncode(list));
    }
  }

  /// 設定單一習慣在某天的完成與否（補打勾用）。
  static Future<void> setDoneOn(
    SharedPreferences prefs,
    String date,
    String id, {
    required bool done,
  }) async {
    final set = doneIdsOn(prefs, date).toSet();
    if (done) {
      set.add(id);
    } else {
      set.remove(id);
    }
    await setDoneIdsOn(prefs, date, set);
  }

  // ── 某天「當時存在的習慣」 ────────────────────────────────

  /// 回傳 [date]（yyyy-MM-dd）當天存在的每日習慣，供補打勾列出。
  /// 依 createdAt / deletedAt 過濾：那天還沒建、或已經刪掉的不列。
  /// [activeHabits] 是目前的 habits 清單（已帶 id/createdAt），
  /// [tombstones] 是 [HabitHistory.tombstones]。日期字串可直接字典序比較。
  /// 每筆回傳 `{id, name, deleted}`，deleted=true 代表是已刪除的條目。
  static List<Map<String, dynamic>> dailyHabitsAsOf({
    required List<Map<String, dynamic>> activeHabits,
    required List<Map<String, dynamic>> tombstones,
    required String date,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final h in activeHabits) {
      if ((h['frequency'] ?? 'daily') == 'weekly') continue;
      final id = h['id'];
      if (id is! String) continue;
      final created = h['createdAt'];
      if (created is String && created.compareTo(date) > 0) continue;
      out.add({'id': id, 'name': h['name'], 'deleted': false});
    }
    for (final t in tombstones) {
      if ((t['frequency'] ?? 'daily') == 'weekly') continue;
      final id = t['id'];
      if (id is! String) continue;
      final created = t['createdAt'];
      if (created is String && created.compareTo(date) > 0) continue;
      final deleted = t['deletedAt'];
      if (deleted is String && deleted.compareTo(date) < 0) continue;
      out.add({'id': id, 'name': t['name'], 'deleted': true});
    }
    return out;
  }

  // ── 刪除墓碑 ─────────────────────────────────────────────

  static List<Map<String, dynamic>> tombstones(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.habitTombstones);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 記下一筆刪除墓碑（同 id 先去重，避免重建後重複）。
  static Future<void> addTombstone(
    SharedPreferences prefs, {
    required String id,
    required String name,
    required String frequency,
    required String createdAt,
    required String deletedAt,
  }) async {
    final list = tombstones(prefs)..removeWhere((t) => t['id'] == id);
    list.add({
      'id': id,
      'name': name,
      'frequency': frequency,
      'createdAt': createdAt,
      'deletedAt': deletedAt,
    });
    await prefs.setString(PrefsKeys.habitTombstones, jsonEncode(list));
  }
}
