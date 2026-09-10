import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import 'app_pressable.dart';
import 'hold_repeat_button.dart';

typedef TimerHeroBuilder = Widget Function(BuildContext context, double size);

/// 共享留白與獨立窄控制列的最小高度；內容列依真實文字自然排版。
abstract final class TimerModeMetrics {
  static const double controlsHeight = 104;
  static const double horizontalInset = 18;
}

/// 計時以操作優先分三種資訊層級：極矮面板顯示時間摘要；房間旁有寬度時
/// 使用大面盤；功能展開後採單欄。收合優先顯示快捷設定，說明與統計接在後面；不縮小整組觸控區。
class TimerModeFrame extends StatelessWidget {
  final TimerHeroBuilder heroBuilder;
  final Widget? compactReadout;
  final Widget status;
  final Widget progress;
  final Widget controls;
  final Widget? quickPicker;
  final Widget? statusLine;
  final Widget? footer;
  final Widget? topAction;
  final EdgeInsets padding;
  final double fullHeroSize;

  const TimerModeFrame({
    super.key,
    required this.heroBuilder,
    required this.status,
    required this.progress,
    required this.controls,
    this.compactReadout,
    this.quickPicker,
    this.statusLine,
    this.footer,
    this.topAction,
    this.padding = EdgeInsets.zero,
    this.fullHeroSize = 232,
  });

  static const double summaryBreakpoint = 350;
  static const double roomMinHeight = 276;
  static const double roomBreakpoint = 420;

  Widget _slot(String name, Widget child) =>
      KeyedSubtree(key: ValueKey('timer-mode-$name-slot'), child: child);

