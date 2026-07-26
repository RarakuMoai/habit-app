import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/game/snake_arcade/snake_arcade_engine.dart';
import 'package:habit_app/pages/game/snake_arcade/snake_arcade_page.dart';
import 'package:habit_app/pages/game/snake_arcade/snake_arcade_painters.dart';
import 'package:habit_app/utils/prefs_keys.dart';
import 'package:habit_app/utils/sfx_service.dart';
import 'package:habit_app/widgets/dice_duel_panel.dart';
import 'package:habit_app/widgets/mascot_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_test_app.dart';

late SnakeArcadeEngine engine;

Widget _harness({VoidCallback? onClose}) {
  return l10nTestApp(
    home: SnakeArcadePage(
      onClose: onClose ?? () {},
      engineBuilder: () {
        engine = SnakeArcadeEngine(seed: 11);
        return engine;
      },
      recordsClock: () => DateTime(2026, 7, 22, 12),
    ),
  );
}

Future<void> _swipe(WidgetTester tester, Offset delta) async {
  final center = tester.getCenter(
    find.byKey(const ValueKey('snake-arcade-board')),
  );
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// 以 ≤100ms 的節拍推進（頁面 ticker 對單幀 dt 有 200ms 上限保險）。
Future<void> _run(WidgetTester tester, int ms) async {
  var left = ms;
  while (left > 0) {
    final chunk = math.min(100, left);
    await tester.pump(Duration(milliseconds: chunk));
    left -= chunk;
  }
}

/// 用接近實機的幀距推進，專門驗證每幀鏡頭位移。
Future<void> _runFrames(WidgetTester tester, int ms) async {
  var left = ms;
  while (left > 0) {
    final chunk = math.min(16, left);
    await tester.pump(Duration(milliseconds: chunk));
    left -= chunk;
  }
}

Future<void> _pumpCurtainCycle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

double _cameraX(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('snake-arcade-minimap')),
  );
  return (paint.painter! as SnakeArcadeMinimapPainter).cameraX;
}

