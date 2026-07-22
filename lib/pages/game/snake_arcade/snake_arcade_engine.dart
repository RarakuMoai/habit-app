// 三指彩蛋「菜園小蛇」的純規則引擎；這裡只放規則，不碰 Flutter。
// 決定性：所有隨機都走建構時注入的種子，advance() 以 5ms 量子推進所有計時
// （速度表、鼴鼠 480/400ms、種子 70ms 全都是 5 的倍數），同一輸入序列必得
// 同一結果，關鍵規則直接可測。
//
// 幾個容易忘的定案：
// - 積分、實體收集數、蛇身長度三者分開累計；能力門檻只看「實體」數，
//   五倍蘿蔔那顆也只算 1 顆實體。
// - 高速的價值＝積分倍率（1 + 0.25×(級−3)），基礎分都取 4 的倍數保證整數。
// - 所有等待狀態（開局／選完能力／暫停後／復活後）都要再滑一次合法方向，
//   引擎絕不自行開跑。
// - 穿身點只處理自我碰撞；牆與鼴鼠照樣致命。
// - 狩獵解除瞬間，蛇頭 3 格內的鼴鼠鑽地離場，杜絕貼臉死。
// - 一般蘿蔔最低數量隨進度由 3 增至 6；磁力果實全場吸收時分數與
//   實體數全算，但單次成長封頂 4 格，避免獎勵反成自撞懲罰。

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

/// 四方向。保留 arcade 專屬型別，規則層不依賴 Flutter。
enum ArcadeDirection {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  final int dx;
  final int dy;
  const ArcadeDirection(this.dx, this.dy);

  ArcadeDirection get opposite => switch (this) {
    ArcadeDirection.up => ArcadeDirection.down,
    ArcadeDirection.down => ArcadeDirection.up,
    ArcadeDirection.left => ArcadeDirection.right,
    ArcadeDirection.right => ArcadeDirection.left,
  };
}

@immutable
class ArcadePoint {
  final int x;
  final int y;
  const ArcadePoint(this.x, this.y);

  ArcadePoint move(ArcadeDirection direction) =>
      ArcadePoint(x + direction.dx, y + direction.dy);

  /// Chebyshev 距離：斜向也算 1，生成／驅離半徑都用這個。
  int chebyshev(ArcadePoint other) =>
      math.max((x - other.x).abs(), (y - other.y).abs());

  @override
  bool operator ==(Object other) =>
      other is ArcadePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

enum ArcadePhase { waiting, running, choosingAbility, paused, gameOver }

/// 等待狀態的原因，只影響 UI 提示文案。
enum ArcadeWaitReason { newGame, abilityPicked, revived, resumed }

enum ArcadeCollectibleType { carrot, gold, magnetFruit }

class ArcadeCollectible {
  final ArcadePoint cell;
  final ArcadeCollectibleType type;
  const ArcadeCollectible(this.cell, this.type);
}

enum ArcadeMoleState { telegraph, active }

class ArcadeMole {
  ArcadePoint cell;
  ArcadePoint previousCell;
  ArcadeDirection facing;
  ArcadeMoleState state;
  int telegraphMsLeft;

  ArcadeMole({
    required this.cell,
    required this.facing,
    this.state = ArcadeMoleState.telegraph,
    this.telegraphMsLeft = SnakeArcadeEngine.moleTelegraphMs,
    ArcadePoint? previousCell,
  }) : previousCell = previousCell ?? cell;
}

class ArcadeBullet {
  ArcadePoint cell;
  ArcadePoint previousCell;
  final ArcadeDirection direction;
  ArcadeBullet(this.cell, this.direction, {ArcadePoint? previousCell})
    : previousCell = previousCell ?? cell;
}

enum ArcadeAbility {
  extraLife('多一命', '倒下時在安全處醒來（可存 3 次）'),
  speedUp('踩油門', '快一級，得分倍率 +25%'),
  speedDown('踩剎車', '慢一級，得分倍率 −25%'),
  fiveFold('五倍蘿蔔', '下一份收穫價值 ×5'),
  selfPass('穿身術', '補滿 3 點，穿過自己每格用 1 點'),
  hunt('狩獵時刻', '20 秒內用蛇頭吃鼴鼠，目標 3 隻'),
  carrotRain('蘿蔔雨', '田裡馬上多 4 根胡蘿蔔'),
  rapidSeed('速射種子', '種子冷卻縮短（可疊 2 次）'),
  carrotMagnet('蘿蔔磁鐵', '吸取範圍增加 1 格（最多 3 格）'),
  laser('三排雷射', '10 秒內改射三排雷射，射程 12 格');

  final String label;
  final String description;
  const ArcadeAbility(this.label, this.description);
}

/// advance() 期間發生的事，UI 取走後配音效／震動／特效。
enum ArcadeEvent {
  started,
  ateCarrot,
  ateGold,
  ateFiveFold,
  carrotPulled,
  magnetFruitSpawned,
  magnetFruitCollected,
  abilityOffered,
  molesUnlocked,
  shot,
  laserStarted,
  laserShot,
  laserEnded,
  moleKilled,
  huntStarted,
  huntWarnTick,
  huntEnded,
  huntFull,
  died,
  revived,
  gameOver,
}

class SnakeArcadeEngine {
  // ── 世界與版面 ──────────────────────────────────────────
  static const int worldSize = 40;
  static const int spawnMargin = 2; // 收集物／鼴鼠不生在最邊線
  static const int reviveMargin = 3;

  // ── 速度表：固定級距 35ms，倍率 1 + 0.25×(級−3) ─────────
  static const List<int> stepIntervalsMs = [380, 345, 310, 275, 240, 205, 170];
  static const int startSpeedLevel = 3; // 1-based
  static const List<int> multiplierQuarters = [2, 3, 4, 5, 6, 7, 8];

