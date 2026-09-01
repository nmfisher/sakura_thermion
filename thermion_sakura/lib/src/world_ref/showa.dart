/// Geometry port of the two ageing Showa shopfront displays from showa.js.
///
/// Canvas lettering and sleeve art are represented by their dominant colours;
/// every object that contributes to the street-level silhouette is geometric.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'make_props.dart';
import 'street.dart';

const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _dark = Mat(0x322e3b, tint: 0x4b4560, bands: '2');
const _wood = Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');
const _woodDark = Mat(0x74563f, tint: 0x554e74, bands: '3');
const _card = Mat(0xc9a878, tint: 0x6f6790, bands: '3');
const _cream = Mat(0xefe6d2, tint: 0x6f6790, bands: '3');

List<Tri> _place(List<Part> parts, double x, double y, double z,
    {double ry = 0}) {
  final group = trs(x, y, z, 0, ry);
  return bake([
    for (final part in parts) Part(part.geo, group * part.matrix, part.mat),
  ]);
}

/// Dress the two units at the same fixed coordinates used by shotengai.js.
List<Tri> buildShowa() {
  const frontageX = 19.2;
  const edge = frontageX + 0.15;
  final out = <Tri>[];

  void crates(double x, double z, int n, int seed, double ry) {
    out.addAll(
        makeCrates(x: x, y: groundY(z) + 0.13, z: z, n: n, seed: seed, ry: ry));
  }

  // 電器 たかの, z 35.2 .. 38.3.
  const dz0 = 35.2, dz1 = 38.3;
  final dy = groundY((dz0 + dz1) / 2) + 0.13;
  out.addAll(_makeVertSign(frontageX + 0.22, dy + 1.55, dz1 - 0.5, 'denki'));
  crates(edge + 0.36, dz0 + 0.55, 2, 9311, math.pi / 2);
  out.addAll(_makeOldTv(edge + 0.4, dy + 0.56, dz0 + 0.55, math.pi / 2 - 0.18));
  out.addAll(_makeFan(edge + 0.34, dy, dz0 + 1.5, math.pi / 2 + 0.3));
  crates(edge + 0.3, dz1 - 1.5, 1, 9312, math.pi / 2 - 0.1);
  out.addAll(_makeRadio(edge + 0.32, dy + 0.28, dz1 - 1.5, math.pi / 2 + 0.24));
  out.addAll(_makeBulbBoxes(edge + 0.3, dy, dz0 + 2.2, math.pi / 2, 9313));
  out.addAll(_makeChalkBoard(edge + 0.5, dy, dz1 - 0.75, math.pi / 2 + 0.1, 1));
  out.addAll(_makeAircon(
      frontageX + 0.24, dy + 1.85, dz0 + 0.35, math.pi / 2, 0.74, 0.52));
  out.addAll(_makeBucket(edge + 0.16, dy, dz0 + 2.9, -0.7));
  out.addAll(_place([
    Part(planeGeometry(0.36, 0.5), trs(0, 0, 0, 0, math.pi / 2, 0.02),
        const Mat(0xd7b06f, unlit: true))
  ], frontageX + 0.04, dy + 1.6, dz0 + 0.34));

  // レコード ほしぞら, z 38.5 .. 41.6.
  const rz0 = 38.5, rz1 = 41.6;
  final ry = groundY((rz0 + rz1) / 2) + 0.13;
  out.addAll(_makeVertSign(frontageX + 0.22, ry + 1.55, rz0 + 0.5, 'record'));
  out.addAll(
      _makeLpCrate(edge + 0.93, ry, rz1 - 0.9, math.pi / 2 - 0.12, 9321));
  out.addAll(
      _makeLpCrate(edge + 0.93, ry, rz1 - 1.9, math.pi / 2 + 0.08, 9322));
  out.addAll(_makeDisplayCase(edge + 0.44, ry, rz0 + 1.1, math.pi / 2, 9323));
  out.addAll(
      _makeChalkBoard(edge + 0.5, ry, rz0 + 0.34, math.pi / 2 - 0.14, 0));
  out.addAll(makePlanter(
      x: edge + 0.97,
      y: ry,
      z: rz1 - 2.6,
      r: 0.23,
      flower: false,
      seed: 9324,
      n: 4));
  out.addAll(_makeAircon(
      frontageX + 0.24, ry + 1.9, rz1 - 0.35, math.pi / 2, 0.7, 0.5));
  crates(edge + 0.28, rz0 + 2.35, 3, 9325, math.pi / 2 + 0.15);
  out.addAll(_place([
    Part(planeGeometry(0.34, 0.48), trs(0, 0, 0, 0, math.pi / 2, -0.025),
        const Mat(0x8aa7c4, unlit: true))
  ], frontageX - 0.03, ry + 1.58, rz0 + 1.98));

  return out;
}

