// UsageStats（本機匿名使用統計）：累加、跨日分檔、壞資料容錯、保留期修剪。
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bump 同日同事件累加、不同事件分開計', () async {
    final now = DateTime(2026, 7, 2, 10);
    await UsageStats.bump(UsageEvents.waterAdd, now: now);
    await UsageStats.bump(UsageEvents.waterAdd, now: now);
    await UsageStats.bump(UsageEvents.habitCheck, now: now);

    final prefs = await SharedPreferences.getInstance();
    final counts = UsageStats.dayCounts(prefs, '2026-07-02');
    expect(counts[UsageEvents.waterAdd], 2);
    expect(counts[UsageEvents.habitCheck], 1);
  });

  test('bump 跨日分開存，recordedDays 新到舊', () async {
    await UsageStats.bump(UsageEvents.habitCheck, now: DateTime(2026, 7, 1, 12));
    await UsageStats.bump(UsageEvents.habitCheck, now: DateTime(2026, 7, 2, 12));

    final prefs = await SharedPreferences.getInstance();
    expect(UsageStats.recordedDays(prefs), ['2026-07-02', '2026-07-01']);
    expect(UsageStats.dayCounts(prefs, '2026-07-01')[UsageEvents.habitCheck], 1);
    expect(UsageStats.dayCounts(prefs, '2026-07-02')[UsageEvents.habitCheck], 1);
  });

  test('事件名 helper 組出預期字串', () {
    expect(UsageEvents.tab('water'), 'tab.water');
    expect(UsageEvents.timerStart('focus'), 'timer.focus.start');
  });

  test('decodeDay 對壞 JSON / 非 map / 非數字值容錯', () {
    expect(UsageStats.decodeDay(null), isEmpty);
    expect(UsageStats.decodeDay(''), isEmpty);
    expect(UsageStats.decodeDay('not json'), isEmpty);
    expect(UsageStats.decodeDay('[1,2]'), isEmpty);
    expect(UsageStats.decodeDay('{"a": 3, "b": "oops"}'), {'a': 3});
  });

  test('壞掉的當日資料不會炸，重新從 1 開始累計', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.usageDay('2026-07-02'): 'corrupted!!',
    });
    await UsageStats.bump(UsageEvents.waterAdd, now: DateTime(2026, 7, 2));
    final prefs = await SharedPreferences.getInstance();
    expect(
      UsageStats.dayCounts(prefs, '2026-07-02')[UsageEvents.waterAdd],
      1,
    );
  });

  test('寫入新的一天時，超過保留期的舊 key 被清掉、期內保留', () async {
    final today = DateTime(2026, 7, 2);
    final withinRetention = today.subtract(
      const Duration(days: UsageStats.retentionDays - 1),
    );
    final beyondRetention = today.subtract(
      const Duration(days: UsageStats.retentionDays + 1),
    );
    await UsageStats.bump(UsageEvents.habitCheck, now: beyondRetention);
    await UsageStats.bump(UsageEvents.habitCheck, now: withinRetention);
    await UsageStats.bump(UsageEvents.habitCheck, now: today);

    final prefs = await SharedPreferences.getInstance();
    final days = UsageStats.recordedDays(prefs);
    expect(days, hasLength(2));
    expect(days, contains('2026-07-02'));
    expect(days, isNot(contains(_ymd(beyondRetention))));
  });
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
