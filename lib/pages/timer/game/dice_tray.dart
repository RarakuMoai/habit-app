// 骰盤：全螢幕物理場擲骰（不打斷計時）。
//
// 互動核心：手指＝彈簧吸引子——按住把骰子「吸」過來（多指時每顆骰子
// 被最近的手指吸）、拖動跟手、放手繼承速度甩出去；螢幕邊界＝牆壁反彈、
// 骰子彼此碰撞，阻尼衰減到靜止＝結算合計。「擲骰子」鈕給不想甩的人
// （全部骰子隨機炸開）。
//
// 視覺是偽 3D：滾動中用透視矩陣翻轉骰面（滾越快翻越兇）＋快速換面，
// 靜止時回正平躺。點數由亂數決定，物理只決定「何時定格」——2D 物理
// 推不出真實骰面朝向，這是刻意的取捨。
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
  bool _settled = false; // 靜止且結算完（顯示合計）

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

    // 停止判定：沒手指、全員慢下來 → 結算
    final calm = _pointers.isEmpty && _world.isCalm;
    if (calm && !_settled && _world.hasBeenThrown) {
      _settled = true;
      playHaptic(HapticLevel.medium);
      setState(() {});
    } else if (!calm && _settled) {
      _settled = false;
      setState(() {});
    }
  }

  // 夠力的碰撞給觸覺＋偶爾一聲喀噠（節流，免得像鞭炮）
  void _handleImpact(double strength) {
    final now = DateTime.now();
    if (now.difference(_lastImpactFeedback).inMilliseconds < 110) return;
    _lastImpactFeedback = now;
    if (strength > 900) {
      playFeedback(SfxCue.gamePass, haptic: HapticLevel.light);
    } else {
      playHaptic(HapticLevel.selection);
    }
  }

  void _setCount(int delta) {
    final next = (_count + delta).clamp(1, maxDice);
    if (next == _count) return;
    playHaptic(HapticLevel.selection);
    setState(() {
      _count = next;
      _settled = false;
      _world.spawn(next);
    });
    _prefs?.setInt(PrefsKeys.gameTableDiceCount, next);
  }

  void _throwAll() {
    playFeedback(SfxCue.gamePass);
    _settled = false;
    _world.throwAll();
  }

  // ── 多指吸力 ─────────────────────────────────────────────

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _settled = false;
    playHaptic(HapticLevel.selection); // 「吸住了」
  }

  void _pointerMove(PointerMoveEvent e) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }
  }

  void _pointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) _world.markThrown(); // 放手＝這把開始滾
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
                      alignment: const Alignment(0, -0.55),
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _settled && _count > 1 ? 1 : 0,
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

// ── 物理 ───────────────────────────────────────────────────

class _Die {
  Offset pos;
  Offset vel = Offset.zero;
  double angle;
  double angVel = 0;
  int value;
  double rollAccum = 0; // 累積移動量，超過門檻就換面
  double wobble; // 偽 3D 翻滾相位

  _Die(this.pos, this.angle, this.value, this.wobble);

  double get speed => vel.distance;
}

/// 輕量 2D 剛體世界：彈簧吸力、牆壁反彈、等質量圓碰撞、阻尼。
/// 60fps Ticker 驅動，repaint 走 ChangeNotifier（painter 直接聽）。
class _DiceWorld extends ChangeNotifier {
  final _rng = math.Random();

  /// 物理牆（已扣掉上下 UI 區的內縮矩形；骰子不會滾到按鈕底下）。
  Rect bounds = Rect.zero;
  double dieSize = 80;
  List<_Die> dice = [];
  bool hasBeenThrown = false;

  void Function(double strength)? onImpact;

  // 手感參數（實機調校入口都在這）
  static const _springK = 34.0; // 吸力彈簧
  static const _springDamp = 7.5; // 吸力阻尼（防彈簧震盪）
  static const _linDamp = 1.4; // 自由滾動線性阻尼 /s
  static const _angDamp = 1.7; // 角阻尼 /s
  static const _restitution = 0.72; // 牆壁恢復係數
  static const _calmSpeed = 18.0;
  static const _calmSpin = 0.9;

  double get _radius => dieSize * 0.52;

  int get total => dice.fold(0, (sum, d) => sum + d.value);

