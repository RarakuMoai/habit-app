import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'habit_history.dart';
import 'logical_date.dart';
import 'prefs_keys.dart';

const String waterHabitName = '喝足夠的水';

abstract final class WaterHabitLink {
  static List<Map<String, dynamic>> _loadHabits(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.habits);
    if (raw == null || raw.isEmpty) return [];
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

  static bool hasHabit(SharedPreferences prefs) =>
      _loadHabits(prefs).any((habit) => habit['name'] == waterHabitName);

  /// 喝水頁開啟時，保證首頁也有對應的每日習慣。
  static Future<bool> ensureHabit(SharedPreferences prefs) async {
    final habits = _loadHabits(prefs);
    if (habits.any((habit) => habit['name'] == waterHabitName)) return false;
    final today = LogicalDate.stringFor(
      DateTime.now(),
      LogicalDate.load(prefs),
    );
    final habit = <String, dynamic>{
      'id': HabitHistory.newId(),
      'name': waterHabitName,
      'createdAt': today,
      'done': false,
      'frequency': 'daily',
    };
    final weightIndex = habits.indexWhere((h) => h['name'] == '體重紀錄');
    habits.insert(weightIndex == 0 ? 1 : 0, habit);
    await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    return true;
  }

  /// 關閉喝水頁時一併移除連動習慣，並保留墓碑供過去七天補登。
  static Future<bool> removeHabit(SharedPreferences prefs) async {
    final habits = _loadHabits(prefs);
    final index = habits.indexWhere((habit) => habit['name'] == waterHabitName);
    if (index == -1) return false;
    final habit = habits.removeAt(index);
    final today = LogicalDate.stringFor(
      DateTime.now(),
      LogicalDate.load(prefs),
    );
    final id = habit['id'] as String?;
    if (id != null) {
      await HabitHistory.addTombstone(
        prefs,
        id: id,
        name: waterHabitName,
        frequency: (habit['frequency'] ?? 'daily') as String,
        createdAt: (habit['createdAt'] as String?) ?? today,
        deletedAt: today,
      );
      await HabitHistory.setDoneOn(prefs, today, id, done: false);
    }
    await prefs.setString(PrefsKeys.habits, jsonEncode(habits));
    return true;
  }

  /// 升級舊資料時取並集：開過喝水頁或已有喝水習慣，就補齊另一邊。
  static Future<bool> reconcile(SharedPreferences prefs) async {
    final enabled = prefs.getBool(PrefsKeys.waterEnabled) ?? false;
    final hasWaterHabit = hasHabit(prefs);
    if (enabled && !hasWaterHabit) return ensureHabit(prefs);
    if (!enabled && hasWaterHabit) {
      await prefs.setBool(PrefsKeys.waterEnabled, true);
      return true;
    }
    return false;
  }
}
