/// Dart port of reference water-feature modules: canal.js, lake.js, lakeroad.js.
///
/// Builds the drainage channel concrete and water surface, the lake water body
/// with reflection layers, and the lake road / embankment as triangle soup.
///
/// Textures and animated layers remain static geometric equivalents in the
/// native port. Canal structures and bank dressing live in
/// `canal_details.dart`; lake-site structures live in `kohan.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillSurfaceY;
import 'lakeform.dart' as lakeform;
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart';

// ---------------------------------------------------------------------------
// Constants -- canal (landform.js + canal.js)
// ---------------------------------------------------------------------------

const _canalZ = -24.0;
const _canalHalf = 2.5;
const _canalDepth = 1.75;
const _canalX0 = -98.0;
const _canalX1 = 106.0;
const _endTail = 3.2;
const _hwT = 0.75;
const _wallIn = 2.16; // canalHalf - 0.34
const _slabOut = 6.0;
const _dressW = -58.0;
const _dressE = 44.0;
const _roadGap0 = -4.7;
const _roadGap1 = 7.9;

// ---------------------------------------------------------------------------
// Constants -- lake (lakeform.js + lake.js)
// ---------------------------------------------------------------------------

const _lakeLevel = 3.40;
const _lakeGx0 = 136.0;
const _lakeGx1 = 256.0;
const _lakeGz0 = -142.0;
const _lakeGz1 = -34.0;

/// The lake centre, for echo direction computation.
const _lakeCx = 196.0;
const _lakeCz = -88.0;

// ---------------------------------------------------------------------------
// Constants -- dam (lakeform.js)
// ---------------------------------------------------------------------------

const _damAx = 143.0, _damAz = -44.0;
const _damBx = 157.0, _damBz = -37.0;

// ---------------------------------------------------------------------------
// Shoreline polygon (lakeform.js SHORE, for shallow-margin strips)
// ---------------------------------------------------------------------------

final _shore = lakeform.lakeShore
    .map((point) => <double>[point.x, point.z])
    .toList(growable: false);

lakeform.LakeNear _lakeNear(double x, double z) => lakeform.lakeNear(x, z)!;

double _lakeDepth(double x, double z) => lakeform.lakeDepthProfile(x, z);

/// Marching-squares fill of a positive scalar field, matching `lake.js`.
/// Adjacent cells share interpolated crossings, so the waterline and tone bands
/// are continuous rather than stair-stepped rectangles.
List<Tri> _contourFill(
    double Function(double x, double z) field, double y, Mat material) {
  const step = 2.0;
  final out = <Tri>[];
  final nx = ((_lakeGx1 - _lakeGx0) / step).ceil();
  final nz = ((_lakeGz1 - _lakeGz0) / step).ceil();
  var row = List<double>.generate(
      nz + 1, (j) => field(_lakeGx0, _lakeGz0 + j * step));
  for (var i = 0; i < nx; i++) {
    final xa = _lakeGx0 + i * step, xb = xa + step;
    final next =
        List<double>.generate(nz + 1, (j) => field(xb, _lakeGz0 + j * step));
    for (var j = 0; j < nz; j++) {
      final za = _lakeGz0 + j * step, zb = za + step;
      final values = [row[j], next[j], next[j + 1], row[j + 1]];
      if (values.every((value) => value <= 0)) continue;
      final points = [
        Vector2(xa, za),
        Vector2(xb, za),
        Vector2(xb, zb),
        Vector2(xa, zb),
      ];
      final polygon = <Vector2>[];
      for (var edge = 0; edge < 4; edge++) {
        final a = edge, b = (edge + 1) % 4;
        if (values[a] > 0) polygon.add(points[a]);
        if ((values[a] > 0) != (values[b] > 0)) {
          final t = values[a] / (values[a] - values[b]);
          polygon.add(points[a] + (points[b] - points[a]) * t);
        }
      }
      for (var k = 1; k + 1 < polygon.length; k++) {
        out.add(Tri(
          Vector3(polygon[0].x, y, polygon[0].y),
          Vector3(polygon[k + 1].x, y, polygon[k + 1].y),
          Vector3(polygon[k].x, y, polygon[k].y),
          Vector3(0, 1, 0),
          material,
        ));
      }
    }
    row = next;
  }
  return out;
}

