// 骰盤物理世界：平面剛體運動＋3D 姿態（渲染在 dice_tray.dart）。
//
// 點數完全由物理決定——減速時「復位力矩」把骰子轉倒在最近的面上
//（立方體 24 個軸對齊方向），哪面朝上就是幾點，不用亂數換面。
//
// 公平性（防「控骰」）：純滾動的總轉角＝滑行距離÷半徑是決定性的，
// 直線輕甩只會在單一滾動軸的 4 個面之間循環、控力道甚至能瞄面。
// 兩個「物理性」的隨機源打散：離手隨機自旋（現實中手指本來就會帶旋）
// ＋每次出手的滾動係數微擾（模擬骰子與桌面接觸的不完美滾動）。
// 六面均勻性由 test/dice_world_test.dart 的蒙地卡羅檢定把關。
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

// ── 3D 數學（迷你四元數，只做需要的事）──────────────────────

class DiceQuat {
  double w, x, y, z;

  DiceQuat(this.w, this.x, this.y, this.z);

  DiceQuat.identity() : this(1, 0, 0, 0);

  factory DiceQuat.axisAngle(double ax, double ay, double az, double angle) {
    final s = math.sin(angle / 2);
    return DiceQuat(math.cos(angle / 2), ax * s, ay * s, az * s);
  }

  DiceQuat operator *(DiceQuat o) => DiceQuat(
    w * o.w - x * o.x - y * o.y - z * o.z,
    w * o.x + x * o.w + y * o.z - z * o.y,
    w * o.y - x * o.z + y * o.w + z * o.x,
    w * o.z + x * o.y - y * o.x + z * o.w,
  );

  void normalizeSelf() {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    if (n == 0) return;
    w /= n;
    x /= n;
    y /= n;
    z /= n;
  }

  double dot(DiceQuat o) => w * o.w + x * o.x + y * o.y + z * o.z;

  /// 旋轉向量 v（q v q⁻¹ 的展開式，零配置版）。
  (double, double, double) rotate(double vx, double vy, double vz) {
    final tx = 2 * (y * vz - z * vy);
    final ty = 2 * (z * vx - x * vz);
    final tz = 2 * (x * vy - y * vx);
    return (
      vx + w * tx + (y * tz - z * ty),
      vy + w * ty + (z * tx - x * tz),
      vz + w * tz + (x * ty - y * tx),
    );
  }

  DiceQuat conjugated() => DiceQuat(w, -x, -y, -z);

  /// 到 target 的最短旋轉誤差：回傳旋轉向量（單位軸×角，世界系）
  /// 與誤差角。復位力矩用——對誤差施力矩而不是直接插值姿態。
  (double, double, double, double) errorAxisTo(DiceQuat target) {
    final e = target * conjugated();
    var ew = e.w, ex = e.x, ey = e.y, ez = e.z;
    if (ew < 0) {
      ew = -ew;
      ex = -ex;
      ey = -ey;
      ez = -ez;
    }
    final s = math.sqrt(math.max(0.0, 1 - ew * ew));
    if (s < 1e-6) return (0, 0, 0, 0);
    final angle = 2 * math.acos(math.min(1.0, ew));
    return (ex / s * angle, ey / s * angle, ez / s * angle, angle);
  }

  DiceQuat clone() => DiceQuat(w, x, y, z);
}

// ── 立方體幾何（面配置與 pip 位置，渲染與點數判定共用）─────────

class DieFace {
  final double nx, ny, nz; // 法線
  final double t1x, t1y, t1z; // 面內切向量 1
  final double t2x, t2y, t2z; // 面內切向量 2
  final int value;

  const DieFace(
    this.nx,
    this.ny,
    this.nz,
    this.t1x,
    this.t1y,
    this.t1z,
    this.t2x,
    this.t2y,
    this.t2z,
    this.value,
  );
}

abstract final class DieGeometry {
  // 面配置：+Z=1、−Z=6、+X=2、−X=5、+Y=3、−Y=4（對面相加＝7）
  static const faces = [
    DieFace(0, 0, 1, 1, 0, 0, 0, 1, 0, 1),
    DieFace(0, 0, -1, 1, 0, 0, 0, -1, 0, 6),
    DieFace(1, 0, 0, 0, 0, -1, 0, 1, 0, 2),
    DieFace(-1, 0, 0, 0, 0, 1, 0, 1, 0, 5),
    DieFace(0, 1, 0, 1, 0, 0, 0, 0, -1, 3),
    DieFace(0, -1, 0, 1, 0, 0, 0, 0, 1, 4),
  ];

