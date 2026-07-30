import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_widgets.dart';
import 'package:habit_app/pages/family/habit_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('家庭分數欄位提供完成按鈕並可收起數字鍵盤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final habit = ChildHabit(
      id: 'habit-1',
      childId: 'child-1',
      name: '整理書包',
      points: 10,
    );

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
                child: const Text('編輯習慣'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('編輯習慣'));
    await tester.pumpAndSettle();

    final numberField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.keyboardType == TextInputType.number,
    );
    expect(numberField, findsOneWidget);
    expect(
      tester.widget<TextField>(numberField).textInputAction,
      TextInputAction.done,
    );
    expect(find.byKey(familyNumberKeyboardDoneButtonKey), findsOneWidget);

    await tester.tap(numberField);
    await tester.pump();
    final editableText = find.descendant(
      of: numberField,
      matching: find.byType(EditableText),
    );
    final focusNode = tester.widget<EditableText>(editableText).focusNode;
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(familyNumberKeyboardDoneButtonKey));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });
}
