// 骰盤：全螢幕物理場擲骰（不打斷計時）。
//
// 互動核心：手指＝彈簧吸引子——按住把骰子「吸」過來（多指時每顆骰子
// 被最近的手指吸）、拖動跟手、放手繼承速度甩出去；螢幕邊界＝牆壁反彈、
// 骰子彼此碰撞，阻尼衰減到靜止＝結算合計。
//
// 視覺是「真 3D」：每顆骰子是軟體渲染的立方體（8 頂點 6 面、透視投影、
// 背面剔除、面光照、稜線），姿態用四元數＋3D 角速度積分，移動時沿
// 滾動軸自然翻滾。靜止時姿態 snap 到立方體 24 個軸對齊方向中最近者，
// 「哪面朝上就是幾點」——點數完全由物理決定，不用亂數換面。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/prefs_keys.dart';
import '../../../utils/sfx_service.dart';
import 'table_timer_theme.dart';

class DiceTrayOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const DiceTrayOverlay({super.key, required this.onClose});

  @override
  State<DiceTrayOverlay> createState() => _DiceTrayOverlayState();
}

class _DiceTrayOverlayState extends State<DiceTrayOverlay>
    with SingleTickerProviderStateMixin {
  static const int maxDice = 6;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  final _world = _DiceWorld();
  final Map<int, Offset> _pointers = {};

  SharedPreferences? _prefs;
  int _count = 2;
  bool _showTotal = false;

  DateTime _lastImpactFeedback = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _world.onImpact = _handleImpact;
    _ticker = createTicker(_onTick)..start();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _count = (p.getInt(PrefsKeys.gameTableDiceCount) ?? 2).clamp(
          1,
          maxDice,
        );
        _world.spawn(_count);
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _world.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastTick = elapsed;
    if (_world.bounds == Rect.zero) return;
    _world.step(dt, _pointers.values.toList());

    if (_world.settled && !_showTotal) {
      _showTotal = true;
      playHaptic(HapticLevel.medium); // 定格
      setState(() {});
    } else if (!_world.settled && _showTotal) {
      _showTotal = false;
      setState(() {});
    }
  }

  // 碰撞回饋分級：音量隨撞擊力道縮放（輕碰小聲、猛撞大聲），
  // 牆壁與骰子互撞都會響；90ms 節流避免像鞭炮。
  // TODO: 專屬骰子碰撞聲（ElevenLabs 生成中）到位後把 gamePass 換掉。
  void _handleImpact(double strength) {
    final now = DateTime.now();
    if (now.difference(_lastImpactFeedback).inMilliseconds < 90) return;
    _lastImpactFeedback = now;
    unawaited(
      SfxService.instance.play(
        SfxCue.gamePass,
        volumeScale: (strength / 2400).clamp(0.25, 1.0),
      ),
    );
    playHaptic(strength > 1100 ? HapticLevel.medium : HapticLevel.selection);
  }

  void _setCount(int delta) {
    final next = (_count + delta).clamp(1, maxDice);
    if (next == _count) return;
    playHaptic(HapticLevel.selection);
    setState(() {
      _count = next;
      _world.spawn(next);
    });
    _prefs?.setInt(PrefsKeys.gameTableDiceCount, next);
  }

  void _throwAll() {
    playFeedback(SfxCue.gamePass);
    _world.throwAll();
  }

  // ── 多指吸力 ─────────────────────────────────────────────

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _world.wake();
    playHaptic(HapticLevel.selection); // 「吸住了」
  }

  void _pointerMove(PointerMoveEvent e) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }
  }

  void _pointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isNotEmpty) return;
    // 最後一指離手＝甩出：出手加成，甩得夠快就給爆發回饋
    _world.releaseBurst();
    if (_world.anyFast) {
      playFeedback(SfxCue.gamePass, haptic: HapticLevel.medium);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: const Color(0xB31A120C),
          child: LayoutBuilder(
            builder: (context, box) {
              // 物理牆內縮：頂部避開顆數列、底部避開擲骰鈕區，
              // 骰子撞「隱形牆」反彈、不會滾到 UI 底下
              final pad = MediaQuery.of(context).padding;
              _world.setBounds(
                Rect.fromLTRB(
                  0,
                  pad.top + 62,
                  box.maxWidth,
                  box.maxHeight - pad.bottom - 168,
                ),
                dieSizeFor(_count),
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 物理場：整面都能按住吸骰子、甩出去
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerUp: (e) => _pointerUp(e.pointer),
                    onPointerCancel: (e) => _pointerUp(e.pointer),
                    child: CustomPaint(
                      painter: _WorldPainter(_world),
                      isComplex: true,
                    ),
                  ),
                  // 頂部：顆數（吸收自己的觸控，不進物理場）
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _countRow(),
                      ),
                    ),
                  ),
                  // 合計：靜止結算後浮現在中央偏上
                  SafeArea(
                    child: Align(
                      alignment: const Alignment(0, -0.62),
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _showTotal && _count > 1 ? 1 : 0,
                          duration: const Duration(milliseconds: 260),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC3C2D21),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: TableTheme.hairline),
                            ),
                            child: Text(
                              '合計 ${_world.total}',
                              style: AppType.digits(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: TableTheme.inkStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 底部：擲骰鈕＋提示＋收起
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _throwButton(),
                            const SizedBox(height: 8),
                            const Text(
                              '按住把骰子吸過來，甩出去！',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: TableTheme.inkFaint,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onClose,
                              child: const Text(
                                '收起',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: TableTheme.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static double dieSizeFor(int count) =>
      count <= 2 ? 92.0 : (count <= 4 ? 80.0 : 70.0);

  Widget _countRow() {
    Widget btn(IconData icon, int delta, bool enabled) {
      return Material(
        color: const Color(0x2EF6ECDD),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _setCount(delta) : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? TableTheme.inkStrong : TableTheme.inkFaint,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, -1, _count > 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            '$_count 顆骰子',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: TableTheme.inkStrong,
              fontFamily: AppType.digits().fontFamily,
            ),
          ),
        ),
        btn(Icons.add_rounded, 1, _count < maxDice),
      ],
    );
  }

  Widget _throwButton() {
    return Material(
      color: TableTheme.warn,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _throwAll,
        child: const SizedBox(
          width: 200,
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.casino_rounded, size: 24, color: Color(0xFF241A12)),
              SizedBox(width: 8),
              Text(
                '擲骰子',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF241A12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 3D 數學（迷你四元數，只做需要的事）──────────────────────

class _Quat {
  double w, x, y, z;

  _Quat(this.w, this.x, this.y, this.z);

  _Quat.identity() : this(1, 0, 0, 0);

  factory _Quat.axisAngle(double ax, double ay, double az, double angle) {
    final s = math.sin(angle / 2);
    return _Quat(math.cos(angle / 2), ax * s, ay * s, az * s);
  }

  _Quat operator *(_Quat o) => _Quat(
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

  double dot(_Quat o) => w * o.w + x * o.x + y * o.y + z * o.z;

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

  /// 朝 target 走一步（短弧 nlerp；snap 用，角度不大夠準）。
  void nlerpTowards(_Quat target, double t) {
    var tw = target.w, tx = target.x, ty = target.y, tz = target.z;
    if (dot(target) < 0) {
      tw = -tw;
      tx = -tx;
      ty = -ty;
      tz = -tz;
    }
    w += (tw - w) * t;
    x += (tx - x) * t;
    y += (ty - y) * t;
    z += (tz - z) * t;
    normalizeSelf();
  }

  _Quat clone() => _Quat(w, x, y, z);
}

// ── 物理 ───────────────────────────────────────────────────

class _Die {
  Offset pos;
  Offset vel = Offset.zero;
  _Quat q;
  double wx = 0, wy = 0, wz = 0; // 角速度（世界系，rad/s）
  int value = 1; // 靜止結算後的朝上點數

  /// 動態 3D 程度（0＝靜止平面正對、1＝全 3D 翻滾），隨能量平滑追蹤。
  double tiltT = 0;

  /// 離手/擲出的爆發 pop（1→0 衰減，畫的時候放大一下）。
  double popT = 0;

  _Die(this.pos, this.q);

  double get speed => vel.distance;
  double get spin => math.sqrt(wx * wx + wy * wy + wz * wz);
}

/// 輕量剛體世界：平面運動＋3D 姿態。
/// 彈簧吸力、牆壁反彈、等質量圓碰撞、阻尼；靜止時姿態 snap 到
/// 立方體 24 個軸對齊方向，朝上面＝點數（物理決定結果）。
class _DiceWorld extends ChangeNotifier {
  final _rng = math.Random();

  Rect bounds = Rect.zero;
  double dieSize = 80;
  List<_Die> dice = [];
  bool hasBeenThrown = false;
  bool settling = false;
  bool settled = false;

  void Function(double strength)? onImpact;

  // 手感參數（實機調校入口都在這）
  static const _springK = 180.0; // 吸力彈簧（吸鐵般緊跟）
  static const _springDamp = 17.0; // 吸力阻尼（近臨界：跟手不震盪）
  static const _linDamp = 1.4; // 自由滾動線性阻尼 /s
  static const _rollCouple = 7.0; // 滾動耦合速率（貼地滾的跟隨度）
  static const _restitution = 0.72; // 牆壁恢復係數
  static const _throwBoost = 1.85; // 離手出手速度加成（甩出去的爽度）
  static const _maxSpeed = 3400.0; // 出手速度上限
  static const _calmSpeed = 16.0;
  static const _calmSpin = 1.1;
  static const _snapRate = 9.0; // 靜止對面收斂速率

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
    settling = false;
    settled = false;
    final center = bounds == Rect.zero ? const Offset(200, 300) : bounds.center;
    dice = [
      for (var i = 0; i < count; i++)
        _Die(
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
    settling = false;
    settled = false;
  }

  void markThrown() => hasBeenThrown = true;

  /// 擲骰鈕：全員隨機炸開。
  void throwAll() {
    hasBeenThrown = true;
    wake();
    for (final d in dice) {
      final a = _rng.nextDouble() * math.pi * 2;
      final power = 1200 + _rng.nextDouble() * 1100;
      d.vel += Offset(math.cos(a), math.sin(a)) * power;
      d.wz += (_rng.nextBool() ? 1 : -1) * (6 + _rng.nextDouble() * 10);
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
      if (d.speed > 250) d.popT = 1;
    }
  }

  /// 有骰子正被甩（離手回饋要不要播的依據）。
  bool get anyFast => dice.any((d) => d.speed > 420);

  void step(double dt, List<Offset> pointers) {
    if (dice.isEmpty || dt <= 0) return;

    if (settled) return; // 靜止定格，等下一次互動

    for (final d in dice) {
      if (pointers.isNotEmpty) {
        // 被最近的手指吸：彈簧-阻尼，拖動跟手、放手自然有出手速度
        var nearest = pointers.first;
        var best = (nearest - d.pos).distanceSquared;
        for (final p in pointers.skip(1)) {
          final dist = (p - d.pos).distanceSquared;
          if (dist < best) {
            best = dist;
            nearest = p;
          }
        }
        final force = (nearest - d.pos) * _springK - d.vel * _springDamp;
        d.vel += force * dt;
      } else {
        d.vel *= math.exp(-_linDamp * dt);
      }

      d.pos += d.vel * dt;

      // 滾動耦合：角速度貼向「沿移動方向滾」的目標值（像在地上滾），
      // z 軸自旋只衰減——甩出去的旋轉會自然轉成翻滾。
      // gate：慢速（被吸住拿在手上）時目標歸零，不會原地無意義自轉
      final gate = math.min(1.0, d.speed / 340);
      final k = 1 - math.exp(-_rollCouple * dt);
      d.wx += (d.vel.dy / _radius * gate - d.wx) * k;
      d.wy += (-d.vel.dx / _radius * gate - d.wy) * k;
      d.wz *= math.exp(-1.6 * dt);

      // 動態 3D 程度：有速度/翻滾就立體，靜下來回到平面正對
      final energy = math.min(1.0, (d.speed + d.spin * 55) / 700);
      d.tiltT += (energy - d.tiltT) * (1 - math.exp(-7.0 * dt));
      d.popT *= math.exp(-5.5 * dt);

      // 四元數積分：dq = 0.5·(0,ω)·q·dt
      final o = _Quat(0, d.wx, d.wy, d.wz) * d.q;
      d.q
        ..w += o.w * 0.5 * dt
        ..x += o.x * 0.5 * dt
        ..y += o.y * 0.5 * dt
        ..z += o.z * 0.5 * dt
        ..normalizeSelf();

      _wallCollide(d);
    }

    _pairCollide();

    // 靜止流程：慢下來 → 姿態 snap 到最近的軸對齊方向 → 定格
    if (pointers.isEmpty && hasBeenThrown && _isCalm) {
      settling = true;
    }
    if (settling) {
      var allAligned = true;
      for (final d in dice) {
        d.vel *= math.exp(-8.0 * dt);
        d.wx *= math.exp(-8.0 * dt);
        d.wy *= math.exp(-8.0 * dt);
        d.wz *= math.exp(-8.0 * dt);
        final target = _nearestOrient(d.q);
        d.q.nlerpTowards(target, 1 - math.exp(-_snapRate * dt));
        if (d.q.dot(target).abs() < 0.99995) allAligned = false;
      }
      if (allAligned) {
        for (final d in dice) {
          d.value = _topValueOf(d.q);
        }
        settling = false;
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

  void _wallCollide(_Die d) {
    final r = _radius;
    var hit = 0.0;
    if (d.pos.dx < bounds.left + r && d.vel.dx < 0) {
      hit = d.vel.dx.abs();
      d.vel = Offset(-d.vel.dx * _restitution, d.vel.dy);
      d.wz += d.vel.dy * 0.01;
    } else if (d.pos.dx > bounds.right - r && d.vel.dx > 0) {
      hit = d.vel.dx.abs();
      d.vel = Offset(-d.vel.dx * _restitution, d.vel.dy);
      d.wz -= d.vel.dy * 0.01;
    }
    if (d.pos.dy < bounds.top + r && d.vel.dy < 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.wz -= d.vel.dx * 0.01;
    } else if (d.pos.dy > bounds.bottom - r && d.vel.dy > 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.wz += d.vel.dx * 0.01;
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
          a.wz += rel * 0.005;
          b.wz -= rel * 0.005;
          if (rel.abs() > 260) onImpact?.call(rel.abs());
        }
      }
    }
  }

  // ── 立方體 24 個軸對齊方向（snap 目標）──────────────────

  static final List<_Quat> _orient24 = _gen24();

  static List<_Quat> _gen24() {
    final bases = <_Quat>[
      _Quat.identity(),
      _Quat.axisAngle(1, 0, 0, math.pi / 2),
      _Quat.axisAngle(1, 0, 0, -math.pi / 2),
      _Quat.axisAngle(1, 0, 0, math.pi),
      _Quat.axisAngle(0, 1, 0, math.pi / 2),
      _Quat.axisAngle(0, 1, 0, -math.pi / 2),
    ];
    return [
      for (final b in bases)
        for (var k = 0; k < 4; k++)
          _Quat.axisAngle(0, 0, 1, k * math.pi / 2) * b,
    ];
  }

  static _Quat _nearestOrient(_Quat q) {
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
  static int _topValueOf(_Quat q) {
    var bestValue = 1;
    var bestZ = -2.0;
    for (final f in _DieGeometry.faces) {
      final (_, _, nz) = q.rotate(f.nx, f.ny, f.nz);
      if (nz > bestZ) {
        bestZ = nz;
        bestValue = f.value;
      }
    }
    return bestValue;
  }
}

// ── 立方體幾何與渲染 ────────────────────────────────────────

class _Face {
  final double nx, ny, nz; // 法線
  final double t1x, t1y, t1z; // 面內切向量 1
  final double t2x, t2y, t2z; // 面內切向量 2
  final int value;

  const _Face(
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

abstract final class _DieGeometry {
  // 面配置：+Z=1、−Z=6、+X=2、−X=5、+Y=3、−Y=4（對面相加＝7）
  static const faces = [
    _Face(0, 0, 1, 1, 0, 0, 0, 1, 0, 1),
    _Face(0, 0, -1, 1, 0, 0, 0, -1, 0, 6),
    _Face(1, 0, 0, 0, 0, -1, 0, 1, 0, 2),
    _Face(-1, 0, 0, 0, 0, 1, 0, 1, 0, 5),
    _Face(0, 1, 0, 1, 0, 0, 0, 0, -1, 3),
    _Face(0, -1, 0, 1, 0, 0, 0, 0, 1, 4),
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

/// 物理場畫家：軟體渲染立方體（透視投影＋背面剔除＋面光照＋稜線）。
class _WorldPainter extends CustomPainter {
  final _DiceWorld world;

  _WorldPainter(this.world) : super(repaint: world);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in world.dice) {
      _paintDie(canvas, d);
    }
  }

  void _paintDie(Canvas canvas, _Die d) {
    // 離手/擲出瞬間 pop 放大一下（出手回饋）
    final h = world.dieSize * 0.40 * (1 + 0.14 * d.popT);
    final persp = h * 7.5; // 相機距離（弱透視）
    final energy = math.min(1.0, (d.speed + d.spin * 55) / 850);
    // 動態視角：靜止＝0 傾角（平面正對、乾淨讀數），被吸住/甩動時
    // 前傾展現立體——「靜止像 2D、動起來才 3D」
    final viewQ = d.tiltT < 0.01
        ? d.q
        : _Quat.axisAngle(1, 0, 0, -0.34 * d.tiltT) * d.q;

    // 貼地陰影：滾得越兇越大越散
    canvas.drawOval(
      Rect.fromCenter(
        center: d.pos + Offset(0, h * (0.85 + energy * 0.25)),
        width: h * (2.5 + energy * 0.7),
        height: h * (1.05 + energy * 0.3),
      ),
      Paint()
        ..color = Color.fromARGB((70 * (1 - energy * 0.35)).round(), 12, 7, 4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + energy * 8),
    );

    Offset project(double x, double y, double z) {
      final s = persp / (persp - z);
      return d.pos + Offset(x * s, y * s);
    }

    // 光源：左上偏前
    const lx = -0.38, ly = -0.53, lz = 0.76;

    // 只畫朝向相機的面（凸體不互遮，免排序）
    for (final f in _DieGeometry.faces) {
      final (nx, ny, nz) = viewQ.rotate(f.nx, f.ny, f.nz);
      if (nz <= 0.02) continue;

      final (t1x, t1y, t1z) = viewQ.rotate(f.t1x, f.t1y, f.t1z);
      final (t2x, t2y, t2z) = viewQ.rotate(f.t2x, f.t2y, f.t2z);

      // 面中心與四角（world 座標，中心在原點）
      final cx = nx * h, cy = ny * h, cz = nz * h;
      Offset corner(double su, double sv) => project(
        cx + (t1x * su + t2x * sv) * h,
        cy + (t1y * su + t2y * sv) * h,
        cz + (t1z * su + t2z * sv) * h,
      );

      final p1 = corner(-1, -1);
      final p2 = corner(1, -1);
      final p3 = corner(1, 1);
      final p4 = corner(-1, 1);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();

      // 面光照：法線對光源
      final lambert = math.max(0.0, nx * lx + ny * ly + nz * lz);
      final bright = 0.58 + 0.42 * lambert;
      final faceColor = Color.lerp(
        const Color(0xFFB99F82),
        const Color(0xFFFFFAEF),
        bright,
      )!;

      canvas.drawPath(path, Paint()..color = faceColor);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, h * 0.045)
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x40513A28),
      );

      // pip：畫「面上的圓盤」——以面切向量的螢幕投影當基底做
      // 仿射變換，斜視角下自然壓成橢圓、貼面不會凸出稜線
      final pipPaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF241A12),
          const Color(0xFF4A382A),
          1 - bright,
        )!;
      final pipR = h * 0.19;
      final e1 = Offset(t1x, t1y) * pipR; // 螢幕空間基向量（弱透視近似）
      final e2 = Offset(t2x, t2y) * pipR;
      for (final p in _DieGeometry.pips[f.value]!) {
        final u = p.dx * 0.9, v = p.dy * 0.9;
        final pos = project(
          cx + (t1x * u + t2x * v) * h,
          cy + (t1y * u + t2y * v) * h,
          cz + (t1z * u + t2z * v) * h,
        );
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.transform(
          (Matrix4.identity()
                ..setEntry(0, 0, e1.dx)
                ..setEntry(1, 0, e1.dy)
                ..setEntry(0, 1, e2.dx)
                ..setEntry(1, 1, e2.dy))
              .storage,
        );
        canvas.drawCircle(Offset.zero, 1, pipPaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) => false; // repaint 由 world 通知
}
