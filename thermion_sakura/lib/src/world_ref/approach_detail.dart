/// Visible street composition from `approach.js` and `gakkomae.js`.
///
/// Completes the school-route camera with the bakery frontage, its bicycles,
/// the close parked lorry, route guardrails, utility/sign silhouettes, and the
/// cherry/grove planting that frames the bend into ひばり山.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'details.dart';
import 'make_pole.dart';
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'pixel_text.dart';
import 'street.dart';

const _wall = Mat(0xf2e7d3, tint: 0x6f6790, bands: '3');
const _wallAlt = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3');
const _roof = Mat(0x59617a, tint: 0x544e74, bands: '3');
const _blue = Mat(0x385f9f, tint: 0x4d5680, bands: '3');
const _glass = Mat(0x53627a, unlit: true, noOutline: true);
const _interior = Mat(0xc9b58d, unlit: true, noOutline: true);
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _sign = Mat(0xfff5d5, unlit: true);
const _signInk = Mat(0x8f7359, unlit: true, noOutline: true);
const _yellow = Mat(0xf4c033, unlit: true);
const _black = Mat(0x322e3b, tint: 0x4b4560, bands: '2');

void _box(List<Part> p, double w, double h, double d, Mat m, double x, double y,
    double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  p.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), m));
}

List<Tri> _bakery() {
  final p = <Part>[];
  const x0 = -11.45, x1 = -4.95, z0 = -60.55, z1 = -55.05;
  const y = 1.05;
  const h1 = 3.0, h2 = 2.5;
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;

  _box(p, x1 - x0, h1, z1 - z0, _wall, cx, y + h1 / 2, cz);
  _box(p, x1 - x0 - .25, h2, z1 - z0 - .2, _wallAlt, cx - .08, y + h1 + h2 / 2,
      cz);
  _box(p, x1 - x0 + .35, .2, z1 - z0 + .35, _roof, cx, y + h1 + h2 + .1, cz);
  _box(p, .18, .20, z1 - z0 + .3, _roof, x1 + .05, y + h1, cz);

  // Road-facing glass shopfront and blue fabric canopy.
  _box(p, .08, 2.05, 3.75, _glass, x1 + .045, y + 1.18, cz + .15);
  _box(p, .12, .42, 3.92, _blue, x1 + .10, y + 2.55, cz + .15);
  _box(p, 1.55, .13, 4.15, _blue, x1 + .78, y + 2.63, cz + .15, 0, 0, -.13);
  for (var i = 0; i <= 4; i++) {
    _box(p, .11, 2.08, .08, _metal, x1 + .09, y + 1.18, cz - 1.72 + i * .86);
  }
  _box(p, .22, .18, 3.9, _metalDark, x1 + .09, y + .14, cz + .15);
  // Warm shelves and round product displays behind the glazing.
  for (var row = 0; row < 2; row++) {
    _box(p, .10, .08, 3.2, _interior, x1 - .10, y + .72 + row * .65, cz + .15);
  }

  // Cream fascia and the Canvas2D sign from the source scene.
  _box(p, .15, .82, 4.45, _sign, x1 + .08, y + 4.56, cz + .05);
  appendPixelText(p, 'パン工房 こむぎ',
      x: x1 + .17,
      y: y + 4.56,
      z: cz + .05,
      height: .32,
      charWidth: .27,
      spacing: .045,
      depth: .035,
      ry: math.pi / 2,
      mat: _signInk);
  // Two upper windows and balcony rail.
  for (final z in [cz - 1.25, cz + 1.25]) {
    _box(p, .08, 1.15, 1.45, _glass, x1 + .045, y + 3.55, z);
    _box(p, .11, 1.2, .08, _metal, x1 + .08, y + 3.55, z);
  }
  _box(p, .8, .10, 4.5, _metalDark, x1 + .38, y + 3.0, cz);
  for (var i = 0; i <= 8; i++) {
    _box(p, .06, 1.0, .06, _metalDark, x1 + .72, y + 3.45,
        z0 + .45 + i * (z1 - z0 - .9) / 8);
  }
  _box(p, .06, .06, 4.6, _metalDark, x1 + .72, y + 3.94, cz);
  return bake(p);
}

