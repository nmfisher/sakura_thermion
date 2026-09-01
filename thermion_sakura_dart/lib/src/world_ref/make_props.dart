/// Dart port of reference `src/world/props.js` foreground factories:
/// `makeKeiTruck`, `makeBicycle`, `makeCone`, `makeBarrier`,
/// `makeGuardrail`, `makePlanter`, `makeCrates`.
///
/// Built entirely on the geometry substrate (`geom/three_geom.dart`).
/// Mirrors `make_pole.dart` conventions: returns `List<Tri>`, inline
/// material colours, defers textures, skips `hullOutline`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// ---------------------------------------------------------------------------
// Material palette — mirrors props.js mats().
// PAL values from palette.js are inlined as const ints.
// ---------------------------------------------------------------------------

const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _dark = Mat(0x322e3b, tint: 0x4b4560, bands: '2'); // PAL.black
const _white = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3'); // PAL.wallWhite
const _terracotta = Mat(0xc57a5a, tint: 0x6f5680, bands: '3');
const _leaf = Mat(0x5aa578, tint: 0x5b6f8c, bands: '3'); // PAL.leaf
const _leafDeep = Mat(0x3f7f60, tint: 0x5b6f8c, bands: '3'); // PAL.leafDeep
const _red = Mat(0xe0453f, tint: 0x7a4060, bands: '3'); // PAL.red
const _orange = Mat(0xef8a3c, tint: 0x8f6050, bands: '3'); // PAL.orange
const _rope = Mat(0xf0e5ca, tint: 0x6f6790, bands: '3'); // PAL.rope

// ---------------------------------------------------------------------------
// Helpers — not in substrate but needed by these factories.
// ---------------------------------------------------------------------------