List<Tri> _lakeRing(
    double x, double z, double innerRadius, double outerRadius, double y) {
  const segments = 24;
  final out = <Tri>[];
  for (var i = 0; i < segments; i++) {
    final a0 = i / segments * math.pi * 2;
    final a1 = (i + 1) / segments * math.pi * 2;
    final i0 = Vector3(
        x + math.cos(a0) * innerRadius, y, z + math.sin(a0) * innerRadius);
    final i1 = Vector3(
        x + math.cos(a1) * innerRadius, y, z + math.sin(a1) * innerRadius);
    final o0 = Vector3(
        x + math.cos(a0) * outerRadius, y, z + math.sin(a0) * outerRadius);
    final o1 = Vector3(
        x + math.cos(a1) * outerRadius, y, z + math.sin(a1) * outerRadius);
    out
      ..add(Tri(i0, i1, o1, Vector3(0, 1, 0), _mLakeRipple))
      ..add(Tri(i0, o1, o0, Vector3(0, 1, 0), _mLakeRipple));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Road routes (hills.js ROUTES)
// ---------------------------------------------------------------------------

/// Lake road climb: pts have (x, z, heightAboveDatum).
const _lakeRoadPts = <List<double>>[
  [89.0, -60.0, 0.00],
  [89.0, -46.0, 0.00],
  [90.4, -36.4, 0.00],
  [96.0, -33.6, 0.00],
  [104.0, -32.4, 0.10],
  [112.0, -31.6, 0.60],
  [120.0, -31.4, 1.70],
  [130.0, -32.0, 3.00],
  [139.0, -33.0, 4.10],
  [147.0, -34.0, 5.10],
  [153.0, -35.2, 5.80],
  [157.0, -37.0, 6.30],
];

/// Dam crest road: pts have (x, z, heightAboveDatum).
const _damRoadPts = <List<double>>[
  [157.0, -37.0, 6.30],
  [152.6, -39.2, 6.30],
  [148.0, -41.5, 6.30],
  [143.0, -44.0, 6.20],
  [140.4, -48.0, 5.90],
];

/// Shore road south leg: pts have (x, z) only; Y approximated from bank profile.
const _shoreRoadPts = <List<double>>[
  [139.4, -51.6],
  [134.6, -57.0],
  [131.4, -64.0],
  [130.0, -72.0],
  [130.0, -80.0],
  [131.8, -88.0],
  [134.8, -95.6],
  [138.8, -103.0],
  [144.2, -111.6],
  [150.6, -119.6],
  [158.0, -128.0],
  [166.0, -137.0],
  [173.0, -145.6],
  [179.0, -153.6],
  [186.4, -158.4],
  [195.0, -159.6],
  [203.0, -157.0],
  [209.4, -153.8],
];

// ---------------------------------------------------------------------------
// Materials (PAL colours, inline, no textures)
// ---------------------------------------------------------------------------

// Canal concrete
const _mConcrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _mConcreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _mConcreteDark = Mat(0xa7a2b0, tint: 0x655d84, bands: '3');
const _mMoss = Mat(0x7d9c74, tint: 0x5b6f8c, bands: '3');

// Water (unlit = flat, no cel shading)
const _mWaterDeep = Mat(0x6d90ad, unlit: true);
const _mWaterSky = Mat(0xcadff0, unlit: true);
const _mBedBand = Mat(0x5b7d99, unlit: true);

// Lake water
const _mLakeWater = Mat(0x7ba6bd, unlit: true);
const _mLakeShallow = Mat(0x9dc4bd, unlit: true);
const _mLakeDeep = Mat(0x5f83a4, unlit: true);
const _mLakeSky = Mat(0xcfe3f2, unlit: true);
const _mLakeGlint = Mat(0xf2f7fa, unlit: true);
const _mLakeRipple = Mat(0x86a9ba, unlit: true, noOutline: true);
const _mLakeHillEcho = Mat(0x86a8a8, unlit: true);
const _mLakeBloomEcho = Mat(0xe6c3cf, unlit: true);
const _mLilyPad = Mat(0x6f9a72, unlit: true, noOutline: true);
const _mLilyPadAlt = Mat(0x84ab7c, unlit: true, noOutline: true);
const _mLilyFlower = Mat(0xf4e4ea, tint: 0x9c93b8, bands: 'soft');
const _mDuck = Mat(0x6e6a62, tint: 0x6f6790, bands: '3');
const _mDuckPale = Mat(0xe4dccc, tint: 0x8a83a8, bands: '3');
const _mDuckBill = Mat(0xc89228, tint: 0x7a7396, bands: '3');
const _mDrift = Mat(0xb6ada0, tint: 0x7a7396, bands: '3');
const _mLakeStone = Mat(0xb4aeb6, tint: 0x6f6790, bands: '3');
const _mWaterPetal = Mat(0xf1c4d2, unlit: true, noOutline: true);
const _mReed = Mat(0xa8c884, tint: 0x8a9cb0, bands: 'soft');
const _mReedDeep = Mat(0x8cae6c, tint: 0x8a9cb0, bands: 'soft');
const _mReedHead = Mat(0xd4c79a, tint: 0x9c93b8, bands: 'soft');

// Road
const _mAsphalt = Mat(0x9a95a6, tint: 0x6a608f, bands: '3');
// Materials reserved for lake-road and shore structures.
// ignore: unused_element
const _mGravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _mWhite = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2');
const _mYellow = Mat(0xf0c341, tint: 0x8e86ad, bands: '2');
const _mMetal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _mMetalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _mTimber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _mTimberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
// ignore: unused_element
const _mRock = Mat(0xb4aeb6, tint: 0x6f6790, bands: '3');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a flat grid at constant [y], spanning x=[x0..x1], z=[z0..z1].
/// Mirrors the street.dart terrain-grid pattern (positions + indices + computeNormals).
ThreeGeom _flatGrid(double x0, double x1, double z0, double z1, double y,
    [double step = 2.0]) {
  final nx = ((x1 - x0) / step).round().clamp(1, 99999);
  final nz = ((z1 - z0) / step).round().clamp(1, 99999);
  final sx = nx > 0 ? (x1 - x0) / nx : step;
  final sz = nz > 0 ? (z1 - z0) / nz : step;
  final pos = <double>[];
  final idx = <int>[];
  for (int iz = 0; iz <= nz; iz++) {
    for (int ix = 0; ix <= nx; ix++) {
      pos.addAll([x0 + ix * sx, y, z0 + iz * sz]);
    }
  }
  final row = nx + 1;
  for (int iz = 0; iz < nz; iz++) {
    for (int ix = 0; ix < nx; ix++) {
      final a = ix + row * iz;
      final b = ix + row * (iz + 1);
      final c = (ix + 1) + row * (iz + 1);
      final d = (ix + 1) + row * iz;
      idx.addAll([a, b, d, b, c, d]);
    }
  }
  final g = ThreeGeom(Float32List.fromList(pos), Float32List(0), idx);
  return ThreeGeom(g.positions, computeNormals(g), g.indices);
}

/// A road-strip segment from polyline point [a] to [b], width [w],
/// with Y linearly interpolated from [yA] to [yB].  Returns baked triangles.
List<Tri> _roadSeg(
    List<double> a, List<double> b, double w, double yA, double yB, Mat mat) {
  final dx = b[0] - a[0], dz = b[1] - a[1];
  final len = math.sqrt(dx * dx + dz * dz);
  if (len < 0.5) return [];
  // perpendicular to direction (left of travel = inward for CCW roads)
  final px = -dz / len;
  final hw = w / 2.0;
  final step = math.min(1.0, len / 4.0).clamp(0.3, 1.0);
  final g = stripGeometry(
    a[1],
    b[1],
    step,
    (z) {
      final t = dz.abs() > 0.01 ? (z - a[1]) / dz : 0.0;
      return Vector2(a[0] + dx * t + px * hw, yA + (yB - yA) * t);
    },
    (z) {
      final t = dz.abs() > 0.01 ? (z - a[1]) / dz : 0.0;
      return Vector2(a[0] + dx * t - px * hw, yA + (yB - yA) * t);
    },
  );
  return bake([Part(g, Matrix4.identity(), mat)]);
}

/// A thin line strip along a road segment, offset [lateralOff] from centre.
List<Tri> _lineSeg(List<double> a, List<double> b, double lateralOff,
    double lineW, double yA, double yB, Mat mat) {
  final dx = b[0] - a[0], dz = b[1] - a[1];
  final len = math.sqrt(dx * dx + dz * dz);
  if (len < 0.5) return [];
  final px = -dz / len;
  final hw = lineW / 2.0;
  final step = math.min(1.0, len / 4.0).clamp(0.3, 1.0);
  final g = stripGeometry(
    a[1],
    b[1],
    step,
    (z) {
      final t = dz.abs() > 0.01 ? (z - a[1]) / dz : 0.0;
      final cx = a[0] + dx * t + px * lateralOff;
      final ux = dx / len;
      return Vector2(cx - ux * hw, yA + (yB - yA) * t + 0.03);
    },
    (z) {
      final t = dz.abs() > 0.01 ? (z - a[1]) / dz : 0.0;
      final cx = a[0] + dx * t + px * lateralOff;
      final ux = dx / len;
      return Vector2(cx + ux * hw, yA + (yB - yA) * t + 0.03);
    },
  );
  return bake([Part(g, Matrix4.identity(), mat)]);
}

/// Bake a polyline route into road-surface strips.
/// For 3-element points, Y = groundY(z) + pt[2] - terrainDrop.
/// For 2-element points, Y = groundY(z) + approx (bank level).
List<Tri> _bakeRoute(List<List<double>> pts, double w, Mat mat) {
  final out = <Tri>[];
  for (int i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final yA = a.length >= 3
        ? groundY(a[1]) + a[2] - terrainDrop
        : groundY(a[1]) + _lakeLevel - terrainDrop + 1.8;
    final yB = b.length >= 3
        ? groundY(b[1]) + b[2] - terrainDrop
        : groundY(b[1]) + _lakeLevel - terrainDrop + 1.8;
    out.addAll(_roadSeg(a, b, w, yA, yB, mat));
  }
  return out;
}

/// White edge lines along both sides of a route.
List<Tri> _edgeLines(List<List<double>> pts, double w) {
  final out = <Tri>[];
  for (int i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final yA = a.length >= 3
        ? groundY(a[1]) + a[2] - terrainDrop
        : groundY(a[1]) + _lakeLevel - terrainDrop + 1.8;
    final yB = b.length >= 3
        ? groundY(b[1]) + b[2] - terrainDrop
        : groundY(b[1]) + _lakeLevel - terrainDrop + 1.8;
    final off = w / 2 - 0.28;
    for (final s in [-1, 1]) {
      out.addAll(_lineSeg(a, b, s * off, 0.11, yA, yB, _mWhite));
    }
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════
// buildCanal -- the drainage channel (concrete + water)
// ═════════════════════════════════════════════════════════════════════════

/// The [用水路] -- drainage channel concrete and water surface.
///
/// Port of canal.js: revetment walls, channel bed, coping, bank slabs,
/// weep holes, algae tide line, water-surface grid, darker depth bands,
/// and sky-reflection blocks.
///
/// The companion `canal_details.dart` supplies the crossings, sluice,
/// headwalls, paths, railings, planting, reeds, furniture, and signage.
/// Only the train-streak reflection remains dynamic in the browser source;
/// this deterministic native scene presents the authored opening state.
List<Tri> buildCanal() {
  final y0 = groundY(_canalZ);
  final waterY = y0 - 1.15;
  final bedY = y0 - _canalDepth + 0.28;
  final xMid = (_canalX0 + _canalX1) / 2.0;
  final totalL = (_canalX1 - _canalX0) + 2 * _endTail;
  final out = <Tri>[];
  final parts = <Part>[];

  // -- bank slabs (both sides, gapped for the road crossing) --
  final bankRuns = <List<double>>[
    [_canalX0 - _endTail, _roadGap0],
    [_roadGap1, _canalX1 + _endTail],
  ];
  for (final s in [-1, 1]) {
    final zc = _canalZ + s * ((_canalHalf + _slabOut) / 2);
    for (final run in bankRuns) {
      parts.add(Part(
        boxGeometry(run[1] - run[0], 0.9, _slabOut - _canalHalf),
        trs((run[0] + run[1]) / 2, y0 - 0.45, zc),
        _mConcreteMid,
      ));
    }
  }

  // -- revetment walls (both sides, full length including tails) --
  for (final s in [-1, 1]) {
    parts.add(Part(
      boxGeometry(totalL, _canalDepth, 0.34),
      trs(xMid, y0 - _canalDepth / 2, _canalZ + s * (_canalHalf - 0.17)),
      _mConcreteMid,
    ));
  }

  // -- channel bed --
  parts.add(Part(
    boxGeometry(totalL, 0.28, _wallIn * 2),
    trs(xMid, bedY - 0.14, _canalZ),
    _mConcreteMid,
  ));

  // -- coping (dressed stretch only, gapped for road) --
  final dressRuns = <List<double>>[
    [_dressW, _roadGap0],
    [_roadGap1, _dressE],
  ];
  for (final s in [-1, 1]) {
    for (final run in dressRuns) {
      parts.add(Part(
        boxGeometry(run[1] - run[0], 0.16, 0.56),
        trs((run[0] + run[1]) / 2, y0 + 0.08,
            _canalZ + s * (_canalHalf - 0.05)),
        _mConcrete,
      ));
    }
  }

  // -- weep holes (small dark boxes, dressed stretch) --
  for (double x = _dressW + 3; x < _dressE - 3; x += 4.6) {
    if (x > _roadGap0 - 1 && x < _roadGap1 + 1) continue;
    for (final s in [-1, 1]) {
      parts.add(Part(
        boxGeometry(0.24, 0.18, 0.06),
        trs(x, y0 - 0.62, _canalZ + s * (_wallIn + 0.03)),
        _mConcreteDark,
      ));
    }
  }

  // -- algae tide line on the revetment (dressed stretch) --
  for (final s in [-1, 1]) {
    for (final run in dressRuns) {
      parts.add(Part(
        boxGeometry(run[1] - run[0], 0.22, 0.03),
        trs((run[0] + run[1]) / 2, waterY + 0.1,
            _canalZ + s * (_wallIn - 0.02)),
        _mMoss,
      ));
    }
  }

  out.addAll(bake(parts));

  // -- water surface (flat grid, headwall to headwall) --
  final wX0 = _canalX0 + _hwT;
  final wX1 = _canalX1 - _hwT;
  final wg =
      _flatGrid(wX0, wX1, _canalZ - _wallIn, _canalZ + _wallIn, waterY, 2.0);
  out.addAll(bake([Part(wg, Matrix4.identity(), _mWaterDeep)]));

  // -- darker depth bands (scattered planes on water, dressed stretch) --
  final rng = RngKit(9091);
  final dL = _dressE - _dressW;
  final depthParts = <Part>[];
  for (int i = 0; i < 22; i++) {
    depthParts.add(Part(
      planeGeometry(rng.range(3.0, 7.0), rng.range(0.5, 1.3)),
      trs(_dressW + 3 + rng.range(0, dL - 8), waterY + 0.006,
          _canalZ + rng.range(-0.6, 0.6), -math.pi / 2, 0, 0),
      _mBedBand,
    ));
  }
  out.addAll(bake(depthParts));

  // -- sky-reflection blocks (pale panels on water, dressed stretch) --
  final skyParts = <Part>[];
  for (int i = 0; i < 38; i++) {
    skyParts.add(Part(
      planeGeometry(rng.range(1.4, 4.4), rng.range(0.16, 0.42)),
      trs(_dressW + 2 + rng.range(0, dL - 5), waterY + 0.014,
          _canalZ + rng.range(-1.3, 1.3), -math.pi / 2, 0, 0),
      _mWaterSky,
    ));
  }
  out.addAll(bake(skyParts));

  return out;
}

// ═════════════════════════════════════════════════════════════════════════
// buildLake -- the lake water surface
// ═════════════════════════════════════════════════════════════════════════

/// [ひばり湖] -- the water surface and its visual layers.
///
/// Port of lake.js: water body (flat grid), shallow margin (strips along
/// shoreline), deep-middle (central area), sky-reflection blocks, glint
/// bands, and echo reflections (hill/blossom).
///
/// Deferred: animated wind lanes, ripple rings, reeds, lily pads, flowers,
/// birds/ducks/wakes, flotsam (driftwood, posts, stones), riding petals,
/// shore barrier colliders, outfall stream (needs channelLine).
List<Tri> buildLake() {
  // waterY at z=-88: groundY(-88) is fully ramped at 1.05
  final wy = groundY(-88.0) + _lakeLevel - terrainDrop;
  final rng = RngKit(70211);
  final out = <Tri>[];

  // -- scalar-field body and depth-tone layers --
  // The source lake is the positive contour of its authored bed, not a survey
  // rectangle. The signed shoreline distance masks the perched lake away from
  // the surrounding buried hill apron.
  out.addAll(_contourFill((x, z) {
    final near = _lakeNear(x, z);
    return math.min(_lakeDepth(x, z), near.distance + 1.2);
  }, wy, _mLakeWater));
  out.addAll(_contourFill((x, z) {
    final near = _lakeNear(x, z);
    final depth = _lakeDepth(x, z);
    return math.min(math.min(depth - .06, .85 - depth), near.distance + 1.0);
  }, wy + .012, _mLakeShallow));
  out.addAll(_contourFill((x, z) {
    final near = _lakeNear(x, z);
    return math.min(_lakeDepth(x, z) - 1.75, near.distance);
  }, wy + .008, _mLakeDeep));

  // -- sky-reflection blocks (pale panels on the surface) --
  final skyParts = <Part>[];
  for (int k = 0; k < 96; k++) {
    final x = rng.range(_lakeGx0 + 4, _lakeGx1 - 4);
    final z = rng.range(_lakeGz0 + 4, _lakeGz1 - 4);
    // skip if clearly outside the shoreline (rough bbox check)
    if (x < 142 || x > 250 || z < -137 || z > -40) continue;
    skyParts.add(Part(
      planeGeometry(rng.range(2.6, 8.0), rng.range(0.5, 1.5)),
      trs(x, wy + 0.026, z, -math.pi / 2, rng.range(-0.22, 0.22), 0),
      _mLakeSky,
    ));
  }
  out.addAll(bake(skyParts));

  // -- glint bands: very few, very pale, very long --
  final glintParts = <Part>[];
  for (final spec in [
    [166.0, -62.0, 26.0],
    [182.0, -74.0, 34.0],
    [196.0, -96.0, 30.0],
    [212.0, -66.0, 22.0],
    [226.0, -104.0, 18.0],
  ]) {
    for (int k = 0; k < 3; k++) {
      glintParts.add(Part(
        planeGeometry(spec[2] * rng.range(0.5, 1.0), rng.range(0.10, 0.22)),
        trs(
            spec[0] + rng.range(-4, 4),
            wy + 0.032,
            spec[1] + rng.range(-2.6, 2.6),
            -math.pi / 2,
            rng.range(-0.1, 0.1),
            0),
        _mLakeGlint,
      ));
    }
  }
  out.addAll(bake(glintParts));

  // -- echo reflections: hill echo (far rim) and bloom echo (near bank) --
  _buildEchoes(out, rng, wy);

  // Deterministic still-frame of the slow ten-second ripple cycle. The native
  // renderer has no scene animation loop, so retain the single mid-basin ring
  // visible in the reference capture rather than freezing every ring at once.
  out.addAll(_lakeRing(158, -74, 1.34, 1.48, wy + .036));

  return out;
}

/// Static authored details that give the reservoir scale and life: sheltered
/// lily bays, four waterbirds with wakes, old fence posts and driftwood at the
/// fluctuating waterline, riprap, and blossom collected against the lee shore.
List<Tri> buildLakeDetails() {
  final rng = RngKit(70531);
  final waterY = groundY(-88) + _lakeLevel - terrainDrop;
  final out = <Tri>[];
  final pads = <Part>[], flowers = <Part>[];

  for (final bay in const [
    (218.0, -50.0, 13.0, 46),
    (184.0, -118.0, 11.0, 38),
    (206.0, -128.0, 12.0, 34),
  ]) {
    var accepted = 0;
    for (var attempt = 0;
        attempt < bay.$4 * 8 && accepted < bay.$4;
        attempt++) {
      final angle = rng.range(0, math.pi * 2);
      final radius = math.sqrt(rng.next()) * bay.$3;
      final x = bay.$1 + math.cos(angle) * radius;
      final z = bay.$2 + math.sin(angle) * radius;
      final depth = _lakeDepth(x, z);
      if (depth < .22 || depth > 1.15 || !lakeform.inLakePoly(x, z)) continue;
      final r = rng.range(.26, .52);
      pads.add(Part(
          cylGeometry(r, r * .88, .018, 9),
          trs(x, waterY + .018, z, 0, rng.range(0, 3), 0),
          accepted.isEven ? _mLilyPad : _mLilyPadAlt));
      if (rng.chance(.13)) {
        flowers
          ..add(Part(cylGeometry(0, .075, .13, 6), trs(x, waterY + .075, z),
              _mLilyFlower))
          ..add(Part(icosahedronGeometry(.055, 0), trs(x, waterY + .15, z),
              _mLilyFlower));
      }
      accepted++;
    }
  }
  out
    ..addAll(bake(pads))
    ..addAll(bake(flowers));

  // Four stationary birds, as in the source; their wakes carry the silhouette
  // at the distances where the bodies alone would read as dots.
  final darkBird = <Part>[],
      paleBird = <Part>[],
      bills = <Part>[],
      wakes = <Part>[];
  for (final bird in const [
    (163.0, -70.0, .9, false),
    (166.4, -73.2, 1.7, true),
    (204.0, -120.0, -2.1, false),
    (227.0, -58.0, 2.6, true),
  ]) {
    final x = bird.$1, z = bird.$2, yaw = bird.$3;
    if (_lakeDepth(x, z) < .15) continue;
    final c = math.cos(yaw), s = math.sin(yaw);
    darkBird
      ..add(Part(icosahedronGeometry(.155, 1),
          trs(x, waterY + .005, z, 0, yaw, 0, 1.32, .78, 1), _mDuck))
      ..add(Part(cylGeometry(0, .085, .24, 5),
          trs(x - c * .21, waterY + .075, z + s * .21, 0, yaw, -.9), _mDuck))
      ..add(Part(cylGeometry(.036, .05, .20, 6),
          trs(x + c * .13, waterY + .135, z - s * .13, 0, yaw, -.2), _mDuck));
    (bird.$4 ? paleBird : darkBird).add(Part(
        icosahedronGeometry(.062, 1),
        trs(x + c * .155, waterY + .245, z - s * .155),
        bird.$4 ? _mDuckPale : _mDuck));
    bills.add(Part(boxGeometry(.085, .024, .038),
        trs(x + c * .215, waterY + .23, z - s * .215, 0, yaw, 0), _mDuckBill));
    for (var k = 0; k < 3; k++) {
      final offset = .5 + k * .9;
      wakes.add(Part(
          planeGeometry(.7 + k * .55, .07),
          trs(x - c * offset, waterY + .03, z + s * offset, -math.pi / 2,
              yaw + math.pi / 2, 0),
          _mLakeRipple));
    }
  }
  out
    ..addAll(bake(darkBird))
    ..addAll(bake(paleBird))
    ..addAll(bake(bills))
    ..addAll(bake(wakes));

  final wood = <Part>[], wetWood = <Part>[], stones = <Part>[];
  for (var k = 0; k < 9; k++) {
    final t = k / 8;
    final x = 206 + t * 18, z = -138.6 + t * 3.4;
    final depth = _lakeDepth(x, z);
    if (depth < -.2) continue;
    final height = rng.range(.9, 1.45);
    final baseY = waterY - math.max(0, depth);
    wood.add(Part(
        cylGeometry(.062, .075, height, 6),
        trs(x, baseY + height / 2, z, rng.range(-.05, .05), 0,
            rng.range(-.09, .09)),
        _mTimber));
    wetWood.add(Part(cylGeometry(.078, .09, .3, 6),
        trs(x, baseY + math.max(0, depth) * .5, z), _mTimberDark));
  }
  for (final log in const [
    (162.4, -128.0, 2.4, .7),
    (196.0, -140.0, 3.1, -.4),
    (232.0, -136.0, 1.9, 1.2),
    (250.0, -104.0, 2.6, .2),
    (244.0, -118.0, 2.1, -1.0),
  ]) {
    final depth = math.max(0, _lakeDepth(log.$1, log.$2));
    wood.add(Part(
        cylGeometry(.11, .15, log.$3, 6),
        trs(log.$1, waterY - depth + .09, log.$2, math.pi / 2, log.$4, .04),
        _mDrift));
  }
  for (var attempt = 0; attempt < 520 && stones.length < 110; attempt++) {
    final x = rng.range(_lakeGx0, _lakeGx1);
    final z = rng.range(_lakeGz0, _lakeGz1);
    final depth = _lakeDepth(x, z);
    if (depth < -.55 || depth > .30) continue;
    final r = rng.range(.16, .42);
    stones.add(Part(
        icosahedronGeometry(r, 0),
        trs(x, waterY - math.max(0, depth) + r * .36, z, rng.range(-.3, .3),
            rng.range(0, 3), rng.range(-.3, .3), 1, rng.range(.5, .8), 1),
        _mLakeStone));
  }
  out
    ..addAll(bake(wood))
    ..addAll(bake(wetWood))
    ..addAll(bake(stones));

  final petals = <Part>[];
  for (var attempt = 0; attempt < 2480 && petals.length < 620; attempt++) {
    final x = rng.range(_lakeGx0, _lakeGx1);
    final z = rng.range(_lakeGz0, _lakeGz1);
    final depth = _lakeDepth(x, z);
    if (depth < .05 || !lakeform.inLakePoly(x, z)) continue;
    if (!rng.chance(depth < .9 ? .8 : .14)) continue;
    final scale = rng.range(.8, 1.5);
    petals.add(Part(
        planeGeometry(.17, .13),
        trs(x, waterY + .042, z, -math.pi / 2, rng.range(0, 6.28), 0, scale, 1,
            scale),
        _mWaterPetal));
  }
  out.addAll(bake(petals));
  return out;
}

/// Simplified echo reflections: scattered planes representing block-colour
/// reflections of the far rim (hillEcho) and near-bank cherry blossoms
/// (bloomEcho), laid toward the viewer from their source shore.
void _buildEchoes(List<Tri> out, RngKit rng, double wy) {
  // -- far rim echoes (hill echo, desaturated blue-green) --
  final hillParts = <Part>[];
  for (final pt in [
    [172.0, -41.4],
    [182.0, -40.2],
    [192.0, -39.6],
    [202.0, -39.8],
    [212.0, -40.6],
    [222.0, -43.4],
    [231.0, -48.4],
    [239.0, -55.0],
    [245.0, -63.0],
    [248.0, -72.0],
    [249.0, -82.0],
    [248.0, -92.0],
    [245.0, -102.0],
    [241.0, -112.0],
  ]) {
    final x = pt[0], z = pt[1];
    final dx = _lakeCx - x, dz = _lakeCz - z;
    final n = math.sqrt(dx * dx + dz * dz);
    final ux = dx / n, uz = dz / n;
    final segLen = rng.range(9, 19);
    final wide = rng.range(2.2, 5.0);
    var run = 0.0;
    while (run < segLen) {
      final seg = rng.range(1.6, 4.4);
      final px = x + ux * (run + seg / 2);
      final pz = z + uz * (run + seg / 2);
      // rough inside-lake check
      if (px > _lakeGx0 + 10 &&
          px < _lakeGx1 - 10 &&
          pz > _lakeGz0 + 10 &&
          pz < _lakeGz1 - 10) {
        hillParts.add(Part(
          planeGeometry(wide * rng.range(0.7, 1.15), seg),
          trs(px, wy + 0.018, pz, -math.pi / 2, math.atan2(ux, uz), 0),
          _mLakeHillEcho,
        ));
      }
      run += seg + rng.range(0.5, 2.0);
    }
  }
  // peninsula echoes
  for (final pt in [
    [188.0, -104.0],
    [193.0, -100.4],
    [198.0, -104.0]
  ]) {
    final x = pt[0], z = pt[1];
    final dx = x - 176.0, dz = z + 96.0;
    final n = math.sqrt(dx * dx + dz * dz);
    final ux = dx / n, uz = dz / n;
    var run = 0.0;
    final segLen = rng.range(5, 9);
    while (run < segLen) {
      final seg = rng.range(1.6, 4.4);
      hillParts.add(Part(
        planeGeometry(rng.range(1.6, 3.0) * rng.range(0.7, 1.15), seg),
        trs(x + ux * (run + seg / 2), wy + 0.018, z + uz * (run + seg / 2),
            -math.pi / 2, math.atan2(ux, uz), 0),
        _mLakeHillEcho,
      ));
      run += seg + rng.range(0.5, 2.0);
    }
  }
  out.addAll(bake(hillParts));

  // -- near bank blossom echoes (pink) --
  final bloomParts = <Part>[];
  for (final pt in [
    [143.4, -71.6],
    [142.4, -85.0],
    [147.0, -97.6],
    [161.0, -125.4],
    [173.6, -132.0],
    [204.4, -134.0],
    [215.6, -136.4],
    [228.0, -134.6],
  ]) {
    final x = pt[0], z = pt[1];
    final dx = _lakeCx - x, dz = _lakeCz - z;
    final n = math.sqrt(dx * dx + dz * dz);
    final ux = dx / n, uz = dz / n;
    var run = 0.0;
    final segLen = rng.range(4, 8);
    while (run < segLen) {
      final seg = rng.range(1.6, 4.4);
      bloomParts.add(Part(
        planeGeometry(rng.range(1.2, 2.6) * rng.range(0.7, 1.15), seg),
        trs(x + ux * (run + seg / 2), wy + 0.022, z + uz * (run + seg / 2),
            -math.pi / 2, math.atan2(ux, uz), 0),
        _mLakeBloomEcho,
      ));
      run += seg + rng.range(0.5, 2.0);
    }
  }
  out.addAll(bake(bloomParts));
}

// ═════════════════════════════════════════════════════════════════════════
// buildLakePier -- 見晴らし桟橋
// ═════════════════════════════════════════════════════════════════════════

/// The lake park's principal viewpoint: a 26 m timber trestle on piles, with
/// a broad head platform and timber rails. Dimensions and placement follow
/// `kohan.js buildPier`; the deck is deliberately only 0.5 m above the water.
List<Tri> buildLakePier() {
  const rootX = 140.8; // SHORE_GAPS[0].x - 1.4
  const endX = 168.4; // SITES.pierHead.x + 1.4
  const headX = 167.0;
  const z = -80.0;
  const walkW = 2.4;
  final waterY = groundY(z) + _lakeLevel - terrainDrop;
  final deckY = waterY + 0.5;
  final parts = <Part>[];

  void timberBox(double w, double h, double d, double x, double y, double zz,
      {Mat mat = _mTimber, double ry = 0}) {
    parts.add(Part(boxGeometry(w, h, d), trs(x, y, zz, 0, ry, 0), mat));
  }

  // Six independently supported bays make the changing water depth visible.
  // Closely spaced cross-planks are the dominant line-work in the reference.
  const walkEnd = endX - 3.2;
  const bays = 6;
  for (var bay = 0; bay < bays; bay++) {
    final x0 = rootX + (walkEnd - rootX) * bay / bays;
    final x1 = rootX + (walkEnd - rootX) * (bay + 1) / bays;
    final bayLength = x1 - x0;
    final cx = (x0 + x1) / 2;

    for (final side in [-1.0, 1.0]) {
      timberBox(bayLength + 0.04, 0.19, 0.14, cx, deckY - 0.12,
          z + side * (walkW / 2 - 0.28),
          mat: _mTimberDark);
    }
    final boardCount = math.max(2, (bayLength / 0.2).round());
    for (var k = 0; k < boardCount; k++) {
      final bx = x0 + 0.08 + k * (bayLength - 0.16) / (boardCount - 1);
      timberBox(0.168, 0.055, walkW, bx, deckY + 0.03, z);
    }
  }

  // The 5.6 x 4.8 m viewpoint head.
  for (final side in [-1.0, 0.0, 1.0]) {
    timberBox(5.6, 0.19, 0.14, headX, deckY - 0.12, z + side * (4.8 / 2 - 0.28),
        mat: _mTimberDark);
  }
  const headBoardCount = 24;
  for (var k = 0; k < headBoardCount; k++) {
    final bz = z - 2.4 + 0.08 + k * (4.8 - 0.16) / (headBoardCount - 1);
    timberBox(5.6, 0.055, 0.168, headX, deckY + 0.03, bz);
  }

  // Paired piles: shallow at the park edge, progressively taller offshore.
  for (double px = rootX + 0.28; px <= walkEnd - 0.1; px += 1.9) {
    final depth = 0.25 + 2.15 * ((px - rootX) / (endX - rootX));
    final height = deckY - (waterY - depth) + 0.12;
    for (final side in [-1.0, 1.0]) {
      parts.add(Part(
        cylGeometry(0.10, 0.12, height, 7),
        trs(px, deckY - height / 2 + 0.06, z + side * (walkW / 2 - 0.28)),
        _mTimberDark,
      ));
    }
  }
  for (final px in [headX - 2.5, headX, headX + 2.5]) {
    const depth = 2.35;
    final height = deckY - (waterY - depth) + 0.12;
    for (final pz in [z - 2.12, z, z + 2.12]) {
      parts.add(Part(
        cylGeometry(0.10, 0.12, height, 7),
        trs(px, deckY - height / 2 + 0.06, pz),
        _mTimberDark,
      ));
    }
  }

  void rail(double ax, double az, double bx, double bz) {
    final dx = bx - ax, dz = bz - az;
    final len = math.sqrt(dx * dx + dz * dz);
    final ry = math.atan2(dx, dz);
    final n = math.max(2, (len / 1.35).round());
    for (var k = 0; k <= n; k++) {
      final t = k / n;
      timberBox(0.1, 1.05, 0.1, ax + dx * t, deckY + 0.55, az + dz * t);
    }
    for (final h in [1.0, 0.52]) {
      timberBox(0.07, 0.07, len, (ax + bx) / 2, deckY + h, (az + bz) / 2,
          ry: ry);
    }
  }

  for (final side in [-1.0, 1.0]) {
    rail(rootX, z + side * walkW / 2, endX - 3.6, z + side * walkW / 2);
  }
  rail(headX - 2.8, z - 2.4, headX + 2.8, z - 2.4);
  rail(headX - 2.8, z + 2.4, headX + 2.8, z + 2.4);
  rail(headX + 2.8, z - 2.4, headX + 2.8, z + 2.4);
  rail(headX - 2.8, z - 2.4, headX - 2.8, z - 1.3);
  rail(headX - 2.8, z + 1.3, headX - 2.8, z + 2.4);

  // Four low bollards and the two compact lamps visible on the head rails.
  for (final point in [
    [headX - 2.2, z - 2.1],
    [headX + 2.2, z - 2.1],
    [headX - 2.2, z + 2.1],
    [headX + 2.2, z + 2.1],
  ]) {
    parts.add(Part(cylGeometry(0.09, 0.11, 0.44, 8),
        trs(point[0], deckY + 0.25, point[1]), _mTimberDark));
    parts.add(Part(cylGeometry(0.13, 0.13, 0.06, 8),
        trs(point[0], deckY + 0.48, point[1]), _mTimberDark));
  }
  for (final side in [-1.0, 1.0]) {
    final lz = z + side * 2.1;
    parts.add(Part(cylGeometry(0.055, 0.065, 1.5, 7),
        trs(headX - 2.6, deckY + 0.81, lz), _mMetalDark));
    timberBox(0.22, 0.14, 0.22, headX - 2.6, deckY + 1.62, lz, mat: _mMetal);
  }

  return bake(parts);
}

// ═════════════════════════════════════════════════════════════════════════
// buildLakeReeds -- 葦
// ═════════════════════════════════════════════════════════════════════════

/// Dense reed beds following the lake's shallow contour. The west park shore
/// is deliberately thinner than the natural south and east banks, matching the
/// mowing/revetment treatment in `lake.js`.
List<Tri> buildLakeReeds() {
  final rng = RngKit(70419);
  final waterY = groundY(-88.0) + _lakeLevel - terrainDrop;
  final reedParts = <List<Part>>[<Part>[], <Part>[]];
  final headParts = <Part>[];

  // Source geometry has its pivot at the base so lean moves the blade tip.
  final blade = applyMatrix(
      cylGeometry(0, 0.038, 1, 5), Matrix4.translation(Vector3(0, 0.5, 0)));
  final head = applyMatrix(
      cylGeometry(0, 0.06, 0.4, 5), Matrix4.translation(Vector3(0, 0.2, 0)));

  // Pick shoreline segments by length and by the authored bank treatment.
  // 0..7 is the park/boat-house side; 8..27 is the natural reed flat; the
  // northern rim is moderately planted.
  final cumulative = <double>[];
  var totalWeight = 0.0;
  for (var i = 0; i < _shore.length; i++) {
    final a = _shore[i], b = _shore[(i + 1) % _shore.length];
    final dx = b[0] - a[0], dz = b[1] - a[1];
    final len = math.sqrt(dx * dx + dz * dz);
    final density = i <= 7
        ? 0.34
        : i <= 27
            ? 1.0
            : 0.62;
    totalWeight += len * density;
    cumulative.add(totalWeight);
  }

  for (var clump = 0; clump < 620; clump++) {
    final choice = rng.range(0, totalWeight);
    var segment = 0;
    while (segment < cumulative.length - 1 && choice > cumulative[segment]) {
      segment++;
    }
    final a = _shore[segment];
    final b = _shore[(segment + 1) % _shore.length];
    final dx = b[0] - a[0], dz = b[1] - a[1];
    final len = math.sqrt(dx * dx + dz * dz);
    final t = rng.range(0.02, 0.98);
    final edgeX = a[0] + dx * t;
    final edgeZ = a[1] + dz * t;
    final inwardX = -dz / len;
    final inwardZ = dx / len;
    final depth = rng.range(0.02, 0.55);
    final inset = rng.range(0.35, 1.1) + depth * rng.range(3.2, 8.0);
    final x = edgeX + inwardX * inset;
    final z = edgeZ + inwardZ * inset;
    final baseY = waterY - depth;

    final blades = rng.ints(9, 16);
    for (var k = 0; k < blades; k++) {
      final angle = rng.range(0, math.pi * 2);
      final radius = rng.range(0, 0.34);
      final px = x + math.cos(angle) * radius;
      final pz = z + math.sin(angle) * radius;
      final height = rng.range(1.45, 2.35);
      final lean = rng.range(0.06, 0.26);
      final leanAngle = rng.range(0, math.pi * 2);
      final rx = lean * math.sin(leanAngle);
      final rz = -lean * math.cos(leanAngle);
      reedParts[k % 2].add(Part(
        blade,
        trs(px, baseY, pz, rx, 0, rz, 1, height, 1),
        k.isEven ? _mReed : _mReedDeep,
      ));
      if (rng.chance(0.34)) {
        headParts.add(Part(
          head,
          trs(
              px + math.sin(leanAngle) * lean * height * 0.5,
              baseY + height * 0.98,
              pz - math.cos(leanAngle) * lean * height * 0.5,
              rx,
              rng.range(0, 3),
              rz),
          _mReedHead,
        ));
      }
    }
  }

  return [
    ...bake(reedParts[0]),
    ...bake(reedParts[1]),
    ...bake(headParts),
  ];
}

/// Trees framing the north-east end of the lake. These are the exact dam-side
/// plantings authored by `lakeroad.js`, visible beyond the pier from the park.
List<Tri> buildLakeRimPlanting({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final out = <Tri>[];
  out.addAll(buildGrove([
    GroveSpot(
        x: 138.0,
        z: -39.0,
        y: hillSurfaceY(138.0, -39.0),
        scale: 1.45,
        seed: 9231,
        spread: 1.1),
    GroveSpot(
        x: 162.6,
        z: -34.6,
        y: hillSurfaceY(162.6, -34.6),
        scale: 1.5,
        seed: 9232,
        spread: 1.15),
    // The first hill-forest belt above the north shore. Canopy centres were
    // recovered from the reference planet and map back to these flat points.
    GroveSpot(
        x: 192.0,
        z: -37.0,
        y: hillSurfaceY(192.0, -37.0),
        scale: 1.5,
        seed: 40117,
        spread: 1.12),
    GroveSpot(
        x: 212.0,
        z: -39.0,
        y: hillSurfaceY(212.0, -39.0),
        scale: 1.48,
        seed: 40124,
        spread: 1.1),
  ]));
  out.addAll(buildSakura([
    SakuraSpot(
        x: 159.6,
        z: -47.4,
        y: hillSurfaceY(159.6, -47.4),
        scale: 1.2,
        seed: 9241,
        lean: 0.12,
        leanDir: 2.0),
    SakuraSpot(
        x: 204.0,
        z: -36.0,
        y: hillSurfaceY(204.0, -36.0),
        scale: 1.18,
        seed: 40131,
        lean: 0.1,
        leanDir: 3.5),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  final cedars = <CedarSpot>[];
  var cedarSeed = 52140;
  for (final point in [
    [180.0, -24.0],
    [186.0, -30.0],
    [189.0, -24.0],
    [195.0, -30.0],
    [198.0, -24.0],
    [201.0, -30.0],
    [204.0, -24.0],
    [207.0, -30.0],
    [210.0, -18.0],
    [213.0, -24.0],
    [216.0, -30.0],
    [219.0, -24.0],
    [222.0, -18.0],
  ]) {
    cedars.add(CedarSpot(
        x: point[0],
        z: point[1],
        y: hillSurfaceY(point[0], point[1]),
        scale: 0.96,
        seed: cedarSeed++));
  }
  out.addAll(buildCedar(cedars));
  return out;
}

// ═════════════════════════════════════════════════════════════════════════
// buildLakeRoad -- the road, embankment, and way over the hill
// ═════════════════════════════════════════════════════════════════════════

/// [湖畔道路] -- the management road, embankment, and spillway.
///
/// Port of lakeroad.js: three road surfaces (climb, dam crest, shore),
/// white edge lines, dam crest kerbs, spillway concrete, cutting kerb
/// and drainage channel, and guard-rail posts.
///
/// `lakeroad_details.dart` supplies railings, signage, furniture, planting,
/// management works, dam apparatus, trail access, and the overlook platform.
List<Tri> buildLakeRoad() {
  final out = <Tri>[];
  final parts = <Part>[];

  // -- road surfaces (three legs) --
  out.addAll(_bakeRoute(_lakeRoadPts, 4.0, _mAsphalt));
  out.addAll(_bakeRoute(_damRoadPts, 4.0, _mAsphalt));
  out.addAll(_bakeRoute(_shoreRoadPts, 3.6, _mAsphalt));

  // -- edge lines (white, both sides, all three legs) --
  out.addAll(_edgeLines(_lakeRoadPts, 4.0));
  out.addAll(_edgeLines(_damRoadPts, 4.0));
  out.addAll(_edgeLines(_shoreRoadPts, 3.6));

  // -- centre line (yellow, dashed, climb only) --
  for (int i = 4; i < _lakeRoadPts.length - 1; i++) {
    final a = _lakeRoadPts[i], b = _lakeRoadPts[i + 1];
    // dash: emit every other segment (approx 2.4 m dash)
    if (i % 2 == 0) continue;
    final yA = groundY(a[1]) + a[2] - terrainDrop;
    final yB = groundY(b[1]) + b[2] - terrainDrop;
    out.addAll(_lineSeg(a, b, 0.0, 0.13, yA, yB, _mYellow));
  }

  // -- cutting kerb (x 116..138, north side of road) --
  for (int k = 0; k < 22; k++) {
    final t = k / 21.0;
    final x = 116 + t * 22;
    final z = -31.4 - t * 0.6 + 3.1;
    final y = groundY(z) + _lakeLevel - terrainDrop - 0.3;
    // approximate: road surface is at grade + flat value
    parts.add(Part(
      boxGeometry(1.1, 0.55, 0.34),
      trs(x, y + 0.16, z, 0, 0.06, 0),
      _mConcreteMid,
    ));
  }

  // -- cutting channel (open U-section beside kerb) --
  for (int k = 0; k < 30; k++) {
    final t = k / 29.0;
    final x = 116 + t * 22;
    final z = -31.4 - t * 0.6 + 2.6;
    final y = groundY(z) + _lakeLevel - terrainDrop - 0.3;
    parts.add(
        Part(boxGeometry(0.78, 0.2, 0.42), trs(x, y + 0.02, z), _mConcrete));
    parts.add(Part(
        boxGeometry(0.78, 0.26, 0.09), trs(x, y + 0.1, z - 0.2), _mConcrete));
    parts.add(Part(
        boxGeometry(0.78, 0.26, 0.09), trs(x, y + 0.1, z + 0.2), _mConcrete));
  }

  // -- dam crest kerbs (both sides, along the dam centreline) --
  final damDx = _damBx - _damAx, damDz = _damBz - _damAz;
  final damLen = math.sqrt(damDx * damDx + damDz * damDz);
  final damUx = damDx / damLen, damUz = damDz / damLen;
  // perpendicular to dam (toward lake = south-east)
  final damNx = -damUz, damNz = damUx;
  for (int k = 0; k <= 15; k++) {
    final t = k / 15.0;
    for (final s in [1, -1]) {
      final px = _damAx + damDx * t + damNx * s * 2.15;
      final pz = _damAz + damDz * t + damNz * s * 2.15;
      // approximate Y: dam crest is at groundY + 6.3
      final py = groundY(pz) + _lakeLevel - terrainDrop + 2.9;
      parts.add(Part(
        boxGeometry(1.35, 0.34, 0.26),
        trs(px, py + 0.08, pz, 0, math.atan2(damUx, damUz), 0),
        _mConcreteMid,
      ));
    }
  }

  // -- spillway: concrete lining along approximate channel --
  // The spillway runs from the dam crest NE end down the outfall valley.
  // Approximate as a straight line from (155.6, -34.6) toward (150.6, -30.2).
  final spillPts = <List<double>>[
    [155.6, -34.6, 0.0],
    [152.0, -33.0, -0.4],
    [148.6, -31.8, -0.8],
    [145.0, -30.8, -1.2],
  ];
  for (int i = 0; i < spillPts.length - 1; i++) {
    final a = spillPts[i], b = spillPts[i + 1];
    final dx = b[0] - a[0], dz = b[1] - a[1];
    final len = math.sqrt(dx * dx + dz * dz);
    if (len < 0.5) continue;
    final ry = math.atan2(dx, dz);
    final cx = (a[0] + b[0]) / 2, cz = (a[1] + b[1]) / 2;
    final cy = groundY(cz) + _lakeLevel - terrainDrop - 0.8;
    // invert slab
    parts.add(Part(
      boxGeometry(3.0, 0.22, len + 0.1),
      trs(cx, cy + 0.05, cz, 0, ry, 0),
      _mConcrete,
    ));
    // side walls
    for (final s in [-1, 1]) {
      final wx = cx + math.cos(ry) * s * 1.62;
      final wz = cz - math.sin(ry) * s * 1.62;
      parts.add(Part(
        boxGeometry(0.26, 0.9, len + 0.1),
        trs(wx, (cy + 0.05 + 0.7) / 2, wz, 0, ry, 0),
        _mConcrete,
      ));
    }
  }
  // weir lip at spillway head
  {
    final a = spillPts[0];
    final ry = math.atan2(spillPts[1][0] - a[0], spillPts[1][1] - a[1]);
    parts.add(Part(
      boxGeometry(3.2, 0.42, 0.34),
      trs(a[0], groundY(a[1]) + _lakeLevel - terrainDrop - 0.8 + 0.05, a[1], 0,
          ry, 0),
      _mConcrete,
    ));
  }

  // -- slab bridge over spillway --
  {
    final bx = 155.6, bz = -34.6;
    final by = groundY(bz) + _lakeLevel - terrainDrop - 0.6;
    parts.add(Part(
      boxGeometry(5.6, 0.34, 4.6),
      trs(bx, by - 0.17, bz, 0, 0.6, 0),
      _mConcreteMid,
    ));
  }

  out.addAll(bake(parts));

  // -- guard-rail posts along cutting (simplified: metal cylinders) --
  final guardPts = <List<double>>[
    [112.0, -33.4],
    [120.0, -33.2],
    [130.0, -33.8],
    [139.0, -34.8],
  ];
  for (final pt in guardPts) {
    final x = pt[0], z = pt[1];
    final y = groundY(z) + _lakeLevel - terrainDrop - 0.3;
    out.addAll(bake([
      Part(cylGeometry(0.045, 0.055, 0.82, 7), trs(x, y + 0.41, z), _mMetal),
    ]));
  }
  // west-bend guard
  final guardW = <List<double>>[
    [132.4, -66.0],
    [131.0, -73.0],
    [131.0, -80.0],
    [132.6, -87.0],
  ];
  for (final pt in guardW) {
    final x = pt[0], z = pt[1];
    final y = groundY(z) + _lakeLevel - terrainDrop + 1.0;
    out.addAll(bake([
      Part(cylGeometry(0.045, 0.055, 0.82, 7), trs(x, y + 0.41, z), _mMetal),
    ]));
  }

  return out;
}
