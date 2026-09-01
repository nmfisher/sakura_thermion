/// Dart port of the reference `src/world/street.js` — the ground terrain grid,
/// the asphalt road, and the painted edge lines. Foundational: it also defines
/// the road-centre / ground-height curves (`centerX`, `groundY`) every other
/// module places against.
///
/// Textures (drain/tactile/road-paint decals) and the canal trench cutout
/// (`cutTrench`, from landform.js) are deferred — the surfaces use solid cel
/// colours for now and will pick up their decals once the texture substrate lands.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// Constants (street.js).
const roadHalf = 3.15;
const walkW = 1.55;
const walkH = 0.135;
const terrainDrop = 0.015;
const zMin = -66.0;
const zMax = 52.0;
const crossBand = 3.35;

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// Hermite smoothstep tolerating a > b (util.js sstep).
double sstep(double a, double b, double v) {
  final t = _clamp((v - a) / (b - a == 0 ? 1e-6 : b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/// Road centreline x as the street curves (street.js centerX).
double centerX(double z) => 3.0 * sstep(-11, -36, z) - 3.4 * sstep(16, 44, z);

/// Ground height along the street — it climbs gently past the crossing.
double groundY(double z) => 1.05 * sstep(-13, -32, z) + 0.45 * sstep(28, 48, z);

// Materials (street.js — solid cel; textures deferred).
const _lineMat = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2'); // PAL.lineWhite
const _walkMat = Mat(0xdcd8e2, tint: 0x7d74a0, bands: '3');
const _walkAltMat = Mat(0xe7e2e6, tint: 0x7d74a0, bands: '3');
const _gutterMat = Mat(0xbdb8c4, tint: 0x6f6790, bands: '3');
const _drainMat = Mat(0x6d687a, tint: 0x5d5878, bands: '3');
const _manholeMat = Mat(0x878b96, tint: 0x5c5680, bands: '3');

/// The displaced terrain grid (320 m square, 2 m cells, sampled to groundY),
/// offset −20 m in z as in the reference.
ThreeGeom _terrainGrid() {
  const w = 320.0, d = 320.0, seg = 160, off = -20.0;
  final hw = w / 2, hd = d / 2, sw = w / seg, sd = d / seg;
  final pos = <double>[], idx = <int>[];
  for (int iz = 0; iz <= seg; iz++) {
    for (int ix = 0; ix <= seg; ix++) {
      final x = ix * sw - hw;
      final zWorld = (iz * sd - hd) + off;
      pos.addAll([x, groundY(zWorld) - terrainDrop, zWorld]);
    }
  }
  final row = seg + 1;
  for (int iz = 0; iz < seg; iz++) {
    for (int ix = 0; ix < seg; ix++) {
      final a = ix + row * iz;
      final b = ix + row * (iz + 1);
      final c = (ix + 1) + row * (iz + 1);
      final dd = (ix + 1) + row * iz;
      idx.addAll([a, b, dd, b, c, dd]);
    }
  }
  final g = ThreeGeom(Float32List.fromList(pos), Float32List(0), idx);
  return ThreeGeom(g.positions, computeNormals(g), g.indices);
}

List<Tri> _stripPart(
    Mat mat, double from, double to, double off0, double off1, double y,
    {required int side}) {
  // side ±1: a/b edges offset from the centreline (matches street.js sideStrips).
  Vector2 edge(double z, double off) =>
      Vector2(centerX(z) + side * off, groundY(z) + y);
  final g = stripGeometry(
    from,
    to,
    1.2,
    (z) => edge(z, side > 0 ? off0 : off1),
    (z) => edge(z, side > 0 ? off1 : off0),
    flip: side < 0,
  );
  return bake([Part(g, Matrix4.identity(), mat)]);
}

/// Build the street surface (terrain + road + edge lines) as a triangle soup.
List<Tri> buildStreet({
  int roadColor = 0x8e8a9c,
  int roadPatchColor = 0x9a95a6,
  int terrainColor = 0xc4c4b6,
  int curbColor = 0xc7c2d0,
  int tactileColor = 0xf2c53d,
}) {
  final out = <Tri>[];
  final roadMat = Mat(roadColor, tint: 0x6a608f, bands: '3');
  final roadPatchMat = Mat(roadPatchColor, tint: 0x6a608f, bands: '3');
  final terrainMat = Mat(terrainColor, tint: 0x7a7396, bands: '3');
  final curbMat = Mat(curbColor, tint: 0x6f6790, bands: '3');
  final tactileMat = Mat(tactileColor, tint: 0x9a7f4a, bands: '2');

  // Terrain + asphalt (geometry parts → bake).
  out.addAll(bake([Part(_terrainGrid(), Matrix4.identity(), terrainMat)]));
  final road = stripGeometry(
    zMin,
    zMax,
    1.1,
    (z) => Vector2(centerX(z) - roadHalf, groundY(z) + 0.012),
    (z) => Vector2(centerX(z) + roadHalf, groundY(z) + 0.012),
  );
  out.addAll(bake([Part(road, Matrix4.identity(), roadMat)]));

  // Flat repair patches from the reference keep the broad asphalt field from
  // becoming a single dead tone.
  for (final p in const [
    (-0.9, 8.4, 2.6, 3.2),
    (1.6, 19.5, 2.0, 4.4),
    (-1.4, -8.5, 3.0, 2.4),
    (0.8, 27.0, 2.4, 5.0),
    (-1.9, 34.0, 2.2, 3.6),
    (2.0, -20.0, 2.2, 3.0),
  ]) {
    final g = applyMatrix(planeGeometry(p.$3, p.$4),
        trs(centerX(p.$2) + p.$1, groundY(p.$2) + 0.018, p.$2, -math.pi / 2));
    out.addAll(bake([Part(g, Matrix4.identity(), roadPatchMat)]));
  }

  // White edge lines, broken by the crossing band (already-baked strips).
  for (final r in [
    [zMin, -crossBand],
    [crossBand, zMax],
  ]) {
    for (final side in [1, -1]) {
      out.addAll(
          _stripPart(_lineMat, r[0], r[1], 2.72, 2.86, 0.024, side: side));
    }
  }

  void roadRect(Mat mat, double x, double z, double w, double d,
      [double ry = 0, double y = 0.022]) {
    final g = applyMatrix(
        planeGeometry(w, d), trs(x, groundY(z) + y, z, -math.pi / 2, ry));
    out.addAll(bake([Part(g, Matrix4.identity(), mat)]));
  }

  // The opening-frame 止まれ marking. In the reference capture's Linux
  // browser the requested Japanese UI fonts are unavailable, so Canvas paints
  // the three characters as vertically stacked missing-glyph boxes. Recreate
  // that observed footprint directly instead of the former H-like shorthand.
  const paintMat = Mat(0xf4f2f6, unlit: true);
  void stopMark(double dx, double z, double size, [double ry = 0]) {
    final cx = centerX(z) + dx + size * .008;
    final glyphW = size * .15;
    final glyphD = size * .53;
    final strokeX = size * .036;
    final strokeZ = size * .045;
    for (final offset in [-.28, .33, .93]) {
      final zz = z + offset * size;
      // Lift above the manual projected tree shadows, matching the decal's
      // renderOrder=1 in three.js.
      roadRect(paintMat, cx, zz - glyphD / 2, glyphW, strokeZ, ry, .044);
      roadRect(paintMat, cx, zz + glyphD / 2, glyphW, strokeZ, ry, .044);
      roadRect(paintMat, cx - glyphW / 2, zz, strokeX, glyphD, ry, .044);
      roadRect(paintMat, cx + glyphW / 2, zz, strokeX, glyphD, ry, .044);
    }
  }

  stopMark(1.45, 8.5, 1.5);
  stopMark(-1.5, -9.6, 1.5, math.pi);

  // Hollow crossing-ahead diamonds at the reference positions.
  void diamond(double dx, double z, double size, [double ry = 0]) {
    final cx = centerX(z) + dx;
    final len = size * 0.9;
    for (final rz in [math.pi / 4 + ry, -math.pi / 4 + ry]) {
      roadRect(paintMat, cx - math.sin(rz) * size * 0.38,
          z - math.cos(rz) * size * 0.38, 0.085, len, rz);
      roadRect(paintMat, cx + math.sin(rz) * size * 0.38,
          z + math.cos(rz) * size * 0.38, 0.085, len, rz);
    }
  }

  diamond(1.5, 16.5, 1.35);
  diamond(-1.55, -17.5, 1.35, math.pi);
  diamond(1.6, 25.0, 1.3);

  // Stop bars sit on their traffic lane, not across the full carriageway.
  for (final s in [1.0, -1.0]) {
    final z = s * (crossBand + 0.85);
    roadRect(_lineMat, centerX(z) + s * 1.35, z, 2.55, 0.42, 0, 0.026);
  }

  // Raised footways, kerb faces, outer paving band, tactile run and gutter.
  for (final r in const [(zMin, -crossBand), (crossBand, zMax)]) {
    for (final side in [1, -1]) {
      out.addAll(_stripPart(
          _walkMat, r.$1, r.$2, roadHalf, roadHalf + walkW, walkH,
          side: side));
      out.addAll(_stripPart(_walkAltMat, r.$1, r.$2, roadHalf + walkW,
          roadHalf + walkW + 0.22, walkH,
          side: side));
      out.addAll(_stripPart(tactileMat, r.$1, r.$2, roadHalf + 0.44,
          roadHalf + 0.78, walkH + 0.014,
          side: side));
      out.addAll(_stripPart(
          _gutterMat, r.$1, r.$2, roadHalf - 0.30, roadHalf - 0.02, 0.004,
          side: side));

      final curb = stripGeometry(
        r.$1,
        r.$2,
        1.2,
        (z) => Vector2(centerX(z) + side * roadHalf, groundY(z)),
        (z) => Vector2(centerX(z) + side * roadHalf, groundY(z) + walkH),
        flip: side < 0,
      );
      out.addAll(bake([Part(curb, Matrix4.identity(), curbMat)]));
    }
  }

  // Alternating kerb drains, matching the 7.4 m reference cadence.
  int grateIndex = 0;
  for (double z = -44; z <= 46 && grateIndex < 26; z += 7.4) {
    if (z.abs() < crossBand + 1.2) continue;
    final side = grateIndex.isEven ? 1.0 : -1.0;
    final ry = math.atan2(centerX(z + 0.31) - centerX(z - 0.31), 0.62);
    out.addAll(bake([
      Part(
          boxGeometry(0.26, 0.05, 0.62),
          trs(centerX(z) + side * (roadHalf - 0.16), groundY(z) + 0.03, z, 0,
              ry),
          _drainMat)
    ]));
    grateIndex++;
  }

  // Seven low twelve-sided manhole covers.
  for (final p in const [
    (-1.1, 6.2),
    (1.4, 15.0),
    (-0.6, -9.5),
    (1.9, 24.0),
    (-1.7, 31.5),
    (0.4, -19.0),
    (2.2, 41.0),
  ]) {
    out.addAll(bake([
      Part(cylGeometry(0.32, 0.32, 0.04, 12),
          trs(centerX(p.$2) + p.$1, groundY(p.$2) + 0.024, p.$2), _manholeMat)
    ]));
  }

  return out;
}
