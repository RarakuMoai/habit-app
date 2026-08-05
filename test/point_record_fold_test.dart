import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/pages/family/point_record_tab.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

PointRecord _completion({
  required String id,
  required String time,
  required String sourceId,
  int delta = 5,
  int total = 0,
}) => PointRecord(
  id: id,
  childId: 'child-1',
  time: time,
  reason: '完成習慣：做家事',
  delta: delta,
  total: total,
  kind: PointRecordKind.habitCompletion,
  sourceId: sourceId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTab(WidgetTester tester, List<PointRecord> records) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.pointRecords: jsonEncode(
        records.map((r) => r.toJson()).toList(),
      ),
    });
    await tester.pumpWidget(
      l10nTestApp(
        home: Scaffold(
          body: PointRecordTab(
            child: ChildData(id: 'child-1', name: '小兔', points: 0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('同一天同一習慣的完成紀錄摺成一列，展開後看得到每一次', (tester) async {
    final today = todayStr();
    await pumpTab(tester, [
      // 新到舊（寫入端是 insert(0)）
      _completion(id: 'r3', time: '$today 21:00', sourceId: 'h1', total: 15),
      _completion(id: 'r2', time: '$today 12:00', sourceId: 'h1', total: 10),
      _completion(id: 'r1', time: '$today 08:00', sourceId: 'h1', total: 5),
    ]);

    // 摺成一列：標題帶次數，三筆合計 +15
    expect(find.text('完成習慣：做家事 ×3'), findsOneWidget);
    expect(find.text('完成習慣：做家事'), findsNothing);
    expect(find.text('+15 分'), findsOneWidget);

    // 展開後逐筆看得到時間
    await tester.tap(find.text('完成習慣：做家事 ×3'));
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('不同天、不同習慣、以及撤銷紀錄都不會被摺在一起', (tester) async {
    final today = todayStr();
    await pumpTab(tester, [
      _completion(id: 'r4', time: '$today 09:00', sourceId: 'h2', total: 20),
      _completion(id: 'r3', time: '$today 08:00', sourceId: 'h1', total: 15),
      PointRecord(
        id: 'r2',
        childId: 'child-1',
        time: '$today 07:00',
        reason: '撤銷完成：做家事',
        delta: -5,
        total: 10,
        kind: PointRecordKind.habitReversal,
        sourceId: 'h1',
        reversesRecordId: 'r1',
      ),
      _completion(id: 'r1', time: '$today 06:00', sourceId: 'h1', total: 15),
    ]);

    // h1 的兩筆完成雖然同一天，但中間那筆是撤銷、kind 不同，撤銷自成一列
    expect(find.text('撤銷完成：做家事'), findsOneWidget);
    // h1 的兩筆完成摺成一列，h2 自成一列
    expect(find.text('完成習慣：做家事 ×2'), findsOneWidget);
    expect(find.text('完成習慣：做家事'), findsOneWidget);
  });

  testWidgets('單筆時外觀不變：沒有次數後綴、標題就是原本的理由', (tester) async {
    final today = todayStr();
    await pumpTab(tester, [
      _completion(id: 'r1', time: '$today 08:00', sourceId: 'h1', total: 5),
    ]);

    expect(find.text('完成習慣：做家事'), findsOneWidget);
    expect(find.textContaining('×'), findsNothing);
    // 單筆的副標是完整時間戳，不是只有日期
    expect(find.text('$today 08:00'), findsOneWidget);
  });
}
