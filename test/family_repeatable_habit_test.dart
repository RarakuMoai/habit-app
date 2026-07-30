import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/pages/family/habit_sheets.dart';
import 'package:habit_app/pages/family/habit_tab.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('每日可多次習慣會顯示次數、時間並能取消指定紀錄', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final child = ChildData(id: 'child-1', name: '小兔', points: 0);
    final habit = ChildHabit(
      id: 'habit-1',
      childId: child.id,
      name: '做家事',
      points: 10,
      frequency: HabitFrequency.repeatable,
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.children: jsonEncode([child.toJson()]),
      PrefsKeys.childHabits: jsonEncode([habit.toJson()]),
    });

    var pointsChanged = 0;
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(
          body: HabitTab(child: child, onPointsChanged: () => pointsChanged++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('做家事'), findsOneWidget);
    expect(find.text('今天還沒有紀錄'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('repeatable-add-habit-1')));
    await tester.pumpAndSettle();

    expect(child.points, 10);
    expect(pointsChanged, 1);
    expect(find.textContaining('今天 1 次'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    var records = await loadRecords(prefs);
    expect(records, hasLength(1));
    expect(records.single.kind, PointRecordKind.habitCompletion);
    expect(records.single.sourceId, habit.id);

    await tester.tap(find.textContaining('今天 1 次'));
    await tester.pumpAndSettle();

    expect(find.text('今天的「做家事」'), findsOneWidget);
    expect(find.text('第 1 次'), findsOneWidget);
    expect(find.text('取消這次'), findsOneWidget);

    await tester.tap(find.text('取消這次'));
    await tester.pumpAndSettle();

    expect(child.points, 0);
    expect(pointsChanged, 2);
    expect(find.textContaining('已於'), findsOneWidget);

    records = await loadRecords(prefs);
    expect(records, hasLength(2));
    expect(records.first.kind, PointRecordKind.habitReversal);
    expect(records.first.reversesRecordId, records.last.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('編輯習慣可以選擇每日可多次模式', (tester) async {
    final habit = ChildHabit(
      id: 'habit-1',
      childId: 'child-1',
      name: '做家事',
      points: 10,
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.childHabits: jsonEncode([habit.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      l10nTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => unawaited(
                  showEditHabitSheet(
                    context,
                    prefs: prefs,
                    habit: habit,
                    onSaved: () async {},
                  ),
                ),
                child: const Text('編輯'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.tap(find.text('每日可多次'));
    await tester.pumpAndSettle();

    expect(find.text('同一天可重複記錄，每次都會加分'), findsOneWidget);
    await tester.ensureVisible(find.text('儲存'));
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    final saved = await loadHabits(prefs);
    expect(saved.single.frequency, HabitFrequency.repeatable);
  });
}