  /// 各點數的 pip 位置（面局部座標，單位＝半邊長）。
  static const Map<int, List<Offset>> pips = {
    1: [Offset.zero],
    2: [Offset(-0.5, -0.5), Offset(0.5, 0.5)],
    3: [Offset(-0.5, -0.5), Offset.zero, Offset(0.5, 0.5)],
    4: [
      Offset(-0.5, -0.5),
      Offset(0.5, -0.5),
      Offset(-0.5, 0.5),
      Offset(0.5, 0.5),
    ],
    5: [
      Offset(-0.5, -0.5),
      Offset(0.5, -0.5),
      Offset.zero,
      Offset(-0.5, 0.5),
      Offset(0.5, 0.5),
    ],
    6: [
      Offset(-0.55, -0.55),
      Offset(-0.55, 0),
      Offset(-0.55, 0.55),
      Offset(0.55, -0.55),
      Offset(0.55, 0),
      Offset(0.55, 0.55),
    ],
  };
}

// ── 物理 ───────────────────────────────────────────────────

class Die {
  Offset pos;
  Offset vel = Offset.zero;
  DiceQuat q;
  double wx = 0, wy = 0, wz = 0; // 角速度（世界系，rad/s）
  int value = 1; // 靜止結算後的朝上點數

  /// 動態 3D 程度（0＝靜止平面正對、1＝全 3D 翻滾），隨能量平滑追蹤。
  double tiltT = 0;

  /// 離手/擲出的爆發 pop（1→0 衰減，畫的時候放大一下）。
  double popT = 0;

  /// 本次出手的滾動係數微擾（防控骰：打斷「距離→轉角」的決定性）。
  double rollBias = 1;

  Die(this.pos, this.q);

  double get speed => vel.distance;
  double get spin => math.sqrt(wx * wx + wy * wy + wz * wz);
}

/// 輕量剛體世界：彈簧吸力（掌心隊形）、牆壁反彈、等質量圓碰撞、
/// 阻尼＋乾摩擦；減速時復位力矩把骰子轉倒在最近的面上＝點數。
class DiceWorld extends ChangeNotifier {
  DiceWorld({math.Random? rng}) : _rng = rng ?? math.Random();

  final math.Random _rng;

  Rect bounds = Rect.zero;
  double dieSize = 80;
  List<Die> dice = [];
  bool hasBeenThrown = false;
  bool settled = false;
  bool _grabbed = false;

  void Function(double strength)? onImpact;

  // 手感參數（實機調校入口都在這）
  static const _springK = 180.0; // 吸力彈簧（吸鐵般緊跟）
  static const _springDamp = 17.0; // 吸力阻尼（近臨界：跟手不震盪）
  static const _linDamp = 1.4; // 自由滾動線性阻尼 /s
  static const _rollCouple = 7.0; // 滾動耦合速率（貼地滾的跟隨度）
  static const _restitution = 0.72; // 牆壁恢復係數
  static const _throwBoost = 1.85; // 離手出手速度加成（甩出去的爽度）
  static const _maxSpeed = 3400.0; // 出手速度上限
  static const _heldMaxSpin = 2.4; // 拿在手上的翻滾上限 rad/s（捏著＝慢轉）
  static const _dryFriction = 90.0; // 乾摩擦等減速 px/s²（絨布滾阻，真的滾停）
  static const _rightK = 170.0; // 落地復位力矩強度（重力把骰子轉倒在面上）
  static const _calmSpeed = 16.0;
  static const _calmSpin = 1.1;

  double get _radius => dieSize * 0.55;

  int get total => dice.fold(0, (sum, d) => sum + d.value);

  bool get _isCalm =>
      dice.every((d) => d.speed < _calmSpeed && d.spin < _calmSpin);

  void setBounds(Rect rect, double die) {
    if (bounds == rect && dieSize == die) return;
    bounds = rect;
    dieSize = die;
    if (dice.isEmpty) return;
    for (final d in dice) {
      d.pos = _clampToBounds(d.pos);
    }
  }

  void spawn(int count) {
    hasBeenThrown = false;
    settled = false;
    final center = bounds == Rect.zero ? const Offset(200, 300) : bounds.center;
    dice = [
      for (var i = 0; i < count; i++)
        Die(
          center +
              Offset(
                math.cos(i * math.pi * 2 / count) * dieSize * 1.15,
                math.sin(i * math.pi * 2 / count) * dieSize * 0.85,
              ),
          _orient24[_rng.nextInt(24)].clone(),
        )..value = 0,
    ];
    // 初始就對齊，直接算好朝上點數
    for (final d in dice) {
      d.value = _topValueOf(d.q);
    }
    notifyListeners();
  }

  void wake() {
    settled = false;
  }

