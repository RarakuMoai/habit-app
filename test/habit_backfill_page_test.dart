// 補打勾頁：載入昨天、列出當時存在的每日習慣、勾選會寫進歷史。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/habit_backfill_page.dart';
import 'package:habit_app/utils/habit_history.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用預設換日時間（4 點）算出的「昨天」＝補登頁預設選的日子。
  final today = LogicalDate.dayOf(DateTime.now(), LogicalDate.defaultHour);
  final yesterday = _fmt(today.subtract(const Duration(days: 1)));

  testWidgets('列出每日與喝水習慣、排除每週、勾選寫入昨天歷史', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.habits: jsonEncode([
        {
          'id': 'h_read',
          'name': '閱讀',
          'frequency': 'daily',
          'createdAt': '2020-01-01',
        },
        {
          'id': 'h_week',
          'name': '每週運動',
          'frequency': 'weekly',
          'createdAt': '2020-01-01',
        },
        {
          'id': 'h_water',
          'name': '喝足夠的水',
          'frequency': 'daily',
          'createdAt': '2020-01-01',
        },
      ]),
    });

    await tester.pumpWidget(l10nTestApp(home: const HabitBackfillPage()));
    await tester.pumpAndSettle();

    // 每日習慣與喝水列出；每週習慣不列為可勾項。
    expect(find.text('閱讀'), findsOneWidget);
    expect(find.text('每週運動'), findsNothing);
    expect(find.text('喝足夠的水'), findsOneWidget);

    // 勾「閱讀」→ 寫進昨天的歷史
    await tester.tap(find.text('閱讀'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(HabitHistory.doneIdsOn(prefs, yesterday), contains('h_read'));

    // 再點一次取消 → 從歷史移除、key 清掉
    await tester.tap(find.text('閱讀'));
    await tester.pumpAndSettle();
    expect(HabitHistory.doneIdsOn(prefs, yesterday), isEmpty);
  });

  testWidgets('補喝水寫入合格量，取消後還原原紀錄', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.waterGoalMl: 1800,
      PrefsKeys.waterCupMl: 300,
      PrefsKeys.habits: jsonEncode([
        {
          'id': 'h_water',
          'name': '喝足夠的水',
          'frequency': 'daily',
          'createdAt': '2020-01-01',
        },
      ]),
      PrefsKeys.waterEntries(yesterday):
          '[{"ml":300,"kind":"cup","at":"2026-01-01T08:00:00.000"}]',
    });

    await tester.pumpWidget(l10nTestApp(home: const HabitBackfillPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喝足夠的水'));
    await tester.pumpAndSettle();

    var prefs = await SharedPreferences.getInstance();
    var entries =
        jsonDecode(prefs.getString(PrefsKeys.waterEntries(yesterday))!)
            as List<dynamic>;
    expect((entries.single as Map<String, dynamic>)['ml'], 1800);
    expect(HabitHistory.doneIdsOn(prefs, yesterday), contains('h_water'));

    await tester.tap(find.text('喝足夠的水'));
    await tester.pumpAndSettle();
    prefs = await SharedPreferences.getInstance();
    entries =
        jsonDecode(prefs.getString(PrefsKeys.waterEntries(yesterday))!)
            as List<dynamic>;
    expect((entries.single as Map<String, dynamic>)['ml'], 300);
    expect(HabitHistory.doneIdsOn(prefs, yesterday), isEmpty);
  });

  testWidgets('已刪除的習慣在它存在的日子仍可補，標記已刪除', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.habits: jsonEncode(<Map<String, dynamic>>[]),
      PrefsKeys.habitTombstones: jsonEncode([
        {
          'id': 'h_floss',
          'name': '牙線',
          'frequency': 'daily',
          'createdAt': '2020-01-01',
          'deletedAt': '2099-01-01',
        },
      ]),
    });

    await tester.pumpWidget(l10nTestApp(home: const HabitBackfillPage()));
    await tester.pumpAndSettle();

    expect(find.text('牙線'), findsOneWidget);
    expect(find.text('已刪除'), findsOneWidget);

    await tester.tap(find.text('牙線'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(HabitHistory.doneIdsOn(prefs, yesterday), contains('h_floss'));
  });

  testWidgets('日期列固定只有昨天起往前七天', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(l10nTestApp(home: const HabitBackfillPage()));
    await tester.pumpAndSettle();

    final strip = find.byKey(const ValueKey('backfill-date-strip'));
    expect(strip, findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.byType(GestureDetector)),
      findsNWidgets(7),
    );
  });
}
