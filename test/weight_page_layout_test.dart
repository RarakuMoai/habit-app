import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/weight_page.dart';
import 'package:habit_app/utils/app_style.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/mascot.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  testWidgets('今日體重卡在窄螢幕保持緊湊，並說清楚與上次的差值', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = LogicalDate.dayOf(DateTime.now(), LogicalDate.defaultHour);
    final yesterday = today.subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      PrefsKeys.weightRecords: jsonEncode([
        {
          'date': dateString(today),
          'time': '08:20',
          'weight': 70.5,
          'body_fat': 21.4,
        },
        {
          'date': dateString(yesterday),
          'time': '08:10',
          'weight': 70.0,
          'body_fat': 21.6,
        },
      ]),
      PrefsKeys.userHeight: 170.0,
      PrefsKeys.userGender: '男',
      PrefsKeys.userBirthday: '1990-01-01',
      PrefsKeys.userActivityLevel: '中度',
      PrefsKeys.unitSystem: 'metric',
    });
    MascotPanelPrefs.openValue.value = 1;

    await tester.pumpWidget(const MaterialApp(home: WeightPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('較上次 +0.5 kg'), findsOneWidget);
    expect(find.text('體脂率'), findsOneWidget);
    expect(find.text('BMI'), findsOneWidget);
    expect(find.text('BMR'), findsOneWidget);
    expect(find.text('TDEE'), findsOneWidget);

    final cardFinder = find.byKey(const ValueKey('today-weight-card'));
    expect(cardFinder, findsOneWidget);
    expect(
      tester.getSize(cardFinder).height,
      lessThan(175),
      reason: '今日卡應維持單屏可掃讀的緊湊高度',
    );

    final card = tester.widget<Container>(cardFinder);
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, AppSurfaces.card);
    expect(decoration.gradient, isNull);
  });
}
