import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LogicalDate.stringFor 換日線', () {
    test('換日時間以前（凌晨 1:30，hour=4）仍算前一天', () {
      final at = DateTime(2026, 6, 27, 1, 30);
      expect(LogicalDate.stringFor(at, 4), '2026-06-26');
    });

    test('換日時間以前的最後一刻（3:59，hour=4）仍算前一天', () {
      final at = DateTime(2026, 6, 27, 3, 59);
      expect(LogicalDate.stringFor(at, 4), '2026-06-26');
    });

    test('正好到換日時間（4:00，hour=4）就算新的一天', () {
      final at = DateTime(2026, 6, 27, 4, 0);
      expect(LogicalDate.stringFor(at, 4), '2026-06-27');
    });

    test('白天（中午，hour=4）算當天', () {
      final at = DateTime(2026, 6, 27, 12, 0);
      expect(LogicalDate.stringFor(at, 4), '2026-06-27');
    });

    test('hour=0 等同純日曆日（午夜後就換日）', () {
      final at = DateTime(2026, 6, 27, 0, 30);
      expect(LogicalDate.stringFor(at, 0), '2026-06-27');
    });

    test('跨月：7/1 凌晨 2 點（hour=4）回退到 6/30', () {
      final at = DateTime(2026, 7, 1, 2, 0);
      expect(LogicalDate.stringFor(at, 4), '2026-06-30');
    });

    test('跨年：1/1 凌晨 1 點（hour=4）回退到去年 12/31', () {
      final at = DateTime(2026, 1, 1, 1, 0);
      expect(LogicalDate.stringFor(at, 4), '2025-12-31');
    });

    test('超出範圍的小時會被 clamp（>6 當 6，<0 當 0）', () {
      final at = DateTime(2026, 6, 27, 5, 30);
      // hour=99 → clamp 到 6：5:30 - 6h = 前一天
      expect(LogicalDate.stringFor(at, 99), '2026-06-26');
      // hour=-5 → clamp 到 0：當天
      expect(LogicalDate.stringFor(at, -5), '2026-06-27');
    });
  });

  group('LogicalDate.dayOf', () {
    test('回傳邏輯日的零點 DateTime', () {
      final at = DateTime(2026, 6, 27, 1, 30);
      expect(LogicalDate.dayOf(at, 4), DateTime(2026, 6, 26));
    });
  });

  group('LogicalDate load/save', () {
    test('沒設定過回退到 defaultHour 並同步 notifier', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(LogicalDate.load(prefs), LogicalDate.defaultHour);
      expect(LogicalDate.notifier.value, LogicalDate.defaultHour);
    });

    test('save 會 clamp、持久化並同步 notifier', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await LogicalDate.save(prefs, 99); // 超範圍
      expect(prefs.getInt(PrefsKeys.dayStartHour), LogicalDate.maxHour);
      expect(LogicalDate.notifier.value, LogicalDate.maxHour);
      expect(LogicalDate.hourOf(prefs), LogicalDate.maxHour);
    });

    test('hourOf 不會動 notifier', () async {
      SharedPreferences.setMockInitialValues({PrefsKeys.dayStartHour: 3});
      final prefs = await SharedPreferences.getInstance();
      LogicalDate.notifier.value = 1; // 故意設成別的
      expect(LogicalDate.hourOf(prefs), 3);
      expect(LogicalDate.notifier.value, 1); // 仍是 1，沒被改
    });
  });
}