  // ── 積分（基礎分皆 4 的倍數，乘倍率必為整數） ────────────
  static const int carrotScore = 12;
  static const int goldScore = 28;
  static const int huntEatScore = 60;
  static const int huntFullBonus = 48;

  // ── 節奏 ────────────────────────────────────────────────
  static const int initialLength = 4;
  static const int initialCarrotFloor = 3;
  static const int maxCarrotFloor = 6;
  static const int firstAbilityAt = 5;
  static const int moleUnlockAt = 15; // 第二輪能力後（累計 ≥15 顆）
  static const int moleTelegraphMs = 1200;
  static const int moleStepMs = 480;
  static const int moleHuntStepMs = 400;
  static const int moleSpawnBaseMs = 6000;
  static const int moleSpawnJitterMs = 3000; // 6–9 秒（5ms 對齊）
  static const int bulletStepMs = 70;
  static const int shootCooldownMs = 900;
  static const int maxBulletsAirborne = 2;
  static const int huntDurationMs = 20000;
  static const int huntTargetKills = 3;
  static const int huntTargetMinHeadDistance = 5;
  static const int huntTargetMaxHeadDistance = 9;
  static const int huntEndGraceRadius = 3;
  static const int maxLives = 3;
  static const int maxPassPoints = 3;
  static const int maxRapidSeedStacks = 2;
  static const int maxCarrotMagnetLevel = 3;
  static const int laserDurationMs = 10000;
  static const int laserCooldownMs = 900;
  static const int laserRange = 12;
  static const int laserFlashDurationMs = 140;
  static const int magnetFruitUnlockAt = 8;
  static const int magnetFruitSpawnBaseMs = 30000;
  static const int magnetFruitSpawnJitterMs = 15000;
  static const int magnetFruitLifetimeMs = 15000;
  static const int magnetFruitMinHeadDistance = 6;
  static const int magnetFruitMaxHeadDistance = 10;
  static const int globalVacuumBonusCarrots = 4;
  static const int globalVacuumGrowthCap = 4;
  static const int moleSpawnMinHeadDistance = 6;
  static const int reviveClearRadius = 5;
  static const int _quantumMs = 5;

  final math.Random _rng;

  // ── 蛇 ─────────────────────────────────────────────────
  final List<ArcadePoint> _body = [];
  ArcadeDirection _direction = ArcadeDirection.right;
  bool _hasMoved = false; // 復活後長度 1 時任何方向都合法
  int _pendingGrowth = 0;
  final List<ArcadeDirection> _inputQueue = [];

  // ── 場上實體 ───────────────────────────────────────────
  final List<ArcadeCollectible> _collectibles = [];
  final List<ArcadeMole> _moles = [];
  final List<ArcadeBullet> _bullets = [];

  // ── 進度 ───────────────────────────────────────────────
  ArcadePhase _phase = ArcadePhase.waiting;
  ArcadeWaitReason _waitReason = ArcadeWaitReason.newGame;
  int _score = 0;
  int _physicalCount = 0;
  int _speedLevel = startSpeedLevel;
  int _lives = 0;
  int _passPoints = 0;
  bool _fiveFoldArmed = false;
  int _rapidSeedStacks = 0;
  int _carrotMagnetLevel = 0;
  int _laserMsLeft = 0;
  int _laserFlashMsLeft = 0;
  int _abilityRounds = 0;
  int _nextAbilityAt = firstAbilityAt;
  List<ArcadeAbility> _offeredAbilities = const [];

  // ── 狩獵 ───────────────────────────────────────────────
  bool _huntArmed = false; // 選了狩獵、等恢復移動才起跑
  bool _huntActive = false;
  int _huntMsLeft = 0;
  int _huntEaten = 0;

  // ── 統計 ───────────────────────────────────────────────
  int _maxLength = initialLength;
  int _huntKills = 0;
  int _shotKills = 0;

  // ── 計時累加器 ─────────────────────────────────────────
  int _snakeAcc = 0;
  int _moleAcc = 0;
  int _bulletAcc = 0;
  int _shootCooldownLeft = 0;
  int _moleSpawnIn = 0;
  int _magnetFruitSpawnIn = 0;
  int _magnetFruitTtlMs = 0;
  int _advanceRemainder = 0;

  final List<ArcadeEvent> _events = [];

  SnakeArcadeEngine({int? seed})
    : _rng = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch) {
    const center = worldSize ~/ 2;
    for (var i = 0; i < initialLength; i++) {
      _body.add(ArcadePoint(center - i, center));
    }
    _direction = ArcadeDirection.right;
    _moleSpawnIn = _nextMoleSpawnDelay();
    _magnetFruitSpawnIn = _nextMagnetFruitSpawnDelay();
    for (var i = 0; i < initialCarrotFloor; i++) {
      _spawnCarrot();
    }
  }

