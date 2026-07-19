import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import 'hold_repeat_button.dart';

typedef TimerHeroBuilder = Widget Function(BuildContext context, double size);

/// 四種計時模式共用的光學尺寸。頁面只提供內容，不再自行決定每個區塊高度。
abstract final class TimerModeMetrics {
  static const double statusHeight = 36;
  static const double statusWidth = 132;
  static const double progressHeight = 18;
  static const double controlsHeight = 104;
  static const double statusLineHeight = 18;
  static const double quickPickerHeight = 56;
  static const double footerHeight = 50;
  static const double horizontalInset = 18;
}

/// 計時分頁各工具共用的版型骨架。
///
/// 完整、緊湊與超緊湊三種狀態都維持相同資訊順序；模式只注入自己的
/// 核心主視覺、狀態、控制與快速設定。高度介於兩端時，主視覺保持單一實例
/// 滑動縮放，周邊內容錯開淡入淡出，避免雙影與瞬移。
class TimerModeFrame extends StatelessWidget {
  final TimerHeroBuilder heroBuilder;
  final Widget status;
  final Widget progress;
  final Widget controls;
  final Widget? quickPicker;
  final Widget? statusLine;
  final Widget? footer;
  final Widget? topAction;
  final EdgeInsets padding;
  final double fullHeroSize;
  final double compactHeroMinSize;
  final double compactHeroMaxSize;
  final double compactHeightReserve;

  const TimerModeFrame({
    super.key,
    required this.heroBuilder,
    required this.status,
    required this.progress,
    required this.controls,
    this.quickPicker,
    this.statusLine,
    this.footer,
    this.topAction,
    this.padding = EdgeInsets.zero,
    this.fullHeroSize = 246,
    this.compactHeroMinSize = 110,
    this.compactHeroMaxSize = 170,
    this.compactHeightReserve = 110,
  });

  static const double compactBreakpoint = 390;
  static const double fullBreakpoint = 520;
  static const double ultraCompactBreakpoint = 230;

  static const Alignment _fullHeroAlignment = Alignment(0, -0.32);
  static const Alignment _compactHeroAlignment = Alignment(-0.46, -0.16);

