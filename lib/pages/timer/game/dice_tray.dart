// 骰盤：全螢幕物理場擲骰（不打斷計時）。物理引擎在 dice_world.dart。
//
// 互動核心：手指＝彈簧吸引子——按住把骰子「吸」過來（多指時每顆骰子
// 被最近的手指吸）、拖動跟手、放手繼承速度甩出去；螢幕邊界＝牆壁反彈、
// 骰子彼此碰撞，阻尼衰減到靜止＝結算合計。
//
// 視覺是「真 3D」：每顆骰子是軟體渲染的圓角立方體（8 頂點 6 面、透視
// 投影、背面剔除、面光照），姿態用四元數＋3D 角速度積分，移動時沿
// 滾動軸自然翻滾。減速時「復位力矩」把骰子物理性地轉倒在最近的面上
//（立方體 24 個軸對齊方向），「哪面朝上就是幾點」——點數完全由物理
// 決定，不用亂數換面。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/prefs_keys.dart';
import '../../../utils/sfx_service.dart';
import 'dice_world.dart';
import 'table_timer_theme.dart';

/// 兔咪骰子屋：不開對局、只想骰骰子時的獨立全螢幕頁
/// （入口卡「只骰骰子」直達）。底層與正式對局共用家庭遊戲桌，
/// overlay 再鋪深色霧面，保留骰盤對比與操作辨識度。
class DiceTrayPage extends StatelessWidget {
  const DiceTrayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TableTheme.feltEdge,
      body: DecoratedBox(
        decoration: TableTheme.feltBackground(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: Image(
                image: AssetImage(TableTheme.tableAsset),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            DiceTrayOverlay(onClose: () => Navigator.of(context).maybePop()),
          ],
        ),
      ),
    );
  }
}

class DiceTrayOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const DiceTrayOverlay({super.key, required this.onClose});

  @override
  State<DiceTrayOverlay> createState() => _DiceTrayOverlayState();
}