/// Exact port of `THREE.TorusGeometry(radius, tube, radialSegments,
/// tubularSegments, arc)`. Uses the three.js r150-era vertex layout (ring in
/// the XY plane, tube along Z), matching the reference.
ThreeGeom _torusGeometry(
    double radius, double tube, int radialSegments, int tubularSegments,
    [double arc = -1.0]) {
  if (arc < 0) arc = math.pi * 2;
  final pos = <double>[], nor = <double>[], idx = <int>[];
  for (int j = 0; j <= radialSegments; j++) {
    for (int i = 0; i <= tubularSegments; i++) {
      final u = i / tubularSegments * arc;
      final v = j / radialSegments * math.pi * 2;
      final cv = math.cos(v), sv = math.sin(v);
      final cu = math.cos(u), su = math.sin(u);
      pos.addAll(
          [(radius + tube * cv) * cu, (radius + tube * cv) * su, tube * sv]);
      nor.addAll([cv * cu, cv * su, sv]);
    }
  }
  for (int j = 0; j < radialSegments; j++) {
    for (int i = 0; i < tubularSegments; i++) {
      final a = j * (tubularSegments + 1) + i;
      final b = a + tubularSegments + 1;
      idx.addAll([a, b, a + 1, b, b + 1, a + 1]);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Unit cylinder (1×1×1, 6 radial segments) — shared by bicycle tubes.
final ThreeGeom _unitCyl = cylGeometry(1, 1, 1, 6);

/// Place a geometry at [p] with optional Euler-XYZ rotation, into [arr].
void _at(List<Part> arr, ThreeGeom geo, Vector3 p, Mat mat,
    [double rx = 0, double ry = 0, double rz = 0]) {
  arr.add(Part(geo, trs(p.x, p.y, p.z, rx, ry, rz), mat));
}

/// Cylinder tube between two joints [a] and [b] with radius [r].
/// Port of bicycle's `tube()` helper.
void _tube(List<Part> arr, Vector3 a, Vector3 b, double r, Mat mat) {
  final dir = b - a;
  final len = dir.length;
  if (len < 1e-4) return;
  final mid = (a + b) * 0.5;
  final q = quatFromUnitVectors(Vector3(0, 1, 0), dir.normalized());
  arr.add(Part(_unitCyl, composePRS(mid, q, Vector3(r, len, r)), mat));
}

/// Bake parts, then offset to (x,y,z) and apply optional Euler-XYZ rotation.
List<Tri> _bakePlace(List<Part> parts, double x, double y, double z,
    {double rx = 0, double ry = 0, double rz = 0}) {
  final baked = bake(parts);
  final off = Vector3(x, y, z);
  if (rx == 0 && ry == 0 && rz == 0) {
    return [
      for (final t in baked)
        Tri(t.a + off, t.b + off, t.c + off, t.normal, t.mat)
    ];
  }
  final rot = trs(0, 0, 0, rx, ry, rz);
  return [
    for (final t in baked)
      Tri(
        rot.transformed3(t.a) + off,
        rot.transformed3(t.b) + off,
        rot.transformed3(t.c) + off,
        rot.transformed3(t.normal),
        t.mat,
      )
  ];
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeKeiTruck
// ═══════════════════════════════════════════════════════════════════════════════

/// Kei truck (light flatbed). Returns baked world-space triangles.
///
/// [color] body colour (default PAL.taxiYellow = 0xf5be2a).
/// [load] 'crates' | 'sheet' | 'empty' (default 'crates').
/// [ry] yaw in radians.
/// [x], [y], [z] world offset.
///
/// Deferred: rear number plate (canvas texture).
List<Tri> makeKeiTruck({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  int color = 0xf5be2a,
  String load = 'crates',
}) {
  final parts = <Part>[];

  // Materials (may differ from palette defaults when custom [color] is used).
  final bodyMat = Mat(color, tint: 0x8f7050, bands: '3');
  // Deep variant: multiply RGB channels by 0.78.
  final bodyDeep = Mat(
    (((color >> 16) & 0xff) * 0.78).toInt() << 16 |
        (((color >> 8) & 0xff) * 0.78).toInt() << 8 |
        ((color & 0xff) * 0.78).toInt(),
    tint: 0x8f7050,
    bands: '3',
  );
  const glassMat = Mat(0x53627a, tint: 0x4a4a6c, bands: '3'); // PAL.glassDark
  const bedMat = Mat(0xbba98c, tint: 0x6f6790, bands: '3');
  const hubMat = Mat(0xe8e6ea, tint: 0x6f6790, bands: '2');
  const headMat = Mat(0xfff4d8, unlit: true);
  const tailMat = Mat(0xf06050, unlit: true);

  const L = 3.32, W = 1.46;
  const halfPi = math.pi / 2;

  // ── chassis + flatbed ──
  parts.add(Part(boxGeometry(L, 0.34, W), trs(0, 0.68, 0), bodyDeep));

  // ── cab ──
  parts.add(
      Part(boxGeometry(1.26, 1.06, W), trs(L / 2 - 0.68, 1.38, 0), bodyMat));
  // windscreen
  parts.add(Part(
      boxGeometry(0.06, 0.62, W - 0.16), trs(L / 2 - 0.06, 1.62, 0), glassMat));
  // side glass
  for (final s in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(1.0, 0.56, 0.06),
        trs(L / 2 - 0.7, 1.6, s * (W / 2 - 0.02)), glassMat));
  }
  // roof lip
  parts.add(Part(
      boxGeometry(1.3, 0.1, W + 0.06), trs(L / 2 - 0.68, 1.9, 0), bodyDeep));
  // centre pillar
  parts.add(Part(
      boxGeometry(0.08, 0.62, 0.07), trs(L / 2 - 0.08, 1.62, 0), bodyDeep));

  // ── load bed with drop sides ──
  parts.add(Part(boxGeometry(1.86, 0.06, W), trs(-0.62, 0.88, 0), bedMat));
  for (final s in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(1.86, 0.42, 0.07),
        trs(-0.62, 1.06, s * (W / 2 - 0.03)), bodyMat));
  }
  parts.add(Part(boxGeometry(0.07, 0.42, W), trs(-1.55, 1.06, 0), bodyMat));

  // ── load ──
  if (load == 'crates') {
    const crateA = Mat(0x3f7fbf, tint: 0x4a4a92, bands: '3'); // PAL.crate
    const crateB = Mat(0xe25a4a, tint: 0x4a4a92, bands: '3'); // PAL.crateAlt
    for (int i = 0; i < 3; i++) {
      parts.add(Part(
        boxGeometry(0.42, 0.26, 0.34),
        trs(-0.35 - i * 0.15, 1.04 + i * 0.26, i % 2 == 0 ? -0.08 : 0.08),
        i == 1 ? crateA : crateB,
      ));
    }
  } else if (load == 'sheet') {
    const sheetMat = Mat(0x8fa2b4, tint: 0x5c5680, bands: '3');
    const sheetSkirt = Mat(0x7e8fa0, tint: 0x5c5680, bands: '3');
    parts.add(
        Part(boxGeometry(1.5, 0.4, W - 0.18), trs(-0.62, 1.11, 0), sheetMat));
    parts.add(Part(
        boxGeometry(1.62, 0.07, W - 0.06), trs(-0.62, 0.94, 0), sheetSkirt));
    for (final dx in [-1.12, -0.62, -0.12]) {
      parts.add(
          Part(boxGeometry(0.05, 0.44, W - 0.14), trs(dx, 1.11, 0), _rope));
    }
  }

  // ── wheels ──
  for (final wx in [L / 2 - 0.72, -L / 2 + 0.6]) {
    for (final s in [-1.0, 1.0]) {
      final wz = s * (W / 2 - 0.06);
      // tyre (cylinder rotated to lie along Z)
      parts.add(Part(cylGeometry(0.29, 0.29, 0.2, 12),
          trs(wx, 0.29, wz, halfPi, 0, 0), _dark));
      // hub
      parts.add(Part(cylGeometry(0.13, 0.13, 0.22, 10),
          trs(wx, 0.29, s * (W / 2 - 0.02), halfPi, 0, 0), hubMat));
      // wheel arch
      parts.add(Part(boxGeometry(0.72, 0.1, 0.1),
          trs(wx, 0.62, s * (W / 2 + 0.01)), bodyDeep));
    }
  }

  // ── lights, bumper, mirrors ──
  for (final s in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(0.06, 0.16, 0.26),
        trs(L / 2 + 0.01, 1.0, s * 0.48), headMat));
    parts.add(Part(boxGeometry(0.06, 0.13, 0.2),
        trs(-L / 2 - 0.01, 1.0, s * 0.48), tailMat));
    // mirrors
    parts.add(Part(boxGeometry(0.05, 0.16, 0.11),
        trs(L / 2 - 0.5, 1.92, s * (W / 2 + 0.16)), _dark));
    parts.add(Part(boxGeometry(0.04, 0.04, 0.2),
        trs(L / 2 - 0.5, 1.86, s * (W / 2 + 0.08)), _metalDark));
  }
  // bumpers
  parts.add(Part(
      boxGeometry(0.1, 0.16, W - 0.1), trs(L / 2 + 0.03, 0.78, 0), _metal));
  parts.add(Part(
      boxGeometry(0.1, 0.16, W - 0.1), trs(-L / 2 - 0.03, 0.78, 0), _metal));

  // ── plate: DEFERRED (canvas texture platePlate) ──

  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeBicycle
