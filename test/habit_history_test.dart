import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/utils/habit_history.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('newId 連續產生不重複', () {
    final ids = {for (var i = 0; i < 500; i++) HabitHistory.newId()};
    expect(ids, hasLength(500));
  });

  test('setDoneOn / doneIdsOn 逐日累積與移除', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await HabitHistory.setDoneOn(prefs, '2026-06-20', 'h1', done: true);
    await HabitHistory.setDoneOn(prefs, '2026-06-20', 'h2', done: true);
    // 重複設 true 不會重覆
    await HabitHistory.setDoneOn(prefs, '2026-06-20', 'h1', done: true);

    expect(HabitHistory.doneIdsOn(prefs, '2026-06-20').toSet(), {'h1', 'h2'});
    // 另一天彼此獨立
    expect(HabitHistory.doneIdsOn(prefs, '2026-06-21'), isEmpty);

    await HabitHistory.setDoneOn(prefs, '2026-06-20', 'h1', done: false);
    expect(HabitHistory.doneIdsOn(prefs, '2026-06-20'), ['h2']);
  });

  test('清空某天會移除 key，不留空殼', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await HabitHistory.setDoneIdsOn(prefs, '2026-06-20', ['h1']);
    expect(prefs.containsKey(PrefsKeys.habitDoneDay('2026-06-20')), isTrue);

    await HabitHistory.setDoneIdsOn(prefs, '2026-06-20', const []);
    expect(prefs.containsKey(PrefsKeys.habitDoneDay('2026-06-20')), isFalse);
  });

  test('墓碑寫入並以 id 去重', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await HabitHistory.addTombstone(
      prefs,
      id: 'h1',
      name: '舊名字',
      frequency: 'daily',
      createdAt: '2026-06-01',
      deletedAt: '2026-06-20',
    );
    // 同 id 再寫一次（例如重建後又刪）只保留最新一筆
    await HabitHistory.addTombstone(
      prefs,
      id: 'h1',
      name: '新名字',
      frequency: 'daily',
      createdAt: '2026-06-10',
      deletedAt: '2026-06-25',
    );

    final stones = HabitHistory.tombstones(prefs);
    expect(stones, hasLength(1));
    expect(stones.single['name'], '新名字');
    expect(stones.single['deletedAt'], '2026-06-25');
  });

  test('dailyHabitsAsOf 依 createdAt/deletedAt 篩出當天存在的條目', () {
    final active = [
      {'id': 'a', 'name': '冥想', 'frequency': 'daily', 'createdAt': '2026-06-01'},
      {'id': 'b', 'name': '新習慣', 'frequency': 'daily', 'createdAt': '2026-06-25'},
      {'id': 'w', 'name': '每週運動', 'frequency': 'weekly', 'createdAt': '2026-06-01'},
    ];
    final tombs = [
      {
        'id': 'c',
        'name': '已刪',
        'frequency': 'daily',
        'createdAt': '2026-06-01',
        'deletedAt': '2026-06-20',
      },
    ];

    // 6/15：a 存在、b 還沒建、c 還在、每週不算
    final d15 = HabitHistory.dailyHabitsAsOf(
      activeHabits: active,
      tombstones: tombs,
      date: '2026-06-15',
    );
    expect(d15.map((e) => e['id']).toSet(), {'a', 'c'});
    expect(d15.firstWhere((e) => e['id'] == 'c')['deleted'], isTrue);

    // 6/28：a 存在、b 已建、c 已刪
    final d28 = HabitHistory.dailyHabitsAsOf(
      activeHabits: active,
      tombstones: tombs,
      date: '2026-06-28',
    );
    expect(d28.map((e) => e['id']).toSet(), {'a', 'b'});
  });

  test('壞掉的 JSON 回傳空集合不丟例外', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.habitDoneDay('2026-06-20'): 'not json',
      PrefsKeys.habitTombstones: '{bad',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(HabitHistory.doneIdsOn(prefs, '2026-06-20'), isEmpty);
    expect(HabitHistory.tombstones(prefs), isEmpty);
  });
}