List<Tri> _stationer() {
  final p = <Part>[];
  const x0 = -7.8, x1 = -3.0, z0 = -64.5, z1 = -60.9;
  const y = 1.05;
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
  const h1 = 3.1, h2 = 2.65;
  const stationerWall = Mat(0xe4ebf2, tint: 0x6f6790, bands: '3');

  _box(p, x1 - x0, h1, z1 - z0, stationerWall, cx, y + h1 / 2, cz);
  _box(p, x1 - x0 - .22, h2, z1 - z0 - .18, _wallAlt, cx - .05, y + h1 + h2 / 2,
      cz);
  _box(p, x1 - x0 + .26, .18, z1 - z0 + .28, _roof, cx, y + h1 + h2 + .09, cz);

  _box(p, .08, 2.04, 2.75, _glass, x1 + .045, y + 1.18, cz);
  for (var i = 0; i <= 3; i++) {
    _box(p, .10, 2.1, .07, _metal, x1 + .08, y + 1.18, z0 + .43 + i * .9);
  }
  _box(p, .16, .42, 3.15, _blue, x1 + .12, y + 2.56, cz);
  _box(p, 1.12, .12, 3.25, _blue, x1 + .58, y + 2.61, cz, 0, 0, -.11);
  _box(p, .14, .72, 3.05, _sign, x1 + .09, y + 4.65, cz);
  appendPixelText(p, '文具 ひばり堂',
      x: x1 + .175,
      y: y + 4.65,
      z: cz,
      height: .29,
      charWidth: .25,
      spacing: .045,
      depth: .03,
      ry: math.pi / 2,
      mat: _signInk);
  for (final z in [cz - .92, cz + .92]) {
    _box(p, .08, 1.08, 1.16, _glass, x1 + .045, y + 3.58, z);
    _box(p, .10, 1.12, .07, _metal, x1 + .08, y + 3.58, z);
  }
  return bake(p);
}

List<Tri> _warningSign() {
  final p = <Part>[];
  const x = -1.35, z = -60.2, y = 1.05;
  _box(p, .08, 2.2, .08, _metalDark, x, y + 1.1, z);
  _box(p, .12, .86, .86, _black, x, y + 1.82, z);
  _box(p, .14, .54, .54, _yellow, x, y + 1.82, z, math.pi / 4, 0, 0);
  _box(p, .16, .25, .05, _black, x, y + 1.82, z - .31);
  return bake(p);
}

List<Tri> _approachRoadPaint() {
  const paint = Mat(0xf4f2f6, unlit: true, noOutline: true);
  final parts = <Part>[];

  // The source uses a 1.35 x 2.55 Canvas2D diamond decal. Rebuild its four
  // strokes as geometry so the native renderer remains texture-free.
  void diamond(double z, double dx) {
    final x = centerX(z) + dx;
    const halfW = 1.35 / 2, halfD = 2.55 / 2, stroke = .085;
    final corners = <Vector3>[
      Vector3(x, groundY(z) + .044, z - halfD),
      Vector3(x + halfW, groundY(z) + .044, z),
      Vector3(x, groundY(z) + .044, z + halfD),
      Vector3(x - halfW, groundY(z) + .044, z),
    ];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i], b = corners[(i + 1) % corners.length];
      final d = b - a;
      parts.add(Part(
          boxGeometry(stroke, .012, d.length),
          trs((a.x + b.x) / 2, a.y, (a.z + b.z) / 2, 0, math.atan2(d.x, d.z)),
          paint));
    }
  }

  diamond(-40.0, 1.5);
  diamond(-57.5, -1.5);
  return bake(parts);
}

