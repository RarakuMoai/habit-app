// 回顧／足跡的逐日彙總：把習慣、喝水、專注、運動的每日資料，整理成
// 一段時間（週／月）的溫柔摘要。純讀取、不寫入；語氣由頁面決定，這裡只算數。
//
// 每個領域的逐日資料來源：
// - 習慣：HabitHistory.doneIdsOn(date) + dailyHabitsAsOf（含已刪除墓碑）
// - 喝水：waterEntries(date) 加總 ml（舊資料退回 waterDay 杯數×cupMl + extra）
// - 專注：timerTomatoes(date，舊 key 名) / timerFocusMinutesDay(date)
// - 運動：exerciseSessions(date) / exerciseMinutesDay(date)
import 'package:shared_preferences/shared_preferences.dart';

import 'habit_history.dart';
import 'prefs_keys.dart';
import 'water_entries.dart';

/// 單一習慣在一段時間的達成：done = 完成天數，total = 那段時間它存在的天數。
class HabitTally {
  final String id;
  final String name;
  final bool deleted;
  final int done;
  final int total;
  const HabitTally({
    required this.id,
    required this.name,
    required this.deleted,
    required this.done,
    required this.total,
  });
}

class HabitReview {
  /// 有「至少完成一個每日習慣」的天數。
  final int daysActive;

  /// 每日習慣「全勤」的天數（且當天確實有習慣存在）。
  final int daysAllDone;

  /// 範圍內「有每日習慣存在」的天數（分母）。
  final int trackedDays;

  /// 每個習慣的達成 tally，依完成天數由高到低。
  final List<HabitTally> perHabit;

  const HabitReview({
    required this.daysActive,
    required this.daysAllDone,
    required this.trackedDays,
    required this.perHabit,
  });
}

class WaterReview {
  final int daysMetGoal;
  final int daysWithData;
  final int avgMlOnDataDays;
  const WaterReview({
    required this.daysMetGoal,
    required this.daysWithData,
    required this.avgMlOnDataDays,
  });
}

/// 專注 / 運動共用：count（回合或次數）+ minutes（分鐘）。
class CountReview {
  final int count;
  final int minutes;
  final int activeDays;
  const CountReview({
    required this.count,
    required this.minutes,
    required this.activeDays,
  });
}

abstract final class ReviewStats {
  static HabitReview habits(
    SharedPreferences prefs, {
    required List<String> dates,
    required List<Map<String, dynamic>> activeHabits,
    required List<Map<String, dynamic>> tombstones,
  }) {
    var daysActive = 0;
    var daysAllDone = 0;
    var trackedDays = 0;
    final tallies = <String, HabitTally>{};

    for (final date in dates) {
      final asOf = HabitHistory.dailyHabitsAsOf(
        activeHabits: activeHabits,
        tombstones: tombstones,
        date: date,
      );
      if (asOf.isEmpty) continue;
      trackedDays++;
      final doneIds = HabitHistory.doneIdsOn(prefs, date).toSet();
      var doneToday = 0;
      for (final h in asOf) {
        final id = h['id'] as String;
        final isDone = doneIds.contains(id);
        if (isDone) doneToday++;
        final prev = tallies[id];
        tallies[id] = HabitTally(
          id: id,
          name: (h['name'] as String?) ?? '習慣',
          deleted: h['deleted'] == true,
          done: (prev?.done ?? 0) + (isDone ? 1 : 0),
          total: (prev?.total ?? 0) + 1,
        );
      }
      if (doneToday > 0) daysActive++;
      if (doneToday == asOf.length) daysAllDone++;
    }

    final perHabit = tallies.values.toList()
      ..sort((a, b) => b.done.compareTo(a.done));
    return HabitReview(
      daysActive: daysActive,
      daysAllDone: daysAllDone,
      trackedDays: trackedDays,
      perHabit: perHabit,
    );
  }

  static WaterReview water(
    SharedPreferences prefs, {
    required List<String> dates,
    required int goalMl,
    required int cupMl,
  }) {
    var daysMetGoal = 0;
    var daysWithData = 0;
    var totalMlOnDataDays = 0;
    for (final date in dates) {
      final ml = _waterMlOn(prefs, date, cupMl);
      if (ml <= 0) continue;
      daysWithData++;
      totalMlOnDataDays += ml;
      if (goalMl > 0 && ml >= goalMl) daysMetGoal++;
    }
    return WaterReview(
      daysMetGoal: daysMetGoal,
      daysWithData: daysWithData,
      avgMlOnDataDays: daysWithData == 0
          ? 0
          : (totalMlOnDataDays / daysWithData).round(),
    );
  }

  static int _waterMlOn(SharedPreferences prefs, String date, int cupMl) {
    final entries = parseWaterEntries(
      prefs.getString(PrefsKeys.waterEntries(date)),
      maxEntryMl: 12000,
    );
    if (entries.isNotEmpty) {
      return entries.fold<int>(0, (sum, e) => sum + e.ml);
    }
    // 舊資料：杯數 × cupMl + 額外量
    final cups = prefs.getInt(PrefsKeys.waterDay(date)) ?? 0;
    final extra = prefs.getInt(PrefsKeys.waterExtra(date)) ?? 0;
    return cups * cupMl + extra;
  }

  static CountReview focus(
    SharedPreferences prefs, {
    required List<String> dates,
  }) {
    return _counts(
      prefs,
      dates: dates,
      countKey: PrefsKeys.timerTomatoes,
      minuteKey: PrefsKeys.timerFocusMinutesDay,
    );
  }

  static CountReview exercise(
    SharedPreferences prefs, {
    required List<String> dates,
  }) {
    return _counts(
      prefs,
      dates: dates,
      countKey: PrefsKeys.exerciseSessions,
      minuteKey: PrefsKeys.exerciseMinutesDay,
    );
  }

  static CountReview _counts(
    SharedPreferences prefs, {
    required List<String> dates,
    required String Function(String) countKey,
    required String Function(String) minuteKey,
  }) {
    var count = 0;
    var minutes = 0;
    var activeDays = 0;
    for (final date in dates) {
      final c = prefs.getInt(countKey(date)) ?? 0;
      final m = prefs.getInt(minuteKey(date)) ?? 0;
      if (c > 0 || m > 0) activeDays++;
      count += c;
      minutes += m;
    }
    return CountReview(count: count, minutes: minutes, activeDays: activeDays);
  }
}