class _DiceTrayOverlayState extends State<DiceTrayOverlay>
    with SingleTickerProviderStateMixin {
  static const int maxDice = 6;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  final _world = DiceWorld();
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
  void _handleImpact(double strength) {
    final now = DateTime.now();
    if (now.difference(_lastImpactFeedback).inMilliseconds < 90) return;
    _lastImpactFeedback = now;
    unawaited(
      SfxService.instance.play(
        SfxCue.gameDice,
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
    playFeedback(SfxCue.gameDice);
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
      playFeedback(SfxCue.gameDice, haptic: HapticLevel.medium);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        // 家庭桌仍要讀得出來，只做足以讓骰子與白字浮起的柔焦／壓暗；
        // 原本 70% 深色絨布遮罩會把新版 CG 幾乎整張吃掉。
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: ColoredBox(
          color: const Color(0x991A120C),
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
                      painter: DiceWorldPainter(_world),
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
                              _l10n.dtTotal(_world.total),
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
                            Text(
                              _l10n.dtHint,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: TableTheme.inkFaint,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onClose,
                              child: Text(
                                _l10n.dtCollapse,
                                style: const TextStyle(
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
            _l10n.dtDiceCount(_count),
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
        child: SizedBox(
          width: 200,
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.casino_rounded,
                size: 24,
                color: Color(0xFF241A12),
              ),
              const SizedBox(width: 8),
              Text(
                _l10n.dtRoll,
                style: const TextStyle(
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

/// 物理場畫家：軟體渲染「圓角」立方體——照真骰子畫：
/// 稜與角帶弧度（內縮立方體 ⊕ 球的 Minkowski 輪廓）、平面部分內縮、
/// 透視投影＋背面剔除＋面光照；台式細節：1 點紅色大點、4 點紅色。
/// 公開給骰盤以外的重用場（兔咪骰子對決彩蛋 widgets/dice_duel_panel.dart）。
class DiceWorldPainter extends CustomPainter {
  final DiceWorld world;

  DiceWorldPainter(this.world) : super(repaint: world);

  /// 稜/角圓弧佔半邊長的比例（0.2 ≈ 一般桌遊骰的圓潤度）。
  static const _bevel = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in world.dice) {
      _paintDie(canvas, d);
    }
  }

  void _paintDie(Canvas canvas, Die d) {
    // 離手/擲出瞬間 pop 放大一下（出手回饋）
    final h = world.dieSize * 0.40 * (1 + 0.14 * d.popT);
    final persp = h * 7.5; // 相機距離（弱透視）
    final energy = math.min(1.0, (d.speed + d.spin * 55) / 850);
    // 動態視角：靜止＝0 傾角（平面正對、乾淨讀數），被吸住/甩動時
    // 前傾展現立體——「靜止像 2D、動起來才 3D」
    final viewQ = d.tiltT < 0.01
        ? d.q
        : DiceQuat.axisAngle(1, 0, 0, -0.34 * d.tiltT) * d.q;

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

    // 圓角機身：真骰子＝內縮立方體 ⊕ 球（Minkowski）。輪廓取內縮
    // ±a 的 8 頂點凸包，再用圓 join/cap 的粗描邊往外長 rEdge——
    // 正好就是稜帶圓弧、角帶球面的骰子形
    final a = h * (1 - _bevel); // 平面部分半寬
    final rEdge = h * _bevel; // 稜/角圓弧半徑
    final corners = <Offset>[];
    for (var i = 0; i < 8; i++) {
      final (x, y, z) = viewQ.rotate(
        (i & 1) == 0 ? -a : a,
        (i & 2) == 0 ? -a : a,
        (i & 4) == 0 ? -a : a,
      );
      corners.add(project(x, y, z));
    }
    final hullPath = Path()..addPolygon(_hull(corners), true);
    // 機身沿光源方向由亮到暗：弧面「包著光」的漸層質感
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6E9D2), Color(0xFF977C5F)],
      ).createShader(Rect.fromCircle(center: d.pos, radius: h * 1.55));
    canvas.drawPath(hullPath, bodyPaint);
    canvas.drawPath(
      hullPath,
      bodyPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = rEdge * 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 光源：左上偏前
    const lx = -0.38, ly = -0.53, lz = 0.76;

    // 只畫朝向相機的面（凸體不互遮，免排序）。剔除門檻抬高：
    // 幾乎側對的面只剩一條細縫，畫了反而是落定前的邊緣破圖
    for (final f in DieGeometry.faces) {
      final (nx, ny, nz) = viewQ.rotate(f.nx, f.ny, f.nz);
      if (nz <= 0.06) continue;

      final (t1x, t1y, t1z) = viewQ.rotate(f.t1x, f.t1y, f.t1z);
      final (t2x, t2y, t2z) = viewQ.rotate(f.t2x, f.t2y, f.t2z);

      // 平面部分：中心離骰心 h（=a+rEdge），四角只到 ±a——
      // 面外圈那一圈機身漸層就是看得到的圓稜倒角
      final cx = nx * h, cy = ny * h, cz = nz * h;
      Offset corner(double su, double sv) => project(
        cx + (t1x * su + t2x * sv) * a,
        cy + (t1y * su + t2y * sv) * a,
        cz + (t1z * su + t2z * sv) * a,
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

      final facePaint = Paint()..color = faceColor;
      canvas.drawPath(path, facePaint);
      // 圓 join 描邊把面的四角磨圓，面與圓稜的接縫柔化不見稜線；
      // 側得越厲害描邊越細，避免斜面被描邊撐出鼓包
      canvas.drawPath(
        path,
        facePaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.10 * math.min(1.0, nz * 2.2)
          ..strokeJoin = StrokeJoin.round,
      );

      // pip：畫「面上的圓盤」——以面切向量的螢幕投影當基底做
      // 仿射變換，斜視角下自然壓成橢圓、貼面不會凸出稜線。
      // 台式骰子細節：1 點紅色大點、4 點紅色，其餘深棕
      final red = f.value == 1 || f.value == 4;
      final pipPaint = Paint()
        ..color = red
            ? Color.lerp(
                const Color(0xFFC4402F),
                const Color(0xFF8C2B21),
                1 - bright,
              )!
            : Color.lerp(
                const Color(0xFF241A12),
                const Color(0xFF4A382A),
                1 - bright,
              )!;
      // 凹窩：偏一側的較亮內圓，留一彎深色月牙＝鑽孔漆點的立體感
      final pipInner = Paint()
        ..color = Color.lerp(pipPaint.color, faceColor, 0.18)!;
      final pipR = h * (f.value == 1 ? 0.30 : 0.18);
      final e1 = Offset(t1x, t1y) * pipR; // 螢幕空間基向量（弱透視近似）
      final e2 = Offset(t2x, t2y) * pipR;
      for (final p in DieGeometry.pips[f.value]!) {
        final u = p.dx * 0.9, v = p.dy * 0.9;
        final pos = project(
          cx + (t1x * u + t2x * v) * a,
          cy + (t1y * u + t2y * v) * a,
          cz + (t1z * u + t2z * v) * a,
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
        canvas.drawCircle(const Offset(0.13, 0.13), 0.8, pipInner);
        canvas.restore();
      }
    }
  }

  /// 投影頂點的 2D 凸包（單調鏈；只有 8 點，成本可忽略）。
  static List<Offset> _hull(List<Offset> pts) {
    pts.sort(
      (p, q) => p.dx == q.dx ? p.dy.compareTo(q.dy) : p.dx.compareTo(q.dx),
    );
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lo = <Offset>[];
    for (final p in pts) {
      while (lo.length >= 2 && cross(lo[lo.length - 2], lo.last, p) <= 0) {
        lo.removeLast();
      }
      lo.add(p);
    }
    final hi = <Offset>[];
    for (final p in pts.reversed) {
      while (hi.length >= 2 && cross(hi[hi.length - 2], hi.last, p) <= 0) {
        hi.removeLast();
      }
      hi.add(p);
    }
    lo.removeLast();
    hi.removeLast();
    return lo..addAll(hi);
  }

  @override
  bool shouldRepaint(DiceWorldPainter old) => false; // repaint 由 world 通知
}