  /// 本次出手的滾動係數：±50% 微擾（不完美滾動——防「控力道瞄面」）。
  double _newRollBias() => 0.5 + _rng.nextDouble();

  /// 出手隨機翻滾踢擊：手指/擲出本來就會帶不可控的旋——三軸都踢，
  /// 把「直線甩只在單一軸 4 面循環、控力道可瞄面」的決定性打散。
  /// 幅度經 test/dice_world_test.dart 對抗情境校準，別隨手調小。
  void _tumbleKick(Die d) {
    d.wx += _rng.nextDouble() * 48 - 24;
    d.wy += _rng.nextDouble() * 48 - 24;
    d.wz += (_rng.nextBool() ? 1 : -1) * (6 + _rng.nextDouble() * 10);
  }

  /// 擲骰鈕：全員隨機炸開。
  void throwAll() {
    hasBeenThrown = true;
    wake();
    for (final d in dice) {
      final a = _rng.nextDouble() * math.pi * 2;
      final power = 1200 + _rng.nextDouble() * 1100;
      d.vel += Offset(math.cos(a), math.sin(a)) * power;
      d.rollBias = _newRollBias();
      _tumbleKick(d);
      d.popT = 1;
    }
  }

  /// 離手爆發：最後一指放開時呼叫——出手速度加成，甩出去要夠爽。
  void releaseBurst() {
    hasBeenThrown = true;
    for (final d in dice) {
      final boosted = d.vel * _throwBoost;
      d.vel = boosted.distance > _maxSpeed
          ? boosted * (_maxSpeed / boosted.distance)
          : boosted;
      d.rollBias = _newRollBias();
      if (d.speed > 250) {
        d.popT = 1;
        _tumbleKick(d);
      }
    }
  }

  /// 有骰子正被甩（離手回饋要不要播的依據）。
  bool get anyFast => dice.any((d) => d.speed > 420);