  // ── 對外唯讀狀態 ───────────────────────────────────────
  ArcadePhase get phase => _phase;
  ArcadeWaitReason get waitReason => _waitReason;
  List<ArcadePoint> get body => List.unmodifiable(_body);
  ArcadePoint get head => _body.first;
  ArcadeDirection get direction => _direction;
  List<ArcadeCollectible> get collectibles => List.unmodifiable(_collectibles);
  List<ArcadeMole> get moles => List.unmodifiable(_moles);
  List<ArcadeBullet> get bullets => List.unmodifiable(_bullets);
  int get score => _score;
  int get physicalCount => _physicalCount;
  int get length => _body.length + _pendingGrowth;
  int get speedLevel => _speedLevel;
  int get stepIntervalMs => stepIntervalsMs[_speedLevel - 1];
  double get scoreMultiplier => multiplierQuarters[_speedLevel - 1] / 4;
  int get lives => _lives;
  int get passPoints => _passPoints;
  bool get fiveFoldArmed => _fiveFoldArmed;
  int get rapidSeedStacks => _rapidSeedStacks;
  int get carrotMagnetLevel => _carrotMagnetLevel;
  int get laserMsLeft => _laserMsLeft;
  bool get laserActive => _laserMsLeft > 0;
  int get laserFlashMsLeft => _laserFlashMsLeft;
  int get carrotFloor => switch (_physicalCount) {
    >= 50 => maxCarrotFloor,
    >= 30 => 5,
    >= 15 => 4,
    _ => initialCarrotFloor,
  };
  int get moleCap => switch (_physicalCount) {
    >= 60 => 6,
    >= 45 => 5,
    >= 30 => 4,
    _ => 3,
  };
  int get abilityRounds => _abilityRounds;
  int get nextAbilityAt => _nextAbilityAt;
  List<ArcadeAbility> get offeredAbilities => _offeredAbilities;
  bool get huntActive => _huntActive;
  bool get huntArmed => _huntArmed;
  int get huntMsLeft => _huntMsLeft;
  int get huntEaten => _huntEaten;
  bool get molesUnlocked => _physicalCount >= moleUnlockAt;
  int get maxLength => _maxLength;
  int get huntKills => _huntKills;
  int get shotKills => _shotKills;
  int get shootCooldownLeftMs => _shootCooldownLeft;
  int get shootCooldownTotalMs => _currentShootCooldown();
  double get moleRenderProgress => _phase == ArcadePhase.running
      ? (_moleAcc / ((_huntActive ? moleHuntStepMs : moleStepMs) * 0.78)).clamp(
          0.0,
          1.0,
        )
      : 1;
  double get bulletRenderProgress => _phase == ArcadePhase.running
      ? (_bulletAcc / (bulletStepMs * 0.82)).clamp(0.0, 1.0)
      : 1;
  bool get canShoot =>
      _phase == ArcadePhase.running &&
      !_huntActive &&
      _shootCooldownLeft == 0 &&
      (laserActive || _bullets.length < maxBulletsAirborne);

  /// UI 一次取走本回合事件。
  List<ArcadeEvent> takeEvents() {
    final out = List<ArcadeEvent>.from(_events);
    _events.clear();
    return out;
  }

  // ── 輸入 ───────────────────────────────────────────────

  /// 滑動輸入：等待狀態下的合法方向會直接開跑；行進中最多緩衝兩步轉向。
  void enqueueDirection(ArcadeDirection input) {
    switch (_phase) {
      case ArcadePhase.waiting:
        if (!_isLegalStartDirection(input)) return;
        _direction = input;
        _inputQueue.clear();
        _phase = ArcadePhase.running;
        _snakeAcc = 0;
        if (_huntArmed) _startHunt();
        _events.add(ArcadeEvent.started);
      case ArcadePhase.running:
        final last = _inputQueue.isEmpty ? _direction : _inputQueue.last;
        if (input == last || input == last.opposite) return;
        if (_inputQueue.length >= 2) return;
        _inputQueue.add(input);
      case ArcadePhase.choosingAbility:
      case ArcadePhase.paused:
      case ArcadePhase.gameOver:
        break;
    }
  }

  bool _isLegalStartDirection(ArcadeDirection input) {
    if (_body.length <= 1 && !_hasMoved) return true;
    return input != _direction.opposite;
  }

  /// 發射。狩獵中停用；冷卻與在場種子數也在這裡把關。
  bool shoot() {
    if (!canShoot) return false;
    if (laserActive) return _shootLaser();
    final target = head.move(_direction);
    if (!_inWorld(target)) return false;
    _shootCooldownLeft = _currentShootCooldown();
    final hit = _activeMoleAt(target);
    if (hit != null) {
      _killMoleByShot(hit);
    } else {
      _bullets.add(ArcadeBullet(target, _direction, previousCell: head));
    }
    _events.add(ArcadeEvent.shot);
    return true;
  }

  int _currentShootCooldown() {
    if (laserActive) return laserCooldownMs;
    var cooldown = shootCooldownMs;
    for (var i = 0; i < _rapidSeedStacks; i++) {
      cooldown = cooldown * 3 ~/ 5; // ×0.6，900 → 540 → 324→325（5ms 對齊）
    }
    return _alignQuantum(cooldown);
  }

  int _alignQuantum(int ms) => (ms + _quantumMs - 1) ~/ _quantumMs * _quantumMs;

  bool _shootLaser() {
    _shootCooldownLeft = laserCooldownMs;
    _laserFlashMsLeft = laserFlashDurationMs;
    final hits = _moles.where((mole) {
      if (mole.state != ArcadeMoleState.active) return false;
      final dx = mole.cell.x - head.x;
      final dy = mole.cell.y - head.y;
      return switch (_direction) {
        ArcadeDirection.right => dx >= 1 && dx <= laserRange && dy.abs() <= 1,
        ArcadeDirection.left => dx <= -1 && dx >= -laserRange && dy.abs() <= 1,
        ArcadeDirection.down => dy >= 1 && dy <= laserRange && dx.abs() <= 1,
        ArcadeDirection.up => dy <= -1 && dy >= -laserRange && dx.abs() <= 1,
      };
    }).toList();
    for (final mole in hits) {
      _killMoleByShot(mole);
    }
    _events.add(ArcadeEvent.laserShot);
    return true;
  }

  /// 進行中才可暫停（外部凍結：切背景、足跡開啟等也走這裡）。
  bool pause() {
    if (_phase != ArcadePhase.running) return false;
    _phase = ArcadePhase.paused;
    return true;
  }

  /// 暫停面板按「繼續」→ 回等待狀態，仍要滑動才動。
  void leavePause() {
    if (_phase != ArcadePhase.paused) return;
    _phase = ArcadePhase.waiting;
    _waitReason = ArcadeWaitReason.resumed;
  }

