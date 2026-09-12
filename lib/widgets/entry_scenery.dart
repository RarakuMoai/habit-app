import 'package:flutter/material.dart';

import '../utils/app_style.dart';

/// The original V3 key art selected by the user, copied without modification.
const kEntryCoverAsset = 'assets/scenes/onboarding/entry_living_room_v3.png';

/// Byte-identical to the native LaunchImage@3x raster. Render with BoxFit.cover
/// in the full viewport to match LaunchScreen.storyboard's scaleAspectFill.
const kEntryLaunchAsset = 'assets/scenes/onboarding/launch_bridge.png';

/// Shared cover/first-meeting camera into the unmodified key art.
///
/// The caller supplies bounded, full-viewport constraints and owns controls,
/// safe areas, loading failures and transitions. The baked-in character is never
/// layered with another mascot or animated separately from this illustration.
class EntryScenery extends StatelessWidget {
  const EntryScenery({
    super.key,
    this.topScrim = false,
    this.bottomScrim = false,
  });

  final bool topScrim;
  final bool bottomScrim;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(kEntryCoverAsset, fit: BoxFit.cover),
          if (topScrim)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppSurfaces.canvas.withValues(alpha: .88),
                    AppSurfaces.canvas.withValues(alpha: 0),
                  ],
                  stops: const [0, .34],
                ),
              ),
            ),
          if (bottomScrim)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppSurfaces.canvas.withValues(alpha: 0),
                    AppSurfaces.canvas.withValues(alpha: .96),
                  ],
                  stops: const [.58, 1],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
