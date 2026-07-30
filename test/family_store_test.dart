// applyPoints / applyPointsBatch：積分寫入唯一入口的行為測試
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_models.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 每個 test 各自 seed 一個有 10 分的小孩
  Future<(SharedPreferences, ChildData)> seed() async {
    final child = ChildData(id: 'c1', name: '小明', points: 10);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.children: jsonEncode([child.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    return (prefs, child);
  }

  group('applyPointsBatch', () {
    test('多筆異動：總分逐筆累計，children 落盤、傳入物件同步', () async {
      final (prefs, child) = await seed();
      final total = await applyPointsBatch(
        prefs: prefs,
        child: child,
        entries: [
          (delta: 5, reason: '特殊積分：幫忙做家事'),
          (delta: 10, reason: '特殊積分：考試進步'),
          (delta: -3, reason: '特殊積分：吵架'),
        ],
      );
      expect(total, 22);
      expect(child.points, 22);

      final saved = (jsonDecode(prefs.getString(PrefsKeys.children)!) as List)
          .map((e) => ChildData.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(saved.single.points, 22);
    });

    test('紀錄順序與逐筆呼叫一致：新的在前、total 逐筆累計', () async {
      final (prefs, child) = await seed();
      await applyPointsBatch(
        prefs: prefs,
        child: child,
        entries: [(delta: 5, reason: 'A'), (delta: 10, reason: 'B')],
      );
      final records = await loadRecords(prefs);
      expect(records.length, 2);
      // 最新（B）在最前
      expect(records[0].reason, 'B');
      expect(records[0].delta, 10);
      expect(records[0].total, 25);
      expect(records[1].reason, 'A');
      expect(records[1].delta, 5);
      expect(records[1].total, 15);
      // id 不重複
      expect(records[0].id, isNot(records[1].id));
    });

    test('空清單是 no-op', () async {
      final (prefs, child) = await seed();
      final total = await applyPointsBatch(
        prefs: prefs,
        child: child,
        entries: [],
      );
      expect(total, 10);
      expect(await loadRecords(prefs), isEmpty);
    });

    test('找不到小孩時不寫入，回傳原積分', () async {
      final (prefs, _) = await seed();
      final ghost = ChildData(id: 'nobody', name: '幽靈', points: 7);
      final total = await applyPointsBatch(
        prefs: prefs,
        child: ghost,
        entries: [(delta: 5, reason: 'X')],
      );
      expect(total, 7);
      expect(await loadRecords(prefs), isEmpty);
    });
  });

  group('applyPoints（單筆，委派批次版）', () {
    test('單筆加分與扣分', () async {
      final (prefs, child) = await seed();
      expect(
        await applyPoints(
          prefs: prefs,
          child: child,
          delta: 5,
          reason: '完成習慣：刷牙',
        ),
        15,
      );
      expect(
        await applyPoints(
          prefs: prefs,
          child: child,
          delta: -5,
          reason: '撤銷完成：刷牙',
        ),
        10,
      );
      final records = await loadRecords(prefs);
      expect(records.length, 2);
      expect(records[0].total, 10);
      expect(records[1].total, 15);
    });

    test('可重複習慣以紀錄 ID 精確連結完成與撤銷', () async {
      final (prefs, child) = await seed();
      const completionId = 'habit-completion-1';

      await applyPoints(
        prefs: prefs,
        child: child,
        delta: 7,
        reason: '完成習慣：做家事',
        recordContext: const PointRecordContext(
          id: completionId,
          kind: PointRecordKind.habitCompletion,
          sourceId: 'habit-1',
        ),
      );
      await applyPoints(
        prefs: prefs,
        child: child,
        delta: -7,
        reason: '撤銷完成：做家事',
        recordContext: const PointRecordContext(
          kind: PointRecordKind.habitReversal,
          sourceId: 'habit-1',
          reversesRecordId: completionId,
        ),
      );

      final records = await loadRecords(prefs);
      final completions = habitCompletionRecordsForDay(
        records: records,
        habitId: 'habit-1',
        date: todayStr(),
      );
      final reversals = habitReversalsByCompletionId(records);

      expect(child.points, 10);
      expect(completions, hasLength(1));
      expect(completions.single.id, completionId);
      expect(completions.single.delta, 7);
      expect(reversals[completionId]?.delta, -7);
      expect(reversals[completionId]?.sourceId, 'habit-1');
    });

    test('舊積分紀錄沒有來源欄位時仍可讀取', () {
      final record = PointRecord.fromJson({
        'id': 'legacy',
        'child_id': 'c1',
        'time': '2026-07-30 09:15',
        'reason': '舊紀錄',
        'delta': 5,
        'total': 15,
      });

      expect(record.kind, isNull);
      expect(record.sourceId, isNull);
      expect(record.reversesRecordId, isNull);
    });
  });
}
