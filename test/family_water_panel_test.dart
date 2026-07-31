import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/pages/family/habit_tab.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ChildData> pumpTab(WidgetTester tester, {required String habitName}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final child = ChildData(id: 'child-1', name: '小兔', points: 0);
    final habit = ChildHabit(
      id: 'habit-1',
      childId: child.id,
      name: habitName,
      points: 5,
      frequency: HabitFrequency.repeatable,
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.children: jsonEncode([child.toJson()]),
      PrefsKeys.childHabits: jsonEncode([habit.toJson()]),
    });
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(body: HabitTab(child: child, onPointsChanged: () {})),
      ),
    );
    await tester.pumpAndSettle();
    return child;
  }

  testWidgets('「今日多喝水」的卡片按鈕是「喝水去」', (tester) async {
    await pumpTab(tester, habitName: kFamilyWaterHabitName);
    expect(find.text('喝水去'), findsOneWidget);
    expect(find.text('記一次'), findsNothing);
  });

  testWidgets('其他可多次習慣維持「記一次」', (tester) async {
    await pumpTab(tester, habitName: '做家事');
    expect(find.text('記一次'), findsOneWidget);
    expect(find.text('喝水去'), findsNothing);
  });

  testWidgets('喝水面板記一杯會加分、留下時間，並可取消該杯', (tester) async {
    final child = await pumpTab(tester, habitName: kFamilyWaterHabitName);

    await tester.tap(find.text('喝水去'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('今日補水'), findsOneWidget);
    expect(find.text('0 / 8 杯'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('family-water-drink')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(child.points, 5);
    expect(find.text('1 / 8 杯'), findsOneWidget);
    // 杯數就是這個習慣的完成紀錄，時間與撤銷都從那裡來
    final prefs = await SharedPreferences.getInstance();
    final records = await loadRecords(prefs);
    expect(records.single.kind, PointRecordKind.habitCompletion);
    expect(records.single.sourceId, 'habit-1');

    await tester.tap(find.text('取消這次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(child.points, 0);
    expect(find.text('0 / 8 杯'), findsOneWidget);
    expect(find.textContaining('已於'), findsOneWidget);
  });

  testWidgets('每日目標可調整並存成這個小孩自己的設定', (tester) async {
    await pumpTab(tester, habitName: kFamilyWaterHabitName);
    await tester.tap(find.text('喝水去'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('8 杯'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('9 杯'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.familyWaterGoal('child-1')), 9);
  });
}