  void chooseAbility(int index) {
    if (_phase != ArcadePhase.choosingAbility) return;
    if (index < 0 || index >= _offeredAbilities.length) return;
    _applyAbility(_offeredAbilities[index]);
    _offeredAbilities = const [];
    _phase = ArcadePhase.waiting;
    _waitReason = ArcadeWaitReason.abilityPicked;
  }

  void _applyAbility(ArcadeAbility ability) {
    switch (ability) {
      case ArcadeAbility.extraLife:
        _lives = math.min(maxLives, _lives + 1);
      case ArcadeAbility.speedUp:
        _speedLevel = math.min(stepIntervalsMs.length, _speedLevel + 1);
      case ArcadeAbility.speedDown:
        _speedLevel = math.max(1, _speedLevel - 1);
      case ArcadeAbility.fiveFold:
        _fiveFoldArmed = true;
      case ArcadeAbility.selfPass:
        _passPoints = maxPassPoints;
      case ArcadeAbility.hunt:
        _huntArmed = true;
      case ArcadeAbility.carrotRain:
        for (var i = 0; i < 4; i++) {
          _spawnCarrot();
        }
      case ArcadeAbility.rapidSeed:
        _rapidSeedStacks = math.min(maxRapidSeedStacks, _rapidSeedStacks + 1);
      case ArcadeAbility.carrotMagnet:
        _carrotMagnetLevel = math.min(
          maxCarrotMagnetLevel,
          _carrotMagnetLevel + 1,
        );
      case ArcadeAbility.laser:
        _laserMsLeft = laserDurationMs;
        _events.add(ArcadeEvent.laserStarted);
    }
  }

  // ── 能力池 ─────────────────────────────────────────────

  static const Map<ArcadeAbility, int> _abilityWeights = {
    ArcadeAbility.extraLife: 16,
    ArcadeAbility.speedUp: 14,
    ArcadeAbility.speedDown: 10,
    ArcadeAbility.fiveFold: 14,
    ArcadeAbility.selfPass: 14,
    ArcadeAbility.hunt: 12,
    ArcadeAbility.carrotRain: 10,
    ArcadeAbility.rapidSeed: 10,
    ArcadeAbility.carrotMagnet: 12,
    ArcadeAbility.laser: 10,
  };

  bool _abilityValid(ArcadeAbility ability) => switch (ability) {
    ArcadeAbility.extraLife => _lives < maxLives,
    ArcadeAbility.speedUp => _speedLevel < stepIntervalsMs.length,
    ArcadeAbility.speedDown => _speedLevel > 1,
    ArcadeAbility.fiveFold => !_fiveFoldArmed,
    ArcadeAbility.selfPass => _passPoints < maxPassPoints,
    ArcadeAbility.hunt => molesUnlocked && !_huntArmed && !_huntActive,
    ArcadeAbility.carrotRain => true,
    ArcadeAbility.rapidSeed => _rapidSeedStacks < maxRapidSeedStacks,
    ArcadeAbility.carrotMagnet => _carrotMagnetLevel < maxCarrotMagnetLevel,
    ArcadeAbility.laser => molesUnlocked && !laserActive,
  };

  List<ArcadeAbility> _drawAbilities() {
    final pool = ArcadeAbility.values.where(_abilityValid).toList();
    final picked = <ArcadeAbility>[];
    while (picked.length < 3 && pool.isNotEmpty) {
      final total = pool.fold(0, (sum, a) => sum + _abilityWeights[a]!);
      var roll = _rng.nextInt(total);
      for (final ability in pool) {
        roll -= _abilityWeights[ability]!;
        if (roll < 0) {
          picked.add(ability);
          pool.remove(ability);
          break;
        }
      }
    }
    return picked;
  }

  // ── 時間推進 ───────────────────────────────────────────

  void advance(int elapsedMs) {
    if (_phase != ArcadePhase.running || elapsedMs <= 0) return;
    _advanceRemainder += elapsedMs;
    while (_advanceRemainder >= _quantumMs && _phase == ArcadePhase.running) {
      _advanceRemainder -= _quantumMs;
      _tickQuantum();
    }
  }

  void _tickQuantum() {
    if (_laserMsLeft > 0) {
      _laserMsLeft = math.max(0, _laserMsLeft - _quantumMs);
      if (_laserMsLeft == 0) _events.add(ArcadeEvent.laserEnded);
    }
    if (_laserFlashMsLeft > 0) {
      _laserFlashMsLeft = math.max(0, _laserFlashMsLeft - _quantumMs);
    }
    if (_shootCooldownLeft > 0) {
      _shootCooldownLeft = math.max(0, _shootCooldownLeft - _quantumMs);
    }

    _bulletAcc += _quantumMs;
    while (_bulletAcc >= bulletStepMs) {
      _bulletAcc -= bulletStepMs;
      _stepBullets();
    }

    _tickMoleTelegraphs();
    _moleAcc += _quantumMs;
    final moleInterval = _huntActive ? moleHuntStepMs : moleStepMs;
    while (_moleAcc >= moleInterval) {
      _moleAcc -= moleInterval;
      _stepMoles();
    }

    if (_huntActive) _tickHunt();

    _tickMoleSpawner();
    _tickMagnetFruit();

    _snakeAcc += _quantumMs;
    while (_snakeAcc >= stepIntervalMs && _phase == ArcadePhase.running) {
      _snakeAcc -= stepIntervalMs;
      _stepSnake();
    }
  }

  // ── 蛇移動 ─────────────────────────────────────────────

