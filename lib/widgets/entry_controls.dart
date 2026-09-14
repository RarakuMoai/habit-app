import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import 'app_pressable.dart';
import 'entry_loading_scene.dart';

/// Entry actions use the same press feedback and palette as the daily app.
class EntryPrimaryAction extends StatelessWidget {
  const EntryPrimaryAction({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    child: AppPressable(
      onPressed: onPressed,
      borderRadius: 20,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: onPressed == null ? AppSurfaces.fill : AppPalette.brand,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppSurfaces.card.withValues(alpha: .45)),
          boxShadow: onPressed == null
              ? const []
              : [
                  BoxShadow(
                    color: AppInk.strong.withValues(alpha: .13),
                    blurRadius: 20,
                    offset: const Offset(0, 7),
                  ),
                ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: onPressed == null ? AppInk.soft : AppSurfaces.card,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ),
    ),
  );
}

/// A paper-pattern curtain joins the two different scene cameras.
/// Other app navigation keeps the existing platform page transitions.
class EntryPageRoute<T> extends MaterialPageRoute<T> {
  EntryPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => EntrySceneMotion.route;

  @override
  Duration get reverseTransitionDuration => AppMotion.quick;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final mq = MediaQuery.of(context);
    if (mq.disableAnimations || mq.accessibleNavigation) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final cover = Curves.easeOut.transform((t / .35).clamp(0, 1));
        final reveal = Curves.easeInOutCubic.transform(
          ((t - .35) / .65).clamp(0, 1),
        );
        return IgnorePointer(
          ignoring: t < 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: t >= .35 ? 1 : 0, child: child),
              if (t < 1)
                Opacity(
                  opacity: cover,
                  child: ClipPath(
                    clipper: EntryPaperRevealClipper(reveal),
                    child: const EntryLoadingScene(
                      label: '',
                      showStatus: false,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
