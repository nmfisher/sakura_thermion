/// Dart port of the reference `src/world/buildings.js::makeHouse` — a residential
/// house: wall volume + sill + the four roof kinds (gable/hip/shed/flat) + front
/// windows, door, shutters, porch canopy and steps, second-floor windows + balcony.
///
/// External clutter (post box, bicycle, planters, bins) is deferred — those live
/// in props.js and get ported alongside the rest of the street furniture. The
/// building itself is complete. Built on the geometry substrate → bit-faithful.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// mats() — building palette (buildings.js WALLS/ROOFS + PAL).
const _wallCols = <int>[
  0xfaf6ef, 0xf2e7d3, 0xd6e3ee, 0xe7dbc4, 0xdedee6, 0xf0dcda, 0xdccdb6, 0xdde2d6
];
const _roofCols = <int>[0x59617a, 0x4d5c78, 0x6b585c, 0x4f6b70];
Mat _wallMat(int i) => Mat(_wallCols[i], tint: 0x6f6790, bands: '3');
Mat _roofMat(int i) => Mat(_roofCols[i], tint: 0x514b70, bands: '3');
const _trimMat = Mat(0x8b8496, tint: 0x5c5680, bands: '3'); // PAL.trim
const _metalMat = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDarkMat = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _glassMat = Mat(0x53627a, unlit: true); // flat PAL.glassDark
const _concreteMat = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3'); // PAL.concrete
const _doorMat = Mat(0x8a6f5c, tint: 0x5c5680, bands: '3');

class HouseOpts {
  const HouseOpts({
    required this.x,
    required this.z,
    this.w = 6.2,
    this.d = 7.0,
    this.floors = 2,
    this.face = 'x-',
    this.seed = 21,
    this.wall,
    this.roof,
    this.roofKind,
    this.shedDir,
    this.y = 0,
    this.porch = false,
    this.shutters = false,
  });
  final double x, z, w, d, y;
  final int floors, seed;
  final String face;
  final int? wall, roof;
  final String? roofKind;
  final int? shedDir;
  final bool porch, shutters;
}

final _faceDirs = <String, Vector2>{
  'x-': Vector2(-1, 0),
  'x+': Vector2(1, 0),
  'z-': Vector2(0, -1),
  'z+': Vector2(0, 1),
};