  void _stepSnake() {
    if (_inputQueue.isNotEmpty) {
      _direction = _inputQueue.removeAt(0);
    }
    final target = head.move(_direction);
    _hasMoved = true;

    if (!_inWorld(target)) {
      _die();
      return;
    }

    final mole = _activeMoleAt(target);
    if (mole != null) {
      if (_huntActive) {
        _eatMoleByHunt(mole);
      } else {
        _die();
        return;
      }
    }

    if (_hitsOwnBody(target)) {
      if (_passPoints > 0) {
        _passPoints--;
      } else {
        _die();
        return;
      }
    }

    _body.insert(0, target);
    if (_pendingGrowth > 0) {
      _pendingGrowth--;
    } else {
      _body.removeLast();
    }
    _maxLength = math.max(_maxLength, length);

    final fieldPowerIndex = _collectibles.indexWhere(
      (c) => c.cell == target && c.type == ArcadeCollectibleType.magnetFruit,
    );
    if (fieldPowerIndex >= 0) {
      _collectibles.removeAt(fieldPowerIndex);
      _triggerGlobalVacuum();
      return;
    }

    _collectProduceNear(target);
  }

  /// 自我碰撞判定：尾巴這步若會空出（無待成長）則不算撞。
  bool _hitsOwnBody(ArcadePoint target) {
    final tailVacates = _pendingGrowth == 0;
    final lastIndex = _body.length - 1;
    for (var i = 1; i < _body.length; i++) {
      if (tailVacates && i == lastIndex) continue;
      if (_body[i] == target) return true;
    }
    return false;
  }

  void _collectProduceNear(ArcadePoint center) {
    final produce =
        _collectibles
            .where(
              (item) =>
                  item.type != ArcadeCollectibleType.magnetFruit &&
                  center.chebyshev(item.cell) <= _carrotMagnetLevel,
            )
            .toList()
          ..sort(
            (a, b) =>
                center.chebyshev(a.cell).compareTo(center.chebyshev(b.cell)),
          );
    if (produce.isEmpty) return;
    final pulled = produce.any((item) => item.cell != center);
    _collectProduceBatch(produce);
    if (pulled) _events.add(ArcadeEvent.carrotPulled);
  }

  void _collectProduceBatch(List<ArcadeCollectible> items, {int? growthCap}) {
    final hadMolesUnlocked = molesUnlocked;
    var growthAdded = 0;
    for (final item in items) {
      if (!_collectibles.remove(item)) continue;
      final base = switch (item.type) {
        ArcadeCollectibleType.carrot => carrotScore,
        ArcadeCollectibleType.gold => goldScore,
        ArcadeCollectibleType.magnetFruit => 0,
      };
      final fiveFold = _fiveFoldArmed;
      _fiveFoldArmed = false;
      _score += _applyMultiplier(base) * (fiveFold ? 5 : 1);
      final desiredGrowth = fiveFold ? 2 : 1;
      final allowedGrowth = growthCap == null
          ? desiredGrowth
          : math.min(desiredGrowth, math.max(0, growthCap - growthAdded));
      _pendingGrowth += allowedGrowth;
      growthAdded += allowedGrowth;
      _physicalCount += 1; // 五倍那顆也只算 1 顆實體
      _events.add(
        fiveFold
            ? ArcadeEvent.ateFiveFold
            : item.type == ArcadeCollectibleType.gold
            ? ArcadeEvent.ateGold
            : ArcadeEvent.ateCarrot,
      );
    }
    if (!hadMolesUnlocked && molesUnlocked) {
      _events.add(ArcadeEvent.molesUnlocked);
    }
    _refillCarrots();
    if (_phase == ArcadePhase.running && _physicalCount >= _nextAbilityAt) {
      _openAbilityChoice();
    }
  }

  void _triggerGlobalVacuum() {
    _magnetFruitTtlMs = 0;
    _magnetFruitSpawnIn = _nextMagnetFruitSpawnDelay();
    for (var i = 0; i < globalVacuumBonusCarrots; i++) {
      _spawnCarrot();
    }
    final produce =
        _collectibles
            .where((item) => item.type != ArcadeCollectibleType.magnetFruit)
            .toList()
          ..sort(
            (a, b) => head.chebyshev(a.cell).compareTo(head.chebyshev(b.cell)),
          );
    _collectProduceBatch(produce, growthCap: globalVacuumGrowthCap);
    _events.add(ArcadeEvent.magnetFruitCollected);
  }

  int _applyMultiplier(int base) =>
      base * multiplierQuarters[_speedLevel - 1] ~/ 4;

  void _openAbilityChoice() {
    _abilityRounds += 1;
    // 間隔 +10、+12、…、+18 之後固定 +20。
    final increment = math.min(20, 8 + 2 * _abilityRounds);
    _nextAbilityAt += increment;
    _offeredAbilities = _drawAbilities();
    _phase = ArcadePhase.choosingAbility;
    _events.add(ArcadeEvent.abilityOffered);
  }

  // ── 收集物生成 ─────────────────────────────────────────

  void _refillCarrots() {
    var normals = _collectibles
        .where((c) => c.type == ArcadeCollectibleType.carrot)
        .length;
    while (normals < carrotFloor) {
      if (!_spawnCarrot()) break;
      normals++;
    }
  }

  bool _spawnCarrot() {
    final cell = _randomFreeCell(margin: spawnMargin, avoidHeadRadius: 1);
    if (cell == null) return false;
    _collectibles.add(ArcadeCollectible(cell, ArcadeCollectibleType.carrot));
    return true;
  }

  int _nextMagnetFruitSpawnDelay() =>
      magnetFruitSpawnBaseMs +
      _rng.nextInt(magnetFruitSpawnJitterMs ~/ _quantumMs) * _quantumMs;

