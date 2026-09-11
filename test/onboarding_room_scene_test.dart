import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_app/widgets/onboarding_room_scene.dart';

void main() {
  for (final viewport in [
    const Size(402, 390),
    const Size(320, 210),
    const Size(320, 86),
    const Size(680, 390),
  ]) {
    test('room crop and feet share rug ground in $viewport', () {
      final geometry = OnboardingRoomGeometry(viewport);
      final frame = Offset.zero & viewport;
      expect(geometry.room.left, lessThanOrEqualTo(frame.left));
      expect(geometry.room.top, lessThanOrEqualTo(frame.top));
      expect(geometry.room.right, greaterThanOrEqualTo(frame.right));
      expect(geometry.room.bottom, greaterThanOrEqualTo(frame.bottom));
      final rug = Offset(
        geometry.room.center.dx,
        geometry.room.top + geometry.room.height * 0.83,
      );
      final feet = Offset(
        geometry.mascot.center.dx,
        geometry.mascot.top + geometry.mascot.height * 216 / 252,
      );
      expect((feet - rug).distance, lessThan(0.001));
      // Entire stage remains in frame, including the breathing/pose canvas.
      expect(geometry.mascot.top, greaterThanOrEqualTo(0));
      expect(geometry.mascot.bottom, lessThanOrEqualTo(viewport.height));
    });
  }
}
