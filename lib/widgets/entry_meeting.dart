import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import 'entry_controls.dart';
import 'entry_scenery.dart';

/// Presentation only: OnboardingPage retains progression, saving and skip.
class EntryMeeting extends StatelessWidget {
  const EntryMeeting({
    super.key,
    required this.text,
    required this.last,
    required this.ready,
    required this.failed,
    required this.busy,
    required this.onNext,
    required this.onSkip,
    required this.onRetry,
  });
  final String text;
  final bool last, ready, failed, busy;
  final VoidCallback onNext, onSkip, onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final dialogue = Text(
      ready ? text : l.commonLoading,
      key: ValueKey('entry-meeting-${last ? 'together' : 'hello'}'),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.55),
    );
    return Scaffold(
      key: const ValueKey('onboarding-story'),
      backgroundColor: AppSurfaces.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const EntryScenery(),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: TextButton(
                      key: const ValueKey('onboarding-skip'),
                      style: TextButton.styleFrom(
                        backgroundColor: AppSurfaces.card.withValues(
                          alpha: .92,
                        ),
                      ),
                      onPressed: ready && !busy ? onSkip : null,
                      child: Text(l.csSkip),
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  flex: 0,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: MediaQuery.sizeOf(context).height * .48,
                    ),
                    decoration: BoxDecoration(
                      color: AppSurfaces.card.withValues(alpha: .97),
                      borderRadius: BorderRadius.circular(
                        AppCardStyle.sheetRadius,
                      ),
                      border: Border.all(color: AppSurfaces.card),
                      boxShadow: [
                        BoxShadow(
                          color: AppInk.strong.withValues(alpha: .15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.mascotDefaultName,
                                  style: const TextStyle(
                                    color: AppPalette.brand,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (reduce)
                                  dialogue
                                else
                                  AnimatedSize(
                                    duration: AppMotion.quick,
                                    alignment: Alignment.topLeft,
                                    child: dialogue,
                                  ),
                                if (failed)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      l.csSaveError,
                                      style: const TextStyle(
                                        color: AppInk.danger,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        EntryPrimaryAction(
                          key: const ValueKey('onboarding-primary'),
                          label: failed
                              ? l.csRetry
                              : last
                              ? l.entryEnterRoom
                              : l.csContinue,
                          onPressed: busy
                              ? null
                              : failed
                              ? onRetry
                              : ready
                              ? onNext
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
