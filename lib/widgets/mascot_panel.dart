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

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

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
    _pressCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _pressCtl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    _pressCtl.dispose();
    super.dispose();
  }

  // 落地到 prefs（拖曳/動畫結束才呼叫）
  Future<void> _persist() => MascotPanelPrefs.persist();

  void _onTapDown(TapDownDetails _) => _pressCtl.forward();
  void _onTapCancel() => _pressCtl.reverse();

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    final target = _ctl.value >= 0.5 ? 0.0 : 1.0;
    _pressCtl.reverse();
    await _animateToWithSpring(target, velocity: 0);
    await _persist();
  }

  void _onDragStart(DragStartDetails _) {
    _ctl.stop();
    _pressCtl.forward();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // dy 正值（往下）= 展開、負值（往上）= 收合
    final delta = d.delta.dy / widget.dragExtent;
    _ctl.value = (_ctl.value + delta).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    _pressCtl.reverse();
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
    HapticFeedback.lightImpact();
    await _animateToWithSpring(target, velocity: velocityFraction);
    await _persist();
  }

  Future<void> _animateToWithSpring(double target, {double velocity = 0}) {
    final sim = SpringSimulation(_spring, _ctl.value, target, velocity);
    return _ctl.animateWith(sim);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: MascotPanelPrefs.openValue,
      builder: (_, v, _) => GestureDetector(
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
          child: Center(
            child: ScaleTransition(
              scale: _pressScale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 52,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(
                    alpha: v > 0.5 ? 0.35 : 0.6,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
