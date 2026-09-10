import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// 保留原尺寸觸控區的輕按壓。不擁有業務回饋，音效與觸覺由事件呼叫端發出。
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.borderRadius = AppCardStyle.radius,
    this.semanticsLabel,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;
  final String? semanticsLabel;
  final bool? selected;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.semanticsLabel,
      selected: widget.selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          onTap: widget.onPressed,
          onHighlightChanged: _setPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppPalette.brand.withValues(alpha: 0.06),
          child: AnimatedScale(
            scale: _pressed && !reduced ? AppPressMotion.scale : 1,
            duration: reduced
                ? Duration.zero
                : _pressed
                ? AppPressMotion.down
                : AppPressMotion.release,
            curve: AppPressMotion.curve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 分頁回來時只展開目前頁面，保留 IndexedStack 的資料與捲動位置。
class AppPageReveal extends StatefulWidget {
  const AppPageReveal({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<AppPageReveal> createState() => _AppPageRevealState();
}

class _AppPageRevealState extends State<AppPageReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.settle,
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
  );

  @override
  void didUpdateWidget(covariant AppPageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        !oldWidget.active &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.55, end: 1.0).animate(_curve),
    child: widget.child,
  );
}