double _cameraY(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('snake-arcade-minimap')),
  );
  return (paint.painter! as SnakeArcadeMinimapPainter).cameraY;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('菜園小蛇專屬音效都已收入 asset bundle', () async {
    const cues = [
      SfxCue.snakeStart,
      SfxCue.snakeCollect,
      SfxCue.snakeBonus,
      SfxCue.snakePower,
      SfxCue.snakeSeed,
      SfxCue.snakeHit,
      SfxCue.snakeHunt,
      SfxCue.snakeWarning,
      SfxCue.snakeGameOver,
      SfxCue.snakeRevive,
      SfxCue.snakeMagnetSpawn,
      SfxCue.snakeMagnetVacuum,
      SfxCue.snakeLaserCharge,
      SfxCue.snakeLaserShot,
      SfxCue.snakeMoleRise,
    ];
    expect(cues.map((cue) => cue.assetPath).toSet(), hasLength(cues.length));
    for (final cue in cues) {
      final data = await rootBundle.load(cue.assetPath);
      expect(data.lengthInBytes, greaterThan(1000), reason: cue.assetPath);
    }
  });

  test('同幀複合事件只選最高語意音效', () {
    expect(
      snakeArcadeFeedbackForEvents(const [
        ArcadeEvent.died,
        ArcadeEvent.revived,
      ])?.cue,
      SfxCue.snakeRevive,
    );
    expect(
      snakeArcadeFeedbackForEvents(const [
        ArcadeEvent.moleKilled,
        ArcadeEvent.huntFull,
        ArcadeEvent.huntEnded,
      ])?.cue,
      SfxCue.snakeBonus,
    );
    expect(
      snakeArcadeFeedbackForEvents(const [
        ArcadeEvent.ateCarrot,
        ArcadeEvent.abilityOffered,
      ])?.cue,
      SfxCue.snakePower,
    );
    expect(
      snakeArcadeFeedbackForEvents(const [
        ArcadeEvent.magnetFruitCollected,
      ])?.cue,
      SfxCue.snakeMagnetVacuum,
    );
    expect(
      snakeArcadeFeedbackForEvents(const [ArcadeEvent.laserShot])?.cue,
      SfxCue.snakeLaserShot,
    );
  });

  test('相位鎖定鏡頭正常等速，只有落差超標才限速校正', () {
    const interval = 310;
    final speed = 1000 / interval;
    final normal = snakeArcadeCameraVelocity(
      cameraX: 13,
      cameraY: 11.5,
      headX: 20.5,
      headY: 20.5,
      viewportColumns: 15,
      viewportRows: 18,
      direction: ArcadeDirection.right,
      stepIntervalMs: interval,
    );
    expect(normal.x, closeTo(speed, 0.0001));
    expect(normal.y, 0);

    final lagged = snakeArcadeCameraVelocity(
      cameraX: 11,
      cameraY: 11.5,
      headX: 20.5,
      headY: 20.5,
      viewportColumns: 15,
      viewportRows: 18,
      direction: ArcadeDirection.right,
      stepIntervalMs: interval,
    );
    expect(lagged.x, greaterThan(speed));
    expect(lagged.x, lessThanOrEqualTo(speed * 1.55));
    expect(lagged.y, 0);
  });

  testWidgets('鏡頭在蛇跳格前持續移動，蛇跳格當幀不會跟著跳一格', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    engine.debugClearCollectibles();
    final headBefore = engine.head;
    final cameraBefore = _cameraX(tester);

    await _swipe(tester, const Offset(40, 0));
    await _runFrames(tester, 100);
    expect(engine.head, headBefore);
    expect(_cameraX(tester), greaterThan(cameraBefore + 0.2));

    await _runFrames(tester, engine.stepIntervalMs - 110);
    expect(engine.head, headBefore);
    final cameraBeforeStep = _cameraX(tester);
    await _runFrames(tester, 15);
    expect(engine.head.x, headBefore.x + 1);
    expect((_cameraX(tester) - cameraBeforeStep).abs(), lessThan(0.2));
  });

  testWidgets('合法轉向一確認，鏡頭會在蛇下一次跳格前先平滑轉向', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    engine.debugClearCollectibles();

    await _swipe(tester, const Offset(40, 0));
    await _runFrames(tester, 40);
    final headBeforeTurn = engine.head;
    await _swipe(tester, const Offset(0, -40));
    final cameraBeforeTurn = _cameraY(tester);
    await _runFrames(tester, 50);

    expect(engine.head, headBeforeTurn);
    expect(_cameraY(tester), lessThan(cameraBeforeTurn - 0.1));
  });

  testWidgets('進場等待滑動；滑動後才開始移動', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('全螢幕滑動開始'), findsOneWidget);
    final headBefore = engine.head;
    await _run(tester, 600);
    expect(engine.head, headBefore); // 不滑不動

    await _swipe(tester, const Offset(0, -40));
    await _run(tester, 400);
    expect(engine.head.y, lessThan(headBefore.y));
    expect(find.text('全螢幕滑動開始'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手機直式棋盤在上、資訊列在下；橫式改為棋盤左導航右且不裁切', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(768, 1024),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_harness());
      await tester.pump();
      final board = tester.getRect(
        find.byKey(const ValueKey('snake-arcade-board')),
      );
      final dock = tester.getRect(
        find.byKey(const ValueKey('arcade-control-dock')),
      );
      expect(board.top, lessThan(dock.top), reason: '$size 應為上下版型');
      expect(
        board.height,
        greaterThan(board.width),
        reason: '$size 應使用直向長方形視野',
      );
      expect(
        find.byKey(const ValueKey('snake-arcade-minimap')),
        findsOneWidget,
        reason: '$size 手機／平板都要常駐小地圖',
      );
      expect(dock.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull, reason: '$size 不應 overflow');
    }

    for (final size in const [Size(667, 320), Size(1024, 768)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_harness());
      await tester.pump();
      final board = tester.getRect(
        find.byKey(const ValueKey('snake-arcade-board')),
      );
      final dock = tester.getRect(
        find.byKey(const ValueKey('arcade-control-dock')),
      );
      expect(board.left, lessThan(dock.left), reason: '$size 應為左右版型');
      expect(
        find.byKey(const ValueKey('snake-arcade-minimap')),
        findsOneWidget,
        reason: '$size 橫向也要常駐小地圖',
      );
      expect(dock.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull, reason: '$size 不應 overflow');
    }

    expect(find.byKey(const ValueKey('arcade-mascot')), findsNothing);
    expect(find.byKey(const ValueKey('arcade-seed-button')), findsNothing);
  });

  testWidgets('暫停面板；繼續後仍要滑動才動', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _swipe(tester, const Offset(0, -40));
    await _run(tester, 400);

    await tester.tap(find.byKey(const ValueKey('arcade-pause-button')));
    await tester.pump();
    expect(find.text('已暫停'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arcade-resume-button')));
    await tester.pump();
    expect(find.text('滑動繼續'), findsOneWidget);
    final head = engine.head;
    await _run(tester, 800);
    expect(engine.head, head);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全螢幕點擊發射；暫停控制鍵不會誤射', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    engine
      ..debugSetPhysicalCount(SnakeArcadeEngine.moleUnlockAt)
      ..debugClearCollectibles();
    await _swipe(tester, const Offset(0, -40));

    await tester.tap(find.byKey(const ValueKey('snake-arcade-board')));
    await tester.pump();
    expect(engine.bullets, hasLength(1));
    expect(engine.shootCooldownLeftMs, greaterThan(0));

    await _run(tester, 950);
    expect(engine.canShoot, isTrue);
    await tester.tap(find.byKey(const ValueKey('arcade-pause-button')));
    await tester.pump();
    expect(engine.phase, ArcadePhase.paused);
    expect(engine.bullets, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('有進度離開會確認，取消後停在滑動繼續', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_harness(onClose: () => closed++));
    await tester.pump();
    await _swipe(tester, const Offset(0, -40));

    await tester.tap(find.byKey(const ValueKey('arcade-exit-button')));
    await tester.pump();
    expect(find.text('離開菜園小蛇？'), findsOneWidget);
    expect(closed, 0);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(closed, 0);
    expect(find.text('滑動繼續'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arcade-exit-button')));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '離開遊戲'));
    await tester.pump();
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有進度重新開始會先確認', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _swipe(tester, const Offset(0, -40));
    final previous = engine;
    await tester.tap(find.byKey(const ValueKey('arcade-pause-button')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('arcade-restart-button')));
    await tester.pump();
    expect(find.text('重新開始？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(engine, same(previous));

    await tester.tap(find.byKey(const ValueKey('arcade-restart-button')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, '重新開始'),
      ),
    );
    await tester.pump();
    expect(engine, isNot(same(previous)));
    expect(find.text('全螢幕滑動開始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('第 5 顆蘿蔔跳三選一；選完要再滑動', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    engine.debugSetPhysicalCount(4);
    engine.debugClearCollectibles();
    engine.debugPlaceCollectible(
      engine.head.move(ArcadeDirection.right),
      ArcadeCollectibleType.carrot,
    );

    await _swipe(tester, const Offset(40, 0));
    await _run(tester, 400);
    expect(find.text('選一個能力'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arcade-ability-option-0')));
    await tester.pump();
    expect(find.text('選一個能力'), findsNothing);
    expect(find.text('滑動繼續'), findsOneWidget);

    final head = engine.head;
    await _run(tester, 800);
    expect(engine.head, head);
    expect(tester.takeException(), isNull);
  });

  testWidgets('第 15 顆會顯示鼴鼠與全螢幕點擊引導', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    engine
      ..debugSetPhysicalCount(14)
      ..debugClearCollectibles()
      ..debugPlaceCollectible(
        engine.head.move(ArcadeDirection.right),
        ArcadeCollectibleType.carrot,
      );

    await _swipe(tester, const Offset(40, 0));
    await _run(tester, 400);
    expect(find.text('鼴鼠來了！點畫面任意位置發射'), findsOneWidget);
    expect(find.byKey(const ValueKey('arcade-notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('結算進榜：預設署名帶 app 暱稱、登錄後寫入本機排行榜', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.userNickname: '兔友'});
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(); // 等 records 載入

    engine.debugClearCollectibles();
    engine.debugPlaceCollectible(
      engine.head.move(ArcadeDirection.right),
      ArcadeCollectibleType.carrot,
    );
    await _swipe(tester, const Offset(40, 0));
    await _run(tester, 400);
    expect(engine.score, greaterThan(0));

    engine.debugClearCollectibles();
    await _swipe(tester, const Offset(0, -40));
    await _run(tester, 8000); // 衝上牆
    expect(engine.phase, ArcadePhase.gameOver);
    await tester.pump();

    expect(find.text('進榜了！要用誰的名字記下來？'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('arcade-name-field')),
    );
    expect(field.controller!.text, '兔友');

    await tester.enterText(
      find.byKey(const ValueKey('arcade-name-field')),
      '小紅',
    );
    await tester.tap(find.byKey(const ValueKey('arcade-register-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('小紅'), findsWidgets); // 榜上有名
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.snakeArcadeData), contains('小紅'));

    await tester.tap(find.byKey(const ValueKey('arcade-retry-button')));
    await tester.pump();
    expect(find.text('全螢幕滑動開始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全螢幕彩蛋：窗簾開場、離開後回呼 onClosed', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      l10nTestApp(
        home: SnakeArcadeEgg(
          onClosed: () => closed = true,
          engineBuilder: () => SnakeArcadeEngine(seed: 11),
          recordsClock: () => DateTime(2026, 7, 22, 12),
        ),
      ),
    );
    await _pumpCurtainCycle(tester);
    expect(find.byKey(const ValueKey('snake-arcade-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('arcade-exit-button')));
    await _pumpCurtainCycle(tester);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三指長按觸發、且不沿用二指計時；四指不觸發', (tester) async {
    var dice = 0;
    var three = 0;
    await tester.pumpWidget(
      l10nTestApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: TwoFingerEggDetector(
              enabled: true,
              onTrigger: () => dice++,
              onThreeFingerTrigger: () => three++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final g1 = await tester.startGesture(const Offset(300, 300));
    final g2 = await tester.startGesture(const Offset(350, 300));
    await tester.pump(const Duration(milliseconds: 900)); // 二指計時進行中
    final g3 = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 1900)); // 三指重新計時

    expect(dice, 0);
    expect(three, 1);

    await g1.up();
    await g2.up();
    await g3.up();
    await tester.pump();

    final h1 = await tester.startGesture(const Offset(300, 300));
    final h2 = await tester.startGesture(const Offset(350, 300));
    final h3 = await tester.startGesture(const Offset(400, 300));
    final h4 = await tester.startGesture(const Offset(450, 300));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(dice, 0);
    expect(three, 1);
    await h1.up();
    await h2.up();
    await h3.up();
    await h4.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell 預設入口由三指開啟全螢幕菜園小蛇', (tester) async {
    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: MascotPageShell(
            accent: Colors.green,
            scene: ColoredBox(color: Colors.white),
            child: Text('原本功能卡'),
          ),
        ),
      ),
    );

    final shell = find.byType(MascotPageShell);
    final origin = tester.getTopLeft(shell);
    final a = await tester.createGesture(pointer: 71);
    final b = await tester.createGesture(pointer: 72);
    final c = await tester.createGesture(pointer: 73);
    await a.down(origin + const Offset(80, 60));
    await b.down(origin + const Offset(160, 60));
    await c.down(origin + const Offset(240, 60));
    await tester.pump(const Duration(milliseconds: 1900));
    await a.up();
    await b.up();
    await c.up();
    await _pumpCurtainCycle(tester);

    expect(find.byType(SnakeArcadeEgg), findsOneWidget);
    expect(find.byKey(const ValueKey('snake-arcade-page')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('骰子彩蛋開啟時，上方三指長按會無縫切到菜園小蛇', (tester) async {
    await tester.pumpWidget(
      l10nTestApp(
        home: const Scaffold(
          body: MascotPageShell(
            accent: Colors.green,
            scene: ColoredBox(color: Colors.white),
            child: Text('原本功能卡'),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(MascotPageShell));
    final diceA = await tester.createGesture(pointer: 81);
    final diceB = await tester.createGesture(pointer: 82);
    await diceA.down(origin + const Offset(120, 60));
    await diceB.down(origin + const Offset(250, 60));
    await tester.pump(const Duration(milliseconds: 1900));
    await diceA.up();
    await diceB.up();
    await _pumpCurtainCycle(tester);
    expect(find.byType(DiceDuelEgg), findsOneWidget);

    final snakeA = await tester.createGesture(pointer: 83);
    final snakeB = await tester.createGesture(pointer: 84);
    final snakeC = await tester.createGesture(pointer: 85);
    await snakeA.down(origin + const Offset(80, 60));
    await snakeB.down(origin + const Offset(180, 60));
    await snakeC.down(origin + const Offset(280, 60));
    await tester.pump(const Duration(milliseconds: 1900));
    await snakeA.up();
    await snakeB.up();
    await snakeC.up();
    await _pumpCurtainCycle(tester);

    expect(find.byType(DiceDuelEgg), findsNothing);
    expect(find.byType(SnakeArcadeEgg), findsOneWidget);
    expect(find.byKey(const ValueKey('snake-arcade-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
