/// Street furniture and the crossing-corner cluster — ports of the reference
/// `props.js`/`index.js` placements: utility poles with overhead cabling, the
/// kei truck, bicycles, post box, convex mirror, cones, planters and the
/// shrine. Simplified geometry, faithful positions and palette.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import '../palette.dart';
import 'street.dart';

class PoleDef {
  const PoleDef(this.x, this.z, {this.h = 9.0, this.seed = 301, this.lamp = false, this.armDir = 1});
  final double x, z, h;
  final int seed;
  final bool lamp;
  final int armDir;
}

const List<PoleDef> poleDefs = [
  PoleDef(-3.86, 4.55, h: 9.4, seed: 301, lamp: true, armDir: 1),
  PoleDef(-4.35, 14.2, h: 9.0, seed: 302, armDir: 1),
  PoleDef(-4.85, 24.6, h: 9.2, seed: 303, lamp: true, armDir: 1),
  PoleDef(-6.6, 35.0, h: 8.8, seed: 304, armDir: 1),
  PoleDef(3.98, -6.6, h: 9.2, seed: 305, lamp: true, armDir: -1),
  PoleDef(6.35, -16.5, h: 9.0, seed: 306, armDir: -1),
  PoleDef(8.4, -31.6, h: 8.8, seed: 307, lamp: true, armDir: -1),
  PoleDef(4.35, 20.8, h: 9.0, seed: 308, armDir: -1),
  PoleDef(4.5, 34.0, h: 8.6, seed: 309, lamp: true, armDir: -1),
  PoleDef(12.5, 3.7, h: 8.4, seed: 310, armDir: -1),
  PoleDef(-16.5, -4.4, h: 8.6, seed: 311, armDir: 1),
];

class Pole {
  const Pole(this.x, this.z, this.h);
  final double x, z, h;
}

/// Utility poles with a street-lamp arm, seated on the ground (sidewalk-aware).
List<Pole> buildPoles(Mesh m) {
  final poles = <Pole>[];
  for (final d in poleDefs) {
    final y = groundY(d.z) +
        ((d.x - centerX(d.z)).abs() < roadHalf + walkW ? walkH : 0);
    // tapered pole
    m.cylUnit(Matrix4.translation(Vector3(d.x, y + d.h / 2, d.z))..scale(0.055, d.h, 0.055),
        Pal.metalDark, segments: 8, tint: 0x5c5680);
    // arm reaching over the road
    final armLen = 1.2;
    m.boxAt(armLen, 0.05, 0.05, Pal.metalDark,
        d.x + d.armDir * armLen / 2, y + d.h - 0.55, d.z, tint: 0x5c5680);
    if (d.lamp) {
      // lamp housing + white glow box
      m.boxAt(0.32, 0.14, 0.18, 0x3a4468, d.x + d.armDir * armLen, y + d.h - 0.62, d.z,
          tint: 0x4b4560, bands: '2');
      m.quadRaw(
        Vector3(d.x + d.armDir * (armLen - 0.05), y + d.h - 0.68, d.z - 0.09),
        Vector3(d.x + d.armDir * (armLen - 0.05), y + d.h - 0.68, d.z + 0.09),
        Vector3(d.x + d.armDir * (armLen + 0.12), y + d.h - 0.68, d.z + 0.09),
        Vector3(d.x + d.armDir * (armLen + 0.12), y + d.h - 0.68, d.z - 0.09),
        C.srgb(0xfff6e6) * 0.9,
        normal: Vector3(0, 1, 0),
      );
    }
    poles.add(Pole(d.x, d.z, y + d.h));
  }
  return poles;
}

