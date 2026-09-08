// Trial-only curved arm mesh (fixed shoulder + bent centerline).
// Both outfits consume exactly the same geometry and timeline.
import 'dart:math' as math;
import 'dart:ui';

const trialDuration = Duration(milliseconds: 2800);
const shoulder = Offset(388, 563);
const armDirection = Offset(-.36, .9329523031752481);
const armNormal = Offset(-.9329523031752481, -.36);
const bendLength = 100.0;

double smooth(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Rise, hold briefly, then return; zero velocity at both joins.
double armAngle(double ms) {
  final double amount;
  if (ms < 300) {
    amount = 0;
  } else if (ms < 1100) {
    amount = smooth((ms - 300) / 800);
  } else if (ms < 1650) {
    amount = 1;
  } else {
    amount = 1 - smooth((ms - 1650) / 850);
  }
  return amount * 65 * math.pi / 180;
}

/// Bend along the ARM axis and preserve each cross-section's width. Blending
/// rotations by canvas Y pinched the diagonal shoulder and folded triangles.
/// Curvature * half-width stays below 1, so the inside edge cannot fold.
/// This small analytic mesh is a feasibility trial, not a Spine runtime.
Offset deformArm(Offset rest, double angle) {
  final local = rest - shoulder;
  final along = local.dx * armDirection.dx + local.dy * armDirection.dy;
  if (along <= 0 || angle.abs() < 1e-10) return rest;
  final across = local.dx * armNormal.dx + local.dy * armNormal.dy;
  final curvature = angle / bendLength;
  final bend = along.clamp(0.0, bendLength);
  final theta = curvature * bend;
  final tangent = armDirection * math.cos(theta) + armNormal * math.sin(theta);
  final normal = armNormal * math.cos(theta) - armDirection * math.sin(theta);
  final center =
      shoulder +
      armDirection * (math.sin(theta) / curvature) +
      armNormal * ((1 - math.cos(theta)) / curvature) +
      tangent * (along - bend);
  return center + normal * across;
}

({List<Offset> rest, List<Offset> posed, List<int> indices}) armMesh(
  double angle,
) {
  const columns = 15;
  const rows = 23;
  final rest = <Offset>[];
  final posed = <Offset>[];
  final indices = <int>[];
  for (var y = 0; y <= rows; y++) {
    for (var x = 0; x <= columns; x++) {
      // Alpha support measured in arm coordinates: along -26.42..176.92,
      // across -32.45..47.49. Margin includes the antialiased fringe.
      final p =
          shoulder +
          armDirection * (-32 + 216 * y / rows) +
          armNormal * (-38 + 92 * x / columns);
      rest.add(p);
      posed.add(deformArm(p, angle));
      if (x < columns && y < rows) {
        final a = y * (columns + 1) + x;
        final b = a + columns + 1;
        indices.addAll([a, b, a + 1, a + 1, b, b + 1]);
      }
    }
  }
  return (rest: rest, posed: posed, indices: indices);
}
