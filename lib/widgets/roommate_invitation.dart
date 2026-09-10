import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_style.dart';
import '../utils/roommate_events.dart';

/// A quiet, optional invitation attached to the room, with a separate dismiss target.
class RoommateInvitation extends StatelessWidget {
  final RoommateEvent event;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  const RoommateInvitation({
    super.key,
    required this.event,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final invitation = Material(
      color: AppSurfaces.card.withValues(alpha: 0.98),
      elevation: 3,
      shadowColor: AppInk.strong.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppSurfaces.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey('roommate_entry'),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 4, 11),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppPalette.brand,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.invitation(l),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppInk.strong,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.rdInviteTap,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppPalette.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('roommate_invitation_dismiss'),
            tooltip: l.rdInviteDismiss,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 17, color: AppInk.soft),
          ),
        ],
      ),
    );
    // A single quiet entrance; no pulse, countdown, or sound asking for attention.
    if (MediaQuery.disableAnimationsOf(context)) return invitation;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: invitation,
    );
  }
}