  Widget _slot({
    required String name,
    required double height,
    required Widget child,
    bool scaleDown = false,
  }) {
    final aligned = Align(
      child: scaleDown ? FittedBox(fit: BoxFit.scaleDown, child: child) : child,
    );
    return SizedBox(
      key: ValueKey('timer-mode-$name-slot'),
      height: height,
      child: aligned,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          if (height < ultraCompactBreakpoint) {
            return _ultraCompactLayout(context, height, constraints.maxWidth);
          }
          final t = Curves.easeInOutCubic.transform(
            _smoothRange(compactBreakpoint, fullBreakpoint, height),
          );
          if (t <= 0) return _compactLayout(context, height);
          if (t >= 1) return _fullLayout(context);
          return _blendLayouts(context, height, t);
        },
      ),
    );
  }

  Widget _fullLayout(BuildContext context, {bool showHero = true}) {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            _slot(
              name: 'status',
              height: TimerModeMetrics.statusHeight,
              child: status,
            ),
            const SizedBox(height: 6),
            _slot(
              name: 'progress',
              height: TimerModeMetrics.progressHeight,
              child: progress,
              scaleDown: true,
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math.min(
                      math.min(constraints.maxWidth, constraints.maxHeight),
                      fullHeroSize,
                    );
                    return showHero
                        ? heroBuilder(context, size)
                        : SizedBox.square(dimension: size);
                  },
                ),
              ),
            ),
            _slot(
              name: 'controls',
              height: TimerModeMetrics.controlsHeight,
              child: controls,
            ),
            if (statusLine != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TimerModeMetrics.horizontalInset,
                ),
                child: _slot(
                  name: 'status-line',
                  height: TimerModeMetrics.statusLineHeight,
                  child: statusLine!,
                  scaleDown: true,
                ),
              ),
            ],
            if (quickPicker != null) ...[
              const SizedBox(height: 8),
              _slot(
                name: 'quick-picker',
                height: TimerModeMetrics.quickPickerHeight,
                child: quickPicker!,
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 12),
              _slot(
                name: 'footer',
                height: TimerModeMetrics.footerHeight,
                child: footer!,
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
        if (topAction != null)
          Positioned(
            top: 0,
            right: TimerModeMetrics.horizontalInset,
            child: topAction!,
          ),
      ],
    );
  }

  Widget _compactLayout(
    BuildContext context,
    double height, {
    bool showHero = true,
  }) {
    final heroSize = (height - compactHeightReserve).clamp(
      compactHeroMinSize,
      compactHeroMaxSize,
    );
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  showHero
                      ? heroBuilder(context, heroSize)
                      : SizedBox.square(dimension: heroSize),
                  const SizedBox(width: 22),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _slot(
                            name: 'status',
                            height: TimerModeMetrics.statusHeight,
                            child: status,
                          ),
                          const SizedBox(height: 6),
                          _slot(
                            name: 'progress',
                            height: TimerModeMetrics.progressHeight,
                            child: progress,
                            scaleDown: true,
                          ),
                          const SizedBox(height: 10),
                          _slot(
                            name: 'controls',
                            height: TimerModeMetrics.controlsHeight,
                            child: controls,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (quickPicker != null) ...[
              _slot(
                name: 'quick-picker',
                height: TimerModeMetrics.quickPickerHeight,
                child: quickPicker!,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
        if (topAction != null)
          Positioned(
            top: 0,
            right: TimerModeMetrics.horizontalInset,
            child: topAction!,
          ),
      ],
    );
  }

  Widget _ultraCompactLayout(
    BuildContext context,
    double height,
    double width,
  ) {
    final heroSize = (height - 12).clamp(80.0, 150.0);
    final controlsWidth = math.max(0.0, width - heroSize - 18);
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          heroBuilder(context, heroSize),
          const SizedBox(width: 18),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: controlsWidth,
              maxHeight: height,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _slot(
                    name: 'status',
                    height: TimerModeMetrics.statusHeight,
                    child: status,
                  ),
                  const SizedBox(height: 6),
                  _slot(
                    name: 'progress',
                    height: TimerModeMetrics.progressHeight,
                    child: progress,
                    scaleDown: true,
                  ),
                  const SizedBox(height: 8),
                  _slot(
                    name: 'controls',
                    height: TimerModeMetrics.controlsHeight,
                    child: controls,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blendLayouts(BuildContext context, double height, double t) {
    final fullHeight = math.max(height, fullBreakpoint);
    final compactSize = (height - compactHeightReserve).clamp(
      compactHeroMinSize,
      compactHeroMaxSize,
    );
    final heroSize = compactSize + (fullHeroSize - compactSize) * t;
    final heroAlignment = Alignment.lerp(
      _compactHeroAlignment,
      _fullHeroAlignment,
      t,
    )!;
    final compactOpacity = Curves.easeIn.transform((1 - 2 * t).clamp(0.0, 1.0));
    final fullOpacity = Curves.easeIn.transform((2 * t - 1).clamp(0.0, 1.0));

    return ClipRect(
      child: Stack(
        children: [
          if (compactOpacity > 0.01)
            Positioned.fill(
              child: Opacity(
                opacity: compactOpacity,
                child: _compactLayout(context, height, showHero: false),
              ),
            ),
          if (fullOpacity > 0.01)
            Positioned.fill(
              child: Opacity(
                opacity: fullOpacity,
                child: OverflowBox(
                  minHeight: fullHeight,
                  maxHeight: fullHeight,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: fullHeight,
                    child: _fullLayout(context, showHero: false),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Align(
                  alignment: heroAlignment,
                  child: heroBuilder(context, heroSize),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _smoothRange(double start, double end, double value) {
    final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// 各模式共用的狀態膠囊；只由模式提供圖示、文字與主色。
class TimerStatusPill extends StatelessWidget {
  final Object stateKey;
  final Color color;
  final IconData icon;
  final String label;

  const TimerStatusPill({
    super.key,
    required this.stateKey,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: SizedBox(
        key: ValueKey(stateKey),
        width: TimerModeMetrics.statusWidth,
        height: 34,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimerSecondaryAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 步進調整用：點按一次，長按會連續觸發。
  final bool repeatable;

  const TimerSecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.repeatable = false,
  });
}

/// 倒數型模式共用的「次操作／主操作／次操作」控制列。
class TimerControlCluster extends StatelessWidget {
  final Color accent;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final TimerSecondaryAction leading;
  final TimerSecondaryAction trailing;

  const TimerControlCluster({
    super.key,
    required this.accent,
    required this.primaryIcon,
    required this.onPrimary,
    this.primaryLabel,
    required this.leading,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 260;
        final sideSize = compact ? 44.0 : 54.0;
        final primarySize = compact ? 62.0 : 78.0;
        final gap = compact ? 16.0 : 24.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SecondaryButton(action: leading, size: sideSize),
            SizedBox(width: gap),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PrimaryButton(
                  accent: accent,
                  icon: primaryIcon,
                  onTap: onPrimary,
                  size: primarySize,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  child: primaryLabel == null
                      ? null
                      : Text(
                          primaryLabel!,
                          style: AppType.digits(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppInk.soft,
                          ),
                        ),
                ),
              ],
            ),
            SizedBox(width: gap),
            _SecondaryButton(action: trailing, size: sideSize),
          ],
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const _PrimaryButton({
    required this.accent,
    required this.icon,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: accent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: Colors.white,
                    size: size * 0.5,
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

class _SecondaryButton extends StatelessWidget {
  final TimerSecondaryAction action;
  final double size;

  const _SecondaryButton({required this.action, required this.size});

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.fromBorderSide(AppCardStyle.hairline.top),
        boxShadow: AppShadows.flat,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: action.repeatable ? null : action.onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: size,
            child: Icon(action.icon, color: AppInk.soft, size: size * 0.42),
          ),
        ),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.repeatable)
            HoldRepeatButton(onTrigger: action.onTap, child: button)
          else
            button,
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Text(
              action.label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