  void _tickMagnetFruit() {
    final fruitIndex = _collectibles.indexWhere(
      (item) => item.type == ArcadeCollectibleType.magnetFruit,
    );
    if (fruitIndex >= 0) {
      _magnetFruitTtlMs -= _quantumMs;
      if (_magnetFruitTtlMs > 0) return;
      _collectibles.removeAt(fruitIndex);
      _magnetFruitSpawnIn = _nextMagnetFruitSpawnDelay();
      return;
    }
    if (_physicalCount < magnetFruitUnlockAt) return;
    _magnetFruitSpawnIn -= _quantumMs;
    if (_magnetFruitSpawnIn > 0) return;
    final cell = _randomFreeCellNearHead(
      minRadius: magnetFruitMinHeadDistance,
      maxRadius: magnetFruitMaxHeadDistance,
    );
    if (cell == null) {
      _magnetFruitSpawnIn = 1000;
      return;
    }
    _collectibles.add(
      ArcadeCollectible(cell, ArcadeCollectibleType.magnetFruit),
    );
    _magnetFruitTtlMs = magnetFruitLifetimeMs;
    _events.add(ArcadeEvent.magnetFruitSpawned);
  }

  ArcadePoint? _randomFreeCellNearHead({
    required int minRadius,
    required int maxRadius,
  }) {
    final candidates = <ArcadePoint>[];
    for (
      var y = math.max(spawnMargin, head.y - maxRadius);
      y <= math.min(worldSize - spawnMargin - 1, head.y + maxRadius);
      y++
    ) {
      for (
        var x = math.max(spawnMargin, head.x - maxRadius);
        x <= math.min(worldSize - spawnMargin - 1, head.x + maxRadius);
        x++
      ) {
        final cell = ArcadePoint(x, y);
        final distance = head.chebyshev(cell);
        if (distance < minRadius || distance > maxRadius) continue;
        if (_body.contains(cell) ||
            _collectibles.any((c) => c.cell == cell) ||
            _moles.any((m) => m.cell == cell) ||
            _bullets.any((b) => b.cell == cell)) {
          continue;
        }
        candidates.add(cell);
      }
    }
    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }

  /// 生成點：距邊線 [margin] 格、不壓蛇身／收集物／鼴鼠／種子、
  /// 離蛇頭至少 [avoidHeadRadius] 格。抽 40 次不中就整場掃描保底。
  ArcadePoint? _randomFreeCell({
    required int margin,
    required int avoidHeadRadius,
  }) {
    final span = worldSize - margin * 2;
    if (span <= 0) return null;
    bool ok(ArcadePoint cell) =>
        !_body.contains(cell) &&
        _collectibles.every((c) => c.cell != cell) &&
        _moles.every((m) => m.cell != cell) &&
        _bullets.every((b) => b.cell != cell) &&
        head.chebyshev(cell) > avoidHeadRadius;
    for (var attempt = 0; attempt < 40; attempt++) {
      final cell = ArcadePoint(
        margin + _rng.nextInt(span),
        margin + _rng.nextInt(span),
      );
      if (ok(cell)) return cell;
    }
    for (var y = margin; y < worldSize - margin; y++) {
      for (var x = margin; x < worldSize - margin; x++) {
        final cell = ArcadePoint(x, y);
        if (ok(cell)) return cell;
      }
    }
    return null;
  }

  // ── 鼴鼠 ───────────────────────────────────────────────

  int _nextMoleSpawnDelay() =>
      moleSpawnBaseMs +
      _rng.nextInt(moleSpawnJitterMs ~/ _quantumMs) * _quantumMs;

  void _tickMoleSpawner() {
    if (!molesUnlocked || _moles.length >= moleCap) return;
    _moleSpawnIn -= _quantumMs;
    if (_moleSpawnIn > 0) return;
    _moleSpawnIn = _nextMoleSpawnDelay();
    final cell = _randomFreeCell(
      margin: spawnMargin,
      avoidHeadRadius: moleSpawnMinHeadDistance,
    );
    if (cell == null) return;
    _moles.add(
      ArcadeMole(cell: cell, facing: ArcadeDirection.values[_rng.nextInt(4)]),
    );
  }

  void _tickMoleTelegraphs() {
    for (final mole in _moles) {
      if (mole.state != ArcadeMoleState.telegraph) continue;
      mole.telegraphMsLeft -= _quantumMs;
      if (mole.telegraphMsLeft > 0) continue;
      // 預告期間被蛇身壓住就換位重新預告，不憑空冒在蛇底下。
      if (_body.contains(mole.cell)) {
        final relocated = _randomFreeCell(
          margin: spawnMargin,
          avoidHeadRadius: moleSpawnMinHeadDistance,
        );
        if (relocated == null) {
          mole.telegraphMsLeft = moleTelegraphMs;
          continue;
        }
        mole.cell = relocated;
        mole.previousCell = relocated;
        mole.telegraphMsLeft = moleTelegraphMs;
        continue;
      }
      mole.state = ArcadeMoleState.active;
    }
  }

  void _stepMoles() {
    // _killMoleByShot 會從 _moles 移除元素，迭代副本避免並行修改。
    for (final mole in List.of(_moles)) {
      if (mole.state != ArcadeMoleState.active || !_moles.contains(mole)) {
        continue;
      }
      if (_huntActive) {
        mole.previousCell = mole.cell;
        _fleeStep(mole);
      } else {
        mole.previousCell = mole.cell;
        _wanderStep(mole);
      }
      // 鼴鼠自己走進種子所在格也算被命中（與種子前進命中互補）。
      final bulletIndex = _bullets.indexWhere((b) => b.cell == mole.cell);
      if (bulletIndex >= 0) {
        _bullets.removeAt(bulletIndex);
        _killMoleByShot(mole);
      }
    }
  }

