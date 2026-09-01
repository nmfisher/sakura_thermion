/// The street — a faithful port of the reference `src/world/street.js`.
///
/// Everything in the world is placed relative to a single curved centreline
/// along Z. The stretch around the railway crossing is kept straight so the
/// crossing reads cleanly, then the road bends away to the north-west and
/// behind the player. All constants match the reference exactly.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mathutil.dart';
import '../mesh.dart';
import '../palette.dart';

const double roadHalf = 3.15;
const double walkW = 1.55;
const double walkH = 0.135;
const double zMin = -66;
const double zMax = 52;
const double trackHalf = 2.2;
const double gateZ = 2.95;
const double crossBand = 3.35;

/// Lateral drift of the road centre.
double centerX(double z) {
  var x = 0.0;
  x += 3.0 * sstep(-11, -36, z);
  x -= 3.4 * sstep(16, 44, z);
  return x;
}

/// Ground height along the street: it climbs gently past the crossing.
double groundY(double z) {
  return 1.05 * sstep(-13, -32, z) + 0.45 * sstep(28, 48, z);
}

/// Signed distance from the road centre.
double lateral(double x, double z) => x - centerX(z);

/// True inside the two raised footway strips (bounded in z, like the
/// reference).
bool isSidewalk(double x, double z) {
  if (z < zMin || z > zMax) return false;
  final d = lateral(x, z).abs();
  if (z.abs() < crossBand) return false;
  return d > roadHalf - 0.02 && d < roadHalf + walkW;
}

double streetHeight(double x, double z) =>
    groundY(z) + (isSidewalk(x, z) ? walkH : 0);

/// Tessellate a horizontal strip along z between two lateral profiles
/// [a](z) and [b](z) at height [y](z) into [m]. Each cell is one flat cel
/// face, so the road follows its climb in discrete bands like the reference's
/// flat-shaded strips.
void _strip(Mesh m, {
  required double z0,
  required double z1,
  required double Function(double z) a,
  required double Function(double z) b,
  required double Function(double z) y,
  required int color,
  int tint = 0x6c5f8c,
  String bands = '3',
  double step = 1.2,
}) {
  final rows = math.max(2, ((z1 - z0).abs() / step).round() + 1);
  final prevA = a(z0);
  final prevB = b(z0);
  final prevY = y(z0);
  for (int i = 1; i < rows; i++) {
    final t = i / (rows - 1);
    final z = z0 + (z1 - z0) * t;
    final ca = a(z);
    final cb = b(z);
    final cy = y(z);
    // CCW from above so the up-normal is +Y; pass the normal explicitly for
    // the horizontal surfaces.
    m.quad(
      Vector3(prevA, prevY, z0 + (z1 - z0) * ((i - 1) / (rows - 1))),
      Vector3(prevB, prevY, z0 + (z1 - z0) * ((i - 1) / (rows - 1))),
      Vector3(cb, cy, z),
      Vector3(ca, cy, z),
      color: color,
      tint: tint,
      bands: bands,
    );
  }
}

/// Vertical kerb face between the road edge and the footway.
void _kerbFace(Mesh m, {
  required double z0,
  required double z1,
  required int side, // -1 left, +1 right
  required int color,
  int tint = 0x6f6790,
}) {
  final rows = math.max(2, (((z1 - z0).abs()) / 1.2).round() + 1);
  double zAt(int i) => z0 + (z1 - z0) * (i / (rows - 1));
  for (int i = 0; i < rows - 1; i++) {
    final za = zAt(i);
    final zb = zAt(i + 1);
    final xa = centerX(za) + side * roadHalf;
    final xb = centerX(zb) + side * roadHalf;
    final ya = groundY(za);
    final yb = groundY(zb);
    m.quad(
      Vector3(xa, ya, za),
      Vector3(xa, ya + walkH, za),
      Vector3(xb, yb + walkH, zb),
      Vector3(xb, yb, zb),
      color: color,
      tint: tint,
      bands: '3',
    );
  }
}

