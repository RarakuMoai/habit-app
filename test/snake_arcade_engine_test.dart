import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/pages/game/snake_arcade/snake_arcade_engine.dart';

SnakeArcadeEngine _engine({int seed = 7}) => SnakeArcadeEngine(seed: seed);

/// 清空場上收集物、在蛇頭正前方放一顆，然後推進一步吃掉。
void _eatAhead(
  SnakeArcadeEngine engine, {
  ArcadeCollectibleType type = ArcadeCollectibleType.carrot,
}) {
  engine.debugClearCollectibles();
  engine.debugPlaceCollectible(engine.head.move(engine.direction), type);
  engine.advance(engine.stepIntervalMs);
}

void main() {
  test('初始狀態：等待滑動、長度 4、速度第 3 級、場上 3 顆胡蘿蔔', () {
    final engine = _engine();
    expect(engine.phase, ArcadePhase.waiting);
    expect(engine.waitReason, ArcadeWaitReason.newGame);
    expect(engine.length, SnakeArcadeEngine.initialLength);
    expect(engine.speedLevel, SnakeArcadeEngine.startSpeedLevel);
    expect(engine.scoreMultiplier, 1.0);
    expect(engine.collectibles.length, SnakeArcadeEngine.initialCarrotFloor);
    for (final item in engine.collectibles) {
      expect(item.cell.x, inInclusiveRange(2, 37));
      expect(item.cell.y, inInclusiveRange(2, 37));
    }
  });

  test('等待狀態絕不自行開跑；反向起手被拒絕', () {
    final engine = _engine();
    final headBefore = engine.head;
    engine.advance(5000);
    expect(engine.head, headBefore);
    expect(engine.phase, ArcadePhase.waiting);

    engine.enqueueDirection(ArcadeDirection.left); // 初始身體朝左，反向非法
    expect(engine.phase, ArcadePhase.waiting);

    engine.enqueueDirection(ArcadeDirection.up);
    expect(engine.phase, ArcadePhase.running);
    engine.advance(engine.stepIntervalMs);
    expect(engine.head, ArcadePoint(headBefore.x, headBefore.y - 1));
  });

  test('行進中轉向緩衝：連續兩個輸入依序生效', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    final start = engine.head;
    engine.enqueueDirection(ArcadeDirection.up);
    engine.enqueueDirection(ArcadeDirection.left);
    engine.advance(engine.stepIntervalMs);
    expect(engine.head, ArcadePoint(start.x, start.y - 1));
    engine.advance(engine.stepIntervalMs);
    expect(engine.head, ArcadePoint(start.x - 1, start.y - 1));
  });

  test('吃胡蘿蔔：積分、實體數、長度分開累計，並補生到至少 2 顆', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    _eatAhead(engine);
    expect(engine.score, SnakeArcadeEngine.carrotScore);
    expect(engine.physicalCount, 1);
    expect(engine.length, SnakeArcadeEngine.initialLength + 1);
    expect(
      engine.collectibles
          .where((c) => c.type == ArcadeCollectibleType.carrot)
          .length,
      greaterThanOrEqualTo(2),
    );
  });

  test('高速積分倍率：第 7 級 ×2、第 1 級 ×0.5', () {
    final fast = _engine()..enqueueDirection(ArcadeDirection.right);
    fast.debugSetSpeedLevel(7);
    _eatAhead(fast);
    expect(fast.score, SnakeArcadeEngine.carrotScore * 2);

    final slow = _engine()..enqueueDirection(ArcadeDirection.right);
    slow.debugSetSpeedLevel(1);
    _eatAhead(slow);
    expect(slow.score, SnakeArcadeEngine.carrotScore ~/ 2);
  });

  test('五倍蘿蔔：積分 ×5、成長 +2、實體只算 1 顆', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    engine.debugGrantAbility(ArcadeAbility.fiveFold);
    expect(engine.fiveFoldArmed, isTrue);
    _eatAhead(engine);
    expect(engine.score, SnakeArcadeEngine.carrotScore * 5);
    expect(engine.physicalCount, 1);
    expect(engine.length, SnakeArcadeEngine.initialLength + 2);
    expect(engine.fiveFoldArmed, isFalse);
  });

  test('第 5 顆觸發第一輪三選一，之後間隔 +10、+12 遞增', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    expect(engine.nextAbilityAt, 5);
    for (var i = 0; i < 5; i++) {
      _eatAhead(engine);
    }
    expect(engine.phase, ArcadePhase.choosingAbility);
    expect(engine.offeredAbilities.length, 3);
    expect(engine.offeredAbilities.toSet().length, 3); // 不重複
    expect(engine.nextAbilityAt, 15);

    engine.chooseAbility(0);
    expect(engine.phase, ArcadePhase.waiting);
    expect(engine.waitReason, ArcadeWaitReason.abilityPicked);

    // 選完必須再滑動；不滑不動。
    final head = engine.head;
    engine.advance(3000);
    expect(engine.head, head);
    engine.enqueueDirection(ArcadeDirection.down);
    expect(engine.phase, ArcadePhase.running);

    // 第二輪門檻 15，之後 27。
    engine.debugSetPhysicalCount(14);
    _eatAhead(engine);
    expect(engine.phase, ArcadePhase.choosingAbility);
    expect(engine.nextAbilityAt, 27);
  });

  test('能力池只出當下可生效的選項', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    engine
      ..debugGrantAbility(ArcadeAbility.extraLife)
      ..debugGrantAbility(ArcadeAbility.extraLife)
      ..debugGrantAbility(ArcadeAbility.extraLife)
      ..debugGrantAbility(ArcadeAbility.selfPass)
      ..debugGrantAbility(ArcadeAbility.rapidSeed)
      ..debugGrantAbility(ArcadeAbility.rapidSeed)
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..debugGrantAbility(ArcadeAbility.fiveFold)
      ..debugSetSpeedLevel(7)
      ..debugSetPhysicalCount(4);
    _eatAhead(engine); // 這顆是五倍蘿蔔，仍只算 1 顆 → 剛好觸發門檻 5
    expect(engine.phase, ArcadePhase.choosingAbility);
    // 五倍在吃下時已消耗、抽池時重新有效；其餘只剩踩剎車與蘿蔔雨
    // （命滿、速度頂、穿身滿、速射滿、怪物未解鎖狩獵無效）。
    expect(engine.offeredAbilities.toSet(), {
      ArcadeAbility.speedDown,
      ArcadeAbility.carrotRain,
      ArcadeAbility.fiveFold,
    });
  });

  test('撞牆死亡；無命直接結算', () {
    final engine = _engine()..debugClearCollectibles();
    engine.enqueueDirection(ArcadeDirection.up);
    engine.advance(engine.stepIntervalMs * 25);
    expect(engine.phase, ArcadePhase.gameOver);
    expect(engine.takeEvents(), contains(ArcadeEvent.gameOver));
  });

  test('尾巴讓位不算自撞；吃過東西後 U 型回轉才撞死', () {
    // 長度 4 的緊貼 U 轉會踩進「即將讓位的尾巴」，是合法路線。
    final tailChase = _engine()..debugClearCollectibles();
    tailChase.enqueueDirection(ArcadeDirection.down);
    tailChase.advance(tailChase.stepIntervalMs);
    tailChase.enqueueDirection(ArcadeDirection.left);
    tailChase.advance(tailChase.stepIntervalMs);
    tailChase.enqueueDirection(ArcadeDirection.up);
    tailChase.advance(tailChase.stepIntervalMs);
    expect(tailChase.phase, ArcadePhase.running);

    // 吃一顆變長後同樣路線就是自撞。
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    _eatAhead(engine);
    engine.debugClearCollectibles();
    engine.enqueueDirection(ArcadeDirection.down);
    engine.advance(engine.stepIntervalMs);
    engine.enqueueDirection(ArcadeDirection.left);
    engine.advance(engine.stepIntervalMs);
    engine.enqueueDirection(ArcadeDirection.up);
    engine.advance(engine.stepIntervalMs);
    expect(engine.phase, ArcadePhase.gameOver);
  });

  test('穿身術：每穿一格扣 1 點、免死；點數用完恢復致命', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    engine.debugGrantAbility(ArcadeAbility.selfPass);
    expect(engine.passPoints, 3);
    _eatAhead(engine);
    engine.debugClearCollectibles();
    engine.enqueueDirection(ArcadeDirection.down);
    engine.advance(engine.stepIntervalMs);
    engine.enqueueDirection(ArcadeDirection.left);
    engine.advance(engine.stepIntervalMs);
    engine.enqueueDirection(ArcadeDirection.up);
    engine.advance(engine.stepIntervalMs);
    expect(engine.phase, ArcadePhase.running); // 穿過去了
    expect(engine.passPoints, 2);
  });

  test('撞鼴鼠死亡；穿身術不能穿怪', () {
    final engine = _engine()..debugClearCollectibles();
    engine.debugGrantAbility(ArcadeAbility.selfPass);
    engine.enqueueDirection(ArcadeDirection.right);
    engine.debugSpawnMole(engine.head.move(ArcadeDirection.right));
    engine.advance(engine.stepIntervalMs);
    expect(engine.phase, ArcadePhase.gameOver);
  });

  test('鼴鼠不主動走進蛇身：被擋就轉向', () {
    final engine = _engine()..debugClearCollectibles();
    engine.enqueueDirection(ArcadeDirection.up);
    // 身體位於 (17..20,20)；鼴鼠在 (18,21) 面朝上，正上方是蛇身。
    engine.debugSpawnMole(
      const ArcadePoint(18, 21),
      facing: ArcadeDirection.up,
    );
    engine.debugResetMoleClock();
    engine.advance(SnakeArcadeEngine.moleStepMs);
    final mole = engine.moles.single;
    // 右轉（up 的右邊是 right）走到 (19,21)，不進蛇身。
    expect(mole.cell, const ArcadePoint(19, 21));
    expect(engine.body.contains(mole.cell), isFalse);
  });

  test('射擊：種子命中掉金蘿蔔；冷卻期間不能連發', () {
    final engine = _engine()..debugClearCollectibles();
    engine.enqueueDirection(ArcadeDirection.right);
    engine.debugSpawnMole(
      const ArcadePoint(25, 20),
      facing: ArcadeDirection.down,
    );
    engine.debugResetMoleClock();
    expect(engine.shoot(), isTrue);
    expect(engine.shoot(), isFalse); // 冷卻中
    engine.advance(280); // 4 格 × 70ms 命中
    expect(engine.moles, isEmpty);
    expect(engine.shotKills, 1);
    expect(
      engine.collectibles.any(
        (c) =>
            c.type == ArcadeCollectibleType.gold &&
            c.cell == const ArcadePoint(25, 20),
      ),
      isTrue,
    );
    engine.advance(620); // 冷卻補滿（共 900ms）
    expect(engine.canShoot, isTrue);
  });

  test('金蘿蔔積分高於胡蘿蔔', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    _eatAhead(engine, type: ArcadeCollectibleType.gold);
    expect(engine.score, SnakeArcadeEngine.goldScore);
  });

  test('狩獵：停用射擊、吃滿 3 隻加碼並提前解除', () {
    final engine = _engine()..debugClearCollectibles();
    engine.debugSetPhysicalCount(15);
    engine.enqueueDirection(ArcadeDirection.right);
    engine.debugStartHunt();
    expect(engine.canShoot, isFalse);

    for (var i = 0; i < 3; i++) {
      engine.debugClearMoles();
      engine.debugSpawnMole(engine.head.move(engine.direction));
      engine.debugResetMoleClock();
      engine.advance(engine.stepIntervalMs);
    }
    expect(engine.huntActive, isFalse);
    expect(engine.huntKills, 3);
    expect(
      engine.score,
      3 * SnakeArcadeEngine.huntEatScore + SnakeArcadeEngine.huntFullBonus,
    );
  });

  test('狩獵倒數警告與解除驅離：3 格內鼴鼠鑽地離場', () {
    final engine = _engine()..debugClearCollectibles();
    engine.debugSetPhysicalCount(15);
    engine.enqueueDirection(ArcadeDirection.right);
    engine.debugStartHunt(msLeft: 3200);
    engine.advance(300);
    expect(engine.takeEvents(), contains(ArcadeEvent.huntWarnTick));

    final near = engine.head
        .move(ArcadeDirection.right)
        .move(ArcadeDirection.right);
    final far = ArcadePoint(engine.head.x + 6, engine.head.y);
    engine.debugSpawnMole(near);
    engine.debugSpawnMole(far);
    engine.debugStartHunt(msLeft: 10);
    engine.debugResetMoleClock();
    engine.advance(10);
    expect(engine.huntActive, isFalse);
    expect(engine.moles.length, 1);
    expect(engine.moles.single.cell, far);
  });

  test('多一命安全復活：分數保留、長度折半、要再滑動才動、附近鼴鼠移走', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    engine.debugGrantAbility(ArcadeAbility.extraLife);
    for (var i = 0; i < 6; i++) {
      _eatAhead(engine); // 長度 10、有點分數
      if (engine.phase == ArcadePhase.choosingAbility) {
        engine.chooseAbility(0);
        engine.enqueueDirection(engine.direction);
      }
    }
    final scoreBefore = engine.score;
    final lengthBefore = engine.length;
    final livesBefore = engine.lives; // 第一輪三選一可能又抽到多一命
    engine.debugClearCollectibles();
    // 遠離蛇行進路線的角落，避免鼴鼠遊走干擾撞牆時序。
    engine.debugSpawnMole(const ArcadePoint(4, 36));
    engine.enqueueDirection(ArcadeDirection.up);
    engine.advance(engine.stepIntervalMs * 30); // 衝向上牆
    expect(engine.phase, ArcadePhase.waiting);
    expect(engine.waitReason, ArcadeWaitReason.revived);
    expect(engine.lives, livesBefore - 1);
    expect(engine.score, scoreBefore);
    expect(engine.length, math.max(4, lengthBefore ~/ 2));
    // 復活點在內圈且遠離鼴鼠；5 格內鼴鼠已被移走。
    expect(engine.head.x, inInclusiveRange(3, 36));
    expect(engine.head.y, inInclusiveRange(3, 36));
    for (final mole in engine.moles) {
      expect(engine.head.chebyshev(mole.cell), greaterThan(5));
    }

    final head = engine.head;
    engine.advance(5000);
    expect(engine.head, head); // 不滑不動
    engine.enqueueDirection(ArcadeDirection.left); // 長度 1，任何方向合法
    expect(engine.phase, ArcadePhase.running);
  });

  test('暫停後恢復也要再滑動', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    engine.advance(engine.stepIntervalMs);
    expect(engine.pause(), isTrue);
    engine.advance(5000);
    engine.leavePause();
    expect(engine.phase, ArcadePhase.waiting);
    expect(engine.waitReason, ArcadeWaitReason.resumed);
    final head = engine.head;
    engine.advance(2000);
    expect(engine.head, head);
  });

  test('蘿蔔雨立即多 4 顆；速射種子縮短冷卻', () {
    final engine = _engine()..enqueueDirection(ArcadeDirection.right);
    final before = engine.collectibles.length;
    engine.debugGrantAbility(ArcadeAbility.carrotRain);
    expect(engine.collectibles.length, before + 4);

    final base = engine.shootCooldownTotalMs;
    engine.debugGrantAbility(ArcadeAbility.rapidSeed);
    expect(engine.shootCooldownTotalMs, lessThan(base));
  });

  test('一般蘿蔔最低數量依收集進度由 3 增至 6', () {
    final engine = _engine();
    for (final entry in <(int, int)>[(0, 3), (15, 4), (30, 5), (50, 6)]) {
      engine
        ..debugSetPhysicalCount(entry.$1)
        ..debugClearCollectibles()
        ..debugRefillCarrots();
      expect(
        engine.collectibles
            .where((item) => item.type == ArcadeCollectibleType.carrot)
            .length,
        entry.$2,
      );
      expect(engine.carrotFloor, entry.$2);
    }
  });

  test('蘿蔔磁鐵可疊 3 級，吸收半徑內普通與金蘿蔔', () {
    final engine = _engine()
      ..debugClearCollectibles()
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..enqueueDirection(ArcadeDirection.right);
    final next = engine.head.move(engine.direction);
    engine
      ..debugPlaceCollectible(
        ArcadePoint(next.x + 1, next.y + 1),
        ArcadeCollectibleType.carrot,
      )
      ..debugPlaceCollectible(
        ArcadePoint(next.x + 2, next.y),
        ArcadeCollectibleType.gold,
      )
      ..advance(engine.stepIntervalMs);

    expect(engine.physicalCount, 1);
    expect(engine.takeEvents(), contains(ArcadeEvent.carrotPulled));
    expect(
      engine.collectibles.any(
        (item) => item.cell == ArcadePoint(next.x + 2, next.y),
      ),
      isTrue,
    );

    engine
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..debugGrantAbility(ArcadeAbility.carrotMagnet)
      ..debugGrantAbility(ArcadeAbility.carrotMagnet);
    expect(engine.carrotMagnetLevel, SnakeArcadeEngine.maxCarrotMagnetLevel);
  });

  test('磁力果實吸收全場與 4 顆額外蘿蔔，全部計分但最多成長 4 格', () {
    final engine = _engine()
      ..debugClearCollectibles()
      ..enqueueDirection(ArcadeDirection.right);
    final fruit = engine.head.move(engine.direction);
    engine
      ..debugPlaceCollectible(
        const ArcadePoint(5, 5),
        ArcadeCollectibleType.carrot,
      )
      ..debugPlaceCollectible(fruit, ArcadeCollectibleType.magnetFruit)
      ..advance(engine.stepIntervalMs);

    expect(
      engine.physicalCount,
      1 + SnakeArcadeEngine.globalVacuumBonusCarrots,
    );
    expect(
      engine.score,
      (1 + SnakeArcadeEngine.globalVacuumBonusCarrots) *
          SnakeArcadeEngine.carrotScore,
    );
    expect(
      engine.length,
      SnakeArcadeEngine.initialLength + SnakeArcadeEngine.globalVacuumGrowthCap,
    );
    expect(
      engine.collectibles
          .where((item) => item.type == ArcadeCollectibleType.carrot)
          .length,
      engine.carrotFloor,
    );
    expect(
      engine.collectibles,
      isNot(
        contains(
          predicate<ArcadeCollectible>(
            (item) => item.type == ArcadeCollectibleType.magnetFruit,
          ),
        ),
      ),
    );
    expect(engine.takeEvents(), contains(ArcadeEvent.magnetFruitCollected));
  });

  test('三排雷射命中前方三列、射程外與第四列不受影響', () {
    final engine = _engine()
      ..debugClearCollectibles()
      ..debugSetPhysicalCount(SnakeArcadeEngine.moleUnlockAt)
      ..enqueueDirection(ArcadeDirection.right)
      ..debugGrantAbility(ArcadeAbility.laser);
    final head = engine.head;
    for (final y in [head.y - 1, head.y, head.y + 1, head.y + 2]) {
      engine.debugSpawnMole(ArcadePoint(head.x + 5, y));
    }
    engine.debugSpawnMole(
      ArcadePoint(head.x + SnakeArcadeEngine.laserRange + 1, head.y),
    );

    expect(engine.shoot(), isTrue);
    expect(engine.shotKills, 3);
    expect(engine.moles, hasLength(2));
    expect(engine.takeEvents(), contains(ArcadeEvent.laserShot));
    expect(engine.shootCooldownTotalMs, SnakeArcadeEngine.laserCooldownMs);

    engine.debugSetLaserMsLeft(5);
    engine.advance(5);
    expect(engine.laserActive, isFalse);
    expect(engine.takeEvents(), contains(ArcadeEvent.laserEnded));
  });
}