  void step(double dt, List<Offset> pointers) {
    if (dice.isEmpty || dt <= 0) return;

    if (settled) return; // 靜止定格，等下一次互動

    final grabbed = pointers.isNotEmpty;
    _grabbed = grabbed;

    // 吸附目標：多顆吸向同一指時排成小隊形（像抓一把骰子在掌心，
    // 每顆有自己的位置）。全部擠向同一點會擠不進去→被撞開→又被
    // 拉回來永遠互撞，每次碰撞都把自旋打進骰子——「按住時有幾顆
    // 高速亂轉、顆數越多越嚴重」的根源就是這個
    List<Offset>? holdTargets;
    if (grabbed) {
      final targets = List<Offset>.filled(dice.length, Offset.zero);
      final groups = <int, List<int>>{};
      for (var i = 0; i < dice.length; i++) {
        var pi = 0;
        var best = double.infinity;
        for (var j = 0; j < pointers.length; j++) {
          final dd = (pointers[j] - dice[i].pos).distanceSquared;
          if (dd < best) {
            best = dd;
            pi = j;
          }
        }
        (groups[pi] ??= []).add(i);
      }
      groups.forEach((pi, members) {
        final n = members.length;
        if (n == 1) {
          targets[members[0]] = pointers[pi];
          return;
        }
        // 正 n 邊形隊形：相鄰骰心距 ≈ 1.97r（碰撞距外留一絲縫）
        final ringR = _radius * 1.97 / (2 * math.sin(math.pi / n));
        for (var k = 0; k < n; k++) {
          final ang = math.pi * 2 * k / n - math.pi / 2;
          targets[members[k]] =
              pointers[pi] + Offset(math.cos(ang), math.sin(ang)) * ringR;
        }
      });
      holdTargets = targets;
    }

    for (var i = 0; i < dice.length; i++) {
      final d = dice[i];
      if (grabbed) {
        // 被吸向自己的隊形位：彈簧-阻尼，拖動跟手、放手自然有出手速度
        final force =
            (holdTargets![i] - d.pos) * _springK - d.vel * _springDamp;
        d.vel += force * dt;
      } else {
        d.vel *= math.exp(-_linDamp * dt);
        // 乾摩擦（絨布滾阻）：等減速收尾——骰子會物理性地「滾停」，
        // 不是指數漸近的無限漂移再突然凍結
        final sp = d.vel.distance;
        if (sp > 0) {
          final drop = _dryFriction * dt;
          d.vel = sp <= drop ? Offset.zero : d.vel * ((sp - drop) / sp);
        }
      }

      d.pos += d.vel * dt;

      // 滾動耦合：角速度貼向「沿移動方向滾」的目標值（像在地上滾），
      // z 軸自旋只衰減——甩出去的旋轉會自然轉成翻滾。
      // gate：慢速時目標歸零，不會原地無意義自轉
      final gate = math.min(1.0, d.speed / 340);
      var targetWx = d.vel.dy / _radius * gate * d.rollBias;
      var targetWy = -d.vel.dx / _radius * gate * d.rollBias;
      if (grabbed) {
        // 拿在手上＝捏著：追手指的速度再快也只准緩慢轉動，
        // 且收斂更快——已在高速滾的骰子被捏住要馬上慢下來
        final mag = math.sqrt(targetWx * targetWx + targetWy * targetWy);
        if (mag > _heldMaxSpin) {
          targetWx *= _heldMaxSpin / mag;
          targetWy *= _heldMaxSpin / mag;
        }
      }
      final k = 1 - math.exp(-(grabbed ? 15.0 : _rollCouple) * dt);
      d.wx += (targetWx - d.wx) * k;
      d.wy += (targetWy - d.wy) * k;
      d.wz *= math.exp(-(grabbed ? 6.0 : 1.6) * dt);

      // 滾動亂流：桌面/骰身微小不完美＝隨機微力矩，沿途累積角度
      // 擴散（肉眼看不出，統計上把「同一動作同結果」再打散一層）。
      // 只在滾得夠快時作用，不干擾落地復位
      if (!grabbed && gate > 0.1) {
        final turb = 34.0 * math.sqrt(dt) * gate;
        d.wx += (_rng.nextDouble() - 0.5) * turb;
        d.wy += (_rng.nextDouble() - 0.5) * turb;
        d.wz += (_rng.nextDouble() - 0.5) * turb * 0.5;
      }

      // 拿在手上的「絕對」轉速上限：不管自旋從哪打進來（互撞、
      // 牆彈、放手前殘留），捏著的骰子就是不准高速轉
      if (grabbed) {
        final s = d.spin;
        if (s > _heldMaxSpin) {
          final f = _heldMaxSpin / s;
          d.wx *= f;
          d.wy *= f;
          d.wz *= f;
        }
      }

      var errT = 0.0;
      if (!grabbed) {
        // 落地復位「力矩」：越慢重力越佔上風，把骰子物理性地轉倒在
        // 最近的一面上（近臨界阻尼的旋轉彈簧——對誤差施力矩，不是
        // 直接插值姿態，停下的全程都是物理，不會有被拽正的感覺）
        final landing = 1 - math.min(1.0, (d.speed + d.spin * 40) / 520);
        if (landing > 0) {
          final target = _nearestOrient(d.q);
          final (ex, ey, ez, errAngle) = d.q.errorAxisTo(target);
          final kR = _rightK * landing * landing;
          final cR = 2 * math.sqrt(kR); // 臨界阻尼：倒下不彈跳、不震盪
          d.wx += (ex * kR - d.wx * cR) * dt;
          d.wy += (ey * kR - d.wy * cR) * dt;
          d.wz += (ez * kR - d.wz * cR) * dt;
          errT = math.min(1.0, errAngle * 1.4);
        }
      }

      // 動態 3D 程度：被拿住＝微微立起、甩動＝全 3D；落地過程視角
      // 跟著「還沒躺平的程度」走——躺平的那一刻才回到平面正對，
      // 不會出現視角已壓平、姿態卻還斜著的邊緣破圖
      final energy = math.min(1.0, (d.speed + d.spin * 55) / 700);
      final tiltTarget = grabbed
          ? math.max(energy, 0.55)
          : math.max(energy, errT);
      final tk = tiltTarget > d.tiltT ? 7.0 : 12.0;
      d.tiltT += (tiltTarget - d.tiltT) * (1 - math.exp(-tk * dt));
      d.popT *= math.exp(-5.5 * dt);

      // 四元數積分：dq = 0.5·(0,ω)·q·dt
      final o = DiceQuat(0, d.wx, d.wy, d.wz) * d.q;
      d.q
        ..w += o.w * 0.5 * dt
        ..x += o.x * 0.5 * dt
        ..y += o.y * 0.5 * dt
        ..z += o.z * 0.5 * dt
        ..normalizeSelf();

      _wallCollide(d);
    }

    _pairCollide();

    // 靜止結算：物理自己停穩（夠慢＋已躺平）才鎖定點數——
    // 沒有任何強制煞車，停下來的樣子就是滾出來的樣子
    if (!grabbed && hasBeenThrown && _isCalm) {
      var allAligned = true;
      for (final d in dice) {
        if (d.q.dot(_nearestOrient(d.q)).abs() < 0.9999) {
          allAligned = false;
          break;
        }
      }
      if (allAligned) {
        for (final d in dice) {
          d.q = _nearestOrient(d.q).clone(); // 殘差 <1.6°，肉眼看不出跳動
          d.value = _topValueOf(d.q);
          d.vel = Offset.zero;
          d.wx = 0;
          d.wy = 0;
          d.wz = 0;
          d.tiltT = 0; // 定格＝絕對平面正對（step 提前 return，殘值會凍住）
          d.popT = 0;
        }
        settled = true;
      }
    }

    notifyListeners();
  }

