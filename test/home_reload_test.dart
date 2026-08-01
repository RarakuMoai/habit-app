// 首頁習慣載入的「可安全重入」保證。
//
// 舊版 loadHabits 直接 addAll 進既有清單，只能在 initState 跑一次；跨日刷新
// 需要它能被重複呼叫。這份測試釘住重入後的不變量：不重複、不閃空、不吃掉
// 使用者操作、dispose 後不 setState。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/home_page.dart';
import 'package:habit_app/utils/logical_date.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

Map<String, dynamic> _habit(
  String name, {
  bool done = false,
  String? id,
  String? createdAt,
}) {
  return <String, dynamic>{
    'id': ?id,
    'createdAt': ?createdAt,
    'name': name,
    'done': done,
    'frequency': 'daily',
  };
}

String _todayString([int dayStartHour = LogicalDate.defaultHour]) =>
    LogicalDate.stringFor(DateTime.now(), dayStartHour);

/// 掛上首頁並等到第一輪載入完成。
Future<dynamic> _pumpHome(
  WidgetTester tester, {
  bool waterAuto = false,
  bool weightAuto = false,
}) async {
  await tester.pumpWidget(
    l10nTestApp(
      home: HomePage(
        waterHabitAutoComplete: waterAuto,
        weightHabitAutoComplete: weightAuto,
      ),
    ),
  );
  // 第一輪載入是 async；多 pump 幾次讓 prefs 的 microtask 跑完。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.state(find.byType(HomePage)) as dynamic;
}

/// 收掉整棵樹，讓 ticker / timer 不留到下一個測試。
Future<void> _tearDownHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

List<Map<String, dynamic>> _storedHabits(SharedPreferences prefs) {
  final raw = prefs.getString(PrefsKeys.habits);
  if (raw == null) return const [];
  return (jsonDecode(raw) as List<dynamic>)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('重複 reload 不會讓習慣變兩份（記憶體與 storage 都是）', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', id: 'h1', createdAt: '2026-01-01'),
        _habit('走路', id: 'h2', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);
    expect((state.habits as List).length, 2);

    await state.loadHabits();
    await tester.pump();
    await state.loadHabits();
    await tester.pump();

    expect((state.habits as List).length, 2, reason: '記憶體清單不得累加');
    // 清單是 lazy sliver，只斷言可見的那張沒有變成兩張。
    expect(find.text('喝水'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(_storedHabits(prefs).length, 2, reason: 'storage 也不得被寫成兩份');

    await _tearDownHome(tester);
  });

  testWidgets('同日 reload 保留 done 狀態，不會被誤當成跨日重置', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.streak: 5,
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', done: true, id: 'h1', createdAt: '2026-01-01'),
        _habit('走路', id: 'h2', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);
    await state.loadHabits();
    await tester.pump();

    final habits = state.habits as List;
    expect(habits[0]['done'], isTrue);
    expect(habits[1]['done'], isFalse);
    expect(state.streak, 5, reason: '同日 reload 不得動連勝');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.streak), 5);
    expect(_storedHabits(prefs)[0]['done'], isTrue);

    await _tearDownHome(tester);
  });

  testWidgets('同日 reload 不重播卡片進場動畫（維持全不透明）', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', id: 'h1', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);
    // 第一輪的進場動畫跑完
    await tester.pump(const Duration(milliseconds: 600));

    await state.loadHabits();
    await tester.pump(); // reload 後的第一幀

    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('喝水'), matching: find.byType(Opacity))
          .first,
    );
    expect(
      opacity.opacity,
      1.0,
      reason: '同日 reload 若清掉 _animatedIn，這一幀會從 0 重新淡入',
    );

    await _tearDownHome(tester);
  });

  testWidgets('reload 進行中的打勾不落地、不改資料', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', id: 'h1', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);
    expect((state.habits as List)[0]['done'], isFalse);

    // 不 await：_runLoad 在第一個 await 之前已同步把 guard 舉起來。
    final pending = state.loadHabits() as Future<void>;
    state.toggleHabit(0); // 應該被擋下
    await pending;
    await tester.pump();

    expect(
      (state.habits as List)[0]['done'],
      isFalse,
      reason: 'reload 期間的打勾必須被擋，否則會被接著替換的新快照吃掉',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(_storedHabits(prefs)[0]['done'], isFalse);
    expect(
      prefs.getString(PrefsKeys.habitDoneDay(_todayString())),
      isNull,
      reason: '被擋下的打勾不得寫進今天的歷史',
    );

    await _tearDownHome(tester);
  });

  testWidgets('reload 途中 dispose 不會丟出 setState 例外', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', id: 'h1', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);
    final pending = state.loadHabits() as Future<void>;
    await tester.pumpWidget(const SizedBox()); // 載入途中收掉整棵樹
    await pending;
    await tester.pump(const Duration(seconds: 5));

    expect(tester.takeException(), isNull);
  });

  testWidgets('舊資料缺 id/createdAt：遷移一次後重複 reload 結果穩定', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: _todayString(),
      PrefsKeys.onboardingDate: DateTime(2026, 3, 5).toIso8601String(),
      PrefsKeys.habits: jsonEncode([
        {'name': '喝水', 'done': false, 'frequency': 'daily'},
        {'name': '走路', 'done': true, 'frequency': 'daily'},
      ]),
    });

    final state = await _pumpHome(tester);
    final prefs = await SharedPreferences.getInstance();
    final afterFirst = _storedHabits(prefs);
    expect(afterFirst.length, 2);
    expect(afterFirst[0]['id'], isA<String>());
    expect(afterFirst[0]['createdAt'], '2026-03-05');
    final firstIds = afterFirst.map((h) => h['id']).toList();

    await state.loadHabits();
    await tester.pump();

    final afterSecond = _storedHabits(prefs);
    expect(afterSecond.length, 2, reason: '遷移不得製造重複');
    expect(
      afterSecond.map((h) => h['id']).toList(),
      firstIds,
      reason: '已經有 id 就不該重新產生（遷移必須冪等）',
    );

    await _tearDownHome(tester);
  });

  testWidgets('跨日結果不變：連勝結算、勾選重置、歷史保留昨天', (tester) async {
    final today = _todayString();
    final yesterday = LogicalDate.stringFor(
      DateTime.now().subtract(const Duration(days: 1)),
      LogicalDate.defaultHour,
    );
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastOpenDate: yesterday,
      PrefsKeys.streak: 4,
      PrefsKeys.habitDoneDay(yesterday): jsonEncode(['h1', 'h2']),
      PrefsKeys.habits: jsonEncode([
        _habit('喝水', done: true, id: 'h1', createdAt: '2026-01-01'),
        _habit('走路', done: true, id: 'h2', createdAt: '2026-01-01'),
      ]),
    });

    final state = await _pumpHome(tester);

    expect(state.streak, 5, reason: '昨天全完成 → 連勝 +1（既有行為）');
    final habits = state.habits as List;
    expect(habits.length, 2);
    expect(habits.every((h) => h['done'] == false), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.streak), 5);
    expect(prefs.getString(PrefsKeys.lastOpenDate), today);
    expect(
      prefs.getString(PrefsKeys.habitDoneDay(yesterday)),
      jsonEncode(['h1', 'h2']),
      reason: '昨天的歷史不得被跨日重置洗掉',
    );
    expect(
      prefs.getString(PrefsKeys.habitDoneDay(today)),
      isNull,
      reason: '新的一天沒有任何完成，空集合不留空殼 key',
    );

    await tester.pump(const Duration(seconds: 6)); // 讓問候橫幅的計時器跑完
    await _tearDownHome(tester);
  });
}
