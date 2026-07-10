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

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_feedback.dart';
import '../../../utils/app_style.dart';
import '../../../utils/prefs_keys.dart';
import '../../../utils/sfx_service.dart';
import 'dice_world.dart';

/// 可從其他入口直接 push 的全螢幕骰子屋。
///
/// 桌遊對局內仍使用 [DiceTrayOverlay] 疊在進行中的計時器上；需要單獨使用骰子
/// 時則 push 這個頁面，兩個入口共用完全相同的物理與 UI。
class DiceTrayPage extends StatelessWidget {
  const DiceTrayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DiceTrayColors.cream,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_DiceTrayColors.cream, _DiceTrayColors.peachWash],
              ),
            ),
          ),
          DiceTrayOverlay(
            onClose: () {
              unawaited(Navigator.of(context).maybePop());
            },
          ),
        ],
      ),
    );
  }
}

abstract final class _DiceTrayColors {
  static const cream = Color(0xFFFFFAF2);
  static const peachWash = Color(0xFFF9E5D2);
  static const peach = Color(0xFFFFDCC5);
  static const coral = Color(0xFFC95A43);
  static const amber = Color(0xFFF0AE45);
  static const matTop = Color(0xFFFFE8C9);
  static const matBottom = Color(0xFFF1C99E);
  static const matBorder = Color(0xFFE5B987);
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
    // prefs 還沒載完也先有兩顆骰子，release 冷啟動第一下就能操作。
    _world.spawn(_count);
    // 初始骰面是靜態的；真的擲骰或抓骰子時才啟動逐幀物理。
    _ticker = createTicker(_onTick);
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
      _ticker.stop(); // 靜止後不再每幀喚醒 CPU；下一次互動再啟動。
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
      _showTotal = false;
      _world.spawn(next);
    });
    _prefs?.setInt(PrefsKeys.gameTableDiceCount, next);
  }

  void _throwAll() {
    if (_world.dice.isEmpty) return;
    _ensureTicker();
    setState(() => _showTotal = false);
    playFeedback(SfxCue.gameDice);
    _world.throwAll();
  }

  // ── 多指吸力 ─────────────────────────────────────────────

  void _pointerDown(PointerDownEvent e) {
    _ensureTicker();
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

  void _ensureTicker() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // 背景已有 97% 不透明漸層，拿掉全螢幕 blur 可明顯降低舊手機 GPU 負擔。
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF7FFFAF2), Color(0xF7F9E5D2)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                _header(),
                const SizedBox(height: 10),
                _countPanel(),
                const SizedBox(height: 10),
                Expanded(child: _playMat()),
                const SizedBox(height: 10),
                _bottomPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double dieSizeFor(int count) =>
      count <= 2 ? 92.0 : (count <= 4 ? 80.0 : 70.0);

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppSurfaces.card,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppSurfaces.divider),
                  boxShadow: AppShadows.flat,
                ),
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/icon/tabs/game_timer.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: const Text(
                    '兔咪骰子屋',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppInk.strong,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: '關閉骰子屋，回到遊戲',
          child: Semantics(
            button: true,
            label: '回到遊戲，關閉骰子屋',
            child: Material(
              color: AppSurfaces.card,
              shape: StadiumBorder(
                side: BorderSide(
                  color: _DiceTrayColors.coral.withValues(alpha: 0.28),
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: widget.onClose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: _DiceTrayColors.coral,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '回到遊戲',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: AppInk.strong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _countPanel() {
    return Semantics(
      container: true,
      label: '骰子顆數，目前 $_count 顆',
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: AppSurfaces.card.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppSurfaces.divider),
          boxShadow: AppShadows.flat,
        ),
        child: Row(
          children: [
            _countButton(
              icon: Icons.remove_rounded,
              label: '減少一顆骰子',
              enabled: _count > 1,
              onTap: () => _setCount(-1),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$_count 顆骰子',
                      maxLines: 1,
                      style: AppType.digits(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: AppInk.strong,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _countButton(
              icon: Icons.add_rounded,
              label: '增加一顆骰子',
              enabled: _count < maxDice,
              onTap: () => _setCount(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: enabled ? _DiceTrayColors.peach : AppSurfaces.fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox.square(
              dimension: 56,
              child: Icon(
                icon,
                size: 28,
                color: enabled ? _DiceTrayColors.coral : AppInk.iconFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playMat() {
    return LayoutBuilder(
      builder: (context, box) {
        // 控制列已移出物理場，指標與邊界都改用骰盤自己的座標；保留上方結果卡
        // 的呼吸空間，骰子不會滾到合計數字下面。
        final topInset = box.maxHeight >= 210 ? 72.0 : 10.0;
        _world.setBounds(
          Rect.fromLTRB(
            10,
            topInset,
            math.max(10.0, box.maxWidth - 10),
            math.max(topInset + 1, box.maxHeight - 10),
          ),
          dieSizeFor(_count),
        );

        return Semantics(
          container: true,
          label: '骰子遊戲區。可以按住骰子移動，放開手指甩出去。',
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_DiceTrayColors.matTop, _DiceTrayColors.matBottom],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _DiceTrayColors.matBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8D6E63).withValues(alpha: 0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -32,
                  top: -38,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
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
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: IgnorePointer(child: _totalCard()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _totalCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: !_showTotal
          ? const SizedBox.shrink(key: ValueKey('no-total'))
          : Semantics(
              key: ValueKey('total-${_world.total}'),
              container: true,
              liveRegion: true,
              label: '本次合計 ${_world.total} 點',
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppSurfaces.card.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _DiceTrayColors.amber.withValues(alpha: 0.55),
                    ),
                    boxShadow: AppShadows.card,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '本次合計',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppInk.soft,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_world.total}',
                          style: AppType.digits(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: _DiceTrayColors.coral,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '點',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppInk.soft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _bottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: AppSurfaces.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppSurfaces.divider),
        boxShadow: AppShadows.flat,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _throwButton(),
          const SizedBox(height: 7),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 18,
                color: _DiceTrayColors.coral,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  '想自己動手？按住骰子再甩出去！',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: AppInk.soft,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _throwButton() {
    final label = _world.hasBeenThrown ? '再骰一次' : '擲骰子';
    return Tooltip(
      message: '$label，擲出 $_count 顆骰子',
      child: Semantics(
        button: true,
        enabled: _world.dice.isNotEmpty,
        label: '$label，$_count 顆骰子',
        hint: '啟用按鈕開始擲骰',
        child: Material(
          color: _DiceTrayColors.coral,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _world.dice.isEmpty ? null : _throwAll,
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.casino_rounded,
                        size: 27,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 物理場畫家：軟體渲染「圓角」立方體——照真骰子畫：
/// 稜與角帶弧度（內縮立方體 ⊕ 球的 Minkowski 輪廓）、平面部分內縮、
/// 透視投影＋背面剔除＋面光照；台式細節：1 點紅色大點、4 點紅色。
class _WorldPainter extends CustomPainter {
  final DiceWorld world;

  _WorldPainter(this.world) : super(repaint: world);

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
  bool shouldRepaint(_WorldPainter old) => false; // repaint 由 world 通知
}
