import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import 'mascot_scene.dart';
import 'scene_rooms.dart';

/// A camera into the original 1122 × 1402 room. The rug is part of the image:
/// its ground point must move with the image crop, not with a padded UI panel.
class OnboardingRoomScene extends StatelessWidget {
  const OnboardingRoomScene({
    super.key,
    required this.asset,
    required this.reduceMotion,
    required this.paused,
    required this.lighting,
  });

  final String? asset;
  final bool reduceMotion;
  final bool paused;
  final MascotSceneLighting lighting;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final geometry = OnboardingRoomGeometry(
              Size(box.maxWidth, box.maxHeight),
            );
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: geometry.room,
                  child: Image.asset(
                    FourPeriodRoom.home.assets.day,
                    fit: BoxFit.fill,
                  ),
                ),
                if (asset != null)
                  Positioned.fromRect(
                    rect: geometry.mascot,
                    child: FittedBox(
                      child: MascotStage(
                        asset: asset!,
                        accent: AppPalette.habit,
                        reactionTick: 0,
                        onTap: () {},
                        reduceMotion: reduceMotion,
                        paused: paused,
                        poseTransition: reduceMotion
                            ? MascotPoseTransition.cut
                            : MascotPoseTransition.crossFade,
                        lighting: lighting,
                      ),
                    ),
                  ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00FFF8ED), AppSurfaces.canvas],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

@immutable
class OnboardingRoomGeometry {
  OnboardingRoomGeometry(Size viewport) {
    const source = Size(1122, 1402);
    // The clear inner rug, measured in the approved home_day image.
    const rugPoint = Offset(0.5, 0.83);
    final scale = math.max(
      viewport.width / source.width,
      viewport.height / source.height,
    );
    final imageSize = source * scale;
    final imageTop = (viewport.height * 0.80 - imageSize.height * rugPoint.dy)
        .clamp(viewport.height - imageSize.height, 0.0);
    room = Rect.fromLTWH(
      (viewport.width - imageSize.width) / 2,
      imageTop,
      imageSize.width,
      imageSize.height,
    );
    ground = Offset(
      room.left + room.width * rugPoint.dx,
      room.top + room.height * rugPoint.dy,
    );
    // Keep the original room/character proportion, with a height guard for
    // short reading windows. 216 is MascotStage's existing contact-shadow Y.
    final side = math.min(imageSize.width * 252 / 430, viewport.height * 0.92);
    mascot = Rect.fromLTWH(
      ground.dx - side / 2,
      ground.dy - side * 216 / 252,
      side,
      side,
    );
  }

  late final Rect room;
  late final Rect mascot;
  late final Offset ground;
}