/// The big ground sheet, road, footways, kerbs, edge lines, tactile paving,
/// gutter and repair patches. Painted into [m].
void buildStreet(Mesh m) {
  // --- terrain: a large graded sheet under everything ---
  final g = 150.0;
  final cells = 30;
  for (int i = 0; i < cells; i++) {
    for (int j = 0; j < cells; j++) {
      final x0 = -g + i * (2 * g / cells);
      final x1 = -g + (i + 1) * (2 * g / cells);
      final z0 = -g + j * (2 * g / cells);
      final z1 = -g + (j + 1) * (2 * g / cells);
      final y = groundY((z0 + z1) / 2) - 0.015;
      // skip the region under the road (the road itself covers it)
      final inRoadBand = (z0 + z1).abs() < zMax + 4;
      if (inRoadBand && (x0 < roadHalf + walkW + 2 && x1 > -roadHalf - walkW - 2)) continue;
      m.quad(
        Vector3(x0, y, z0),
        Vector3(x0, y, z1),
        Vector3(x1, y, z1),
        Vector3(x1, y, z0),
        color: 0xc4c4b6,
        tint: 0x7a7396,
      );
    }
  }

  // --- asphalt (with the crossing band left for the deck), split into left
  // and right halves so baked tree shadows read crisply ---
  void roadStrip(double z0, double z1, {double step = 0.55}) {
    for (final s in [-1.0, 1.0]) {
      _strip(m,
          z0: z0, z1: z1, step: step,
          a: s < 0 ? (z) => centerX(z) - roadHalf : (z) => centerX(z),
          b: s < 0 ? (z) => centerX(z) : (z) => centerX(z) + roadHalf,
          y: (z) => groundY(z) + 0.012,
          color: Pal.road, tint: 0x6a608f);
    }
  }
  roadStrip(zMin, -crossBand);
  roadStrip(crossBand, zMax);

  // --- a few flat repair patches so the asphalt is not a dead field ---
  final patches = [
    [-0.9, 8.4, 2.6, 3.2], [1.6, 19.5, 2.0, 4.4], [-1.4, -8.5, 3.0, 2.4],
    [0.8, 27.0, 2.4, 5.0], [-1.9, 34.0, 2.2, 3.6], [2.0, -20.0, 2.2, 3.0],
  ];
  for (final p in patches) {
    final dx = p[0].toDouble(), z = p[1].toDouble(), w = p[2].toDouble(), d = p[3].toDouble();
    m.quadRaw(
      Vector3(centerX(z) + dx - w / 2, groundY(z) + 0.018, z - d / 2),
      Vector3(centerX(z) + dx - w / 2, groundY(z) + 0.018, z + d / 2),
      Vector3(centerX(z) + dx + w / 2, groundY(z) + 0.018, z + d / 2),
      Vector3(centerX(z) + dx + w / 2, groundY(z) + 0.018, z - d / 2),
      C.srgb(Pal.roadWorn),
      normal: Vector3(0, 1, 0),
    );
  }

  // --- white edge lines, broken by the crossing ---
  for (final s in [-1.0, 1.0]) {
    _strip(m,
        z0: zMin, z1: -crossBand, step: 0.6,
        a: (z) => centerX(z) + s * 2.72, b: (z) => centerX(z) + s * 2.86,
        y: (z) => groundY(z) + 0.024,
        color: Pal.lineWhite, bands: '2', tint: 0x8e86ad);
    _strip(m,
        z0: crossBand, z1: zMax, step: 0.6,
        a: (z) => centerX(z) + s * 2.72, b: (z) => centerX(z) + s * 2.86,
        y: (z) => groundY(z) + 0.024,
        color: Pal.lineWhite, bands: '2', tint: 0x8e86ad);
  }

  // --- footways, kerb faces, outer edge, tactile paving, gutters ---
  for (final [z0, z1] in [[zMin, -crossBand], [crossBand, zMax]]) {
    for (final s in [-1.0, 1.0]) {
      // footway (inner + outer halves so shadows read)
      _strip(m,
          z0: z0, z1: z1, step: 0.6,
          a: (z) => centerX(z) + s * roadHalf,
          b: (z) => centerX(z) + s * (roadHalf + walkW),
          y: (z) => groundY(z) + walkH,
          color: Pal.sidewalk, tint: 0x7d74a0);
      // warmer outer edge
      _strip(m,
          z0: z0, z1: z1, step: 0.6,
          a: (z) => centerX(z) + s * (roadHalf + walkW),
          b: (z) => centerX(z) + s * (roadHalf + walkW + 0.22),
          y: (z) => groundY(z) + walkH,
          color: Pal.sidewalkAlt, tint: 0x7d74a0);
      // tactile paving — the yellow line along the street
      _strip(m,
          z0: z0, z1: z1, step: 0.6,
          a: (z) => centerX(z) + s * (roadHalf + 0.44),
          b: (z) => centerX(z) + s * (roadHalf + 0.78),
          y: (z) => groundY(z) + walkH + 0.014,
          color: Pal.tactile, bands: '2', tint: 0x9a7f4a);
      // gutter strip along the kerb
      _strip(m,
          z0: z0, z1: z1, step: 0.6,
          a: (z) => centerX(z) + s * (roadHalf - 0.30),
          b: (z) => centerX(z) + s * (roadHalf - 0.02),
          y: (z) => groundY(z) + 0.004,
          color: Pal.gutter, tint: 0x6f6790);
    }
    // kerb faces
    _kerbFace(m, z0: z0, z1: z1, side: -1, color: Pal.curb);
    _kerbFace(m, z0: z0, z1: z1, side: 1, color: Pal.curb);
  }

  // --- manhole covers ---
  final spots = [
    [-1.1, 6.2], [1.4, 15.0], [-0.6, -9.5], [1.9, 24.0], [-1.7, 31.5], [0.4, -19.0], [2.2, 41.0],
  ];
  for (final [dx, z] in spots) {
    m.cylUnit(_cylMat(centerX(z) + dx, groundY(z) + 0.024, z, 0.32, 0.02),
        Pal.metalDark, segments: 10, tint: 0x5c5680);
  }
}

/// Matrix for a squat cylinder (radius [r], height [h]) at (x,y,z).
Matrix4 _cylMat(double x, double y, double z, double r, double h) {
  return Matrix4.translation(Vector3(x, y, z))..scale(r, h, r);
}