/// Overhead cables: a catenary-ish sag between the poles listed by index.
void buildWires(Mesh m, List<Pole> poles) {
  // chains of pole indices + per-cable height offsets (mirrors the reference)
  final chains = <(List<int>, List<List<double>>)>[
    ([0, 1, 2, 3], [[0, -0.7], [-0.42, 0], [-0.86, 0.7]]),
    ([4, 5, 6], [[0, -0.7], [-0.42, 0], [-0.86, 0.7]]),
    ([7, 8], [[0, -0.6], [-0.45, 0.6]]),
    ([0, 4], [[-0.15, 0.2], [-0.62, -0.3]]),
    ([1, 7], [[-0.2, 0.3], [-0.7, -0.4]]),
    ([9, 4], [[-1.0, 0.2]]),
    ([10, 1], [[-1.1, 0.4]]),
  ];
  for (final (idx, offsets) in chains) {
    for (final [dy, dz] in offsets) {
      for (int k = 0; k < idx.length - 1; k++) {
        final a = poles[idx[k]];
        final b = poles[idx[k + 1]];
        final x0 = a.x, z0 = a.z + dz, y0 = a.h - 0.6 + dy;
        final x1 = b.x, z1 = b.z + dz, y1 = b.h - 0.6 + dy;
        final dx = x1 - x0, dz2 = z1 - z0;
        final len = math.sqrt(dx * dx + dz2 * dz2);
        final sag = 0.55;
        final segs = 6;
        for (int s = 0; s < segs; s++) {
          final t0 = s / segs, t1 = (s + 1) / segs;
          final cx0 = x0 + dx * t0, cy0 = y0 + (y1 - y0) * t0 - math.sin(math.pi * t0) * sag;
          final cx1 = x0 + dx * t1, cy1 = y0 + (y1 - y0) * t1 - math.sin(math.pi * t1) * sag;
          m.boxAt(0.012, 0.012, len / segs + 0.01, 0x3a3a46,
              (cx0 + cx1) / 2, (cy0 + cy1) / 2, (z0 + z1) / 2,
              tint: 0x3a3a46, bands: '2');
        }
      }
    }
  }
}

/// The kei truck parked beyond the crossing, left-hand kerb.
void buildKeiTruck(Mesh m, {double x = -2.02, double z = -7.4, double ry = math.pi / 2}) {
  final y = groundY(z);
  final cs = math.cos(ry), sn = math.sin(ry);
  // the truck is authored facing +x, rotated into place
  void addBox(double w, double h, double d, int col, double lx, double ly, double lz,
      {int tint = 0x6a6288, String bands = '3'}) {
    final rx = cs * lx - sn * lz;
    final rz = sn * lx + cs * lz;
    m.boxAt(w, h, d, col, x + rx, y + ly, z + rz, tint: tint, bands: bands);
  }

  // cargo box (pale)
  addBox(2.1, 1.3, 1.4, 0xf0eede, 0.55, 1.35, 0);
  // cab (darker)
  addBox(0.9, 1.15, 1.4, 0x8a93a8, -0.9, 1.25, 0);
  // cab glass
  addBox(0.1, 0.5, 1.2, Pal.glassDark, -1.32, 1.45, 0, bands: '2', tint: 0x4a4468);
  // chassis
  addBox(3.0, 0.25, 1.35, 0x6b6472, 0, 0.6, 0, bands: '2');
  // wheels
  for (final [wx, wz] in [[0.9, 0.75], [-0.85, 0.75], [0.9, -0.75], [-0.85, -0.75]]) {
    m.cylUnit(Matrix4.translation(Vector3(x + cs * wx - sn * wz, y + 0.32, z + sn * wx + cs * wz))
      ..scale(0.3, 0.08, 0.3),
        Pal.black, segments: 8, tint: 0x4b4560, bands: '2');
  }
}

