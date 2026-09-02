/// Dart port of the reference `src/world/props.js::makePole` — a utility pole
/// (post, crossarms with insulators, transformer cans, warning plate, lamp).
///
/// Built entirely on the geometry substrate (`geom/three_geom.dart`): every
/// call is a 1:1 translation of the reference's `box`/`cyl`/`bake`/`trs` calls,
/// so the output matches three.js's geometry bit-for-bit (validated against
/// `tool/extract_part.mjs` — see `bin/validate_pole.dart`). This is the template
/// for porting the rest of the world modules: translate the generation calls,
/// keep the substrate faithful, retire the extracted `.bin` per module.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// mats() — the material palette makePole draws from (mirrors props.js mats()).
const _pole = Mat(0xd6d2d8, tint: 0x6a6288, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _dark = Mat(0x322e3b, tint: 0x4b4560, bands: '2'); // PAL.black
const _white = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3'); // PAL.wallWhite
const _plate = Mat(0xffffff, unlit: true);
const _bulb = Mat(0xfff2d0, unlit: true);

class PoleOpts {
  const PoleOpts({
    this.h = 9.2,
    this.armDir = 1,
    this.armYs,
    this.transformer = true,
    this.lamp = false,
    this.plateFace,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.ry = 0,
    this.seed = 5,
    this.poleColor,
    this.poleUnlit = false,
  });
  final double h;
  final int armDir;
  final List<double>? armYs;
  final bool transformer;
  final bool lamp;
  final double? plateFace;
  final double x, y, z, ry;
  final int seed;
  final int? poleColor;
  final bool poleUnlit;
}

/// Build a utility pole, returning its world-space triangles (offset by x,y,z,
/// matching the reference's `g.position.set(o.x, o.y, o.z)`).
List<Tri> makePole(PoleOpts o) {
  final H = o.h;
  final armDir = o.armDir.toDouble();
  final armYs = o.armYs ?? <double>[H - 0.55, H - 1.5];
  final parts = <Part>[];
  final poleMat =
      o.poleColor == null ? _pole : Mat(o.poleColor!, unlit: o.poleUnlit);
  void push(Mat mat, ThreeGeom geo, Matrix4 mx) =>
      parts.add(Part(geo, mx, mat));

  // Pole + base boss.
  push(poleMat, cylGeometry(0.11, 0.19, H, 8), trs(0, H / 2, 0));
  push(poleMat, cylGeometry(0.24, 0.28, 0.22, 8), trs(0, 0.11, 0));

  // Crossarms with insulators.
  for (int ai = 0; ai < armYs.length; ai++) {
    final y = armYs[ai];
    final len = ai == 0 ? 2.1 : 1.7;
    push(_dark, boxGeometry(0.09, 0.1, len), trs(0, y, 0));
    push(_metal, boxGeometry(0.06, 0.5, 0.06), trs(0, y - 0.3, 0));
    for (int i = -1; i <= 1; i++) {
      if (i == 0 && ai == 1) continue;
      push(_white, cylGeometry(0.06, 0.075, 0.16, 7),
          trs(0, y + 0.13, (i * len) / 2.4));
      push(_metal, cylGeometry(0.02, 0.02, 0.14, 5),
          trs(0, y + 0.04, (i * len) / 2.4));
    }
  }

  // Transformer cans.
  if (o.transformer) {
    final ty = H - 2.9;
    push(_metal, boxGeometry(0.5, 0.14, 1.5), trs(armDir * 0.34, ty + 0.62, 0));
    for (final dz in const [-0.42, 0.42]) {
      push(_metal, cylGeometry(0.24, 0.24, 0.72, 10),
          trs(armDir * 0.34, ty + 0.24, dz));
      push(_metal, cylGeometry(0.26, 0.26, 0.06, 10),
          trs(armDir * 0.34, ty + 0.62, dz));
    }
    push(_dark, boxGeometry(0.28, 0.5, 0.28), trs(-armDir * 0.24, ty + 1.1, 0));
  }

  // Cable bundle up the street-facing side.
  push(_dark, cylGeometry(0.045, 0.045, H - 1.4, 5),
      trs(armDir * 0.135, (H - 1.4) / 2, 0.06));

  // Warning plate (partial cylinder, faces the road). Texture skipped — the
  // plate's geometry is a flat white band; the warning print is a decal.
  final plateFace = o.plateFace ?? (o.armDir > 0 ? math.pi / 2 : -math.pi / 2);
  push(
      _plate,
      cylGeometry(0.205, 0.21, 0.62, 12,
          openEnded: true, thetaStart: -1.0, thetaLength: 2.0),
      trs(0, 2.45, 0, 0, plateFace, 0));

  if (o.lamp) {
    push(_metal, cylGeometry(0.05, 0.05, 1.3, 6),
        trs(armDir * 0.65, H - 3.9, 0, 0, 0, math.pi / 2));
    // Shade: open-ended cone.
    push(_metal, cylGeometry(0, 0.32, 0.26, 12, openEnded: true),
        trs(armDir * 1.28, H - 4.02, 0));
    // Bulb.
    push(_bulb, boxGeometry(0.26, 0.05, 0.26), trs(armDir * 1.28, H - 4.16, 0));
  }

  // Bake in pole-local space, then offset by the pole's world position.
  final baked = bake(parts);
  final off = Vector3(o.x, o.y, o.z);
  if (o.ry != 0) {
    final rot = trs(0, 0, 0, 0, o.ry);
    return [
      for (final t in baked)
        Tri(rot.transformed3(t.a) + off, rot.transformed3(t.b) + off,
            rot.transformed3(t.c) + off, rot.transformed3(t.normal), t.mat)
    ];
  }
  return [
    for (final t in baked) Tri(t.a + off, t.b + off, t.c + off, t.normal, t.mat)
  ];
}

/// Lightweight residential-lane pole used by `plots.js::poleRun`.
///
/// Unlike [makePole], this authored variant has no transformer cans or warning
/// plate and carries its lamp along local Z. District pole runs must use this
/// shape: substituting the full roadside pole puts large equipment into views
/// where the Three.js scene has only a slender cable pole.
List<Tri> makePoleLite(PoleOpts o) {
  final h = o.h;
  final dir = o.armDir.toDouble();
  final parts = <Part>[];
  void push(Mat mat, ThreeGeom geo, Matrix4 mx) =>
      parts.add(Part(geo, mx, mat));

  push(_pole, cylGeometry(.10, .17, h, 8), trs(0, h / 2));
  push(_pole, cylGeometry(.22, .26, .20, 8), trs(0, .10));
  for (var ai = 0; ai < 2; ai++) {
    final y = ai == 0 ? h - .60 : h - 1.50;
    final len = ai == 0 ? 1.90 : 1.50;
    push(_dark, boxGeometry(.08, .09, len), trs(0, y));
    push(_metal, boxGeometry(.05, .44, .05), trs(0, y - .27));
    for (var i = -1; i <= 1; i++) {
      if (i == 0 && ai == 1) continue;
      push(_white, cylGeometry(.055, .07, .15, 7),
          trs(0, y + .12, i * len / 2.4));
    }
  }
  push(_dark, cylGeometry(.04, .04, h - 1.60, 5),
      trs(dir * .125, (h - 1.60) / 2, .055));
  if (o.lamp) {
    push(_metal, boxGeometry(.06, .06, .80), trs(0, h - 2.60, dir * .40));
    push(_metal, cylGeometry(.055, .055, .50, 8), trs(0, h - 2.60, dir * .78));
    push(_metal, cylGeometry(0, .26, .20, 12, openEnded: true),
        trs(0, h - 2.72, dir * .78));
    push(const Mat(0xfff2d0, unlit: true, noOutline: true),
        boxGeometry(.20, .05, .20), trs(0, h - 2.84, dir * .78));
  }

  final baked = bake(parts);
  final rotation = o.ry == 0 ? null : trs(0, 0, 0, 0, o.ry);
  final offset = Vector3(o.x, o.y, o.z);
  return [
    for (final t in baked)
      Tri(
          (rotation?.transformed3(t.a) ?? t.a) + offset,
          (rotation?.transformed3(t.b) ?? t.b) + offset,
          (rotation?.transformed3(t.c) ?? t.c) + offset,
          rotation?.transformed3(t.normal) ?? t.normal,
          t.mat)
  ];
}
