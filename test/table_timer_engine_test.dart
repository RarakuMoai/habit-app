// 桌遊計時器引擎單測：假時鐘 + 手動 tick，不等真時間。
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/table_timer_engine.dart';
import 'package:habit_app/pages/timer/game/table_timer_models.dart';

class FakeClock {
  DateTime now = DateTime(2026, 7, 7, 12);
  void advance(Duration d) => now = now.add(d);
}

TableTimerConfig cfg({
  TableGameMode mode = TableGameMode.party,
  int playerCount = 4,
  int turnSeconds = 60,
  int warnSeconds = 10,
  bool autoAdvance = false,
}) => TableTimerConfig(
  mode: mode,
  players: [
    for (var i = 0; i < playerCount; i++)
      TablePlayer(name: 'P${i + 1}', colorIndex: i),
  ],
  turnSeconds: turnSeconds,
  warnSeconds: warnSeconds,
  autoAdvance: autoAdvance,
);

(TableTimerEngine, FakeClock, List<TableTimerEvent>) build(
  TableTimerConfig config,
) {
  final clock = FakeClock();
  final events = <TableTimerEvent>[];
  final engine = TableTimerEngine(
    config,
    clock: () => clock.now,
    autoTick: false,
  )..onEvent = events.add;
  return (engine, clock, events);
}

