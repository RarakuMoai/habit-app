import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/weight_records.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upsertSavedWeightRecord 會新增或覆蓋同日體重紀錄', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await upsertSavedWeightRecord(
      prefs,
      weightKg: 60,
      at: DateTime(2026, 6, 15, 8, 30),
    );
    await upsertSavedWeightRecord(
      prefs,
      weightKg: 61.2,
      at: DateTime(2026, 6, 15, 21, 5),
    );

    final records = parseWeightRecords(
      prefs.getString(PrefsKeys.weightRecords),
    );
    expect(records, hasLength(1));
    expect(records.single['date'], '2026-06-15');
    expect(records.single['time'], '21:05');
    expect(records.single['weight'], 61.2);
  });

  test('syncWeightHabitForDate 依當日是否有紀錄同步體重習慣', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.habits: jsonEncode([
        {'name': kWeightHabitName, 'done': false, 'frequency': 'daily'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await upsertSavedWeightRecord(
      prefs,
      weightKg: 60,
      at: DateTime(2026, 6, 15, 8),
    );
    final changed = await syncWeightHabitForDate(
      prefs,
      date: DateTime(2026, 6, 15),
    );

    expect(changed, isTrue);
    var habits = jsonDecode(prefs.getString(PrefsKeys.habits)!) as List;
    expect((habits.single as Map)['done'], isTrue);

    await prefs.setString(PrefsKeys.weightRecords, jsonEncode([]));
    await syncWeightHabitForDate(prefs, date: DateTime(2026, 6, 15));
    habits = jsonDecode(prefs.getString(PrefsKeys.habits)!) as List;
    expect((habits.single as Map)['done'], isFalse);
  });
}
