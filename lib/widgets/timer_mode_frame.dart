import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import 'app_pressable.dart';
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

  /// 橫排版型左右兩槽之間的間距。
  static const double _sideGap = 16;

  /// 橫排版型主視覺槽佔內容寬（扣掉左右 inset 與間距）的比例。
  /// 左槽放主視覺、右槽放進度＋控制，各自置中，兩側視覺重量才平衡。
  static const double _heroSlotFraction = 0.46;

  /// 橫排版型右槽的設計高度：進度 + 間距 + 控制。
  static const double _sideColumnHeight =
      TimerModeMetrics.progressHeight + 10 + TimerModeMetrics.controlsHeight;

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

  /// 標頭通常置中、設定固定右側；英文或大字需要更寬設定鈕時，
  /// 改成狀態在左、設定在右，保留完整文字與互不重疊的操作區。
  Widget _header({bool showContent = true}) {
    if (!showContent) {
      return const SizedBox(height: TimerModeMetrics.statusHeight);
    }
    return SizedBox(
      key: const ValueKey('timer-mode-status-slot'),
      height: TimerModeMetrics.statusHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TimerModeMetrics.horizontalInset,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelPainter = TextPainter(
              text: TextSpan(
                text: AppLocalizations.of(context).timerSettingsEntry,
                style: DefaultTextStyle.of(context).style.merge(
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final sideReserve = topAction == null
                ? 0.0
                : math.max(88.0, labelPainter.width + 45);
            labelPainter.dispose();
            // 英文／大字設定鈕較寬時，標頭改為左右對齊；不把狀態文字擠成極小一點。
            final crowded = sideReserve > constraints.maxWidth / 3;
            final statusMaxWidth = math.max(
              0.0,
              constraints.maxWidth -
                  (crowded ? sideReserve + 8 : sideReserve * 2),
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: crowded ? Alignment.centerLeft : Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: statusMaxWidth),
                    child: FittedBox(fit: BoxFit.scaleDown, child: status),
                  ),
                ),
                if (topAction != null)
                  Align(alignment: Alignment.centerRight, child: topAction!),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 緊湊／超緊湊共用的橫排幾何。主視覺同時被「高度公式、左槽寬、
  /// 實際剩餘高」三者封頂，任何機型都不會把整行推到貼齊螢幕邊緣。
  ({
    double bodyTop,
    double bodyHeight,
    double heroSlotWidth,
    double heroSize,
    double rightWidth,
  })
  _sideBySideGeometry({
    required double width,
    required double height,
    required bool ultra,
  }) {
    final bodyTop = (ultra ? 0.0 : 8.0) + TimerModeMetrics.statusHeight + 4.0;
    final reservedBottom = !ultra && quickPicker != null
        ? TimerModeMetrics.quickPickerHeight + 12.0
        : 0.0;
    final bodyHeight = math.max(0.0, height - bodyTop - reservedBottom);
    final innerWidth = math.max(
      0.0,
      width - TimerModeMetrics.horizontalInset * 2,
    );
    final heroSlotWidth = math.max(
      0.0,
      (innerWidth - TimerModeFrame._sideGap) * _heroSlotFraction,
    );
    final heightCap = ultra
        ? bodyHeight.clamp(48.0, 150.0)
        : (height - compactHeightReserve).clamp(
            compactHeroMinSize,
            compactHeroMaxSize,
          );
    final heroSize = math.min(
      bodyHeight,
      math.max(48.0, math.min(heightCap, heroSlotWidth)),
    );
    final rightWidth = math.max(
      1.0,
      innerWidth - heroSlotWidth - TimerModeFrame._sideGap,
    );
    return (
      bodyTop: bodyTop,
      bodyHeight: bodyHeight,
      heroSlotWidth: heroSlotWidth,
      heroSize: heroSize,
      rightWidth: rightWidth,
    );
  }

  /// 橫排主體：左槽主視覺、右槽進度＋控制，各自置中。右槽以固定設計
  /// 尺寸排版，高度不足時整組等比縮小，不會溢位。
  Widget _sideBySideBody(
    BuildContext context, {
    required ({
      double bodyTop,
      double bodyHeight,
      double heroSlotWidth,
      double heroSize,
      double rightWidth,
    })
    geometry,
    bool showHero = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TimerModeMetrics.horizontalInset,
      ),
      child: Row(
        children: [
          SizedBox(
            width: geometry.heroSlotWidth,
            child: Center(
              child: showHero
                  ? heroBuilder(context, geometry.heroSize)
                  : SizedBox.square(dimension: geometry.heroSize),
            ),
          ),
          const SizedBox(width: TimerModeFrame._sideGap),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // 右槽以「真實右槽寬 × 設計高」為固定畫布：控制群拿到有界
                // 寬度自行決定緊湊尺寸；只有高度不足時整組才等比縮小。
                child: SizedBox(
                  width: geometry.rightWidth,
                  height: _sideColumnHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;
          if (height < ultraCompactBreakpoint) {
            return _ultraCompactLayout(context, width, height);
          }
          final t = Curves.easeInOutCubic.transform(
            _smoothRange(compactBreakpoint, fullBreakpoint, height),
          );
          if (t <= 0) return _compactLayout(context, width, height);
          if (t >= 1) return _fullLayout(context);
          return _blendLayouts(context, width, height, t);
        },
      ),
    );
  }

  Widget _fullLayout(
    BuildContext context, {
    bool showHero = true,
    bool showHeader = true,
  }) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _header(showContent: showHeader),
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
    );
  }

  Widget _compactLayout(
    BuildContext context,
    double width,
    double height, {
    bool showHero = true,
    bool showHeader = true,
  }) {
    final geometry = _sideBySideGeometry(
      width: width,
      height: height,
      ultra: false,
    );
    return Column(
      children: [
        const SizedBox(height: 8),
        _header(showContent: showHeader),
        const SizedBox(height: 4),
        Expanded(
          child: _sideBySideBody(
            context,
            geometry: geometry,
            showHero: showHero,
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
    );
  }

  Widget _ultraCompactLayout(
    BuildContext context,
    double width,
    double height,
  ) {
    final geometry = _sideBySideGeometry(
      width: width,
      height: height,
      ultra: true,
    );
    return Column(
      children: [
        _header(),
        const SizedBox(height: 4),
        Expanded(child: _sideBySideBody(context, geometry: geometry)),
      ],
    );
  }

  Widget _blendLayouts(
    BuildContext context,
    double width,
    double height,
    double t,
  ) {
    final fullHeight = math.max(height, fullBreakpoint);
    final compactGeometry = _sideBySideGeometry(
      width: width,
      height: height,
      ultra: false,
    );

    // 完整版主視覺的幾何（fullHeight 座標系）：跟 _fullLayout 的
    // Column 結構逐項對齊，t=1 時浮動主視覺與真實版面零位移接軌。
    const fullHeroTop =
        8.0 +
        TimerModeMetrics.statusHeight +
        6.0 +
        TimerModeMetrics.progressHeight;
    var fullHeroBottom = TimerModeMetrics.controlsHeight + 10.0;
    if (statusLine != null) {
      fullHeroBottom += 8.0 + TimerModeMetrics.statusLineHeight;
    }
    if (quickPicker != null) {
      fullHeroBottom += 8.0 + TimerModeMetrics.quickPickerHeight;
    }
    if (footer != null) fullHeroBottom += 12.0 + TimerModeMetrics.footerHeight;
    final fullExpanded = math.max(
      0.0,
      fullHeight - fullHeroTop - fullHeroBottom,
    );
    final fullSize = math.min(math.min(width, fullExpanded), fullHeroSize);

    final compactCenter = Offset(
      TimerModeMetrics.horizontalInset + compactGeometry.heroSlotWidth / 2,
      compactGeometry.bodyTop + compactGeometry.bodyHeight / 2,
    );
    final fullCenter = Offset(width / 2, fullHeroTop + fullExpanded / 2);
    final heroSize =
        compactGeometry.heroSize + (fullSize - compactGeometry.heroSize) * t;
    final heroCenter = Offset.lerp(compactCenter, fullCenter, t)!;
    // 錯開淡入淡出避免雙影，但保留少量重疊，拖曳中段內容不會整片真空。
    final compactOpacity = Curves.easeIn.transform(
      (1 - 1.6 * t).clamp(0.0, 1.0),
    );
    final fullOpacity = Curves.easeIn.transform(
      (1.6 * t - 0.6).clamp(0.0, 1.0),
    );

    return ClipRect(
      child: Stack(
        children: [
          if (compactOpacity > 0.01)
            Positioned.fill(
              child: Opacity(
                opacity: compactOpacity,
                child: _compactLayout(
                  context,
                  width,
                  height,
                  showHero: false,
                  showHeader: false,
                ),
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
                    child: _fullLayout(
                      context,
                      showHero: false,
                      showHeader: false,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(top: 8, left: 0, right: 0, child: _header()),
          Positioned(
            left: heroCenter.dx - heroSize / 2,
            top: heroCenter.dy - heroSize / 2,
            width: heroSize,
            height: heroSize,
            child: IgnorePointer(
              child: RepaintBoundary(child: heroBuilder(context, heroSize)),
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

/// 四種計時工具共用的深度設定入口。
///
/// 設定與開始／暫停／跳過等即時操作分層：固定在模式右上角，使用低彩度的
/// 次要膠囊，不跟中央主操作搶視覺焦點。
class TimerSettingsAction extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;

  const TimerSettingsAction({super.key, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.white.withValues(alpha: 0.90),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.24)),
        ),
        elevation: enabled ? 1 : 0,
        shadowColor: color.withValues(alpha: 0.20),
        child: InkWell(
          key: const ValueKey('timer-settings-action'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 16, color: color),
                const SizedBox(width: 5),
                Text(
                  AppLocalizations.of(context).timerSettingsEntry,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppInk.strong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: SizedBox(
        key: ValueKey(stateKey),
        width: TimerModeMetrics.statusWidth,
        height: 34,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.10)),
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
  final TimerSecondaryAction? leading;
  final TimerSecondaryAction? trailing;

  const TimerControlCluster({
    super.key,
    required this.accent,
    required this.primaryIcon,
    required this.onPrimary,
    this.primaryLabel,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actionLabel = primaryIcon == Icons.pause_rounded
        ? l10n.stgPause
        : primaryIcon == Icons.stop_rounded
        ? l10n.wdStop
        : l10n.notifStartFallback;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < 260;
        final primary = _PrimaryButton(
          accent: accent,
          icon: primaryIcon,
          label: actionLabel,
          detail: primaryLabel,
          onTap: onPrimary,
          compact: compact,
        );
        if (compact) {
          // 狹窄右槽不縮小整排控制。主操作獨佔一行，次操作各有 44pt 高。
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 52, width: double.infinity, child: primary),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (leading != null)
                    Expanded(
                      child: _SecondaryButton(action: leading!, compact: true),
                    ),
                  if (leading != null && trailing != null)
                    const SizedBox(width: 6),
                  if (trailing != null)
                    Expanded(
                      child: _SecondaryButton(action: trailing!, compact: true),
                    ),
                ],
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TimerModeMetrics.horizontalInset,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null)
                _SecondaryButton(action: leading!, compact: false),
              const SizedBox(width: 12),
              Flexible(child: SizedBox(width: 156, height: 64, child: primary)),
              const SizedBox(width: 12),
              if (trailing != null)
                _SecondaryButton(action: trailing!, compact: false),
            ],
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final bool compact;

  const _PrimaryButton({
    required this.accent,
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return _TimerPressSurface(
      onTap: onTap,
      color: accent,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: Icon(
                icon,
                key: ValueKey(icon),
                color: Colors.white,
                size: compact ? 24 : 28,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      maxLines: 1,
                      style: AppType.digits(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final TimerSecondaryAction action;
  final bool compact;

  const _SecondaryButton({required this.action, required this.compact});

  @override
  Widget build(BuildContext context) {
    final button = _TimerPressSurface(
      onTap: action.repeatable ? null : action.onTap,
      enabled: action.onTap != null,
      color: AppSurfaces.fill,
      radius: 16,
      child: SizedBox(
        width: compact ? null : 56,
        height: compact ? 44 : 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: AppInk.soft, size: compact ? 19 : 22),
            const SizedBox(height: 2),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: AppInk.soft,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: action.label,
      button: true,
      enabled: action.onTap != null,
      child: action.repeatable
          ? HoldRepeatButton(onTrigger: action.onTap, child: button)
          : button,
    );
  }
}

/// 按壓只改繪製，不縮減實際觸控區；降低動態仍保留 Material 底色回饋。
class _TimerPressSurface extends StatelessWidget {
  final VoidCallback? onTap;
  final bool? enabled;
  final Color color;
  final double radius;
  final Widget child;
  const _TimerPressSurface({
    this.onTap,
    this.enabled,
    required this.color,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: (enabled ?? onTap != null) ? 1 : 0.38,
    child: AppPressable(
      onPressed: onTap,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    ),
  );
}