  /// 有方向慣性，但每一步都重新加權。靠牆時向內的權重會大幅提高，
  /// 避免過去一路直走、碰牆後沿牆繞場的視覺假象。
  void _wanderStep(ArcadeMole mole) {
    final candidates = <(ArcadeDirection, int)>[];
    for (final dir in ArcadeDirection.values) {
      final target = mole.cell.move(dir);
      if (!_moleCanEnter(target)) continue;
      var weight = switch (dir) {
        _ when dir == mole.facing => 54,
        _ when dir == mole.facing.opposite => 5,
        _ => 20,
      };
      final currentEdge = _edgeDistance(mole.cell);
      final targetEdge = _edgeDistance(target);
      if (targetEdge == 0) {
        weight = math.max(1, weight ~/ 12);
      } else if (targetEdge == 1) {
        weight = math.max(1, weight ~/ 5);
      } else if (targetEdge == 2) {
        weight = math.max(1, weight ~/ 2);
      }
      if (targetEdge > currentEdge) weight *= 2;
      if (targetEdge < currentEdge) weight = math.max(1, weight ~/ 2);
      candidates.add((dir, weight));
    }
    final direction = _pickWeightedDirection(candidates);
    if (direction == null) return;
    mole.cell = mole.cell.move(direction);
    mole.facing = direction;
  }

  /// 狩獵中同時避開蛇頭與牆。離牆一格的收益略高於多逃離蛇頭一格，
  /// 因此鼴鼠不會為了最大化距離長時間黏在邊界。
  void _fleeStep(ArcadeMole mole) {
    ArcadeDirection? best;
    var bestScore = -1;
    for (final dir in ArcadeDirection.values) {
      final target = mole.cell.move(dir);
      if (!_moleCanEnter(target)) continue;
      final score =
          head.chebyshev(target) * 20 +
          math.min(4, _edgeDistance(target)) * 28 +
          (dir == mole.facing ? 2 : 0) +
          _rng.nextInt(4);
      if (score > bestScore) {
        bestScore = score;
        best = dir;
      }
    }
    if (best == null) return;
    mole.cell = mole.cell.move(best);
    mole.facing = best;
  }

  int _edgeDistance(ArcadePoint cell) => math.min(
    math.min(cell.x, worldSize - 1 - cell.x),
    math.min(cell.y, worldSize - 1 - cell.y),
  );

  ArcadeDirection? _pickWeightedDirection(
    List<(ArcadeDirection, int)> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final total = candidates.fold<int>(0, (sum, item) => sum + item.$2);
    var roll = _rng.nextInt(total);
    for (final candidate in candidates) {
      if (roll < candidate.$2) return candidate.$1;
      roll -= candidate.$2;
    }
    return candidates.last.$1;
  }

  bool _moleCanEnter(ArcadePoint cell) =>
      _inWorld(cell) &&
      !_body.contains(cell) &&
      _moles.every((m) => m.cell != cell) &&
      _collectibles.every((c) => c.cell != cell);

  ArcadeMole? _activeMoleAt(ArcadePoint cell) {
    for (final mole in _moles) {
      if (mole.state == ArcadeMoleState.active && mole.cell == cell) {
        return mole;
      }
    }
    return null;
  }

  void _killMoleByShot(ArcadeMole mole) {
    _moles.remove(mole);
    _shotKills += 1;
    _collectibles.add(ArcadeCollectible(mole.cell, ArcadeCollectibleType.gold));
    _events.add(ArcadeEvent.moleKilled);
  }

  // ── 種子 ───────────────────────────────────────────────

  void _stepBullets() {
    for (var i = _bullets.length - 1; i >= 0; i--) {
      final bullet = _bullets[i];
      final target = bullet.cell.move(bullet.direction);
      if (!_inWorld(target)) {
        _bullets.removeAt(i);
        continue;
      }
      final mole = _activeMoleAt(target);
      if (mole != null) {
        _bullets.removeAt(i);
        _killMoleByShot(mole);
        continue;
      }
      bullet.previousCell = bullet.cell;
      bullet.cell = target;
    }
  }

  // ── 狩獵 ───────────────────────────────────────────────

  void _startHunt() {
    _huntArmed = false;
    _huntActive = true;
    _huntMsLeft = huntDurationMs;
    _huntEaten = 0;
    _bullets.clear(); // 變身期間停用射擊，場上種子直接收掉
    _ensureHuntTargets();
    _events.add(ArcadeEvent.huntStarted);
  }

  /// 把最多三隻既有鼴鼠移到蛇頭 5–9 格內，不足才新增。
  /// 維持原本場上總量，同時保證狩獵開始就看得到可追的目標。
  void _ensureHuntTargets() {
    var nearby = _moles.where((mole) {
      final distance = head.chebyshev(mole.cell);
      if (distance < huntTargetMinHeadDistance ||
          distance > huntTargetMaxHeadDistance) {
        return false;
      }
      mole.state = ArcadeMoleState.active;
      return true;
    }).length;
    final distant = _moles.where((mole) {
      final distance = head.chebyshev(mole.cell);
      return distance < huntTargetMinHeadDistance ||
          distance > huntTargetMaxHeadDistance;
    }).toList();
    for (final mole in distant) {
      if (nearby >= huntTargetKills) break;
      _moles.remove(mole);
      final cell = _randomFreeCellNearHead(
        minRadius: huntTargetMinHeadDistance,
        maxRadius: huntTargetMaxHeadDistance,
      );
      if (cell == null) {
        _moles.add(mole);
        break;
      }
      mole
        ..cell = cell
        ..previousCell = cell
        ..state = ArcadeMoleState.active
        ..telegraphMsLeft = 0;
      _moles.add(mole);
      nearby += 1;
    }
    while (nearby < huntTargetKills) {
      final cell = _randomFreeCellNearHead(
        minRadius: huntTargetMinHeadDistance,
        maxRadius: huntTargetMaxHeadDistance,
      );
      if (cell == null) break;
      _moles.add(
        ArcadeMole(
          cell: cell,
          facing: ArcadeDirection.values[_rng.nextInt(4)],
          state: ArcadeMoleState.active,
          telegraphMsLeft: 0,
        ),
      );
      nearby += 1;
    }
  }