/// A bicycle: two wheel discs + a simple frame, lying along the footway.
void buildBicycle(Mesh m, double x, double z, {double ry = 0, double lean = 0, int color = 0x3f6f9c}) {
  final y = groundY(z) + walkH;
  final cs = math.cos(ry), sn = math.sin(ry);
  Vector3 at(double lx, double ly, double lz) =>
      Vector3(x + cs * lx - sn * lz, y + ly, z + sn * lx + cs * lz);
  // wheels (discs in the XZ plane of the bike)
  for (final [wx, wz] in [[0.0, 0.78], [0.0, -0.78]]) {
    m.cylUnit(Matrix4.translation(at(wx, 0.34, wz))..scale(0.3, 0.045, 0.3),
        Pal.black, segments: 10, tint: 0x4b4560, bands: '2');
  }
  // frame (a lean box)
  m.boxAt(1.5, 0.06, 0.05, color, x + cs * 0 - sn * 0, y + 0.62, z + sn * 0 + cs * 0,
      tint: 0x6a6288, bands: '2');
  // seat post + handlebar hint
  m.boxAt(0.05, 0.35, 0.05, Pal.metalDark, at(0.15, 0.8, 0).x, at(0.15, 0.8, 0).y, at(0.15, 0.8, 0).z,
      tint: 0x5c5680, bands: '2');
}

/// Red post box on its post.
void buildPostBox(Mesh m, double x, double z) {
  final y = groundY(z) + walkH;
  m.cylUnit(Matrix4.translation(Vector3(x, y + 0.35, z))..scale(0.045, 0.7, 0.045),
      Pal.metalDark, segments: 6, tint: 0x5c5680, bands: '2');
  m.boxAt(0.34, 0.42, 0.22, Pal.red, x, y + 1.12, z, tint: 0x7a4060, bands: '2');
  m.boxAt(0.38, 0.1, 0.26, Pal.redDeep, x, y + 1.35, z, tint: 0x7a4060, bands: '2');
}

/// Convex crossing mirror on its pole.
void buildMirror(Mesh m, double x, double z, {double ry = 2.5}) {
  final y = groundY(z) + walkH;
  m.cylUnit(Matrix4.translation(Vector3(x, y + 1.1, z))..scale(0.045, 2.2, 0.045),
      Pal.metalDark, segments: 6, tint: 0x5c5680, bands: '2');
  // mirror disc (blue back, pale face)
  final cs = math.cos(ry), sn = math.sin(ry);
  final mx = x + cs * 0.28, mz = z + sn * 0.28;
  m.cylUnit(Matrix4.translation(Vector3(mx, y + 2.15, mz))..scale(0.18, 0.05, 0.18),
      Pal.blueDeep, segments: 10, tint: 0x4b4560, bands: '2');
  m.quadRaw(
    Vector3(mx - 0.16, y + 2.11, mz - 0.16),
    Vector3(mx + 0.16, y + 2.11, mz - 0.16),
    Vector3(mx + 0.16, y + 2.11, mz + 0.16),
    Vector3(mx - 0.16, y + 2.11, mz + 0.16),
    C.srgb(0xc8d8e4) * 0.85,
    normal: Vector3(0, 1, 0),
  );
}

/// Traffic cones.
void buildCone(Mesh m, double x, double z, {double tilt = 0}) {
  final y = groundY(z);
  m.cylUnit(Matrix4.translation(Vector3(x, y + 0.22, z))..scale(0.11, 0.42, 0.11),
      Pal.orange, segments: 8, tint: 0x7a4060, bands: '2');
  m.quadRaw(
    Vector3(x - 0.12, y + 0.015, z - 0.12),
    Vector3(x + 0.12, y + 0.015, z - 0.12),
    Vector3(x + 0.12, y + 0.015, z + 0.12),
    Vector3(x - 0.12, y + 0.015, z + 0.12),
    C.srgb(Pal.orange) * 0.8,
    normal: Vector3(0, 1, 0),
  );
}

/// A small planter pot with foliage.
void buildPlanter(Mesh m, double x, double z, {double r = 0.22, bool flower = true}) {
  final y = groundY(z) + walkH;
  m.cylUnit(Matrix4.translation(Vector3(x, y + 0.14, z))..scale(r, 0.28, r),
      flower ? Pal.redSoft : Pal.concrete, segments: 8, tint: 0x6a6288, bands: '2');
  for (int i = 0; i < 3; i++) {
    m.ico(Vector3(x + math.cos(i * 2.1) * r * 0.4, y + 0.45, z + math.sin(i * 2.1) * r * 0.4),
        r * 0.5, flower ? Pal.blossom : Pal.leaf,
        tint: 0x6a728c, bands: 'soft', squashY: 0.8);
  }
}

