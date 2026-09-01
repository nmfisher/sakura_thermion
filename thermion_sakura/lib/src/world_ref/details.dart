/// Dart port of reference `src/world/details.js` (relay cabinets), partial
/// `src/world/traffic.js` (deferred -- requires vehicles.js car factories),
/// `src/world/vending.js::makeVendingMachine`, and
/// `src/world/streetprops.js::makeScooter` (as `makeEbike`).
///
/// CONVENTIONS (matching make_props.dart / districts.dart):
///   - Return `List<Tri>`, no context object.
///   - Inline material colours as `const Mat(0x..., ...)` from PAL.
///   - Defer textures; skip `hullOutline`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillSurfaceY;
import 'make_props.dart' show makeKeiTruck;
import 'sign_atlas.dart';
import 'street.dart' show centerX, groundY;

// ---------------------------------------------------------------------------
// Material palette -- inline PAL values from palette.js.
// ---------------------------------------------------------------------------

const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _dark = Mat(0x36333e, tint: 0x4b4560, bands: '2'); // vehicles.js dark
const _shelfMat = Mat(0xf3f0ea, tint: 0x7d74a0, bands: '2');
const _portMat = Mat(0x35373f, tint: 0x3f3a55, bands: '2');
const _trayMat = Mat(0x6e7280, tint: 0x4b4560, bands: '2');
const _cabinet = Mat(0xd8d5da, tint: 0x6f6890, bands: '3'); // PAL.cabinet
const _cabinetTop = Mat(0xb6b2bc, tint: 0x6a6288, bands: '3'); // PAL.cabinetTop
const _amber = Mat(0xef8a3c, tint: 0x8f6050, bands: '2'); // PAL.orange
const _mirrorFace = Mat(0xc8d8e4, tint: 0x6f6790, bands: '3'); // PAL.mirrorFace
const _headlight = Mat(0xfff4d8, unlit: true);
const _plateMat = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3');
const _glassDark = Mat(0x53627a, tint: 0x4b4560, bands: '3'); // PAL.glassDark

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Shorthand: add a box part to [parts].
void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

/// Shorthand: add a cylinder part to [parts].
void _cyl(List<Part> parts, double rt, double rb, double h, int seg, Mat mat,
    double x, double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(cylGeometry(rt, rb, h, seg), trs(x, y, z, rx, ry, rz), mat));
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

/// Exact port of streetprops.js `member` -- a round tube between two points.
/// Pushes onto [parts] with [mat].
void _member(List<Part> parts, Vector3 a, Vector3 b, double r, Mat mat,
    [int seg = 6]) {
  final dir = b - a;
  final len = dir.length;
  if (len < 1e-4) return;
  final mid = (a + b) * 0.5;
  final q = quatFromUnitVectors(Vector3(0, 1, 0), dir.normalized());
  parts.add(Part(
      cylGeometry(r, r, 1, seg), composePRS(mid, q, Vector3(r, len, r)), mat));
}

/// Exact port of vehicles.js `panel` -- a raked box between two profile points.
void _panel(List<Part> parts, Mat mat, double ax, double ay, double bx,
    double by, double w, double t) {
  final dx = bx - ax, dy = by - ay;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-4) return;
  parts.add(Part(boxGeometry(len, t, w),
      trs((ax + bx) / 2, (ay + by) / 2, 0, 0, 0, math.atan2(dy, dx)), mat));
}

