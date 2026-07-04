import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/timer/game/game_clock.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 遊戲計時器純邏輯層的單元測試：不 pump 任何 widget，直接驅動
// GameClockController 的狀態機與 tick 時間運算——這是重寫成
// 邏輯/UI 分層後才測得到的核心行為。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 建一顆指定設定的 controller，並收集事件。
  (GameClockController, List<GameClockEvent>) make({
    GameClockMode mode = GameClockMode.turn,
    int players = 2,
    int turnSeconds = 10,
    int bankSeconds = 30, // setBankSeconds 下限 30
    int increment = 0,
    int warnSeconds = 3,
  }) {
    final c = GameClockController();
    c.setMode(mode);
    c.setPlayerCount(players);
    c.setTurnSeconds(turnSeconds);
    c.setBankSeconds(bankSeconds);
    c.setIncrement(increment);
    c.setWarnSeconds(warnSeconds);
    final events = <GameClockEvent>[];
    c.onEvent = events.add;
    return (c, events);
  }

  group('每回合模式', () {
    test('start 裝滿、tick 扣秒、pass 換手且新玩家重置滿秒', () {
      final (c, _) = make();
      expect(c.start(), isTrue);
      expect(c.running, isTrue);
      c.tick(3.2);
      expect(c.activePlayer.remaining, closeTo(6.8, 1e-9));

      expect(c.pass(), isTrue);
      expect(c.activeIndex, 1);
      expect(c.activePlayer.remaining, 10); // 新的一手裝滿
      expect(c.playerAt(0).remaining, closeTo(6.8, 1e-9)); // 舊玩家停在原處
    });

    test('歸零進超時：不換手、往負數數，turnTimeUp 只發一次', () {
      final (c, events) = make();
      c.start();
      c.tick(11);
      expect(c.turnOvertime, isTrue);
      expect(c.activeIndex, 0); // 不自動換手
      expect(events.where((e) => e == GameClockEvent.turnTimeUp).length, 1);

      c.tick(2);
      expect(c.activePlayer.remaining, lessThan(-2));
      expect(events.where((e) => e == GameClockEvent.turnTimeUp).length, 1);
    });

    test('最後幾秒 warnTick 跨秒各發一次、超時不發', () {
      final (c, events) = make();
      c.start();
      for (var i = 0; i < 12; i++) {
        c.tick(1);
      }
      // 剩 3、2、1 秒各提示一次；歸零後（超時中）不再提示。
      expect(events.where((e) => e == GameClockEvent.warnTick).length, 3);
    });
  });

  group('棋鐘模式', () {
    test('Fischer 增秒：換手時加給剛走完的玩家', () {
      final (c, _) = make(
        mode: GameClockMode.bank,
        bankSeconds: 60,
        increment: 5,
      );
      c.start();
      c.tick(10);
      expect(c.activePlayer.remaining, closeTo(50, 1e-9));
      c.pass();
      expect(c.playerAt(0).remaining, closeTo(55, 1e-9));
      expect(c.activeIndex, 1);
    });

    test('兩人：一人用完直接決出勝負，只發 finished 一個事件', () {
      final (c, events) = make(mode: GameClockMode.bank);
      c.start();
      c.tick(31);
      expect(c.finished, isTrue);
      expect(c.winnerIndex, 1);
      expect(c.playerAt(0).flagged, isTrue);
      expect(c.playerAt(0).remaining, 0);
      expect(events, [GameClockEvent.finished]); // 不疊 playerFlagged
    });

    test('三人：一人出局發 playerFlagged、輪替跳過出局者', () {
      final (c, events) = make(mode: GameClockMode.bank, players: 3);
      c.start();
      c.tick(31); // 玩家1 出局
      expect(c.running, isTrue);
      expect(events, [GameClockEvent.playerFlagged]);
      expect(c.activeIndex, 1);

      c.pass();
      expect(c.activeIndex, 2);
      c.pass();
      expect(c.activeIndex, 1); // 跳過已出局的 0
    });

    test('超時出局被「上一位」還原：拿回寬限秒數、能再次被判出局', () {
      final (c, _) = make(mode: GameClockMode.bank);
      c.start();
      c.tick(31);
      expect(c.finished, isTrue);

      expect(c.undo(), isTrue);
      expect(c.paused, isTrue); // 還原掉勝負 → 暫停，按繼續再開
      expect(c.winnerIndex, -1);
      expect(c.playerAt(0).flagged, isFalse);
      expect(
        c.playerAt(0).remaining,
        GameClockController.undoGraceSeconds, // 不是舊版的負秒數死局
      );

      // 繼續跑，寬限用完要能再次判出局（舊版還原負秒數後永遠不會）。
      expect(c.start(), isTrue);
      c.tick(GameClockController.undoGraceSeconds + 1);
      expect(c.finished, isTrue);
      expect(c.winnerIndex, 1);
    });
  });

  group('開始/暫停/重設/上一位', () {
    test('pause 保留剩餘秒數、暫停中 tick 無效、繼續接著跑', () {
      final (c, _) = make();
      c.start();
      c.tick(4);
      expect(c.pause(), isTrue);
      final atPause = c.activePlayer.remaining;
      c.tick(3); // 暫停中不該扣
      expect(c.activePlayer.remaining, atPause);
      expect(c.start(), isTrue); // 繼續
      c.tick(1);
      expect(c.activePlayer.remaining, closeTo(atPause - 1, 1e-9));
    });

    test('決出勝負後 start 無效，要先 reset', () {
      final (c, _) = make(mode: GameClockMode.bank);
      c.start();
      c.tick(31);
      expect(c.finished, isTrue);
      expect(c.start(), isFalse);
      expect(c.reset(), isTrue);
      expect(c.phase, GameClockPhase.idle);
      expect(c.canUndo, isFalse);
      expect(c.playerAt(0).remaining, 30); // 預覽回滿格
      expect(c.start(), isTrue);
    });

    test('undo 還原換手前的狀態；沒歷史時回 false', () {
      final (c, _) = make();
      expect(c.undo(), isFalse); // 未開局
      c.start();
      expect(c.undo(), isFalse); // 沒歷史
      c.tick(2.5);
      c.pass();
      expect(c.activeIndex, 1);
      expect(c.undo(), isTrue);
      expect(c.activeIndex, 0);
      expect(c.activePlayer.remaining, closeTo(7.5, 1e-9));
    });
  });

  group('玩家設定', () {
    test('待機點玩家卡指定先手；開局後鎖定', () {
      final (c, _) = make(players: 3);
      c.pickFirstPlayer(1);
      expect(c.activeIndex, 1);
      c.start();
      c.pickFirstPlayer(2);
      expect(c.activeIndex, 1); // 開局後不理
    });

    test('拖曳排序搬整個座位：名字跟人走、先手指到的還是同一位、隱藏座位不動', () {
      final (c, _) = make(players: 3);
      c.renamePlayer(0, '甲');
      c.renamePlayer(1, '乙');
      c.renamePlayer(2, '丙');
      c.renamePlayer(3, '隱藏'); // 第 4 席未上場
      c.pickFirstPlayer(2); // 先手＝丙

      c.movePlayer(0, 2); // 甲移到最後 → 乙丙甲
      expect([c.nameOf(0), c.nameOf(1), c.nameOf(2)], ['乙', '丙', '甲']);
      expect(c.nameOf(c.activeIndex), '丙'); // 先手還是丙本人
      expect(c.playerAt(3).name, '隱藏'); // 沒被排序波及
    });

    test('人數縮減後座位名保留，加回來名字還在', () {
      final (c, _) = make(players: 4);
      c.renamePlayer(3, '老四');
      c.setPlayerCount(2);
      expect(c.playerCount, 2);
      c.setPlayerCount(4);
      expect(c.nameOf(3), '老四');
    });

    test('開局後不准動結構設定', () {
      final (c, _) = make();
      c.start();
      c.setPlayerCount(5);
      c.setTurnSeconds(99);
      c.setMode(GameClockMode.bank);
      c.movePlayer(0, 1);
      expect(c.playerCount, 2);
      expect(c.turnSeconds, 10);
      expect(c.mode, GameClockMode.turn);
    });
  });

  group('持久化', () {
    test('persist → loadPrefs 完整還原（key 沿用舊版）', () async {
      SharedPreferences.setMockInitialValues({});
      final (c, _) = make(
        mode: GameClockMode.bank,
        players: 5,
        bankSeconds: 90,
        increment: 7,
        warnSeconds: 8,
      );
      c.renamePlayer(0, '阿明');
      c.setWarnEnabled(false);
      await c.persist();

      final c2 = GameClockController();
      await c2.loadPrefs();
      expect(c2.loaded, isTrue);
      expect(c2.mode, GameClockMode.bank);
      expect(c2.playerCount, 5);
      expect(c2.bankSeconds, 90);
      expect(c2.increment, 7);
      expect(c2.warnEnabled, isFalse);
      expect(c2.warnSeconds, 8);
      expect(c2.nameOf(0), '阿明');

      // key 格式與舊版一致（升級不丟設定的契約）。
      final p = await SharedPreferences.getInstance();
      expect(p.getString(PrefsKeys.gameTimerMode), 'bank');
      expect(p.getInt(PrefsKeys.gameTimerPlayerCount), 5);
      expect(p.getStringList(PrefsKeys.gameTimerNames)?.length, 8);
    });
  });
}