/// A small roadside shrine under the big sakura.
void buildShrine(Mesh m, double x, double z) {
  final y = groundY(z) + walkH;
  // stone base + body
  m.boxAt(0.7, 0.12, 0.5, Pal.shrineStone, x, y + 0.06, z, tint: 0x6f6790, bands: '2');
  m.boxAt(0.5, 0.5, 0.34, 0x8a8478, x, y + 0.35, z, tint: 0x6a6288, bands: '2');
  // dark opening
  m.quadRaw(
    Vector3(x - 0.16, y + 0.12, z - 0.171),
    Vector3(x + 0.16, y + 0.12, z - 0.171),
    Vector3(x + 0.16, y + 0.5, z - 0.171),
    Vector3(x - 0.16, y + 0.5, z - 0.171),
    C.srgb(0x453f4f),
    normal: Vector3(0, 0, -1),
  );
  // roof
  m.boxAt(0.8, 0.1, 0.6, 0x69707e, x, y + 0.66, z, tint: 0x544e74, bands: '2');
  // red bib
  m.quadRaw(
    Vector3(x - 0.12, y + 0.15, z - 0.172),
    Vector3(x + 0.12, y + 0.15, z - 0.172),
    Vector3(x + 0.12, y + 0.4, z - 0.172),
    Vector3(x - 0.12, y + 0.4, z - 0.172),
    C.srgb(Pal.shrineBib),
    normal: Vector3(0, 0, -1),
  );
}

/// Two teal drink vending machines under the shop awning.
void buildVendingMachines(Mesh m) {
  final x = 5.62;
  const spots = <(double, int)>[(5.0, 1), (6.55, 2)];
  for (final (z, seed) in spots) {
    final y = groundY(z) + walkH;
    // body
    m.boxAt(1.05, 1.75, 0.72, Pal.vendTeal, x, y + 0.92, z, tint: 0x4a6a68, bands: '2');
    // white display panel on the street-facing side (toward the camera)
    m.quadRaw(
      Vector3(x - 0.51, y + 1.55, z - 0.36),
      Vector3(x - 0.51, y + 1.55, z + 0.36),
      Vector3(x - 0.51, y + 0.28, z + 0.36),
      Vector3(x - 0.51, y + 0.28, z - 0.36),
      C.srgb(0xf8f5f0),
      normal: Vector3(-1, 0, 0),
    );
    m.quadRaw(
      Vector3(x + 0.51, y + 1.55, z - 0.36),
      Vector3(x - 0.51, y + 1.55, z - 0.36),
      Vector3(x - 0.51, y + 0.28, z - 0.36),
      Vector3(x + 0.51, y + 0.28, z - 0.36),
      C.srgb(0xf8f5f0),
      normal: Vector3(0, 0, -1),
    );
    // a couple of bright cans on the shelf
    for (int i = 0; i < 4; i++) {
      m.boxAt(0.14, 0.26, 0.14, Pal.drinks[(seed * 3 + i * 2) % Pal.drinks.length],
          x - 0.47, y + 0.5 + (i % 2) * 0.55, z - 0.24 + i * 0.16,
          tint: 0x6a6288, bands: '2');
    }
    // top cap
    m.boxAt(1.1, 0.12, 0.78, Pal.vendWhite, x, y + 1.85, z, tint: 0x6f6890, bands: '2');
  }
}