ThreeGeom _makeTorusGeometry(
    double radius, double tube, int rs, int ts, double arc) {
  final pos = <double>[], nor = <double>[], idx = <int>[];
  for (int j = 0; j <= rs; j++) {
    for (int i = 0; i <= ts; i++) {
      final u = i / ts * arc;
      final v = j / rs * math.pi * 2;
      final cv = math.cos(v), sv = math.sin(v);
      final cu = math.cos(u), su = math.sin(u);
      pos
        ..add((radius + tube * cv) * cu)
        ..add((radius + tube * cv) * su)
        ..add(tube * sv);
      nor
        ..add(cv * cu)
        ..add(cv * su)
        ..add(sv);
    }
  }
  for (int j = 0; j < rs; j++) {
    for (int i = 0; i < ts; i++) {
      final a = j * (ts + 1) + i;
      final b = a + ts + 1;
      idx
        ..add(a)
        ..add(b)
        ..add(a + 1)
        ..add(b)
        ..add(b + 1)
        ..add(a + 1);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

// ═══════════════════════════════════════════════════════════════════════════════
// buildDetails -- port of details.js
// ═══════════════════════════════════════════════════════════════════════════════
//
// PORTED:
//   - Relay cabinets + tops (3 placements along the lineside).
//
// DEFERRED:
//   - Notice board, crows, cloth/noren/banners (textures + animation),
//   - Loose paper, cat box, pet bowl, bucket, bicycle, sign post (all use
//     factories from props.js not yet ported here),
//   - Warning plate textures on cabinets.

/// Relay cabinets and other environmental detail geometry.
/// Returns baked world-space triangles.
List<Tri> buildDetails() {
  final parts = <Part>[];

  // Relay cabinets -- three placements from details.js lines 99-112.
  // Each is a box body + top plate.
  const cabinets = [
    (-16.4, 5.8, math.pi / 2),
    (17.0, 5.4, -math.pi / 2),
    (-24.0, -3.9, math.pi),
  ];
  for (final c in cabinets) {
    final cx = c.$1, cz = c.$2, cry = c.$3;
    _box(parts, 0.62, 0.98, 0.4, _cabinet, cx, 0.49, cz, 0, cry);
    _box(parts, 0.7, 0.07, 0.48, _cabinetTop, cx, 1.01, cz, 0, cry);
  }

  return bake(parts);
}

// ═══════════════════════════════════════════════════════════════════════════════
// buildTraffic -- port of traffic.js
// ═══════════════════════════════════════════════════════════════════════════════
//
// DEFERRED:
//   The traffic module places ~40 vehicles from vehicles.js (CAR specs,
//   makeVehicle, parkVehicle) and ~14 scooters from streetprops.js
//   (makeScooter).  Porting vehicles.js is a ~800-line effort covering 9
//   body types, 7 bake groups per vehicle, and textures (plate maps).
//   The scooter factory is ported as makeEbike() below.
//
//   buildTraffic returns empty; the vehicle factories (makeVehicle /
//   makeScooter) are available individually when the placement table is
//   wired up.

/// Static traffic distribution from `traffic.js`.
///
/// District-owned hero vehicles (the hall van, Rokuchome trio, Nanachome
/// short-stay kei and school box lorry) are intentionally excluded here so the
/// composition-first modules can own their shadows without duplicate bodies.
List<Tri> buildTraffic() {
  final out = <Tri>[];
  void car(String kind, int color, double x, double z, double ry, {double? y}) {
    out.addAll(makeVehicle(
        kind: kind, color: color, x: x, y: y ?? groundY(z), z: z, ry: ry));
  }

  void truck(int color, double x, double z, double ry,
      {double? y, String load = 'empty'}) {
    out.addAll(makeKeiTruck(
        color: color, x: x, y: y ?? groundY(z), z: z, ry: ry, load: load));
  }

  const p = math.pi;
  // Crossing, shopping street and north-estate parking.
  car('keivan', CAR.white, centerX(18.4) + 2.05, 18.4, p / 2);
  car('hatch', CAR.cream, centerX(-18.6) + 2.05, -18.6, p / 2);
  truck(CAR.slate, 20.5, 22.0, -p / 2, load: 'sheet');
  car('van', CAR.pearl, 24.1, 31.0, p / 2);
  car('kei', CAR.forest, centerX(50.6) - 2.05, 50.6, -p / 2);
  car('hatch', CAR.silver, 24.53, 49.2, -p / 2);
  car('hatch', CAR.white, 55.4, 9.1, p / 2);
  car('wagon', CAR.navy, 60.2, 9.2, -p / 2);
  car('sedan', CAR.silver, 48.3, 20.6, -p / 2);
  car('kei', CAR.white, 41.45, 10.5, -p / 2, y: .06);
  car('kei', CAR.cream, 28.4, 74.9, -p / 2);
  car('kei', CAR.skyblue, 36.9, 60.4, 0);

  // School route, canal works and rear-school parking.  The close school lorry
  // remains in approach_detail.dart.
  car('minivan', CAR.pearl, -5.6, -39.4, 0);
  car('kei', CAR.tea, -26.2, -49.65, p);
  truck(CAR.white, centerX(-33.6) - 2.05, -33.6, -p / 2);
  car('hatch', CAR.pearl, 12.6, -68.6, p / 2);
  car('kei', CAR.forest, 17.8, -68.6, p / 2);
  car('keivan', CAR.white, 51.2, -71.4, p);
  truck(CAR.slate, 24.0, -98.0, p, load: 'crates');
  car('kei', CAR.skyblue, 88.6, -63.4, 0);

  // Supermarket roof, service yard, coin park and the single kerbside van.
  car('hatch', CAR.white, -38.9, 79.09, -p / 2, y: 6.2);
  car('kei', CAR.mint, -34.1, 79.42, -p / 2, y: 6.2);
  car('keivan', CAR.pearl, -29.3, 79.42, -p / 2, y: 6.2);
  car('kei', CAR.mustard, -39.0, 68.18, p / 2, y: 6.2);
  car('minivan', CAR.silver, -34.2, 68.65, p / 2, y: 6.2);
  car('wagon', CAR.tea, -31.8, 68.61, p / 2, y: 6.2);
  car('boxtruck', CAR.white, -53.7, 74.6, -p / 2);
  truck(CAR.skyblue, -53.6, 85.4, p / 2, load: 'crates');
  car('hatch', CAR.slate, -42.25, 98.53, -p / 2);
  car('kei', CAR.cream, -34.75, 98.2, -p / 2);
  car('van', CAR.pearl, -28.0, 93.71, p);

  // Lake district parking: every vehicle is off the narrow mountain road.
  car('kei', CAR.white, 176.0, -153.0, -p / 2, y: hillSurfaceY(176.0, -153.0));
  car('minivan', CAR.silver, 180.0, -153.0, -p / 2,
      y: hillSurfaceY(180.0, -153.0));
  car('van', CAR.cream, 184.0, -152.8, -p / 2, y: hillSurfaceY(184.0, -152.8));
  car('keivan', CAR.tea, 207.0, -151.4, 0, y: hillSurfaceY(207.0, -151.4));
  car('kei', CAR.skyblue, 211.0, -151.4, 0, y: hillSurfaceY(211.0, -151.4));
  truck(CAR.white, 148.4, -29.6, 0,
      y: hillSurfaceY(148.4, -29.6), load: 'crates');
  car('hatch', CAR.mint, 152.4, -32.4, p / 2, y: hillSurfaceY(152.4, -32.4));

  void scooter(double x, double z, double ry, int color,
      {double lift = 0, bool lake = false}) {
    out.addAll(makeEbike(
        x: x,
        y: (lake ? hillSurfaceY(x, z) : groundY(z)) + lift,
        z: z,
        ry: ry,
        color: color));
  }

  scooter(13.8, 5.6, 0, 0xc9d4dc);
  scooter(24.75, 20.5, p / 2, 0xb8c0c8, lift: .13);
  scooter(3.4, 46.9, p / 2, 0x9fb0a4);
  scooter(-19.6, -56.5, p / 2, 0xc4b49a);
  scooter(-24.2, -35.8, p / 2, 0xa8b4c0);
  scooter(-11.2, 55.0, p / 2, 0xcbbfa6);
  scooter(-4.0, 20.5, -p / 2, 0xc2cdd4, lift: -.02);
  scooter(172.4, -147.6, 0, 0xbfc9b4, lake: true);
  scooter(139.2, -68.4, -p / 2, 0xc8bca8, lake: true);
  scooter(62.55, 60.20, p / 2, 0xbfc9ce);
  scooter(53.35, 62.30, p / 2, 0xcbbfa6);
  scooter(-48.40, 86.40, p / 2, 0xb4bec4);
  scooter(-47.55, 86.75, p / 2 - .14, 0xc9bfa2);

  return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeVehicle -- port of vehicles.js::makeVehicle
// ═══════════════════════════════════════════════════════════════════════════════
//
// Ported: 9 vehicle body specs (kei, keivan, hatch, sedan, wagon, minivan,
// van, boxtruck, minibus) with body/deep/dark/brite/glass/lamp geometry.
// Deferred: number plate textures, emissive lamp materials.

/// Car colour palette from vehicles.js.
abstract final class CAR {
  static const int white = 0xf2eee6;
  static const int pearl = 0xe8e4dc;
  static const int cream = 0xe9dfc6;
  static const int silver = 0xc9c8cc;
  static const int gunmetal = 0x8d8f98;
  static const int charcoal = 0x63626e;
  static const int skyblue = 0xc2d3de;
  static const int slate = 0x7f93a4;
  static const int mint = 0xc3d8cc;
  static const int forest = 0x6d8c78;
  static const int wine = 0x8b4a4c;
  static const int tea = 0xcbbfa6;
  static const int mustard = 0xd9b45f;
  static const int navy = 0x5a7093;
}

/// Vehicle specification table -- exact port of vehicles.js SPEC.
typedef _Spec = Map<String, Object>;

const Map<String, _Spec> _SPEC = {
  'kei': {
    'L': 3.40,
    'W': 1.475,
    'R': 0.275,
    'axle': [1.16, -1.19],
    'sill': 0.38,
    'waist': 1.00,
    'roof': 1.70,
    'cab': [-1.60, 1.15],
    'rakeF': 0.42,
    'rakeR': 0.14,
    'seams': [0.12, -0.80],
    'handles': [-0.60, -1.40],
  },
  'keivan': {
    'L': 3.40,
    'W': 1.475,
    'R': 0.275,
    'axle': [1.18, -1.16],
    'sill': 0.38,
    'waist': 1.02,
    'roof': 1.88,
    'cab': [-1.66, 1.55],
    'rakeF': 0.28,
    'rakeR': 0.06,
    'side': [0.34, 1.22],
    'seams': [0.30],
    'handles': [0.04],
  },
  'hatch': {
    'L': 4.05,
    'W': 1.695,
    'R': 0.30,
    'axle': [1.32, -1.22],
    'sill': 0.36,
    'waist': 0.98,
    'roof': 1.52,
    'cab': [-1.72, 0.88],
    'rakeF': 0.62,
    'rakeR': 0.52,
    'seams': [0.10, -0.85],
    'handles': [-0.20, -1.10],
  },
  'sedan': {
    'L': 4.42,
    'W': 1.695,
    'R': 0.31,
    'axle': [1.36, -1.28],
    'sill': 0.36,
    'waist': 0.97,
    'roof': 1.44,
    'cab': [-1.55, 0.95],
    'rakeF': 0.68,
    'rakeR': 0.62,
    'seams': [0.16, -0.78],
    'handles': [-0.14, -1.02],
  },
  'wagon': {
    'L': 4.25,
    'W': 1.690,
    'R': 0.30,
    'axle': [1.32, -1.20],
    'sill': 0.36,
    'waist': 0.97,
    'roof': 1.54,
    'cab': [-1.92, 0.93],
    'rakeF': 0.60,
    'rakeR': 0.16,
    'seams': [0.14, -0.80],
    'handles': [-0.16, -1.06],
    'steelies': true,
  },
  'minivan': {
    'L': 4.34,
    'W': 1.695,
    'R': 0.30,
    'axle': [1.42, -1.20],
    'sill': 0.38,
    'waist': 1.06,
    'roof': 1.80,
    'cab': [-2.00, 1.32],
    'rakeF': 0.58,
    'rakeR': 0.14,
    'seams': [0.28],
    'handles': [0.02, -1.30],
    'slider': -0.70,
  },
  'van': {
    'L': 4.44,
    'W': 1.695,
    'R': 0.31,
    'axle': [1.48, -1.28],
    'sill': 0.40,
    'waist': 1.12,
    'roof': 1.98,
    'cab': [-2.14, 2.02],
    'rakeF': 0.32,
    'rakeR': 0.06,
    'side': [0.70, 1.62],
    'seams': [0.60],
    'handles': [0.30],
  },
  'boxtruck': {
    'L': 4.80,
    'W': 1.695,
    'R': 0.325,
    'axle': [1.62, -1.16],
    'sill': 0.46,
    'waist': 1.20,
    'roof': 1.98,
    'cab': [0.42, 2.16],
    'rakeF': 0.28,
    'rakeR': 0.10,
    'side': [0.72, 1.84],
    'seams': [0.60],
    'handles': [0.30],
    'box': {'x0': -2.40, 'x1': 0.28, 'y0': 1.06, 'y1': 2.46},
  },
  'minibus': {
    'L': 6.30,
    'W': 2.08,
    'R': 0.36,
    'axle': [2.06, -1.86],
    'sill': 0.52,
    'waist': 1.26,
    'roof': 2.60,
    'cab': [-3.04, 2.94],
    'rakeF': 0.26,
    'rakeR': 0.08,
    'side': [-2.80, 2.55],
    'seams': [1.72, -0.36],
    'handles': <int>[],
    'doors': [1.72, -0.36],
    'bus': true,
  },
};

double _specD(_Spec s, String key, double def) {
  final v = s[key];
  return v is double ? v : def;
}

List<double> _specList(_Spec s, String key) {
  final v = s[key];
  if (v is List) {
    return v.map((e) => (e is num) ? e.toDouble() : 0.0).toList();
  }
  return <double>[];
}

/// Build one parked vehicle. Returns baked world-space triangles.
///
/// [kind] a key of SPEC: 'kei', 'keivan', 'hatch', 'sedan', 'wagon',
///   'minivan', 'van', 'boxtruck', 'minibus'.
/// [color] body colour (a CAR value, default white).
/// [x], [y], [z] world position.
/// [ry] yaw (radians).
List<Tri> makeVehicle({
  String kind = 'kei',
  int color = 0xf2eee6,
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
}) {
  final s = _SPEC[kind] ?? _SPEC['kei']!;
  final parts = <Part>[];

  // Deep colour variant: multiply RGB by 0.76.
  int deepColor(int c) {
    return (((c >> 16) & 0xff) * 0.76).toInt() << 16 |
        (((c >> 8) & 0xff) * 0.76).toInt() << 8 |
        ((c & 0xff) * 0.76).toInt();
  }

  final bodyMat = Mat(color, tint: 0x6a6288, bands: '3');
  final deepMat = Mat(deepColor(color), tint: 0x5e5680, bands: '3');
  final briteMat = _metal;

  final HW = _specD(s, 'W', 1.475) / 2;
  final TRACK = _specD(s, 'W', 1.475) - 0.17;
  final TW = _specD(s, 'R', 0.275) < 0.3 ? 0.165 : 0.195;
  final CW = _specD(s, 'W', 1.475) - 0.14;
  final roofFront = _specList(s, 'cab')[1] - _specD(s, 'rakeF', 0.42);
  final roofRear = _specList(s, 'cab')[0] + _specD(s, 'rakeR', 0.14);
  final sideDefault = <double>[roofRear, roofFront];
  final side = s.containsKey('side') ? _specList(s, 'side') : sideDefault;

  // Lower body mass.
  _box(
      parts,
      _specD(s, 'L', 3.4),
      _specD(s, 'waist', 1.0) - _specD(s, 'sill', 0.38),
      _specD(s, 'W', 1.475),
      bodyMat,
      0,
      (_specD(s, 'sill', 0.38) + _specD(s, 'waist', 1.0)) / 2,
      0);
  // Deep valance.
  _box(
      parts,
      _specD(s, 'L', 3.4) - 0.16,
      _specD(s, 'sill', 0.38) - 0.10,
      _specD(s, 'W', 1.475) - 0.07,
      deepMat,
      0,
      (_specD(s, 'sill', 0.38) + 0.10) / 2 + 0.05,
      0);

  // Bonnet leading edge and boot trailing edge.
  final L = _specD(s, 'L', 3.4);
  final sill = _specD(s, 'sill', 0.38);
  final waist = _specD(s, 'waist', 1.0);
  final W = _specD(s, 'W', 1.475);
  if (L / 2 - _specList(s, 'cab')[1] > 0.55) {
    _panel(parts, bodyMat, L / 2 - 0.01, waist - 0.15, L / 2 - 0.46,
        waist + 0.01, W - 0.05, 0.13);
  }
  if (_specList(s, 'cab')[0] + L / 2 > 0.45) {
    _panel(parts, bodyMat, -L / 2 + 0.01, waist - 0.10, -L / 2 + 0.30,
        waist + 0.01, W - 0.05, 0.11);
  }

  // Cabin core.
  final roof = _specD(s, 'roof', 1.70);
  _box(parts, roofFront - roofRear, roof - waist, CW, bodyMat,
      (roofFront + roofRear) / 2, (waist + roof) / 2, 0);

  // Screen wedges.
  _panel(
      parts, bodyMat, _specList(s, 'cab')[1], waist, roofFront, roof, CW, 0.11);
  _panel(
      parts, bodyMat, _specList(s, 'cab')[0], waist, roofRear, roof, CW, 0.11);

  // Roof cap and drip rails.
  _box(parts, roofFront - roofRear + 0.05, 0.05, CW + 0.03, bodyMat,
      (roofFront + roofRear) / 2, roof - 0.015, 0);
  for (final t in [-1.0, 1.0]) {
    _box(parts, roofFront - roofRear, 0.035, 0.035, deepMat,
        (roofFront + roofRear) / 2, roof - 0.05, t * (CW / 2 + 0.005));
  }

  // Windscreen and backlight laid just outside the body-coloured wedges. The
  // outward offset is essential: a thinner panel on the wedge centreline is
  // swallowed by the solid cabin and leaves vehicles with blank body faces.
  {
    final cx = (roofFront + roofRear) / 2;
    final cy = (waist + roof) / 2;
    void lay(double ax, double ay, double bx, double by, double k) {
      final dx = bx - ax, dy = by - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      final ux = dx / len, uy = dy / len;
      var nx = uy, ny = -ux;
      if (nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0) {
        nx = -nx;
        ny = -ny;
      }
      const o = 0.062;
      _panel(parts, _glassDark, ax + ux * k + nx * o, ay + uy * k + ny * o,
          bx - ux * k + nx * o, by - uy * k + ny * o, CW - 0.15, 0.055);
    }

    lay(_specList(s, 'cab')[1], waist + 0.05, roofFront, roof - 0.045, 0.05);
    lay(_specList(s, 'cab')[0], waist + 0.05, roofRear, roof - 0.045, 0.05);
  }

  // Side glazing.
  {
    final y0 = waist + 0.035, y1 = roof - 0.075;
    final x0 = math.max(side[0], roofRear) + 0.04;
    final x1 = math.min(side[1], roofFront) - 0.04;
    if (x1 > x0 + 0.12) {
      for (final t in [-1.0, 1.0]) {
        _box(parts, x1 - x0, y1 - y0, 0.05, _glassDark, (x0 + x1) / 2,
            (y0 + y1) / 2, t * (CW / 2 - 0.006));
      }
      for (final px in _specList(s, 'seams')) {
        if (px < x0 + 0.06 || px > x1 - 0.06) continue;
        for (final t in [-1.0, 1.0]) {
          _box(parts, 0.075, y1 - y0 + 0.02, 0.05, bodyMat, px, (y0 + y1) / 2,
              t * (CW / 2 - 0.002));
        }
      }
    }
  }

  // Wheels.
  final R = _specD(s, 'R', 0.275);
  for (final ax in _specList(s, 'axle')) {
    for (final t in [-1.0, 1.0]) {
      final zw = t * (TRACK / 2);
      _cyl(parts, R, R, TW, 14, _dark, ax, R, zw, math.pi / 2);
      final isSteelie = s['steelies'] == true;
      _cyl(parts, R * 0.62, R * 0.62, TW + 0.02, 12,
          isSteelie ? deepMat : briteMat, ax, R, zw, math.pi / 2);
      _cyl(parts, R * 0.22, R * 0.22, TW + 0.04, 8, _dark, ax, R, zw,
          math.pi / 2);
      // Arch well + lip (torus arcs).
      parts.add(Part(_makeTorusGeometry(R + 0.015, 0.055, 4, 12, math.pi),
          trs(ax, R + 0.01, t * (HW - 0.095)), _dark));
      parts.add(Part(
          _makeTorusGeometry(R + 0.055, 0.030, 4, 14, math.pi),
          composePRS(Vector3(ax, R + 0.01, t * (HW + 0.008)),
              Quaternion.identity(), Vector3(1, 1, 1.3)),
          deepMat));
    }
  }

  // Bumpers, lamps, flank details.
  final lampY = math.min(waist - 0.17, sill + 0.36);
  for (final sx in [1.0, -1.0]) {
    final bx = sx * (L / 2);
    final isFront = sx > 0;
    _box(parts, 0.10, 0.36, W - 0.02, bodyMat, bx + sx * 0.04, sill + 0.12, 0);
    _box(parts, 0.05, 0.07, W - 0.46, _dark, bx + sx * 0.08, sill + 0.04, 0);
    final lz = W / 2 - 0.20;
    for (final t in [-1.0, 1.0]) {
      if (isFront) {
        _box(parts, 0.05, 0.16, 0.32, _headlight, bx + 0.015, lampY, t * lz);
      } else {
        _box(parts, 0.05, 0.21, 0.155, const Mat(0xd8564e, unlit: true),
            bx - 0.015, lampY + 0.05, t * lz);
        _box(
            parts, 0.055, 0.028, 0.165, _dark, bx - 0.02, lampY + 0.05, t * lz);
        _box(parts, 0.05, 0.055, 0.075, _headlight, bx - 0.015, lampY - 0.10,
            t * (lz - 0.02));
      }
    }
    if (isFront) {
      _box(parts, 0.04, 0.15, W - 0.66, _dark, bx + 0.02, lampY + 0.01, 0);
      _box(parts, 0.05, 0.13, W - 0.50, _dark, bx + 0.05, sill + 0.16, 0);
    } else {
      _box(parts, 0.03, 0.022, W - 0.30, _dark, bx - 0.025, sill + 0.30, 0);
      _box(parts, 0.05, 0.045, 0.34, briteMat, bx - 0.03, waist - 0.13,
          W * 0.14);
    }
  }

  // Exhaust.
  _cyl(parts, 0.033, 0.033, 0.14, 8, briteMat, -L / 2 - 0.02, sill - 0.05,
      -(W / 2 - 0.32), 0, 0, math.pi / 2);

  // Japanese 330 x 165 mm plates, standing clear of each bumper.
  for (final sx in [1.0, -1.0]) {
    _box(parts, 0.012, 0.165, 0.33, _plateMat, sx * (L / 2 + 0.10), sill + 0.13,
        sx * 0.10);
  }

  // Flank details: seams, handles, rocker strip.
  for (final t in [-1.0, 1.0]) {
    final zf = t * (HW + 0.004);
    for (final px in _specList(s, 'seams')) {
      _box(parts, 0.022, waist - sill - 0.10, 0.02, _dark, px,
          (sill + waist) / 2 + 0.02, zf);
    }
    for (final px in _specList(s, 'handles')) {
      _box(parts, 0.15, 0.045, 0.035, briteMat, px, waist - 0.15,
          zf + t * 0.012);
    }
    if (s.containsKey('slider')) {
      _box(parts, 1.10, 0.045, 0.03, deepMat, s['slider'] as double,
          waist - 0.045, zf + t * 0.008);
    }
    _box(parts, L - 0.5, 0.06, 0.03, deepMat, 0, sill + 0.03, zf);
  }

  // Mirrors.
  {
    final mx = _specList(s, 'cab')[1] - 0.14;
    final my = waist + 0.14;
    for (final t in [-1.0, 1.0]) {
      final z0 = t * (HW - 0.02), z1 = t * (HW + 0.17);
      _box(parts, 0.07, 0.05, 0.19, deepMat, mx, my, (z0 + z1) / 2);
      _box(parts, 0.10, 0.16, 0.07, deepMat, mx - 0.01, my + 0.03, z1);
      _box(parts, 0.015, 0.12, 0.05, briteMat, mx - 0.06, my + 0.03, z1);
    }
  }

  // Wipers.
  {
    final wy = waist + 0.035;
    for (final t in [-1.0, 1.0]) {
      _box(parts, 0.34, 0.022, 0.022, _dark, _specList(s, 'cab')[1] - 0.20, wy,
          t * 0.28, 0, 0, 0.12);
    }
  }

  // Minibus folding doors, destination lamp and high skirt.
  if (s['bus'] == true) {
    for (final dx in _specList(s, 'doors')) {
      _box(parts, 0.9, waist - sill - 0.06, 0.03, _dark, dx,
          (sill + waist) / 2 + 0.02, HW + 0.008);
      _box(parts, 0.82, 0.52, 0.04, _glassDark, dx, waist - 0.26, HW + 0.014);
    }
    _box(parts, 0.10, 0.24, 1.10, _dark, _specList(s, 'cab')[1] - 0.18,
        roof - 0.22, 0);
    _box(parts, 0.03, 0.16, 0.96, _headlight, _specList(s, 'cab')[1] - 0.12,
        roof - 0.22, 0);
    _box(parts, L - 0.4, 0.20, W + 0.01, deepMat, 0, sill + 0.02, 0);
  }

  // Box truck cargo box.
  if (s.containsKey('box')) {
    final box = s['box'] as Map<String, dynamic>;
    final x0 = box['x0'] as double;
    final x1 = box['x1'] as double;
    final y0 = box['y0'] as double;
    final y1 = box['y1'] as double;
    _box(parts, x1 - x0, y1 - y0, W + 0.06, deepMat, (x0 + x1) / 2,
        (y0 + y1) / 2, 0);
    for (var i = 0; i < 7; i++) {
      final ribX = x0 + 0.2 + i * ((x1 - x0 - 0.4) / 6);
      for (final t in [-1.0, 1.0]) {
        _box(parts, 0.05, y1 - y0 - 0.14, 0.03, deepMat, ribX, (y0 + y1) / 2,
            t * (W / 2 + 0.045));
      }
    }
    _box(parts, 0.06, y1 - y0 - 0.12, W - 0.04, deepMat, x0 - 0.03,
        (y0 + y1) / 2, 0);
    _box(parts, 0.04, 0.10, W - 0.22, _dark, x0 - 0.07, y0 + 0.14, 0);
    _box(parts, x1 - x0 + 0.06, 0.07, W + 0.12, deepMat, (x0 + x1) / 2,
        y1 + 0.02, 0);
  }

  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeVendingMachine -- port of vending.js::makeVendingMachine
// ═══════════════════════════════════════════════════════════════════════════════
//
// PORTED:
//   - Body with delivery-port notch (5 box slabs, baked into one mesh).
//   - Plinth, base kick plate, levelling feet.
//   - Product display cabinet: back plane, sides, top/bottom, shelf boards.
//   - Header accent strip, glass frame.
//   - Controls area: payment panel, change return, condenser grille.
//   - Port interior: dark liner, tray floor, sides, head.
//   - Side seams.
//
// DEFERRED:
//   - Header/cold/hot/slot/price textures (PlaneGeometry + mapped materials).
//   - Bottle/can instances (InstancedMesh with per-instance colour).
//   - Glass panel (transparent, no-outline).
//   - Selection button emissive glow.
//   - Port flap (translucent, no-outline).
//   - Dispensed can animation.
//   - Interaction hitbox.

/// Vending machine geometry. Returns baked world-space triangles.
///
/// [variant] 0 = white, 1 = red, 2 = teal.
/// [x], [y], [z] world placement.
/// [ry] yaw in radians.
List<Tri> makeVendingMachine({
  int variant = 0,
  int seed = 1,
  bool openingSideShadow = false,
  int openingSideShadowColor = 0x1a687c,
  int tealBodyColor = 0x2e9a98,
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
}) {
  const bodyW = 1.12, bodyH = 1.95, bodyD = 0.72;
  const variants = [
    [0xf8f5f0, 0xe0453f, 0x2d3140], // vendWhite, PAL.red
    [0xdb4038, 0xfdf6ec, 0x2a2c38], // vendRed
    [0x2e9a98, 0xfdf6ec, 0x27313a], // vendTeal
  ];
  final vi = [...variants[variant % 3]];
  if (variant % 3 == 2) vi[0] = tealBodyColor;
  final bodyMat = Mat(vi[0], tint: 0x6f6790, bands: '3');
  final accentMat = Mat(vi[1], tint: 0x6f6790, bands: '3');
  final shelfBackMat = Mat(vi[2], tint: 0x413c58, bands: '2');
  final darkMat = const Mat(0x30333f, tint: 0x4b4560, bands: '2');
  const plinthMat = _metalDark;

  const front = bodyD / 2 + 0.001;
  const yBase = 0.09;
  const BX = bodyW / 2, BZ = bodyD / 2;
  const BY1 = yBase + bodyH;

  // Delivery port dimensions.
  const portX0 = -0.50, portX1 = 0.10, portY0 = 0.125, portY1 = 0.29;
  const portZ = front - 0.11;
  const portW = portX1 - portX0;
  const portMX = (portX0 + portX1) / 2;

  final parts = <Part>[];

  // Plinth.
  parts.add(Part(boxGeometry(bodyW - 0.05, 0.06, bodyD - 0.05), trs(0, 0.06, 0),
      plinthMat));

  // Body: 5 slabs with delivery port notch.
  void slab(double x0, double x1, double y0, double y1, double z0, double z1) {
    parts.add(Part(boxGeometry(x1 - x0, y1 - y0, z1 - z0),
        trs((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), bodyMat));
  }

  slab(-BX, BX, portY1, BY1, -BZ, BZ); // over the port
  slab(-BX, BX, yBase, portY0, -BZ, BZ); // under the port lip
  slab(-BX, portX0, portY0, portY1, -BZ, BZ); // left of port
  slab(portX1, BX, portY0, portY1, -BZ, BZ); // right of port
  slab(portX0, portX1, portY0, portY1, -BZ, portZ); // behind port

  // Header accent strip.
  _box(parts, bodyW - 0.02, 0.36, 0.03, accentMat, 0, yBase + bodyH - 0.22,
      front);
  // Canvas header, represented as its exact high-level marks: a per-variant
  // field, three compact glyph boxes, and the hollow circular brand mark.
  // This retains the reference design even where Japanese UI fonts are absent.
  const signWhite = Mat(0xffffff, unlit: true);
  final headerBg =
      Mat([0xffffff, 0xe0453f, 0x2e9a98][variant % 3], unlit: true);
  final headerFg =
      variant % 3 == 0 ? const Mat(0xe0453f, unlit: true) : signWhite;
  final headerY = yBase + bodyH - 0.22;
  final headerZ = front + 0.034;
  _box(parts, bodyW - 0.06, 0.30, 0.03, headerBg, 0, headerY, front + 0.015);
  for (final gx in [-.32, -.17, -.02]) {
    _box(parts, .09, .018, .012, headerFg, gx, headerY - .07, headerZ);
    _box(parts, .09, .018, .012, headerFg, gx, headerY + .07, headerZ);
    _box(parts, .015, .14, .012, headerFg, gx - .045, headerY, headerZ);
    _box(parts, .015, .14, .012, headerFg, gx + .045, headerY, headerZ);
  }
  const ringRadius = .09;
  for (var i = 0; i < 12; i++) {
    final theta = i * math.pi * 2 / 12;
    _box(
        parts,
        .048,
        .018,
        .012,
        headerFg,
        .30 + math.cos(theta) * ringRadius,
        headerY + math.sin(theta) * ringRadius,
        headerZ,
        0,
        0,
        theta + math.pi / 2);
  }

  // Product display cabinet.
  const dispW = bodyW - 0.22;
  const dispH = 0.94;
  const dispY = yBase + 0.86;
  const dz = front + 0.004;
  const zShelf = dz + 0.055;
  const zGlass = dz + 0.125;
  // Back plane.
  _box(parts, dispW, dispH, 0.02, shelfBackMat, 0, dispY, dz);
  // Cabinet sides.
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.03, dispH, 0.13, bodyMat, s * (dispW / 2 + 0.015), dispY,
        dz + 0.065);
  }
  // Cabinet top/bottom.
  _box(parts, dispW + 0.06, 0.03, 0.13, bodyMat, 0, dispY + dispH / 2 + 0.015,
      dz + 0.065);
  _box(parts, dispW + 0.06, 0.03, 0.13, bodyMat, 0, dispY - dispH / 2 - 0.015,
      dz + 0.065);

  const drinks = [
    0xe0453f,
    0xf4c033,
    0x3d6ec4,
    0x2f9c9a,
    0xef8a3c,
    0x8f6fb5,
    0x5aa578,
    0xf4f2f6,
    0xe86f9c,
    0x44b4d8,
    0xc94f7a,
    0x9dbb3c,
  ];
  final rng = RngKit(1000 + seed * 37);

  // Four stocked shelves. The saturated bottle/can rows are real geometry in
  // vending.js and are the most visible identifying detail of the machines.
  for (var s = 0; s < 4; s++) {
    final sy = dispY - dispH / 2 + 0.13 + s * 0.225;
    _box(parts, dispW - 0.02, 0.018, 0.11, _shelfMat, 0, sy - 0.095, zShelf);
    _box(parts, dispW - 0.02, 0.055, 0.012, signWhite, 0, sy - 0.075,
        zGlass + 0.004);
    final tall = s.isEven;
    for (var i = 0; i < 6; i++) {
      final px = -dispW / 2 + 0.09 + i * (dispW - 0.16) / 5;
      final color = drinks[(s * 6 + i + variant * 3) % drinks.length];
      final h = tall ? 0.165 : 0.11;
      // Consume and apply the same seeded yaw as the instanced reference.
      final yaw = rng.range(0, 3);
      _cyl(
          parts,
          tall ? 0.032 : 0.03,
          tall ? 0.032 : 0.03,
          h,
          8,
          Mat(color, tint: 0x9c93b8, bands: 'soft3'),
          px,
          sy + (tall ? 0.085 : 0.06),
          zShelf + 0.008,
          0,
          yaw);
    }
  }

  // Glass frame.
  _box(parts, dispW + 0.09, 0.038, 0.05, accentMat, 0,
      dispY + dispH / 2 + 0.032, zGlass - 0.01);
  _box(parts, dispW + 0.09, 0.038, 0.05, accentMat, 0,
      dispY - dispH / 2 - 0.032, zGlass - 0.01);
  _box(parts, 0.038, dispH + 0.1, 0.05, accentMat, -dispW / 2 - 0.032, dispY,
      zGlass - 0.01);
  _box(parts, 0.038, dispH + 0.1, 0.05, accentMat, dispW / 2 + 0.032, dispY,
      zGlass - 0.01);
  // Glass panel: DEFERRED (transparent, no-outline).

  // Controls area: bright label plates stand in for the tiny canvas lettering.
  _box(parts, 0.42, 0.10, 0.012, signWhite, -0.28, yBase + 0.36, front + 0.008);
  _box(parts, 0.30, 0.10, 0.012, signWhite, 0.20, yBase + 0.36, front + 0.008);
  // Selection buttons.
  const btnLitMat = const Mat(0xfff2cf, tint: 0x8f86ad, bands: '2');
  for (var r = 0; r < 2; r++) {
    for (var i = 0; i < 5; i++) {
      final bx = -0.45 + i * 0.16;
      final by = 0.37 - r * 0.06;
      _box(parts, 0.15, 0.05, 0.015, r == 0 ? btnLitMat : accentMat, bx, by,
          front + 0.008);
    }
  }

  // Payment panel.
  _box(parts, 0.2, 0.34, 0.02, darkMat, 0.4, yBase + 0.62, front + 0.008);
  _box(
      parts,
      0.12,
      0.02,
      0.025,
      const Mat(0xe8e4dc, tint: 0x6f6790, bands: '2'),
      0.4,
      yBase + 0.72,
      front + 0.014);
  _box(
      parts,
      0.13,
      0.05,
      0.025,
      const Mat(0x8fd4c8, tint: 0x6f6790, bands: '3'),
      0.4,
      yBase + 0.52,
      front + 0.014);

  // Change return.
  _box(parts, 0.17, 0.12, 0.03, darkMat, 0.4, yBase + 0.40, front + 0.005);
  _box(
      parts,
      0.13,
      0.075,
      0.02,
      const Mat(0x1d2029, tint: 0x3f3a55, bands: '2'),
      0.4,
      yBase + 0.385,
      front + 0.02);
  _box(
      parts,
      0.15,
      0.022,
      0.028,
      const Mat(0xc8ccd4, tint: 0x6a6288, bands: '2'),
      0.4,
      yBase + 0.455,
      front + 0.02);
  _box(parts, 0.05, 0.05, 0.03, plinthMat, 0.29, yBase + 0.47, front + 0.02);

  // Condenser grille.
  for (var i = 0; i < 3; i++) {
    _box(parts, 0.34, 0.022, 0.018, darkMat, 0.33, portY0 + 0.03 + i * 0.038,
        front + 0.006);
  }
  _box(parts, 0.38, portY1 - portY0, 0.012, bodyMat, 0.33,
      (portY0 + portY1) / 2, front + 0.001);

  // Port interior.
  final pocketD = front - 0.016 - (portZ + 0.006);
  final pocketZ = portZ + 0.006 + pocketD / 2;
  final pocketH = portY1 - portY0 - 0.02;
  final pocketY = (portY0 + portY1) / 2;
  _box(parts, portW - 0.012, portY1 - portY0, 0.012, _portMat, portMX, pocketY,
      portZ + 0.007); // back
  _box(parts, portW - 0.012, 0.012, pocketD, _trayMat, portMX, portY0 + 0.007,
      pocketZ); // tray floor
  _box(parts, portW - 0.012, 0.01, pocketD, _portMat, portMX, portY1 - 0.006,
      pocketZ); // head
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.01, pocketH, pocketD, _portMat,
        portMX + s * (portW / 2 - 0.007), pocketY, pocketZ); // sides
  }
  // Flap: DEFERRED (translucent).

  // Base kick plate + levelling feet.
  _box(parts, bodyW - 0.06, 0.055, bodyD - 0.06, darkMat, 0, 0.062, 0);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _cyl(parts, 0.028, 0.032, 0.035, 6, plinthMat, sx * (bodyW / 2 - 0.09),
          0.018, sz * (bodyD / 2 - 0.09));
    }
  }

  // Side seams.
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.02, bodyH - 0.1, 0.02, plinthMat, s * (bodyW / 2 + 0.002),
        yBase + bodyH / 2, front - 0.02);
  }

  // In the opening composition the teal machine's exposed +X side sits under
  // the shop/awning shadow. Preserve the diagonal pool of light that remains
  // across its lower front corner; using the exact no-sun cel result for the
  // upper receiver is much closer than treating the whole broad side as lit.
  if (openingSideShadow && variant % 3 == 2) {
    final shadowedTeal = Mat(openingSideShadowColor, unlit: true);
    parts.add(Part(planeGeometry(bodyD, bodyH),
        trs(BX + 0.002, yBase + bodyH / 2, 0, 0, math.pi / 2), shadowedTeal));

    // The shop awning also shades the exposed right strip of the front skin.
    // Sit behind the header, display frame, and controls so those raised parts
    // remain visible while only the uncovered teal body receives this tone.
    parts.add(Part(planeGeometry(0.56, 0.80), trs(0.28, 1.45, front + 0.002),
        const Mat(0x185a66, unlit: true)));
    parts.add(Part(
        planeGeometry(0.13, 0.26),
        trs(dispW / 2 + 0.031, 1.21, dz + 0.065, 0, math.pi / 2),
        const Mat(0x185a66, unlit: true)));

    final brightSide = ThreeGeom(
      Float32List.fromList([
        BX + 0.004,
        yBase,
        BZ,
        BX + 0.004,
        yBase,
        -BZ,
        BX + 0.004,
        0.38,
        -BZ,
        BX + 0.004,
        0.68,
        BZ,
      ]),
      Float32List.fromList([
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
      ]),
      const [0, 1, 3, 1, 2, 3],
    );
    parts.add(Part(brightSide, Matrix4.identity(), bodyMat));
  }

  // Can: DEFERRED (animated).

  return _bakePlace(parts, x, y, z, ry: ry);
}

