// 補打勾頁：載入昨天、列出當時存在的每日習慣、勾選會寫進歷史。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/habit_backfill_page.dart';
import 'package:habit_app/utils/habit_history.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用預設換日時間（4 點）算出的「昨天」＝補登頁預設選的日子。
  final today = LogicalDate.dayOf(DateTime.now(), LogicalDate.defaultHour);
  final yesterday = _fmt(today.subtract(const Duration(days: 1)));

  testWidgets('列出每日習慣、排除每週與連動、勾選寫入昨天歷史', (tester) async {
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

    await tester.pumpWidget(const MaterialApp(home: HabitBackfillPage()));
    await tester.pumpAndSettle();

    // 每日非連動習慣列出；每週與喝水不列為可勾項
    expect(find.text('閱讀'), findsOneWidget);
    expect(find.text('每週運動'), findsNothing);
    // 喝水是連動習慣 → 不在可勾清單，但底部出現導去提示
    expect(find.text('喝足夠的水'), findsNothing);
    expect(find.text('喝水、體重的補登請到各自的頁面'), findsOneWidget);

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

    await tester.pumpWidget(const MaterialApp(home: HabitBackfillPage()));
    await tester.pumpAndSettle();

    expect(find.text('牙線'), findsOneWidget);
    expect(find.text('已刪除'), findsOneWidget);

    await tester.tap(find.text('牙線'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(HabitHistory.doneIdsOn(prefs, yesterday), contains('h_floss'));
  });
}
