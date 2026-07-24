// 兔咪面板控制元件。
//
// 設計目標：iOS bottom sheet 感
//   - 拖曳時兔咪區即時跟著手指（1:1，不是動畫補間）
//   - 放開時依速度+位置 spring 到最近狀態
//   - 點擊時用 AnimationController 順順動畫
//
// 對外 API：
//   [MascotToggleBar]：寬橫條 + 中央把手。
//   呼叫端組合 mascot 場景時，請用 [MascotPanelPrefs.openValue] 連續值
//   去決定場景高度（或 Positioned.top）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../utils/app_feedback.dart';
import '../utils/mascot.dart';

class MascotToggleBar extends StatefulWidget {
  final Color accent;
  // 拖曳時 1 像素對應 openValue 多少變化：傳入「兔咪場景的可拖距離」
  // 例如 home page 場景高 280px，傳 280 → 拖 280px 就完整切換。
  final double dragExtent;

  const MascotToggleBar({
    super.key,
    this.accent = const Color(0xFFFFA552),
    this.dragExtent = 220,
  });

  @override
  State<MascotToggleBar> createState() => _MascotToggleBarState();
}

class _MascotToggleBarState extends State<MascotToggleBar>
    with TickerProviderStateMixin {
  late final AnimationController _ctl;
  // 把手按下時的縮放
  late final AnimationController _pressCtl;
  late final Animation<double> _pressScale;

  // 進行中 spring 動畫的目標端點（沒有動畫時為 null）。頁面被切到背景、
  // TickerMode 凍結 _ctl 時用它把面板收斂到該去的端點。
  double? _animTarget;
  // 這一頁的 TickerMode 是否還在跑（= 是否為當前可見頁）。
  bool _ticking = true;

  // iOS spring 物理參數（接近系統 sheet）
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 26,
  );

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController.unbounded(vsync: this)
      ..value = MascotPanelPrefs.openValue.value
      ..addListener(() {
        // 把 controller 的值 clamp 後同步到 prefs notifier
        final v = _ctl.value.clamp(0.0, 1.0);
        if (MascotPanelPrefs.openValue.value != v) {
          MascotPanelPrefs.openValue.value = v;
        }
      });
    MascotPanelPrefs.settleRequest.addListener(_handleSettleRequest);
    _pressCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _pressScale = Tween<double>(
      begin: 1.0,
      end: 0.82,
    ).animate(CurvedAnimation(parent: _pressCtl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    MascotPanelPrefs.settleRequest.removeListener(_handleSettleRequest);
    _ctl.dispose();
    _pressCtl.dispose();
    super.dispose();
  }

  void _handleSettleRequest() {
    final request = MascotPanelPrefs.settleRequest.value;
    if (request == null) return;
    // 只有目前前景（ticking）的頁面負責跑 spring 並驅動共用的 openValue。
    // 背景頁若也 animateWith，會因 TickerMode 靜音把 sim 凍在半途，等被切回
    // 前景才解凍重播「收合→展開」——連點別的分頁時每頁各殘留一顆凍結 sim、
    // 每次切過去就重播一次。背景頁不用動：openValue 是全 app 共用真相，前景頁
    // 會把它帶到定位，這頁回前景時在 didChangeDependencies 直接同步即可。
    if (!_ticking) return;
    unawaited(_settleTo(request.target, markHintSeen: true, feedback: false));
  }

  void _onTapDown(TapDownDetails _) => _pressCtl.forward();
  void _onTapCancel() => _pressCtl.reverse();

  Future<void> _onTap() async {
    // 共用全域值才是真相：別頁（IndexedStack 保活）切換後可能已改過
    // openValue，而本頁 _ctl 沒跟上會過時，先對齊再決策避免反向跳動。
    _ctl.value = MascotPanelPrefs.openValue.value;
    final target = _ctl.value >= 0.5 ? 0.0 : 1.0;
    await _settleTo(target, markHintSeen: true, feedback: true);
  }

  void _onDragStart(DragStartDetails _) {
    unawaited(MascotPanelPrefs.markHintSeen());
    _ctl.stop();
    // 同上：拖曳起手前先對齊共用真相，避免從過時值起跳。
    _ctl.value = MascotPanelPrefs.openValue.value;
    _pressCtl.forward();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // dy 正值（往下）= 展開、負值（往上）= 收合
    final delta = d.delta.dy / widget.dragExtent;
    _ctl.value = (_ctl.value + delta).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    unawaited(_pressCtl.reverse());
    final velocityFraction = d.velocity.pixelsPerSecond.dy / widget.dragExtent;
    // 依速度決定目標：明顯往下→展開、往上→收合；速度小看位置
    final double target;
    if (velocityFraction > 1.5) {
      target = 1.0;
    } else if (velocityFraction < -1.5) {
      target = 0.0;
    } else {
      target = _ctl.value >= 0.5 ? 1.0 : 0.0;
    }
    await _settleTo(
      target,
      velocity: velocityFraction,
      markHintSeen: false,
      feedback: true,
    );
  }

  Future<void> _settleTo(
    double target, {
    double velocity = 0,
    required bool markHintSeen,
    required bool feedback,
  }) async {
    if (markHintSeen) unawaited(MascotPanelPrefs.markHintSeen());
    if (feedback) playHaptic(HapticLevel.light);
    _ctl.stop();
    _ctl.value = MascotPanelPrefs.openValue.value;
    unawaited(_pressCtl.reverse());
    await _animateToWithSpring(target, velocity: velocity);
  }

  Future<void> _animateToWithSpring(double target, {double velocity = 0}) {
    _animTarget = target;
    final sim = SpringSimulation(_spring, _ctl.value, target, velocity);
    return _ctl.animateWith(sim).whenComplete(() {
      // 正常跑完才清；被取消（whenComplete 不會觸發）或被新動畫覆蓋時不動它。
      if (_animTarget == target) _animTarget = null;
    });
  }

  @override
  void didChangeDependencies() {
    // 先讓 TickerProviderStateMixin 依 TickerMode 靜音/恢復 ticker。
    super.didChangeDependencies();
    final ticking = TickerMode.valuesOf(context).enabled;
    // 這一頁被切到背景：TickerMode 會凍結 _ctl 的 ticker，spring 動畫會卡在半途，
    // 而 openValue 是全 app 共用的真相 → 害每一頁的卡片都卡在一半（且動畫的
    // await 永遠不會完成）。若切走當下還在動畫中，直接把面板收斂到該去的端點。
    if (_ticking && !ticking && (_ctl.isAnimating || _animTarget != null)) {
      final target = _animTarget ?? (_ctl.value >= 0.5 ? 1.0 : 0.0);
      // 此刻正處於 build/依賴變更階段，直接改共用的 openValue 會動到正在 build
      // 的其他頁；延到 frame 結束再吸附（最多殘留一影格的半開，不會永久卡住）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ctl.value = target; // 同步 notify → openValue 收斂到端點、停掉 sim
        _animTarget = null;
      });
    } else if (!_ticking && ticking) {
      // 背景 → 前景：對齊共用真相並丟棄任何殘留 sim，避免被凍住的 spring
      // 一解凍就重播動畫（見 _handleSettleRequest）。設成相等值不會回寫 openValue。
      _ctl.stop();
      _animTarget = null;
      _ctl.value = MascotPanelPrefs.openValue.value;
    }
    _ticking = ticking;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: MascotPanelPrefs.openValue,
      builder: (_, v, _) => ValueListenableBuilder<bool>(
        valueListenable: MascotPanelPrefs.hintSeenValue,
        builder: (_, hintSeen, _) {
          final collapsed = v >= 0.5;
          final showHint = !hintSeen && collapsed;
          return GestureDetector(
            onTapDown: _onTapDown,
            onTapCancel: _onTapCancel,
            onTap: _onTap,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 40,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: -46,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: showHint ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: AnimatedSlide(
                          offset: showHint
                              ? Offset.zero
                              : const Offset(0, 0.15),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: _PanelHint(accent: widget.accent),
                        ),
                      ),
                    ),
                  ),
                  ScaleTransition(
                    scale: _pressScale,
                    child: _PanelHandle(accent: widget.accent, value: v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PanelHandle extends StatelessWidget {
  final Color accent;
  final double value;
  const _PanelHandle({required this.accent, required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 52,
      height: 7,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: value > 0.5 ? 0.35 : 0.6),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _PanelHint extends StatelessWidget {
  final Color accent;
  const _PanelHint({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            '上拉展開功能',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -0.5),
          child: CustomPaint(
            size: const Size(14, 7),
            painter: _BubbleTailPainter(
              fill: const Color(0xFFFFFDF9),
              stroke: accent.withValues(alpha: 0.18),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  const _BubbleTailPainter({required this.fill, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.fill != fill || old.stroke != stroke;
}