void main() {
  test('ready 起跑後輪替會循環回到第一位', () {
    final (engine, _, _) = build(cfg(playerCount: 3));
    expect(engine.phase, TablePhase.ready);

    engine.start();
    expect(engine.phase, TablePhase.running);
    expect(engine.currentPlayer.name, 'P1');
    expect(engine.nextPlayer.name, 'P2');

    engine.advance();
    engine.advance();
    expect(engine.currentPlayer.name, 'P3');
    engine.advance();
    expect(engine.currentPlayer.name, 'P1'); // 繞一圈
    expect(engine.turnCount, 4);
  });

  test('剩餘時間由牆鐘差算出，顯示秒數無條件進位', () {
    final (engine, clock, _) = build(cfg());
    engine.start();
    expect(engine.remainingSeconds, 60);

    clock.advance(const Duration(milliseconds: 500));
    expect(engine.remainingSeconds, 60); // 59.5 → 顯示 60

    clock.advance(const Duration(milliseconds: 600));
    expect(engine.remainingSeconds, 59);

    clock.advance(const Duration(seconds: 59));
    expect(engine.remainingSeconds, 0);
  });

  test('warn / criticalTick / expire 事件在正確門檻各發一次', () {
    final (engine, clock, events) = build(cfg(turnSeconds: 30));
    engine.start();

    clock.advance(const Duration(seconds: 19));
    engine.tick();
    expect(events, isEmpty); // 剩 11 秒還沒到

    clock.advance(const Duration(seconds: 1, milliseconds: 100));
    engine.tick();
    engine.tick(); // 重複 tick 不重複發
    expect(events, [TableTimerEvent.warn]);

    clock.advance(const Duration(seconds: 5)); // 剩 4.9 → 加強區
    engine.tick();
    expect(events.last, TableTimerEvent.criticalTick);

    clock.advance(const Duration(seconds: 1)); // 剩 3.9
    engine.tick();
    expect(events.where((e) => e == TableTimerEvent.criticalTick).length, 2);

    clock.advance(const Duration(seconds: 4)); // 超時
    engine.tick();
    expect(events.last, TableTimerEvent.expire);
    expect(engine.inOvertime, isTrue);
    expect(engine.urgency, 3);

    clock.advance(const Duration(seconds: 3, milliseconds: 200));
    engine.tick();
    expect(engine.overtimeSeconds, 3);
    expect(engine.currentPlayer.name, 'P1'); // 手動模式不自動換
  });

  test('autoAdvance 超時自動換下一位並重置回合鐘', () {
    final (engine, clock, events) = build(
      cfg(turnSeconds: 20, autoAdvance: true),
    );
    engine.start();
    clock.advance(const Duration(seconds: 20, milliseconds: 200));
    engine.tick();

    expect(events, contains(TableTimerEvent.expire));
    expect(events.last, TableTimerEvent.autoAdvance);
    expect(engine.currentPlayer.name, 'P2');
    expect(engine.remainingSeconds, 20);
    expect(engine.inOvertime, isFalse);
  });

  test('暫停凍結剩餘時間，繼續後接著走', () {
    final (engine, clock, _) = build(cfg());
    engine.start();
    clock.advance(const Duration(seconds: 10));
    engine.pause();

    clock.advance(const Duration(minutes: 5)); // 暫停中時間流逝不算
    expect(engine.remainingSeconds, 50);

    engine.resume();
    clock.advance(const Duration(seconds: 10));
    expect(engine.remainingSeconds, 40);
  });

  test('undo 回上一位且該回合整段重來；第一手不能 undo', () {
    final (engine, clock, _) = build(cfg(playerCount: 3));
    engine.start();
    engine.undo(); // 第一手：no-op
    expect(engine.currentPlayer.name, 'P1');

    engine.advance();
    clock.advance(const Duration(seconds: 30));
    engine.undo();
    expect(engine.currentPlayer.name, 'P1');
    expect(engine.remainingSeconds, 60); // 時間重來
    expect(engine.turnCount, 1);
  });

  test('free 模式只正數計時、不發事件', () {
    final (engine, clock, events) = build(
      cfg(mode: TableGameMode.free, turnSeconds: 30),
    );
    engine.start();
    clock.advance(const Duration(seconds: 45));
    engine.tick();

    expect(events, isEmpty);
    expect(engine.urgency, 0);
    expect(engine.inOvertime, isFalse);
    expect(engine.elapsedInTurn, const Duration(seconds: 45));
  });

  test('棋鐘模式只取前兩位玩家', () {
    final (engine, _, _) = build(cfg(mode: TableGameMode.chess));
    expect(engine.players.length, 2);
    engine.start();
    engine.advance();
    expect(engine.currentPlayer.name, 'P2');
    engine.advance();
    expect(engine.currentPlayer.name, 'P1');
  });

  test('統計在換人時結算思考時間與回合數', () {
    final (engine, clock, _) = build(cfg(playerCount: 2));
    engine.start();
    clock.advance(const Duration(seconds: 12));
    engine.advance();

    expect(engine.stats[0].turns, 1);
    expect(engine.stats[0].totalThink, const Duration(seconds: 12));
    expect(engine.stats[1].turns, 0);
    expect(engine.settledTurns, 1); // 進行中的半截回合不算

    clock.advance(const Duration(seconds: 6));
    engine.advance();
    clock.advance(const Duration(seconds: 4));
    engine.advance();
    expect(engine.settledTurns, 3);
    expect(engine.stats[0].totalThink, const Duration(seconds: 16));
    expect(engine.stats[0].averageThink, const Duration(seconds: 8));
  });

  test('常用組合編解碼 round-trip，壞資料回空清單', () {
    final presets = [
      TablePreset(name: '家庭拉密', config: cfg(turnSeconds: 90)),
      TablePreset(
        name: '棋鐘',
        config: cfg(mode: TableGameMode.chess, turnSeconds: 30),
      ),
    ];
    final decoded = TablePreset.decodeList(TablePreset.encodeList(presets));
    expect(decoded.length, 2);
    expect(decoded[0].name, '家庭拉密');
    expect(decoded[0].config.turnSeconds, 90);
    expect(decoded[1].config.mode, TableGameMode.chess);

    expect(TablePreset.decodeList(null), isEmpty);
    expect(TablePreset.decodeList('oops'), isEmpty);
    expect(TablePreset.decodeList('{"v":1,"items":"nope"}'), isEmpty);

    // 超過上限截斷
    final many = TablePreset.encodeList([
      for (var i = 0; i < 9; i++) TablePreset(name: 'P$i', config: cfg()),
    ]);
    expect(TablePreset.decodeList(many).length, TablePreset.maxCount);
  });

  test('config 編解碼 round-trip，壞資料回 fallback', () {
    final original = cfg(mode: TableGameMode.chess, turnSeconds: 90);
    final decoded = TableTimerConfig.decode(original.encode());
    expect(decoded.mode, TableGameMode.chess);
    expect(decoded.turnSeconds, 90);
    expect(decoded.players.length, 4);
    expect(decoded.players.first.name, 'P1');

    expect(
      TableTimerConfig.decode('not json').mode,
      TableTimerConfig.fallback().mode,
    );
    expect(TableTimerConfig.decode(null).players.length, 4);
    expect(
      TableTimerConfig.decode('{"v":1,"mode":"party","players":[]}')
          .players
          .length,
      4, // 玩家不足 → fallback
    );
  });
}