/// Yellow circular crossing-warning sign with a red border, on a pole.
void buildWarningSign(Mesh m, double x, double z, {double ry = 0}) {
  final y = groundY(z) + walkH;
  m.cylUnit(Matrix4.translation(Vector3(x, y + 1.3, z))..scale(0.04, 2.6, 0.04),
      Pal.metalDark, segments: 6, tint: 0x5c5680, bands: '2');
  final cs = math.cos(ry), sn = math.sin(ry);
  final dx = cs * 0.3, dz = sn * 0.3;
  // sign disc: yellow face, red ring
  m.cylUnit(Matrix4.translation(Vector3(x + dx, y + 2.25, z + dz))..scale(0.32, 0.03, 0.32),
      Pal.lineYellow, segments: 12, tint: 0x8f7050, bands: '2');
  m.cylUnit(Matrix4.translation(Vector3(x + dx, y + 2.26, z + dz))..scale(0.36, 0.012, 0.36),
      Pal.red, segments: 12, tint: 0x7a4060, bands: '2');
}

/// Yellow X-shaped railroad crossing sign on its pole.
void buildXSign(Mesh m, double x, double z) {
  final y = groundY(z);
  m.cylUnit(Matrix4.translation(Vector3(x, y + 1.2, z))..scale(0.04, 2.4, 0.04),
      Pal.metalDark, segments: 6, tint: 0x5c5680, bands: '2');
  final hy = y + 2.1;
  for (final rot in [-0.78, 0.78]) {
    final cs = math.cos(rot), sn = math.sin(rot);
    const hw = 0.55, tw = 0.09;
    // a thin plate in the XZ plane rotated by rot about Y
    m.quadRaw(
      Vector3(x + cs * hw - sn * tw, hy, z + sn * hw + cs * tw),
      Vector3(x + cs * hw + sn * tw, hy, z + sn * hw - cs * tw),
      Vector3(x - cs * hw + sn * tw, hy, z - sn * hw - cs * tw),
      Vector3(x - cs * hw - sn * tw, hy, z - sn * hw + cs * tw),
      C.srgb(Pal.lineYellow),
      normal: Vector3(0, 1, 0),
    );
  }
}

/// A small red fire hydrant.
void buildHydrant(Mesh m, double x, double z) {
  final y = groundY(z) + walkH;
  m.cylUnit(Matrix4.translation(Vector3(x, y + 0.3, z))..scale(0.11, 0.55, 0.11),
      Pal.redDeep, segments: 8, tint: 0x7a4060, bands: '2');
  m.cylUnit(Matrix4.translation(Vector3(x, y + 0.62, z))..scale(0.14, 0.07, 0.14),
      Pal.red, segments: 8, tint: 0x7a4060, bands: '2');
}

/// The crossing-corner cluster (reference `index.js` placements).
void buildCornerCluster(Mesh m) {
  buildVendingMachines(m);
  buildWarningSign(m, -4.9, 3.0);
  buildXSign(m, 4.4, -2.0);
  buildHydrant(m, 5.4, 7.6);
  buildMirror(m, -3.62, 3.72);
  buildShrine(m, -5.45, 6.7);
  buildPostBox(m, 3.62, 4.55);
  buildCone(m, 2.62, 4.15);
  buildCone(m, 2.42, 5.05);
  buildKeiTruck(m);
  buildBicycle(m, -4.3, 8.4, ry: math.pi / 2 + 0.08, color: 0x3f6f9c);
  buildBicycle(m, -4.3, 12.2, ry: -math.pi / 2 + 0.06, color: 0xd8a03c);
  buildBicycle(m, 4.3, 13.4, ry: math.pi / 2 + 0.06, color: 0x9c5a4a);
  buildBicycle(m, 5.7, 15.7, ry: -math.pi / 2 - 0.14, color: 0x4f8f6a);
  const planters = <(double, double, double, bool)>[
    (-4.6, 7.9, 0.22, true), (-4.5, 8.6, 0.18, false), (-4.7, 12.6, 0.2, true),
    (4.45, 14.5, 0.19, false), (-4.5, 22.0, 0.21, true), (4.4, 24.5, 0.2, true),
    (-4.6, -8.5, 0.22, false), (5.2, -7.4, 0.2, true), (4.5, 30.0, 0.19, true),
  ];
  for (final (x, z, r, flower) in planters) {
    buildPlanter(m, x, z, r: r, flower: flower);
  }
}