  bool get isCalm =>
      dice.every((d) => d.speed < _calmSpeed && d.angVel.abs() < _calmSpin);

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
    final center = bounds == Rect.zero
        ? const Offset(200, 300)
        : bounds.center;
    dice = [
      for (var i = 0; i < count; i++)
        _Die(
          center +
              Offset(
                math.cos(i * math.pi * 2 / count) * dieSize * 1.1,
                math.sin(i * math.pi * 2 / count) * dieSize * 0.8,
              ),
          _rng.nextDouble() * 0.5 - 0.25,
          1 + _rng.nextInt(6),
          _rng.nextDouble() * math.pi * 2,
        ),
    ];
    notifyListeners();
  }

  void markThrown() => hasBeenThrown = true;

  /// 擲骰鈕：全員隨機炸開。
  void throwAll() {
    hasBeenThrown = true;
    for (final d in dice) {
      final a = _rng.nextDouble() * math.pi * 2;
      final power = 900 + _rng.nextDouble() * 900;
      d.vel += Offset(math.cos(a), math.sin(a)) * power;
      d.angVel += (_rng.nextBool() ? 1 : -1) * (8 + _rng.nextDouble() * 14);
    }
  }

  void step(double dt, List<Offset> pointers) {
    if (dice.isEmpty || dt <= 0) return;

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
        // 被拖著走也要滾起來
        d.angVel += (d.vel.dx.abs() + d.vel.dy.abs()) * dt * 0.004;
      } else {
        final lin = math.exp(-_linDamp * dt);
        d.vel *= lin;
        d.angVel *= math.exp(-_angDamp * dt);
      }

      d.pos += d.vel * dt;
      d.angle += d.angVel * dt;
      d.wobble += (d.speed * 0.012 + d.angVel.abs() * 0.9) * dt * 6;

      // 滾動換面：移動＋旋轉都累積，快就換得快
      d.rollAccum += d.speed * dt + d.angVel.abs() * dt * 60;
      if (d.rollAccum > 46 &&
          (d.speed > _calmSpeed * 2.2 || pointers.isNotEmpty)) {
        d.rollAccum = 0;
        d.value = 1 + _rng.nextInt(6);
      }

      _wallCollide(d);
    }

    _pairCollide();
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
      d.angVel = -d.angVel * 0.6 + d.vel.dy * 0.01;
    } else if (d.pos.dx > bounds.right - r && d.vel.dx > 0) {
      hit = d.vel.dx.abs();
      d.vel = Offset(-d.vel.dx * _restitution, d.vel.dy);
      d.angVel = -d.angVel * 0.6 - d.vel.dy * 0.01;
    }
    if (d.pos.dy < bounds.top + r && d.vel.dy < 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.angVel = -d.angVel * 0.6 - d.vel.dx * 0.01;
    } else if (d.pos.dy > bounds.bottom - r && d.vel.dy > 0) {
      hit = math.max(hit, d.vel.dy.abs());
      d.vel = Offset(d.vel.dx, -d.vel.dy * _restitution);
      d.angVel = -d.angVel * 0.6 + d.vel.dx * 0.01;
    }
    d.pos = _clampToBounds(d.pos);
    if (hit > 260) onImpact?.call(hit);
  }

  void _pairCollide() {
    final minDist = _radius * 2 * 0.92; // 視覺上留一點咬合
    for (var i = 0; i < dice.length; i++) {
      for (var j = i + 1; j < dice.length; j++) {
        final a = dice[i];
        final b = dice[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        if (dist >= minDist || dist == 0) continue;

        final n = delta / dist;
        // 位置分離（各退一半）
        final overlap = (minDist - dist) / 2;
        a.pos -= n * overlap;
        b.pos += n * overlap;

        // 等質量彈性碰撞：交換法線方向速度分量
        final rel = (b.vel - a.vel).dx * n.dx + (b.vel - a.vel).dy * n.dy;
        if (rel < 0) {
          final impulse = n * rel * _restitution;
          a.vel += impulse;
          b.vel -= impulse;
          // 撞一下都轉一點
          a.angVel += rel * 0.006;
          b.angVel -= rel * 0.006;
          if (rel.abs() > 260) onImpact?.call(rel.abs());
        }
      }
    }
  }
}

// ── 繪製 ───────────────────────────────────────────────────

/// 物理場畫家：每顆骰子帶偽 3D 翻滾（透視傾斜隨速度收斂）。
class _WorldPainter extends CustomPainter {
  final _DiceWorld world;

  _WorldPainter(this.world) : super(repaint: world);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in world.dice) {
      final tilt = math.min(1.0, (d.speed + d.angVel.abs() * 60) / 900);
      canvas.save();
      canvas.translate(d.pos.dx, d.pos.dy);
      if (tilt > 0.01) {
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateX(math.sin(d.wobble) * 1.05 * tilt)
          ..rotateY(math.cos(d.wobble * 1.31) * 1.05 * tilt);
        canvas.transform(m.storage);
      }
      canvas.rotate(d.angle);
      _paintDie(canvas, world.dieSize, d.value, tilt);
      canvas.restore();
    }
  }

  void _paintDie(Canvas canvas, double size, int value, double tilt) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size,
      height: size,
    );
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(size * 0.04),
      Radius.circular(size * 0.22),
    );

    // 貼地陰影：飛得越兇影子越散（一點高度感）
    canvas.drawRRect(
      rrect.shift(Offset(0, size * (0.05 + tilt * 0.06))),
      Paint()
        ..color = Color.fromARGB((89 * (1 - tilt * 0.4)).round(), 18, 11, 7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + tilt * 10),
    );

    // 骰身
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8EC), Color(0xFFE9DAC4)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.02
        ..color = const Color(0x33513A28),
    );

    // 點數
    final pip = Paint()..color = const Color(0xFF3C2D21);
    final o = size * 0.24;
    final r = size * 0.085;
    void dot(double dx, double dy) => canvas.drawCircle(Offset(dx, dy), r, pip);

    if (value.isOdd) dot(0, 0);
    if (value >= 2) {
      dot(-o, -o);
      dot(o, o);
    }
    if (value >= 4) {
      dot(o, -o);
      dot(-o, o);
    }
    if (value == 6) {
      dot(-o, 0);
      dot(o, 0);
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) => false; // repaint 由 world 通知
}