// ═══════════════════════════════════════════════════════════════════════════════
// makeEbike -- port of streetprops.js::makeScooter
// ═══════════════════════════════════════════════════════════════════════════════
//
// PORTED:
//   - Full scooter geometry: wheels, mudguards, frame, bodywork, seat,
//     legshield, exhaust, carrier, grab rail, bars, mirrors, headlamp,
//     number plate, side stand.
//
// DEFERRED:
//   - Cockpit details (dial, brake levers, ignition, cargo hook) when
//     [cockpit] is true (uses complex face-normal placement).
//   - Mirror face glass (flat material).

/// Electric scooter / step-through 50. Returns baked world-space triangles.
///
/// [color] body colour (default 0xc9d4dc).
/// [lean] roll angle in radians (default -0.09).
/// [cockpit] if true, adds rider-side controls.
/// [x], [y], [z] world placement.
/// [ry] yaw in radians.
List<Tri> makeEbike({
  int color = 0xc9d4dc,
  double lean = -0.09,
  bool cockpit = false,
  double x = 0,
  double y = 0,
  double z = 0,
  double ry = 0,
}) {
  final bodyMat = Mat(color, tint: 0x6f6790, bands: '3');
  const R = 0.20; // wheel radius

  // Joints (matching streetprops.js P object).
  final RA = Vector3(-0.6, R, 0); // rear axle
  final FA = Vector3(0.57, R, 0); // front axle
  final ENG = Vector3(-0.3, 0.28, 0); // swingarm pivot
  final RS = Vector3(-0.22, 0.3, 0); // rear floor
  final FS = Vector3(0.3, 0.28, 0); // front floor
  final HS = Vector3(0.48, 0.62, 0); // fork crown
  final HT = Vector3(0.4, 0.96, 0); // headstock top
  final BAR = Vector3(0.38, 1.0, 0);
  final SHK = Vector3(-0.44, 0.5, 0);

  final parts = <Part>[];

  // Wheels.
  for (final hub in [RA, FA]) {
    // tyre
    parts.add(Part(boxGeometry(R * 2, 0.09, 0.09),
        trs(hub.x, hub.y, 0, math.pi / 2, 0, 0), _dark));
    // rim
    parts.add(Part(boxGeometry(0.125 * 2, 0.11, 0.11),
        trs(hub.x, hub.y, 0, math.pi / 2, 0, 0), _metal));
    // hub
    parts.add(Part(boxGeometry(0.038 * 2, 0.13, 0.13),
        trs(hub.x, hub.y, 0, math.pi / 2, 0, 0), _dark));
  }

  // Mudguards (torus arcs).
  parts.add(Part(
      _makeTorusGeometry(R + 0.04, 0.026, 4, 14, math.pi * 0.85),
      composePRS(Vector3(FA.x, FA.y, 0), quatFromEulerXyz(0, 0, -0.72),
          Vector3(1, 1, 2.2)),
      bodyMat));
  parts.add(Part(
      _makeTorusGeometry(R + 0.05, 0.032, 4, 12, math.pi * 0.62),
      composePRS(Vector3(RA.x, RA.y, 0), quatFromEulerXyz(0, 0, 0.55),
          Vector3(1, 1, 1.9)),
      bodyMat));

  // Frame tubes.
  for (final s in [-1.0, 1.0]) {
    _member(parts, Vector3(HS.x, HS.y, s * 0.055),
        Vector3(FA.x, FA.y, s * 0.055), 0.019, _metal); // fork
    _member(parts, Vector3(ENG.x, ENG.y, s * 0.062),
        Vector3(RA.x, RA.y, s * 0.062), 0.022, _metal); // swingarm
  }
  _member(parts, HS, HT, 0.026, _metal); // steering column
  _member(parts, HS, FS, 0.026, _metal); // front down spar
  _member(parts, FS, RS, 0.024, _metal); // floor spine
  _member(parts, RS, SHK, 0.024, _metal); // rear frame rail
  _member(parts, Vector3(SHK.x, SHK.y, 0.07),
      Vector3(RA.x + 0.02, RA.y + 0.04, 0.07), 0.024, _metal); // shock
  _member(parts, Vector3(-0.14, 0.26, -0.09), Vector3(-0.24, 0.015, -0.19),
      0.016, _metal); // side stand

  // Bodywork: side panels.
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.5, 0.24, 0.11, bodyMat, -0.4, 0.4, s * 0.125);
  }
  _box(parts, 0.46, 0.09, 0.34, bodyMat, -0.4, 0.505, 0); // deck
  // Seat.
  _box(parts, 0.34, 0.08, 0.3, _dark, -0.46, 0.59, 0);
  _box(parts, 0.16, 0.065, 0.2, _dark, -0.24, 0.575, 0);
  _box(parts, 0.56, 0.03, 0.36, bodyMat, 0.06, 0.275, 0); // footboard
  _box(parts, 0.46, 0.014, 0.28, _dark, 0.04, 0.297, 0); // rubber mat
  // Front apron + legshield + skirt + cowl.
  _box(parts, 0.16, 0.46, 0.42, bodyMat, 0.38, 0.68, 0, 0, 0, 0.22);
  _box(parts, 0.16, 0.16, 0.38, bodyMat, 0.3, 0.4, 0);
  _box(parts, 0.16, 0.18, 0.3, bodyMat, 0.4, 0.94, 0);

  // Exhaust + silencer.
  _member(parts, Vector3(-0.28, 0.28, 0.09), Vector3(-0.5, 0.245, 0.13), 0.024,
      _metal);
  _cyl(parts, 0.045, 0.045, 0.24, 10, _metal, -0.62, 0.24, 0.14, 0, 0,
      math.pi / 2);

  // Carrier.
  _box(parts, 0.28, 0.025, 0.26, _metal, -0.66, 0.655, 0);
  for (final s in [-1.0, 1.0]) {
    _member(parts, Vector3(-0.56, 0.65, s * 0.11),
        Vector3(-0.5, 0.55, s * 0.13), 0.014, _metal);
    _member(parts, Vector3(-0.78, 0.65, s * 0.11),
        Vector3(-0.68, 0.55, s * 0.12), 0.014, _metal);
    // Grab rail.
    _member(parts, Vector3(-0.54, 0.6, s * 0.145),
        Vector3(-0.72, 0.7, s * 0.115), 0.013, _metal);
  }
  _member(parts, Vector3(-0.72, 0.7, -0.115), Vector3(-0.72, 0.7, 0.115), 0.013,
      _metal);

  // Number plate. The source maps platePlate() only onto the local -X face;
  // retain the solid box for its edge/ink and overlay that exact atlas image.
  _box(parts, 0.02, 0.13, 0.24, _plateMat, -0.77, 0.42, 0);

  // Bars + mirrors.
  _cyl(parts, 0.018, 0.018, 0.56, 6, _metal, BAR.x, BAR.y, 0, math.pi / 2);
  _member(parts, HT, BAR, 0.022, _metal);
  for (final s in [-1.0, 1.0]) {
    _cyl(parts, 0.024, 0.024, 0.11, 6, _dark, BAR.x, BAR.y, s * 0.22,
        math.pi / 2);
    _member(parts, Vector3(0.36, 1.02, s * 0.18), Vector3(0.32, 1.24, s * 0.24),
        0.012, _metal);
    _box(parts, 0.03, 0.11, 0.14, _dark, 0.31, 1.26, s * 0.25);
    // Mirror face: DEFERRED (flat material).
    _box(parts, 0.008, 0.09, 0.12, _mirrorFace, 0.294, 1.26, s * 0.25);
    // Turn signals.
    _box(parts, 0.06, 0.05, 0.05, _amber, 0.45, 0.86, s * 0.19);
  }

  // Headlamp.
  _cyl(parts, 0.095, 0.095, 0.06, 14, _metal, 0.48, 0.9, 0, 0, 0, math.pi / 2);
  _cyl(parts, 0.082, 0.082, 0.02, 14, _headlight, 0.514, 0.9, 0);

  // Cockpit details: DEFERRED (complex face-normal placement).
  // When cockpit == true, would add dial, brake levers, ignition barrel,
  // cargo hook -- these use quaternion+face-normal positioning that doesn't
  // map cleanly to the bake substrate without further helper work.

  final out = _bakePlace(parts, x, y, z, rx: lean, ry: ry);
  final placement = trs(x, y, z, lean, ry);
  appendSignAtlasPlane(out, scooterPlateRegion,
      width: 0.24,
      height: 0.13,
      flipU: true,
      matrix: placement * trs(-0.7801, 0.42, 0, 0, -math.pi / 2));
  return out;
}