  void _tickHunt() {
    final before = _huntMsLeft;
    _huntMsLeft -= _quantumMs;
    for (final mark in const [3000, 2000, 1000]) {
      if (before > mark && _huntMsLeft <= mark) {
        _events.add(ArcadeEvent.huntWarnTick);
      }
    }
    if (_huntMsLeft <= 0) _endHunt(full: false);
  }

  void _eatMoleByHunt(ArcadeMole mole) {
    _moles.remove(mole);
    _huntEaten += 1;
    _huntKills += 1;
    _score += _applyMultiplier(huntEatScore);
    _events.add(ArcadeEvent.moleKilled);
    if (_huntEaten >= huntTargetKills) {
      _score += _applyMultiplier(huntFullBonus);
      _events.add(ArcadeEvent.huntFull);
      _endHunt(full: true);
    }
  }

  void _endHunt({required bool full}) {
    _huntActive = false;
    _huntMsLeft = 0;
    // 解除瞬間蛇頭附近的鼴鼠鑽地離場，杜絕無法反應的貼臉死。
    _moles.removeWhere(
      (m) =>
          m.state == ArcadeMoleState.active &&
          head.chebyshev(m.cell) <= huntEndGraceRadius,
    );
    _events.add(ArcadeEvent.huntEnded);
  }

  // ── 死亡與復活 ─────────────────────────────────────────

  void _die() {
    _huntActive = false;
    _huntArmed = false;
    _huntMsLeft = 0;
    _bullets.clear();
    _inputQueue.clear();
    if (_lives > 0) {
      _lives -= 1;
      _revive();
    } else {
      _phase = ArcadePhase.gameOver;
      _events.add(ArcadeEvent.died);
      _events.add(ArcadeEvent.gameOver);
    }
  }

  /// 安全復活：長度折半（下限 4）以待成長方式重新伸展；復活點取
  /// 「距所有鼴鼠最小距離最大」的內圈格（同分取靠中心），附近鼴鼠先移走。
  void _revive() {
    final keptLength = math.max(initialLength, length ~/ 2);
    final spot = _findReviveSpot();
    _body
      ..clear()
      ..add(spot);
    _pendingGrowth = keptLength - 1;
    _hasMoved = false;
    _moles.removeWhere((m) => spot.chebyshev(m.cell) <= reviveClearRadius);
    _snakeAcc = 0;
    _phase = ArcadePhase.waiting;
    _waitReason = ArcadeWaitReason.revived;
    _events.add(ArcadeEvent.died);
    _events.add(ArcadeEvent.revived);
  }

  ArcadePoint _findReviveSpot() {
    const center = ArcadePoint(worldSize ~/ 2, worldSize ~/ 2);
    var best = center;
    var bestMoleDistance = -1;
    var bestCenterDistance = 1 << 30;
    for (var y = reviveMargin; y < worldSize - reviveMargin; y++) {
      for (var x = reviveMargin; x < worldSize - reviveMargin; x++) {
        final cell = ArcadePoint(x, y);
        if (_collectibles.any((c) => c.cell == cell)) continue;
        if (_moles.any((m) => m.cell == cell)) continue;
        var moleDistance = 1 << 20;
        for (final mole in _moles) {
          moleDistance = math.min(moleDistance, cell.chebyshev(mole.cell));
        }
        final centerDistance = cell.chebyshev(center);
        if (moleDistance > bestMoleDistance ||
            (moleDistance == bestMoleDistance &&
                centerDistance < bestCenterDistance)) {
          bestMoleDistance = moleDistance;
          bestCenterDistance = centerDistance;
          best = cell;
        }
      }
    }
    return best;
  }

  bool _inWorld(ArcadePoint cell) =>
      cell.x >= 0 && cell.x < worldSize && cell.y >= 0 && cell.y < worldSize;

  // ── 測試鉤子 ───────────────────────────────────────────

  @visibleForTesting
  void debugPlaceCollectible(ArcadePoint cell, ArcadeCollectibleType type) {
    _collectibles.removeWhere((c) => c.cell == cell);
    _collectibles.add(ArcadeCollectible(cell, type));
    if (type == ArcadeCollectibleType.magnetFruit) {
      _magnetFruitTtlMs = magnetFruitLifetimeMs;
    }
  }

  @visibleForTesting
  void debugClearCollectibles() => _collectibles.clear();

  @visibleForTesting
  void debugSpawnMole(
    ArcadePoint cell, {
    ArcadeDirection facing = ArcadeDirection.left,
    bool active = true,
  }) {
    _moles.add(
      ArcadeMole(
        cell: cell,
        facing: facing,
        state: active ? ArcadeMoleState.active : ArcadeMoleState.telegraph,
      ),
    );
  }

  @visibleForTesting
  void debugClearMoles() => _moles.clear();

  @visibleForTesting
  void debugSetPhysicalCount(int value) => _physicalCount = value;

  @visibleForTesting
  void debugRefillCarrots() => _refillCarrots();

  @visibleForTesting
  void debugGrantAbility(ArcadeAbility ability) => _applyAbility(ability);

  @visibleForTesting
  void debugSetSpeedLevel(int level) =>
      _speedLevel = level.clamp(1, stepIntervalsMs.length);

  @visibleForTesting
  void debugSetLaserMsLeft(int value) => _laserMsLeft = math.max(0, value);

  /// 直接進入狩獵（可指定剩餘毫秒），測倒數警告與解除驅離用。
  @visibleForTesting
  void debugStartHunt({int msLeft = huntDurationMs}) {
    _huntArmed = false;
    _huntActive = true;
    _huntMsLeft = msLeft;
    _huntEaten = 0;
  }

  /// 歸零鼴鼠移動累計，讓測試能保證「蛇先走到、鼴鼠還沒逃」的時序。
  @visibleForTesting
  void debugResetMoleClock() => _moleAcc = 0;

  @visibleForTesting
  void debugStepMoles([int steps = 1]) {
    for (var i = 0; i < steps; i++) {
      _stepMoles();
    }
  }
}
