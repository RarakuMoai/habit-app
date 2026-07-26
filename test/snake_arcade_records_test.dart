import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/game/snake_arcade/snake_arcade_records.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 7, 22, 20, 30); // 週三晚上

  SnakeArcadeScore add(
    SnakeArcadeRecords records, {
    required String name,
    required int score,
    DateTime? time,
  }) {
    return records.addEntry(
      name: name,
      score: score,
      carrots: score ~/ 12,
      maxLength: 10,
      now: time ?? now,
      fallbackName: '玩家',
    );
  }

  test('存讀往返；未知版本整包重來', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final records = SnakeArcadeRecords.empty();
    add(records, name: '小紅', score: 120);
    await records.save(prefs);

    final loaded = SnakeArcadeRecords.load(prefs);
    expect(loaded.entries.length, 1);
    expect(loaded.entries.single.name, '小紅');
    expect(loaded.lastPlayerName, '小紅');
    expect(loaded.recentNames, ['小紅']);

    await prefs.setString(
      PrefsKeys.snakeArcadeData,
      '{"version":99,"entries":[]}',
    );
    expect(SnakeArcadeRecords.load(prefs).entries, isEmpty);

    await prefs.setString(PrefsKeys.snakeArcadeData, 'not json');
    expect(SnakeArcadeRecords.load(prefs).entries, isEmpty);
  });

  test('三榜過濾：今日／本週（週一起算）／歷史', () {
    final records = SnakeArcadeRecords.empty();
    add(records, name: '今天', score: 100);
    add(records, name: '週一', score: 90, time: DateTime(2026, 7, 20, 8));
    add(records, name: '上週日', score: 80, time: DateTime(2026, 7, 19, 23));
    add(records, name: '上月', score: 70, time: DateTime(2026, 6, 5));

    expect(records.board(SnakeArcadeBoard.today, now).map((e) => e.name), [
      '今天',
    ]);
    expect(records.board(SnakeArcadeBoard.week, now).map((e) => e.name), [
      '今天',
      '週一',
    ]);
    expect(records.board(SnakeArcadeBoard.allTime, now).map((e) => e.name), [
      '今天',
      '週一',
      '上週日',
      '上月',
    ]);
  });

  test('同分先達成者在前', () {
    final records = SnakeArcadeRecords.empty();
    add(records, name: '後到', score: 100, time: now);
    add(
      records,
      name: '先到',
      score: 100,
      time: now.subtract(const Duration(hours: 2)),
    );
    expect(records.board(SnakeArcadeBoard.today, now).map((e) => e.name), [
      '先到',
      '後到',
    ]);
  });

  test('進榜判定：榜未滿都進；滿了要贏過第 10 名，同分不擠位', () {
    final records = SnakeArcadeRecords.empty();
    expect(records.qualifies(1, now), isTrue);
    expect(records.qualifies(0, now), isFalse);

    for (var i = 0; i < SnakeArcadeRecords.boardSize; i++) {
      add(records, name: 'p$i', score: 100 + i);
    }
    expect(records.qualifies(100, now), isFalse); // 同分不擠掉第 10 名
    expect(records.qualifies(101, now), isTrue);
  });

  test('署名記憶：預設帶上次、最近名單去重、上限 6 筆、空白補玩家', () {
    final records = SnakeArcadeRecords.empty();
    for (final name in ['爸爸', '媽媽', '姊姊', '弟弟', '阿公', '阿嬤', '爸爸']) {
      add(records, name: name, score: 50);
    }
    expect(records.lastPlayerName, '爸爸');
    expect(records.recentNames.length, 6);
    expect(records.recentNames.first, '爸爸');
    expect(records.recentNames.where((n) => n == '爸爸').length, 1);

    final entry = add(records, name: '   ', score: 60);
    expect(entry.name, '玩家');
  });

  test('修剪：保留歷史前 50，加上最近 8 天內成績', () {
    final records = SnakeArcadeRecords.empty();
    final old = now.subtract(const Duration(days: 30));
    for (var i = 0; i < 60; i++) {
      add(records, name: 'old$i', score: 1000 + i, time: old);
    }
    add(records, name: '今天低分', score: 1, time: now);
    // 今天低分遠不及歷史前 50，但因在 8 天內仍被保留。
    expect(records.entries.any((e) => e.name == '今天低分'), isTrue);
    // 歷史部分只留前 50（分數 1010–1059）。
    final oldKept = records.entries.where((e) => e.name.startsWith('old'));
    expect(oldKept.length, 50);
    expect(oldKept.every((e) => e.score >= 1010), isTrue);
  });
}