  Widget _header() => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: TimerModeMetrics.horizontalInset,
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _slot('status', status),
          ),
        ),
        if (topAction != null) ...[const SizedBox(width: 12), topAction!],
      ],
    ),
  );

  Widget _details({bool includeQuickPicker = true}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (statusLine != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _slot(
            'status-line',
            DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              child: statusLine!,
            ),
          ),
        ),
      if (includeQuickPicker && quickPicker != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _slot('quick-picker', quickPicker!),
        ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _slot('footer', footer!),
        ),
      const SizedBox(height: 16),
    ],
  );

  Widget _summary(BuildContext context, TimerControlCluster actions) {
    final state = status;
    final compactStatus = state is TimerStatusPill
        ? TimerStatusPill(
            stateKey: state.stateKey,
            color: state.color,
            icon: state.icon,
            label: state.label,
            dense: compactReadout != null,
          )
        : state;
    final settings = topAction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TimerModeMetrics.horizontalInset,
          ),
          child: SizedBox(
            key: const ValueKey('timer-summary-stage'),
            height: 68,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ?compactReadout,
                      if (compactReadout != null) const SizedBox(height: 4),
                      _slot('status', compactStatus),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 124,
                  height: 60,
                  child: actions.primaryButton(context, showDetail: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TimerModeMetrics.horizontalInset,
          ),
          child: _slot(
            'controls',
            actions.secondaryActions(
              trailingAction: settings is TimerSettingsAction
                  ? TimerSettingsAction(
                      color: settings.color,
                      onTap: settings.onTap,
                      compact: true,
                    )
                  : settings,
            ),
          ),
        ),
        if (quickPicker != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _slot('quick-picker', quickPicker!),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _slot('progress', progress),
        ),
        _details(includeQuickPicker: false),
      ],
    );
  }

  Widget _room(
    BuildContext context,
    double height,
    TimerControlCluster actions,
  ) {
    // Give the header and shortcuts their natural height first. The stage uses
    // the remainder, so a 120pt jog picker gets a smaller illustration than a
    // 64pt focus picker without moving either set of controls offscreen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TimerModeMetrics.horizontalInset,
                  ),
                  child: LayoutBuilder(
                    builder: (context, stage) {
                      final heroSize = math.min(
                        stage.maxHeight,
                        stage.maxWidth - 172,
                      );
                      return Row(
                        children: [
                          SizedBox.square(
                            key: const ValueKey('timer-hero'),
                            dimension: heroSize,
                            child: heroBuilder(context, heroSize),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 52,
                                  width: double.infinity,
                                  child: actions.primaryButton(context),
                                ),
                                const SizedBox(height: 4),
                                _slot('controls', actions.secondaryActions()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (quickPicker != null) ...[
                const SizedBox(height: 4),
                _slot('quick-picker', quickPicker!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _slot('progress', progress),
        _details(includeQuickPicker: false),
      ],
    );
  }

  Widget _full(BuildContext context, double height, double width) {
    // 在 320pt 展開面板仍給至少 176pt 面盤。其餘資訊自然往下排列，
    // 空間不足就捲動，不能再用左右分槽把面盤封頂在 123pt。
    final heroSize = math.min(width - 64, height >= 480 ? fullHeroSize : 176.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        const SizedBox(height: 12),
        _slot('progress', progress),
        const SizedBox(height: 12),
        SizedBox.square(
          key: const ValueKey('timer-hero'),
          dimension: heroSize,
          child: heroBuilder(context, heroSize),
        ),
        const SizedBox(height: 12),
        _slot(
          'controls',
          SizedBox(
            height: controls is TimerControlCluster
                ? 72
                : TimerModeMetrics.controlsHeight,
            child: controls,
          ),
        ),
        _details(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = controls;
        final room =
            constraints.maxHeight >= roomMinHeight &&
            constraints.maxHeight < roomBreakpoint &&
            constraints.maxWidth >= 380 &&
            actions is TimerControlCluster;
        // 單欄的大面盤加操作需要約 350pt；中等寬度的矮面板也使用摘要，
        // 不能只照顧最窄 320pt，而讓 360pt 把開始按鈕擠到捲動區外。
        final summary =
            !room &&
            constraints.maxHeight < summaryBreakpoint &&
            actions is TimerControlCluster;
        return SingleChildScrollView(
          key: const ValueKey('timer-mode-scroll'),
          padding: EdgeInsets.only(top: summary || room ? 0 : 8, bottom: 4),
          child: summary
              ? _summary(context, actions)
              : room
              ? _room(context, constraints.maxHeight, actions)
              : _full(context, constraints.maxHeight, constraints.maxWidth),
        );
      },
    ),
  );
}

/// 極矮面板使用文字讀值，資訊與面盤相同，字級與觸控區不再跟剩餘高度縮小。
class TimerCompactReadout extends StatelessWidget {
  final String value;
  final Color color;
  final double fontSize;
  const TimerCompactReadout({
    super.key,
    required this.value,
    required this.color,
    this.fontSize = 28,
  });
  @override
  Widget build(BuildContext context) => Text(
    value,
    key: const ValueKey('timer-compact-readout'),
    maxLines: 1,
    softWrap: false,
    style: TextStyle(
      fontSize: fontSize,
      height: 1.0,
      fontWeight: FontWeight.w900,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// 四種計時工具共用的深度設定入口。
///
/// 設定與開始／暫停／跳過等即時操作分層：固定在模式右上角，使用低彩度的
/// 次要膠囊，不跟中央主操作搶視覺焦點。
class TimerSettingsAction extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;
  final bool compact;

  const TimerSettingsAction({
    super.key,
    required this.color,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return KeyedSubtree(
        key: const ValueKey('timer-settings-action'),
        child: _SecondaryButton(
          action: TimerSecondaryAction(
            icon: Icons.tune_rounded,
            label: AppLocalizations.of(context).timerSettingsEntry,
            onTap: onTap,
          ),
          compact: true,
        ),
      );
    }
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
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  final bool dense;

  const TimerStatusPill({
    super.key,
    required this.stateKey,
    required this.color,
    required this.icon,
    required this.label,
    this.dense = false,
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
        height: dense ? 20 : 44,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 12),
          decoration: BoxDecoration(
            color: dense ? Colors.transparent : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: dense
                ? null
                : Border.all(color: color.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisAlignment: dense
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 13 : 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: dense ? 11 : 13,
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

  Widget primaryButton(BuildContext context, {bool showDetail = true}) {
    final l10n = AppLocalizations.of(context);
    final label = primaryIcon == Icons.pause_rounded
        ? l10n.stgPause
        : primaryIcon == Icons.stop_rounded
        ? l10n.wdStop
        : l10n.notifStartFallback;
    return KeyedSubtree(
      key: const ValueKey('timer-primary-action'),
      child: _PrimaryButton(
        accent: accent,
        icon: primaryIcon,
        label: label,
        detail: showDetail ? primaryLabel : null,
        onTap: onPrimary,
        compact: false,
      ),
    );
  }

  Widget secondaryActions({Widget? trailingAction}) => Row(
    children: [
      if (leading != null)
        Expanded(child: _SecondaryButton(action: leading!, compact: true)),
      if (leading != null && trailing != null) const SizedBox(width: 8),
      if (trailing != null)
        Expanded(child: _SecondaryButton(action: trailing!, compact: true)),
      if (trailingAction != null) ...[
        const SizedBox(width: 8),
        Expanded(child: trailingAction),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 260) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 52,
              width: double.infinity,
              child: primaryButton(context),
            ),
            const SizedBox(height: 4),
            secondaryActions(),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TimerModeMetrics.horizontalInset,
        ),
        child: Row(
          children: [
            if (leading != null)
              _SecondaryButton(action: leading!, compact: false),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(height: 64, child: primaryButton(context)),
            ),
            const SizedBox(width: 12),
            if (trailing != null)
              _SecondaryButton(action: trailing!, compact: false),
          ],
        ),
      );
    },
  );
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
        width: compact ? null : 64,
        height: compact ? 48 : 64,
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
                fontSize: compact ? 11 : 12,
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