List<Tri> _projectApproachRoadShadow(List<Tri> caster) {
  const sunX = -52.0, sunY = 62.0, sunZ = 56.0;
  const shadow = Mat(0x5b6183, unlit: true, noOutline: true);
  final out = <Tri>[];

  Vector3 project(Vector3 point) {
    const receiverY = 1.05;
    final t = (point.y - receiverY) / sunY;
    return Vector3(point.x - sunX * t, receiverY + .026, point.z - sunZ * t);
  }

  for (final tri in caster) {
    if (math.max(tri.a.y, math.max(tri.b.y, tri.c.y)) < 2.05) continue;
    var a = project(tri.a), b = project(tri.b), c = project(tri.c);
    final center = (a + b + c) / 3.0;
    if (center.z < -75 || center.z > -43) continue;
    final roadCenter = centerX(center.z);
    if (center.x < roadCenter - roadHalf || center.x > roadCenter + roadHalf) {
      continue;
    }
    if ((b - a).cross(c - a).y < 0) {
      final swap = b;
      b = c;
      c = swap;
    }
    out.add(Tri(a, b, c, Vector3(0, 1, 0), shadow));
  }
  return out;
}

List<Tri> buildApproachDetail({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
  bool includeProjectedRoadShadow = false,
  int blossomLightColor = 0xf8e9ed,
  int blossomColor = 0xecb8cc,
  int blossomDeepColor = 0xe598b9,
}) {
  final scene = <Tri>[];
  void add(List<Tri> tris, {bool casts = true}) {
    scene.addAll(tris);
    if (casts) {
      shadowCasters?.addAll(tris);
      groupedShadowCasters?.addAll(tris);
    }
  }

  add(_bakery());
  add(_stationer());
  add(_warningSign());
  add(_approachRoadPaint(), casts: false);

  // The lorry is deliberately close: the fidelity camera stands just behind
  // its left rear quarter, as does the reference player position.
  add(makeVehicle(
      kind: 'boxtruck',
      color: CAR.white,
      x: 5.0,
      y: 1.05,
      z: -55.1,
      ry: math.pi / 2));

  for (var i = 0; i < 4; i++) {
    add(makeBicycle(
        x: -3.95,
        y: 1.05,
        z: -55.7 - i * .7,
        ry: 0,
        lean: i.isEven ? .035 : -.04,
        color: i.isEven ? 0x405b82 : 0x6e4f58));
  }
  for (var i = 0; i < 3; i++) {
    add(makeBicycle(
        x: -2.45,
        y: 1.05,
        z: -61.6 - i * .62,
        ry: 0,
        lean: i.isEven ? .04 : -.035,
        color: i == 0 ? 0x405b82 : (i == 1 ? 0x7b4d58 : 0x53745e)));
  }
  for (final run in const [
    (-30.5, -38.0),
    (-53.2, -54.6),
    (-61.0, zMin + 1.5),
  ]) {
    final z = (run.$1 + run.$2) / 2;
    add(makeGuardrail(
        x: centerX(z) - roadHalf - .28,
        y: groundY(z),
        z: z,
        ry: math.pi / 2,
        len: (run.$2 - run.$1).abs()));
  }
  for (final run in const [(-40.0, -46.4), (-52.6, -60.0)]) {
    final z = (run.$1 + run.$2) / 2;
    add(makeGuardrail(
        x: centerX(z) + roadHalf + .28,
        y: groundY(z),
        z: z,
        ry: math.pi / 2,
        len: (run.$2 - run.$1).abs()));
  }

  for (final spec in const [
    // approach.js distribution poles
    (7.4, -37.5, 9.0, 331, true, -1, true, 0.0),
    (-2.6, -60.5, 8.8, 335, true, 1, false, 0.0),
    (7.4, -53.5, 8.8, 332, false, -1, true, 0.0),
    (7.5, -63.0, 8.6, 333, true, -1, false, 0.0),
    (-2.5, -43.0, 9.0, 334, false, 1, false, 0.0),
    // gakkomae.js's smaller school-side lamp chain
    (9.9, -33.4, 7.4, 9161, true, -1, true, -math.pi / 2),
    (9.9, -43.6, 7.6, 9162, false, -1, true, -math.pi / 2),
    (9.9, -56.4, 7.6, 9163, true, -1, true, -math.pi / 2),
  ]) {
    add(makePole(PoleOpts(
        x: spec.$1,
        y: groundY(spec.$2),
        z: spec.$2,
        h: spec.$3,
        seed: spec.$4,
        lamp: spec.$5,
        armDir: spec.$6,
        transformer: spec.$7,
        ry: spec.$8)));
  }

  final cherries = buildSakura([
    const SakuraSpot(
        x: 9.5,
        z: -42.6,
        y: 1.05,
        scale: 1.14,
        seed: 9171,
        lean: .11,
        leanDir: 1.7),
    const SakuraSpot(
        x: 9.5,
        z: -55.4,
        y: 1.05,
        scale: 1.20,
        seed: 9172,
        lean: .09,
        leanDir: 4.4),
    const SakuraSpot(
        x: 9.4,
        z: -63.2,
        y: 1.05,
        scale: 1.10,
        seed: 9173,
        lean: .12,
        leanDir: 2.9),
    const SakuraSpot(
        x: -3.2,
        z: -60.0,
        y: 1.05,
        scale: 1.06,
        seed: 9174,
        lean: .10,
        leanDir: 3.4),
    const SakuraSpot(
        x: -3.2,
        z: -63.2,
        y: 1.05,
        scale: 1.16,
        seed: 731,
        lean: .11,
        leanDir: 4.8),
    for (var i = 0; i < 4; i++)
      SakuraSpot(
          x: centerX(-31 - i * 3) - roadHalf - 2.6,
          z: -31 - i * 7.2,
          y: groundY(-31 - i * 7.2),
          scale: 1.08 + (i % 2) * .12,
          seed: 740 + i,
          lean: .10,
          leanDir: 1.5 + i),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  add(cherries);
  if (includeProjectedRoadShadow) {
    scene.addAll(_projectApproachRoadShadow(cherries));
  }

  final cx = centerX(-65);
  add(buildGrove([
    GroveSpot(
        x: 12.6,
        z: -28.6,
        y: groundY(-28.6),
        scale: 1.5,
        seed: 9175,
        spread: 1.15),
    GroveSpot(
        x: -18.0,
        z: -41.0,
        y: groundY(-41),
        scale: 1.4,
        seed: 761,
        spread: 1.15),
    GroveSpot(
        x: -19.4,
        z: -55.0,
        y: groundY(-55),
        scale: 1.32,
        seed: 762,
        spread: 1.1),
    GroveSpot(
        x: -15.0,
        z: -62.0,
        y: groundY(-62),
        scale: 1.5,
        seed: 763,
        spread: 1.2),
    GroveSpot(
        x: cx - 8.0, z: -68.4, y: 1.05, scale: 1.3, seed: 720, spread: 1.1),
    GroveSpot(
        x: cx - 4.4, z: -70.6, y: 1.05, scale: 1.5, seed: 721, spread: 1.1),
    GroveSpot(
        x: cx + 6.4, z: -70.6, y: 1.05, scale: 1.5, seed: 724, spread: 1.1),
    GroveSpot(
        x: cx + 10.0, z: -72.8, y: 1.05, scale: 1.7, seed: 725, spread: 1.1),
  ]));

  add(buildShrubs([
    ShrubSpot(
        x: 10.9, z: -30.9, y: 1.05, r: .44, count: 3, spread: 1.05, seed: 9176),
    ShrubSpot(
        x: 10.4,
        z: -26.4,
        y: groundY(-26.4),
        r: .5,
        count: 4,
        spread: 1.3,
        seed: 9178),
    const ShrubSpot(
        x: -9.4, z: -64.4, y: 1.05, r: .46, count: 3, spread: 1.1, seed: 9177),
    for (var i = 0; i < 5; i++)
      ShrubSpot(
          x: centerX(-36 - i * 5) - roadHalf - 2.2,
          z: -36 - i * 5.6,
          y: groundY(-36 - i * 5.6),
          r: .5,
          count: 3,
          spread: 1.4,
          seed: 750 + i),
  ]));

  return scene;
}