List<Tri> _makeVertSign(double x, double y, double z, String kind) {
  final face = kind == 'denki'
      ? const Mat(0xffe58c, unlit: true)
      : const Mat(0xffd8b8, unlit: true);
  const h = 1.25;
  final p = <Part>[
    Part(boxGeometry(0.2, h, 0.38), Matrix4.identity(), face),
    Part(boxGeometry(0.26, h + 0.14, 0.46), trs(-0.04), _metalDark),
  ];
  // Put the mapped-looking face back over the darker outer case.
  p.add(Part(boxGeometry(0.205, h - 0.08, 0.31), trs(0.095), face));
  for (final dy in [h / 2 - 0.1, -h / 2 + 0.1]) {
    p.add(Part(boxGeometry(0.3, 0.05, 0.05), trs(-0.24, dy), _metalDark));
  }
  return _place(p, x, y, z);
}

List<Tri> _makeOldTv(double x, double y, double z, double ry) {
  const w = 0.5, h = 0.42, d = 0.42;
  final p = <Part>[
    Part(boxGeometry(w, h, d), trs(0, h / 2 + 0.12),
        const Mat(0x8a6a4c, tint: 0x5c5680, bands: '3')),
    Part(boxGeometry(0.4, 0.34, 0.03), trs(-0.04, h / 2 + 0.13, d / 2 + 0.015),
        const Mat(0xd8cdb8, tint: 0x6a6288, bands: '3')),
    Part(boxGeometry(0.33, 0.27, 0.02), trs(-0.04, h / 2 + 0.13, d / 2 + 0.03),
        const Mat(0x4a4b58, tint: 0x413c58, bands: '2')),
    Part(boxGeometry(0.09, 0.1, 0.02), trs(0.19, h / 2 - 0.03, d / 2 + 0.02),
        const Mat(0x6a5f52, tint: 0x554e74, bands: '2')),
    Part(boxGeometry(0.16, 0.03, 0.015), trs(-0.06, 0.16, d / 2 + 0.02),
        const Mat(0xd8cdb8, unlit: true)),
  ];
  for (var i = 0; i < 3; i++) {
    p.add(Part(cylGeometry(0.035, 0.035, 0.03, 10),
        trs(0.19, h / 2 + 0.26 - i * 0.09, d / 2 + 0.025, math.pi / 2), _dark));
  }
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      p.add(Part(
          cylGeometry(0.016, 0.022, 0.14, 6),
          trs(sx * (w / 2 - 0.06), 0.06, sz * (d / 2 - 0.06), sz * 0.16, 0,
              -sx * 0.16),
          _woodDark));
    }
  }
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeFan(double x, double y, double z, double ry) {
  final p = <Part>[
    Part(cylGeometry(0.16, 0.19, 0.05, 12), trs(0, 0.025), _cream),
    Part(cylGeometry(0.05, 0.06, 0.02, 10), trs(0, 0.06), _metalDark),
    Part(cylGeometry(0.026, 0.03, 0.72, 8), trs(0, 0.42), _metal),
    Part(cylGeometry(0.05, 0.05, 0.06, 8), trs(0, 0.78), _cream),
    Part(cylGeometry(0.075, 0.075, 0.16, 10), trs(0, 0.9, -0.07, math.pi / 2),
        _cream),
  ];
  for (final spec in [(0.21, 0.02), (0.2, 0.09)]) {
    const n = 16;
    final seg = 2 * math.pi * spec.$1 / n;
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      p.add(Part(
          boxGeometry(seg, 0.012, 0.012),
          trs(math.cos(a) * spec.$1, 0.9 + math.sin(a) * spec.$1, spec.$2, 0, 0,
              a + math.pi / 2),
          _metal));
    }
  }
  for (var i = 0; i < 8; i++) {
    p.add(Part(boxGeometry(0.4, 0.012, 0.012),
        trs(0, 0.9, 0.055, 0, 0, i / 8 * math.pi), _metal));
  }
  for (var i = 0; i < 3; i++) {
    p.add(Part(
        boxGeometry(0.3, 0.09, 0.012),
        trs(0, 0.9, 0, 0, 0, i / 3 * math.pi * 2),
        const Mat(0xd8d2c0, tint: 0x6a6288, bands: '2')));
  }
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeRadio(double x, double y, double z, double ry) {
  final p = <Part>[
    Part(boxGeometry(0.34, 0.2, 0.16), trs(0, 0.1),
        const Mat(0x7d5f44, tint: 0x5c5680, bands: '3')),
    Part(boxGeometry(0.14, 0.13, 0.01), trs(-0.07, 0.11, 0.085),
        const Mat(0x8f7a5e, tint: 0x554e74, bands: '2')),
    Part(boxGeometry(0.12, 0.05, 0.01), trs(0.08, 0.15, 0.085),
        const Mat(0xe8dcbc, unlit: true)),
    Part(cylGeometry(0.006, 0.006, 0.34, 4),
        trs(0.15, 0.34, -0.05, 0, 0, -0.24), _metal),
  ];
  for (final dx in [0.05, 0.13]) {
    p.add(Part(cylGeometry(0.024, 0.024, 0.02, 10),
        trs(dx, 0.06, 0.085, math.pi / 2), _dark));
  }
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeBulbBoxes(double x, double y, double z, double ry, int seed) {
  final rng = RngKit(seed);
  const cols = [0xdcd2b0, 0xc9bfa0, 0xe2dcc0];
  final p = <Part>[];
  for (var i = 0; i < 4; i++) {
    final dx = rng.range(-0.03, 0.03);
    final dz = rng.range(-0.03, 0.03);
    final yaw = rng.range(-0.12, 0.12);
    p.add(Part(
        boxGeometry(0.26, 0.14, 0.2),
        trs(dx, 0.07 + i * 0.14, dz, 0, yaw),
        Mat(cols[i % 3], tint: 0x6f6790, bands: '3')));
    p.add(Part(boxGeometry(0.2, 0.012, 0.14), trs(dx, 0.142 + i * 0.14, dz),
        const Mat(0x9c8f6e, tint: 0x6f6790, bands: '2')));
  }
  for (final dx in [-0.06, 0.05]) {
    p.add(Part(icosahedronGeometry(0.035, 0), trs(dx, 0.63, 0.04),
        const Mat(0xf2ecd8, unlit: true)));
    p.add(Part(cylGeometry(0.017, 0.017, 0.03, 7), trs(dx, 0.6, 0.04), _metal));
  }
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeLpCrate(double x, double y, double z, double ry, int seed) {
  final rng = RngKit(seed);
  const w = 0.66, d = 0.38, h = 0.34, leg = 0.42;
  final p = <Part>[];
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      p.add(Part(boxGeometry(0.05, leg, 0.05),
          trs(sx * (w / 2 - 0.05), leg / 2, sz * (d / 2 - 0.05)), _woodDark));
    }
  }
  p.add(Part(boxGeometry(w, 0.04, d), trs(0, leg), _woodDark));
  for (final sz in [-1.0, 1.0]) {
    p.add(Part(boxGeometry(w, h, 0.035),
        trs(0, leg + h / 2, sz * (d / 2 - 0.018)), _wood));
  }
  for (final sx in [-1.0, 1.0]) {
    p.add(Part(boxGeometry(0.035, h, d), trs(sx * (w / 2 - 0.018), leg + h / 2),
        _wood));
  }
  p.add(Part(boxGeometry(w - 0.07, 0.03, d - 0.07), trs(0, leg + 0.02), _wood));
  const sleeveCols = [0xd96d78, 0x547da6, 0xe4c56a, 0x6e9871];
  for (var i = 0; i < 9; i++) {
    final c = sleeveCols[rng.ints(0, 3)];
    p.add(Part(
        planeGeometry(0.31, 0.31),
        trs(0, leg + 0.2, -d / 2 + 0.07 + i * ((d - 0.16) / 8),
            -0.3 + rng.range(-0.05, 0.05)),
        Mat(c, unlit: true)));
  }
  p.add(Part(planeGeometry(0.3, 0.34), trs(0, leg + 0.23, -d / 2 + 0.04, -0.3),
      _card));
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeDisplayCase(double x, double y, double z, double ry, int seed) {
  final rng = RngKit(seed);
  const w = 1.0, d = 0.44, h = 0.62, leg = 0.5;
  const frame = Mat(0x7a6a58, tint: 0x5c5680, bands: '3');
  final p = <Part>[];
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      p.add(Part(boxGeometry(0.06, leg, 0.06),
          trs(sx * (w / 2 - 0.06), leg / 2, sz * (d / 2 - 0.06)), frame));
    }
  }
  p.addAll([
    Part(boxGeometry(w, 0.05, d), trs(0, leg), frame),
    Part(boxGeometry(w, 0.06, d), trs(0, leg + h), frame),
    Part(
        boxGeometry(w - 0.1, h - 0.1, 0.03),
        trs(0, leg + h / 2, -d / 2 + 0.03),
        const Mat(0xcfc2a8, tint: 0x6f6790, bands: '3')),
  ]);
  for (final sx in [-1.0, 1.0]) {
    p.add(Part(
        boxGeometry(0.06, h, d), trs(sx * (w / 2 - 0.03), leg + h / 2), frame));
  }
  for (final sz in [-1.0, 1.0]) {
    p.add(Part(boxGeometry(w, 0.05, 0.06),
        trs(0, leg + h - 0.03, sz * (d / 2 - 0.03)), frame));
  }
  const sleeveCols = [0xb45c68, 0x597da6, 0xdfbf66];
  for (var i = 0; i < 3; i++) {
    // Consume the reference RNG even though its selected texture is flattened.
    rng.ints(0, 3);
    p.add(Part(
        planeGeometry(0.28, 0.28),
        trs(-0.3 + i * 0.3, leg + 0.22, -0.02, -0.26),
        Mat(sleeveCols[i], unlit: true)));
  }
  p.add(
      Part(boxGeometry(w - 0.16, 0.03, 0.03), trs(0, leg + 0.08, 0.06), frame));
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeChalkBoard(
    double x, double y, double z, double ry, int variant) {
  final board = variant == 0
      ? const Mat(0x314a42, unlit: true)
      : const Mat(0x3d4652, unlit: true);
  final p = <Part>[
    Part(boxGeometry(0.5, 0.62, 0.05), trs(0, 0.56, 0, -0.18), board),
  ];
  for (final s in [-1.0, 1.0]) {
    p.add(Part(
        boxGeometry(0.05, 0.72, 0.05), trs(s * 0.2, 0.36, -0.13, 0.22), _wood));
  }
  p.add(Part(boxGeometry(0.42, 0.04, 0.04), trs(0, 0.24, -0.1), _wood));
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeAircon(
    double x, double y, double z, double ry, double w, double h) {
  final p = <Part>[
    Part(boxGeometry(w, h, 0.25), trs(0, 0, 0),
        const Mat(0xd7d3ca, tint: 0x6f6790, bands: '3')),
    Part(cylGeometry(h * 0.28, h * 0.28, 0.02, 14),
        trs(0.14, 0, 0.135, math.pi / 2), _metalDark),
  ];
  for (var i = 0; i < 5; i++) {
    p.add(Part(boxGeometry(w * 0.28, 0.018, 0.02),
        trs(-w * 0.22, -h * 0.25 + i * h * 0.11, 0.14), _metalDark));
  }
  return _place(p, x, y, z, ry: ry);
}

List<Tri> _makeBucket(double x, double y, double z, double ry) {
  return _place([
    Part(cylGeometry(0.18, 0.14, 0.28, 12, openEnded: true), trs(0, 0.14),
        const Mat(0x8fa7b4, tint: 0x5c6680, bands: '3')),
    Part(cylGeometry(0.012, 0.012, 0.38, 6), trs(0, 0.29, 0, 0, 0, math.pi / 2),
        _metalDark),
  ], x, y, z, ry: ry);
}
