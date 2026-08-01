import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/review_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final week = ['2026-06-22', '2026-06-23', '2026-06-24'];

  final habits = [
    {
      'id': 'read',
      'name': '閱讀',
      'frequency': 'daily',
      'createdAt': '2020-01-01',
    },
    {
      'id': 'med',
      'name': '冥想',
      'frequency': 'daily',
      'createdAt': '2026-06-23',
    },
  ];

  test('habits：回來天數 / 全勤天數 / 每習慣 tally', () async {
    SharedPreferences.setMockInitialValues({
      // 6/22：只有 read 存在且完成 → 全勤
      PrefsKeys.habitDoneDay('2026-06-22'): '["read"]',
      // 6/23：read、med 都存在，只完成 read → 有回來但非全勤
      PrefsKeys.habitDoneDay('2026-06-23'): '["read"]',
      // 6/24：兩個都完成 → 全勤
      PrefsKeys.habitDoneDay('2026-06-24'): '["read","med"]',
    });
    final prefs = await SharedPreferences.getInstance();

    final hr = ReviewStats.habits(
      prefs,
      dates: week,
      activeHabits: habits,
      tombstones: const [],
      habitFallbackName: '習慣',
    );

    expect(hr.trackedDays, 3);
    expect(hr.daysActive, 3); // 每天都至少完成一個
    expect(hr.daysAllDone, 2); // 6/22、6/24 全勤（6/23 漏 med）

    final read = hr.perHabit.firstWhere((t) => t.id == 'read');
    final med = hr.perHabit.firstWhere((t) => t.id == 'med');
    expect(read.done, 3);
    expect(read.total, 3); // read 三天都存在
    expect(med.done, 1);
    expect(med.total, 2); // med 6/23 才建立，只存在 6/23、6/24
  });

  test('water：達標天數 / 平均（只算有資料的天）', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.waterEntries('2026-06-22'): '[{"ml":2000,"kind":"cup"}]',
      PrefsKeys.waterEntries('2026-06-23'): '[{"ml":1000,"kind":"cup"}]',
      // 6/24 無資料
    });
    final prefs = await SharedPreferences.getInstance();

    final wr = ReviewStats.water(prefs, dates: week, goalMl: 2000, cupMl: 250);
    expect(wr.daysWithData, 2);
    expect(wr.daysMetGoal, 1); // 只有 6/22 達 2000
    expect(wr.avgMlOnDataDays, 1500); // (2000+1000)/2
  });

  test('water：canonical 空陣列存在時不回退到 legacy mirror', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.waterEntries('2026-06-22'): '[]',
      PrefsKeys.waterDay('2026-06-22'): 8,
      PrefsKeys.waterExtra('2026-06-22'): 500,
    });
    final prefs = await SharedPreferences.getInstance();

    final wr = ReviewStats.water(
      prefs,
      dates: const ['2026-06-22'],
      goalMl: 2000,
      cupMl: 250,
    );
    expect(wr.daysWithData, 0);
    expect(wr.daysMetGoal, 0);
    expect(wr.avgMlOnDataDays, 0);
  });

  test('focus / exercise：加總 count 與 minutes 與活躍天數', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.timerTomatoes('2026-06-22'): 3,
      PrefsKeys.timerFocusMinutesDay('2026-06-22'): 75,
      PrefsKeys.timerTomatoes('2026-06-24'): 1,
      PrefsKeys.timerFocusMinutesDay('2026-06-24'): 25,
      PrefsKeys.exerciseSessions('2026-06-23'): 2,
      PrefsKeys.exerciseMinutesDay('2026-06-23'): 40,
    });
    final prefs = await SharedPreferences.getInstance();

    final focus = ReviewStats.focus(prefs, dates: week);
    expect(focus.count, 4);
    expect(focus.minutes, 100);
    expect(focus.activeDays, 2);

    final ex = ReviewStats.exercise(prefs, dates: week);
    expect(ex.count, 2);
    expect(ex.minutes, 40);
    expect(ex.activeDays, 1);
  });

  test('空範圍回傳 0，不丟例外', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final hr = ReviewStats.habits(
      prefs,
      dates: week,
      activeHabits: const [],
      tombstones: const [],
      habitFallbackName: '習慣',
    );
    expect(hr.trackedDays, 0);
    expect(hr.perHabit, isEmpty);
  });
}