  Offset _clampToBounds(Offset p) => Offset(
    p.dx.clamp(
      bounds.left + _radius,
      math.max(bounds.left + _radius, bounds.right - _radius),
    ),
    p.dy.clamp(
      bounds.top + _radius,
      math.max(bounds.top + _radius, bounds.bottom - _radius),
    ),
  );

  void _wallCollide(Die d) {
    final r = _radius;
    // 捏著時碰撞不打自旋進骰子（打了也會被限速，乾脆不打）
    final spinPump = _grabbed ? 0.0 : 0.01;
    var hit = 0.0;
    if (d.pos.dx < bounds.left + r && d.vel.dx < 0) {
      hit = d.vel.dx.abs();
      d.vel = Offset(-d.vel.dx * _restitution, d.vel.dy);
      d.wz += d.vel.dy * spinPump;
    } else if (d.pos.dx > bounds.right - r && d.vel.dx > 0) {
      hit = d.vel.dx.abs();
      d.vel = Offset(-d.vel.dx * _restitution, d.vel.dy);
      d.wz -= d.vel.dy * spinPump;
    }
    if (d.pos.dy < bounds.top + r && d.vel.dy < 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.wz -= d.vel.dx * spinPump;
    } else if (d.pos.dy > bounds.bottom - r && d.vel.dy > 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.wz += d.vel.dx * spinPump;
    }
    d.pos = _clampToBounds(d.pos);
    if (hit > 260) onImpact?.call(hit);
  }

  void _pairCollide() {
    final minDist = _radius * 2 * 0.94;
    for (var i = 0; i < dice.length; i++) {
      for (var j = i + 1; j < dice.length; j++) {
        final a = dice[i];
        final b = dice[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        if (dist >= minDist || dist == 0) continue;

        final n = delta / dist;
        final overlap = (minDist - dist) / 2;
        a.pos -= n * overlap;
        b.pos += n * overlap;

        final rel = (b.vel - a.vel).dx * n.dx + (b.vel - a.vel).dy * n.dy;
        if (rel < 0) {
          final impulse = n * rel * _restitution;
          a.vel += impulse;
          b.vel -= impulse;
          if (!_grabbed) {
            // 捏著時互撞不打自旋（持續互撞會把轉速越疊越高）
            a.wz += rel * 0.005;
            b.wz -= rel * 0.005;
          }
          if (rel.abs() > 260) onImpact?.call(rel.abs());
        }
      }
    }
  }

  // ── 立方體 24 個軸對齊方向（復位目標）────────────────────

  static final List<DiceQuat> _orient24 = _gen24();

  static List<DiceQuat> _gen24() {
    final bases = <DiceQuat>[
      DiceQuat.identity(),
      DiceQuat.axisAngle(1, 0, 0, math.pi / 2),
      DiceQuat.axisAngle(1, 0, 0, -math.pi / 2),
      DiceQuat.axisAngle(1, 0, 0, math.pi),
      DiceQuat.axisAngle(0, 1, 0, math.pi / 2),
      DiceQuat.axisAngle(0, 1, 0, -math.pi / 2),
    ];
    return [
      for (final b in bases)
        for (var k = 0; k < 4; k++)
          DiceQuat.axisAngle(0, 0, 1, k * math.pi / 2) * b,
    ];
  }

  static DiceQuat _nearestOrient(DiceQuat q) {
    var best = _orient24.first;
    var bestDot = -1.0;
    for (final o in _orient24) {
      final d = q.dot(o).abs();
      if (d > bestDot) {
        bestDot = d;
        best = o;
      }
    }
    return best;
  }

  /// 姿態 q 之下「朝相機（+Z）」的面點數。
  /// 面配置照真骰子：1↔6、2↔5、3↔4（對面相加＝7）。
  static int _topValueOf(DiceQuat q) {
    var bestValue = 1;
    var bestZ = -2.0;
    for (final f in DieGeometry.faces) {
      final (_, _, nz) = q.rotate(f.nx, f.ny, f.nz);
      if (nz > bestZ) {
        bestZ = nz;
        bestValue = f.value;
      }
    }
    return bestValue;
  }
}