// ═══════════════════════════════════════════════════════════════════════════════

/// One parked bicycle. Returns baked world-space triangles.
///
/// [color] frame colour (default 0x3f6f9c).
/// [lean] roll angle in radians (applied in bicycle-local space).
/// [ry] yaw, [x], [y], [z] world placement.
///
/// Deferred: spoke discs (transparent CircleGeometry — purely visual,
/// deferred to renderer); basket double-sided material (cosmetic only at
/// this bake resolution).
List<Tri> makeBicycle({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  double lean = 0,
  int color = 0x3f6f9c,
}) {
  const bikeRearLift = 0.018;
  const R = 0.33;
  // Joints (matching reference BIKE object).
  final A = Vector3(-0.52, 0.33 + bikeRearLift, 0); // rear hub
  final B = Vector3(0.55, 0.33, 0); // front hub
  final BB = Vector3(-0.10, 0.28, 0); // bottom bracket
  final SC = Vector3(-0.27, 0.86, 0); // seat cluster
  final HB = Vector3(0.44, 0.60, 0); // fork crown / head tube bottom
  final HT = Vector3(0.49, 0.86, 0); // head tube top
  final BAR = Vector3(0.46, 0.97, 0); // handlebar centre
  final SAD = Vector3(-0.31, 1.00, 0); // saddle

  final frameMat = Mat(color, tint: 0x4a4a92, bands: '3');
  final basketMat = _metal; // NOTE: reference uses DoubleSide — deferred
  final parts = <Part>[];

  // ── wheels (torus rims + hub cylinders + mudguard arcs) ──
  final rimGeo = _torusGeometry(R, 0.021, 5, 18);
  final guardGeo = _torusGeometry(R + 0.055, 0.018, 4, 10, math.pi * 0.78);
  final hubGeo = cylGeometry(0.035, 0.035, 0.085, 6);
  for (final hub in [A, B]) {
    _at(parts, rimGeo, hub, _dark);
    _at(parts, hubGeo, hub, _dark, math.pi / 2); // hub along Z
    // mudguard arc (slight Z rotation to back it off)
    _at(parts, guardGeo, hub, frameMat, 0, 0, 0.11);
  }

  // ── frame tubes ──
  _tube(parts, BB, SC, 0.026, frameMat); // seat tube
  _tube(parts, BB, HB, 0.028, frameMat); // down tube
  _tube(parts, HB, HT, 0.030, frameMat); // head tube
  _tube(parts, SC, HT, 0.024, frameMat); // top tube
  for (final s in [-1.0, 1.0]) {
    final rear = Vector3(A.x, A.y, s * 0.052);
    _tube(parts, BB, rear, 0.019, frameMat); // chain stays
    _tube(parts, SC, rear, 0.017, frameMat); // seat stays
    // fork blades
    _tube(parts, Vector3(HB.x, HB.y, s * 0.045), Vector3(B.x, B.y, s * 0.05),
        0.017, _metal);
  }

  // ── bars and saddle ──
  _tube(parts, SC, SAD, 0.019, _metal); // seat post
  _at(parts, boxGeometry(0.23, 0.055, 0.12),
      Vector3(SAD.x - 0.02, SAD.y + 0.04, 0), _dark);
  _tube(parts, HT, BAR, 0.021, _metal); // stem
  _at(parts, cylGeometry(0.019, 0.019, 0.54, 6), BAR, _metal,
      math.pi / 2); // handlebar
  for (final s in [-1.0, 1.0]) {
    _at(parts, cylGeometry(0.023, 0.023, 0.1, 6),
        Vector3(BAR.x, BAR.y, s * 0.22), _dark, math.pi / 2);
  }
  // bell
  _at(parts, cylGeometry(0.028, 0.028, 0.03, 8),
      Vector3(BAR.x - 0.05, BAR.y + 0.03, -0.12), _dark);

  // ── drive and stand ──
  _at(parts, cylGeometry(0.075, 0.075, 0.012, 12), BB, _dark,
      math.pi / 2); // chainring
  for (final s in [-1.0, 1.0]) {
    final crank = Vector3(BB.x + s * 0.02, BB.y - s * 0.15, s * 0.075);
    _tube(parts, Vector3(BB.x, BB.y, s * 0.075), crank, 0.013, _metal);
    _at(parts, boxGeometry(0.09, 0.02, 0.05),
        Vector3(crank.x, crank.y, s * 0.105), _dark);
  }
  // kickstand
  _tube(parts, Vector3(-0.16, 0.26, 0.06), Vector3(-0.30, 0.015, 0.13), 0.014,
      _metal);

  // ── rear rack ──
  const rackY = R + 0.43;
  _at(parts, boxGeometry(0.29, 0.022, 0.15), Vector3(A.x + 0.02, rackY, 0),
      _metal);
  for (final s in [-1.0, 1.0]) {
    _tube(parts, Vector3(A.x + 0.13, rackY, s * 0.068),
        Vector3(SC.x + 0.03, SC.y - 0.09, s * 0.03), 0.011, _metal);
    _tube(parts, Vector3(A.x - 0.11, rackY, s * 0.068),
        Vector3(A.x + 0.02, A.y + 0.04, s * 0.055), 0.011, _metal);
  }

  // ── basket ──
  const BX = 0.69, BY = 0.87;
  _at(parts, cylGeometry(0.16, 0.12, 0.2, 8, openEnded: true),
      Vector3(BX, BY, 0), basketMat);
  _at(parts, cylGeometry(0.12, 0.12, 0.016, 8), Vector3(BX, BY - 0.095, 0),
      _metal); // floor
  _at(parts, _torusGeometry(0.16, 0.012, 4, 10), Vector3(BX, BY + 0.1, 0),
      _metal, math.pi / 2); // rim
  // stays
  _tube(parts, Vector3(BX - 0.12, BY + 0.08, 0),
      Vector3(BAR.x + 0.02, BAR.y - 0.03, 0), 0.012, _metal);
  _tube(parts, Vector3(BX - 0.05, BY - 0.1, 0),
      Vector3(HB.x + 0.02, HB.y + 0.02, 0), 0.012, _metal);
  // front light
  _at(parts, boxGeometry(0.06, 0.05, 0.07), Vector3(0.52, 0.54, 0), _dark);

  // ── spoke discs: DEFERRED (transparent, per-instance) ──

  // Place: lean is Rx applied before yaw Ry, which matches trs(rx, ry, rz).
  return _bakePlace(parts, x, y, z, rx: lean, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeCone
// ═══════════════════════════════════════════════════════════════════════════════

/// Traffic cone. Returns baked world-space triangles.
///
/// [tilt] tilt angle (radians, around X).
/// [ry] yaw, [x], [y], [z] world placement.
List<Tri> makeCone({
  double x = 0,
  double y = 0,
  double z = 0,
  double tilt = 0,
  double ry = 0,
}) {
  final parts = <Part>[];
  // base plate
  parts.add(Part(boxGeometry(0.34, 0.035, 0.34), trs(0, 0.018, 0),
      const Mat(0xd8763c, tint: 0x8f6050, bands: '3')));
  // cone body (ConeGeometry = cylGeometry with rt=0)
  parts.add(Part(cylGeometry(0, 0.13, 0.6, 10), trs(0, 0.32, 0), _orange));
  // reflective band
  parts.add(Part(cylGeometry(0.088, 0.105, 0.09, 10), trs(0, 0.36, 0), _white));

  return _bakePlace(parts, x, y, z, rx: tilt, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeBarrier
// ═══════════════════════════════════════════════════════════════════════════════

/// Red/white traffic barrier of length [len]. Returns baked triangles.
///
/// [len] barrier length in metres (default 1.6).
/// [ry] yaw, [x], [y], [z] world placement.
List<Tri> makeBarrier({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  double len = 1.6,
}) {
  final parts = <Part>[];
  for (final s in [-1.0, 1.0]) {
    final px = (s * len) / 2;
    // post
    parts.add(Part(cylGeometry(0.045, 0.05, 1.0, 8), trs(px, 0.5, 0), _white));
    // base
    parts.add(Part(boxGeometry(0.16, 0.05, 0.24), trs(px, 0.025, 0), _dark));
    // reflectors
    for (final by in [0.34, 0.72]) {
      parts.add(Part(cylGeometry(0.052, 0.052, 0.2, 8), trs(px, by, 0), _red));
    }
  }
  // top bar
  parts.add(Part(boxGeometry(len, 0.09, 0.05), trs(0, 0.86, 0), _red));
  // white bar
  parts.add(Part(boxGeometry(len - 0.1, 0.07, 0.04), trs(0, 0.62, 0), _white));

  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeGuardrail
// ═══════════════════════════════════════════════════════════════════════════════

/// Metal guardrail of length [len]. Returns baked triangles.
///
/// [len] rail length in metres (default 6).
/// [ry] yaw, [x], [y], [z] world placement.
List<Tri> makeGuardrail({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  double len = 6,
}) {
  final parts = <Part>[];
  // posts every ~2 m
  final n = math.max(2, (len / 2.0).round());
  for (int i = 0; i <= n; i++) {
    final t = -len / 2 + (len / n) * i;
    parts.add(Part(boxGeometry(0.11, 0.82, 0.11), trs(t, 0.41, 0), _metalDark));
  }
  // white rail face
  parts.add(Part(boxGeometry(len, 0.26, 0.07), trs(0, 0.72, 0.02), _white));
  // rail backing
  parts.add(Part(boxGeometry(len, 0.05, 0.1), trs(0, 0.72, 0.01), _metal));

  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makePlanter
// ═══════════════════════════════════════════════════════════════════════════════

/// Terracotta planter with foliage blobs. Returns baked triangles.
///
/// [r] pot radius (default 0.2).
/// [n] number of foliage blobs (default 4).
/// [seed] RNG seed for blob placement.
/// [flower] if true, adds small flower blobs.
/// [x], [y], [z] world placement.
List<Tri> makePlanter({
  double x = 0,
  double y = 0,
  double z = 0,
  double r = 0.2,
  int n = 4,
  int seed = 3,
  bool flower = false,
}) {
  final rng = RngKit(seed);
  final parts = <Part>[];

  // pot body
  parts.add(Part(
      cylGeometry(r, r * 0.78, r * 1.5, 10), trs(0, r * 0.75, 0), _terracotta));
  // rim ring (outer)
  parts.add(Part(cylGeometry(r * 1.08, r * 1.08, r * 0.14, 10),
      trs(0, r * 1.46, 0), const Mat(0xb06a4c, tint: 0x6f5680, bands: '3')));
  // rim ring (inner)
  parts.add(Part(cylGeometry(r * 0.86, r * 0.86, r * 0.1, 10),
      trs(0, r * 1.46, 0), const Mat(0x6b5a4a, tint: 0x6f6790, bands: '2')));

  // foliage blobs
  for (int i = 0; i < n; i++) {
    final blobR = r * rng.range(0.5, 0.85);
    final blobGeo = icosahedronGeometry(blobR, 0);
    final bx = rng.range(-r * 0.6, r * 0.6);
    final by = r * 1.7 + rng.range(0, r * 0.7);
    final bz = rng.range(-r * 0.6, r * 0.6);
    final brx = rng.range(0, 3), bry = rng.range(0, 3), brz = rng.range(0, 3);
    parts.add(Part(blobGeo, trs(bx, by, bz, brx, bry, brz),
        i % 3 == 0 ? _leafDeep : _leaf));
  }

  // flowers (optional)
  if (flower) {
    const flowerColors = [
      0xe0453f,
      0xf4c033,
      0xf0a3c0
    ]; // PAL.red, PAL.yellow, PAL.blossomDeep
    for (int i = 0; i < 3; i++) {
      final fx = rng.range(-r * 0.5, r * 0.5);
      final fz = rng.range(-r * 0.5, r * 0.5);
      final pickedColor = flowerColors[
          (rng.next() * flowerColors.length).floor() % flowerColors.length];
      parts.add(Part(
        icosahedronGeometry(r * 0.2, 0),
        trs(fx, r * 2.1, fz),
        Mat(pickedColor, tint: 0x8f7aa8, bands: '2'),
      ));
    }
  }

  final baked = bake(parts);
  final off = Vector3(x, y, z);
  return [
    for (final t in baked) Tri(t.a + off, t.b + off, t.c + off, t.normal, t.mat)
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// makeCrates
// ═════════════════════════════════════════════════════════════════════════════

/// Stack of moulded shop crates from `props.js::makeCrates`.
///
/// The random calls deliberately retain the reference order: colour, x/z
/// jitter, then yaw. That makes a given [seed] land bit-for-bit like three.js.
List<Tri> makeCrates({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  int n = 4,
  int seed = 4,
}) {
  final rng = RngKit(seed);
  const colors = [0x3f7fbf, 0xe25a4a, 0x4f9d6a];
  final parts = <Part>[];
  for (var i = 0; i < n; i++) {
    final color = rng.pick(colors);
    final dx = rng.range(-0.05, 0.05);
    final dz = rng.range(-0.05, 0.05);
    final yaw = rng.range(-0.1, 0.1);
    parts.add(Part(
      boxGeometry(0.5, 0.28, 0.34),
      trs(dx, 0.14 + i * 0.28, dz, 0, yaw),
      Mat(color, tint: 0x4a4a92, bands: '3'),
    ));
  }
  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Crossing-corner mirror and post box
// ═══════════════════════════════════════════════════════════════════════════════

/// Roadside convex safety mirror from props.js::makeMirror.
List<Tri> makeMirror({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
  double h = 2.55,
  double r = .46,
}) {
  final parts = <Part>[
    Part(cylGeometry(.055, .07, h, 8), trs(0, h / 2, 0), _metalDark),
    Part(cylGeometry(.14, .16, .16, 8), trs(0, .08, 0),
        const Mat(0xd0cbd2, tint: 0x6f6790, bands: '3')),
    // Back shell and blue reflective face, both with their cylinder axes
    // pointing toward local +Z. The back uses a renderer-compensated version
    // of PAL.mirrorBack so its bright cel band lands on the reference orange.
    Part(cylGeometry(r, r, .10, 20), trs(0, h - .1, .06, math.pi / 2),
        const Mat(0xde9f30, tint: 0x8f7050, bands: '3')),
    Part(
        cylGeometry(r * .91, r * .91, .018, 20),
        trs(0, h - .1, .122, math.pi / 2),
        const Mat(0x9fc7df, tint: 0x7d8fb0, bands: '2')),
    Part(
        cylGeometry(r * .12, r * .12, .021, 10),
        trs(-r * .3, h + .05, .137, math.pi / 2),
        const Mat(0xffffff, unlit: true)),
  ];
  return _bakePlace(parts, x, y, z, ry: ry);
}

/// Cylindrical Japanese post box from props.js::makePostBox.
List<Tri> makePostBox({
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
}) {
  const redDeep = Mat(0xb83235, tint: 0x7a4060, bands: '3');
  const redCap = Mat(0xe0453f, tint: 0x7a4060, bands: '3');
  final parts = <Part>[
    Part(cylGeometry(.28, .30, .16, 12), trs(0, .08, 0),
        const Mat(0xd0cbd2, tint: 0x6f6790, bands: '3')),
    Part(cylGeometry(.24, .24, 1.15, 14), trs(0, .74, 0), redDeep),
    // Low-poly sphere slightly sunk into the body gives the reference's domed
    // crown while keeping all geometry in the shared substrate.
    Part(icosahedronGeometry(.255, 2), trs(0, 1.30, 0, 0, 0, 0, 1, .72, 1),
        redDeep),
    Part(cylGeometry(.26, .26, .05, 14), trs(0, 1.30, 0), redCap),
    Part(boxGeometry(.30, .07, .06), trs(0, 1.14, .21), _dark),
    Part(boxGeometry(.26, .34, .04), trs(0, .62, .22),
        const Mat(0xb02c28, tint: 0x7a4060, bands: '3')),
    Part(boxGeometry(.16, .10, .03), trs(0, .42, .235),
        const Mat(0xf6f2e8, unlit: true)),
  ];
  return _bakePlace(parts, x, y, z, ry: ry);
}