List<Tri> makeHouse(HouseOpts o) {
  final rng = RngKit(o.seed);
  final w = o.w, d = o.d, floors = o.floors;
  const fh = 2.72;
  final H = fh * floors;
  final wallMat = _wallMat(o.wall ?? rng.ints(0, _wallCols.length - 1));
  final roofMat = _roofMat(o.roof ?? rng.ints(0, _roofCols.length - 1));
  final roofKind = o.roofKind ?? rng.pick(['gable', 'hip', 'gable', 'flat', 'hip']);

  final dir = _faceDirs[o.face]!;
  final fx = dir.x, fz = dir.y;
  final frontIsX = fx != 0;
  final frontHalf = frontIsX ? w / 2 : d / 2;
  final sideHalf = frontIsX ? d / 2 : w / 2;

  final parts = <Part>[];
  void wall(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, wallMat));
  void roof(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, roofMat));
  void trim(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _trimMat));
  void metal(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _metalMat));
  void metalDark(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _metalDarkMat));
  void glass(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _glassMat));
  void concrete(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _concreteMat));
  void doorP(ThreeGeom g, Matrix4 mx) => parts.add(Part(g, mx, _doorMat));

  // ── volume ──
  wall(boxGeometry(w, H, d), trs(0, H / 2, 0));
  concrete(boxGeometry(w + 0.14, 0.42, d + 0.14), trs(0, 0.21, 0));
  if (floors == 2) {
    trim(boxGeometry(w + 0.08, 0.12, d + 0.08), trs(0, fh, 0));
  }

  // ── roof ──
  const eave = 0.42;
  final rw = w + eave * 2, rd = d + eave * 2;
  if (roofKind == 'gable') {
    final rh = 1.15 + rng.range(0, 0.5);
    final alongZ = d >= w;
    final span = alongZ ? rw : rd;
    final len = alongZ ? rd : rw;
    final slope = math.atan2(rh, span / 2);
    final slabLen = math.sqrt((span / 2) * (span / 2) + rh * rh) + 0.08;
    for (final s in [-1.0, 1.0]) {
      roof(
        boxGeometry(alongZ ? slabLen : len, 0.14, alongZ ? len : slabLen),
        alongZ
            ? trs(s * (span / 4), H + rh / 2, 0, 0, 0, -s * slope)
            : trs(0, H + rh / 2, s * (span / 4), s * slope, 0, 0),
      );
    }
    // gable end triangles (extruded), closing the roof volume.
    final triShape = <Vector2>[
      Vector2(-span / 2 + eave, 0),
      Vector2(span / 2 - eave, 0),
      Vector2(0, rh * (1 - (eave * 2) / span)),
    ];
    final triGeo = applyMatrix(extrudeGeometry(triShape, 0.16), trs(0, 0, -0.08));
    for (final s in [-1.0, 1.0]) {
      wall(
        triGeo,
        alongZ
            ? trs(0, H, s * (len / 2 - eave - 0.02))
            : trs(s * (len / 2 - eave - 0.02), H, 0, 0, math.pi / 2, 0),
      );
    }
    roof(boxGeometry(alongZ ? 0.22 : len, 0.17, alongZ ? len : 0.22), trs(0, H + rh + 0.04, 0));
  } else if (roofKind == 'hip') {
    final rh = 1.05 + rng.range(0, 0.4);
    final pyr = applyMatrix(
        cylGeometry(0, 1 / math.sqrt2, 1, 4), Matrix4.rotationY(math.pi / 4));
    roof(pyr, trs(0, H + rh / 2 + 0.06, 0, 0, 0, 0, rw, rh, rd));
    roof(boxGeometry(rw, 0.16, rd), trs(0, H + 0.06, 0));
  } else if (roofKind == 'shed') {
    final rh = 0.9 + rng.range(0, 0.5);
    final alongZ = d >= w;
    final span = alongZ ? rw : rd;
    final len = alongZ ? rd : rw;
    final dirS = (o.shedDir ?? 1).toDouble();
    final slope = math.atan2(rh, span);
    final slabLen = math.sqrt(span * span + rh * rh) + 0.06;
    roof(
      alongZ ? boxGeometry(slabLen, 0.15, len) : boxGeometry(len, 0.15, slabLen),
      alongZ
          ? trs(0, H + rh / 2 + 0.07, 0, 0, 0, dirS * slope)
          : trs(0, H + rh / 2 + 0.07, 0, -dirS * slope, 0, 0),
    );
    final triShape = <Vector2>[
      Vector2(-span / 2 + eave, 0),
      Vector2(span / 2 - eave, 0),
      Vector2(dirS * (span / 2 - eave), rh * (1 - (eave * 2) / span)),
    ];
    final triGeo = applyMatrix(extrudeGeometry(triShape, 0.16), trs(0, 0, -0.08));
    for (final s in [-1.0, 1.0]) {
      wall(
        triGeo,
        alongZ
            ? trs(0, H, s * (len / 2 - eave - 0.02))
            : trs(s * (len / 2 - eave - 0.02), H, 0, 0, math.pi / 2, 0),
      );
    }
    trim(
      alongZ ? boxGeometry(0.2, 0.2, len) : boxGeometry(len, 0.2, 0.2),
      alongZ ? trs(dirS * span / 2, H + rh + 0.1, 0) : trs(0, H + rh + 0.1, -dirS * span / 2),
    );
    metal(
      alongZ ? boxGeometry(0.14, 0.12, len) : boxGeometry(len, 0.12, 0.14),
      alongZ
          ? trs(-dirS * (span / 2 + 0.04), H + 0.06, 0)
          : trs(0, H + 0.06, dirS * (span / 2 + 0.04)),
    );
  } else {
    // flat
    roof(boxGeometry(w + 0.24, 0.18, d + 0.24), trs(0, H + 0.09, 0));
    for (final s in [-1.0, 1.0]) {
      roof(boxGeometry(w + 0.24, 0.34, 0.14), trs(0, H + 0.28, s * (d / 2 + 0.05)));
      roof(boxGeometry(0.14, 0.34, d + 0.24), trs(s * (w / 2 + 0.05), H + 0.28, 0));
    }
  }

  // ── front windows + door ──
  const winW = 1.5;
  final cols = ((frontHalf * 2 - 1.0) / 2.1).floor();
  final colsN = cols < 1 ? 1 : cols;
  double spread(int i, int n) => -frontHalf + (frontHalf * 2 * (i + 1)) / (n + 1);

  void placeFront(double u, double y, double ww, double wh, {bool isDoor = false}) {
    final px = frontIsX ? fx * (frontHalf + 0.02) : u;
    final pz = frontIsX ? u : fz * (frontHalf + 0.02);
    final dx = frontIsX ? 0.14 : ww;
    final dz = frontIsX ? ww : 0.14;
    if (isDoor) {
      doorP(boxGeometry(dx, wh, dz), trs(px + fx * 0.02, y, pz + fz * 0.02));
      trim(
        boxGeometry(frontIsX ? 0.16 : ww + 0.18, wh + 0.16, frontIsX ? ww + 0.18 : 0.16),
        trs(px - fx * 0.03, y, pz - fz * 0.03),
      );
    } else {
      trim(boxGeometry(dx, wh + 0.14, dz + (frontIsX ? 0.14 : 0)),
          trs(px - fx * 0.02, y, pz - fz * 0.02));
      final gx = frontIsX ? 0.06 : ww - 0.12;
      final gz = frontIsX ? ww - 0.12 : 0.06;
      glass(boxGeometry(gx, wh, gz), trs(px + fx * 0.05, y, pz + fz * 0.05));
      metal(boxGeometry(frontIsX ? 0.07 : 0.06, wh, frontIsX ? 0.06 : 0.07),
          trs(px + fx * 0.07, y, pz + fz * 0.07));
      trim(boxGeometry(frontIsX ? 0.2 : ww + 0.2, 0.08, frontIsX ? ww + 0.2 : 0.2),
          trs(px + fx * 0.03, y - wh / 2 - 0.09, pz + fz * 0.03));
    }
  }

  final doorIdx = rng.ints(0, colsN - 1);
  double doorU = 0;
  for (int i = 0; i < colsN; i++) {
    final u = spread(i, colsN);
    if (i == doorIdx) {
      doorU = u;
      placeFront(u, 1.05, 1.05, 2.05, isDoor: true);
    } else {
      placeFront(u, 1.42, winW, 1.25);
      if (o.shutters) {
        final px = frontIsX ? fx * (frontHalf + 0.14) : u;
        final pz = frontIsX ? u : fz * (frontHalf + 0.14);
        metal(boxGeometry(frontIsX ? 0.2 : winW + 0.24, 0.24, frontIsX ? winW + 0.24 : 0.2),
            trs(px, 2.22, pz));
        metalDark(boxGeometry(frontIsX ? 0.22 : winW + 0.3, 0.05, frontIsX ? winW + 0.3 : 0.22),
            trs(px, 2.36, pz));
      }
    }
  }

  // ── porch canopy + steps over the door ──
  if (o.porch) {
    const out = 0.85;
    final px = frontIsX ? fx * (frontHalf + out / 2) : doorU;
    final pz = frontIsX ? doorU : fz * (frontHalf + out / 2);
    trim(boxGeometry(frontIsX ? out : 1.9, 0.1, frontIsX ? 1.9 : out), trs(px, 2.36, pz));
    metal(
      boxGeometry(frontIsX ? out + 0.08 : 2.0, 0.06, frontIsX ? 2.0 : out + 0.08),
      trs(px, 2.29, pz),
    );
    for (final s in [-1.0, 1.0]) {
      final bx = frontIsX ? fx * (frontHalf + 0.2) : doorU + s * 0.82;
      final bz = frontIsX ? doorU + s * 0.82 : fz * (frontHalf + 0.2);
      metal(boxGeometry(frontIsX ? 0.42 : 0.05, 0.05, frontIsX ? 0.05 : 0.42), trs(bx, 2.18, bz));
      metal(boxGeometry(0.05, 0.34, 0.05), trs(bx, 2.06, bz));
    }
    for (int i = 0; i < 2; i++) {
      final t = 0.42 - i * 0.21;
      final sw = 1.5 - i * 0.14;
      const sd = 0.34;
      final sx2 = frontIsX ? fx * (frontHalf + sd * (i + 0.5)) : doorU;
      final sz2 = frontIsX ? doorU : fz * (frontHalf + sd * (i + 0.5));
      concrete(
        boxGeometry(frontIsX ? sd + 0.04 : sw, t, frontIsX ? sw : sd + 0.04),
        trs(sx2, t / 2, sz2),
      );
    }
  }

  // Bake in house-local space, then offset to world position.
  final baked = bake(parts);
  final off = Vector3(o.x, o.y, o.z);
  return [for (final t in baked) Tri(t.a + off, t.b + off, t.c + off, t.normal, t.mat)];
}
