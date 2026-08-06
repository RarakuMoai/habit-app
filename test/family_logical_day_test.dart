// 家庭模式跟隨換日設定（2026-08-06）。
//
// 改動理由：登記的人是大人不是小孩。大人可能忙到過午夜才想起要幫小孩補登，
// 固定午夜換日會把 00:30 按下去的那筆算成隔天——習慣卡重置、補不進當天。
//
// 這裡釘住三件事：
// 1. 凌晨補登仍算「昨天」（核心情境）
// 2. todayStr / nowStr / currentWeekDateSet 三者基準一致（不一致會導致
//    「卡片說今天沒紀錄，分數卻已經加了」）
// 3. 換日時間設 0 時退化成日曆日（等同改動前的行為）

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/family/family_store.dart';
import 'package:habit_app/utils/logical_date.dart';

void main() {
  // 8/5 23:00 = 睡前登記；8/6 00:30 = 過了午夜才想起要補登。
  final beforeMidnight = DateTime(2026, 8, 5, 23, 0);
  final afterMidnight = DateTime(2026, 8, 6, 0, 30);
  const dayStart = LogicalDate.defaultHour; // 4

  group('大人過午夜補登', () {
    test('00:30 補登與睡前 23:00 算同一個邏輯日', () {
      final before = todayStr(now: beforeMidnight, dayStartHour: dayStart);
      final after = todayStr(now: afterMidnight, dayStartHour: dayStart);

      expect(before, '2026-08-05');
      expect(
        after,
        before,
        reason: '00:30 必須仍算 8/5，否則習慣卡會重置、補登落到隔天',
      );
    });

    test('過了換日線（04:00 之後）才換日', () {
      expect(
        todayStr(now: DateTime(2026, 8, 6, 3, 59), dayStartHour: dayStart),
        '2026-08-05',
      );
      expect(
        todayStr(now: DateTime(2026, 8, 6, 4, 0), dayStartHour: dayStart),
        '2026-08-06',
      );
    });
  });

  group('三個函式基準一致', () {
    test('nowStr 的日期前綴等於 todayStr（查詢比對靠這個）', () {
      for (final at in [
        beforeMidnight,
        afterMidnight,
        DateTime(2026, 8, 6, 3, 59),
        DateTime(2026, 8, 6, 4, 0),
        DateTime(2026, 8, 6, 12, 0),
      ]) {
        final recorded = nowStr(now: at, dayStartHour: dayStart);
        expect(
          recorded.split(' ').first,
          todayStr(now: at, dayStartHour: dayStart),
          reason: '$at：日期前綴與 todayStr 不一致會查不到剛寫進去的紀錄',
        );
      }
    });

    test('nowStr 的時間部分維持真實時鐘', () {
      expect(nowStr(now: afterMidnight, dayStartHour: dayStart), '2026-08-05 00:30');
    });

    test('本週集合以邏輯日推算，00:30 仍屬於上一個邏輯日所在的那一週', () {
      // 8/5 是週三，所以那一週是 8/3(一)–8/9(日)。
      final week = currentWeekDateSet(now: afterMidnight, dayStartHour: dayStart);

      expect(week, contains(todayStr(now: afterMidnight, dayStartHour: dayStart)));
      expect(week.length, 7);
      expect(week, contains('2026-08-03'));
      expect(week, contains('2026-08-09'));
    });

    test('週日深夜補登不會跳到下一週', () {
      // 8/9 是週日；8/10 00:30 在換日線前，仍算 8/9。
      final week = currentWeekDateSet(
        now: DateTime(2026, 8, 10, 0, 30),
        dayStartHour: dayStart,
      );

      expect(week, contains('2026-08-09'));
      expect(
        week,
        isNot(contains('2026-08-10')),
        reason: '8/10 屬於下一週，00:30 的補登不該把週界推過去',
      );
    });
  });

  group('換日時間 0 = 日曆日（改動前的行為）', () {
    test('todayStr 退化成日曆日', () {
      expect(todayStr(now: afterMidnight, dayStartHour: 0), '2026-08-06');
      expect(todayStr(now: beforeMidnight, dayStartHour: 0), '2026-08-05');
    });

    test('週日深夜的週界：日曆日會跳到下一週，邏輯日不會', () {
      // 8/10 00:30。日曆日 → 今天是 8/10(週一) → 新的一週。
      final calendarWeek = currentWeekDateSet(
        now: DateTime(2026, 8, 10, 0, 30),
        dayStartHour: 0,
      );
      expect(calendarWeek, contains('2026-08-10'));
      expect(calendarWeek, isNot(contains('2026-08-09')));

      // 換日 4:00 → 今天仍是 8/9(週日) → 還是上一週。這就是差別所在。
      final logicalWeek = currentWeekDateSet(
        now: DateTime(2026, 8, 10, 0, 30),
        dayStartHour: 4,
      );
      expect(logicalWeek, contains('2026-08-09'));
      expect(logicalWeek, isNot(contains('2026-08-10')));
    });
  });

  group('未帶參數時讀全域 notifier', () {
    tearDown(() => LogicalDate.notifier.value = LogicalDate.defaultHour);

    test('notifier 改變後 todayStr 立即跟著變', () {
      LogicalDate.notifier.value = 0;
      final calendarDay = todayStr(now: afterMidnight);

      LogicalDate.notifier.value = 4;
      final logicalDay = todayStr(now: afterMidnight);

      expect(calendarDay, '2026-08-06');
      expect(logicalDay, '2026-08-05');
    });
  });
}
