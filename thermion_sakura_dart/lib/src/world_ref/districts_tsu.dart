/// Native Dart port of four district modules from the reference:
/// `tsugakuro.js` (5-chome, behind the school route),
/// `uramachi.js` (the back street behind the shrine),
/// `gakkomae.js` (the school route itself),
/// `kawabata.js` (the lane between the canal and the school).
///
/// CONVENTIONS (matching districts.dart / make_house.dart / street.dart):
///   - Return `List<Tri>`, no context object.
///   - Inline material colours as `const Mat(0x..., ...)` from PAL.
///   - Defer textures; skip `hullOutline`.
///   - `RngKit(seed)` mirrors `rngKit`.
///   - Import `makeHouse` / `HouseOpts` for detached houses.
///
/// Context-only navigation and collision registrations are irrelevant to the
/// static renderer. Their visible equivalents are authored directly here:
/// lanes, plot pads, representative housing types, furniture, vegetation, and
/// the distinguishing civil details of each district.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'details.dart' show makeVendingMachine;
import 'make_house.dart';
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';

// ---------------------------------------------------------------------------
// Shared material palette (const, matching palette.js PAL values).
// ---------------------------------------------------------------------------

const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3'); // PAL.concrete
const _concreteMid =
    Mat(0xc2bdc8, tint: 0x6a6288, bands: '3'); // PAL.concreteMid
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _stone = Mat(0xc6c0cb, tint: 0x655d80, bands: '3'); // PAL.stone
const _moss = Mat(0x6e7a62, tint: 0x5b6f8c, bands: '2');
const _asphalt = Mat(0x9a95a6, tint: 0x6a608f, bands: '3');
const _asphaltWorn = Mat(0xa39dab, tint: 0x6a608f, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _grass = Mat(0x91ae72, tint: 0x5b6f8c, bands: '3');
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _glass = Mat(0x9dc0d4, unlit: true);
const _red = Mat(0xe0453f, tint: 0x7a4060, bands: '3');

// ---------------------------------------------------------------------------
// Helpers
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

void _pad(
    List<Part> parts, double x, double z, double w, double d, double y, Mat mat,
    [double h = .06]) {
  _box(parts, w, h, d, mat, x, y + h / 2, z);
}

void _bench(List<Part> parts, double x, double z, double y, double yaw) {
  final q = Matrix4.translationValues(x, y, z) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(1.7, .08, .42), q * trs(0, .45), _timber))
    ..add(Part(boxGeometry(1.7, .08, .12), q * trs(0, .82, -.27), _timber));
  for (final side in [-.62, .62]) {
    parts
        .add(Part(boxGeometry(.10, .45, .10), q * trs(side, .23), _timberDark));
  }
}

void _railX(List<Part> parts, double x0, double x1, double z, double y,
    [double h = .95]) {
  final n = math.max(1, ((x1 - x0) / 2).ceil());
  for (var i = 0; i <= n; i++) {
    _cyl(parts, .035, .04, h, 7, _metal, x0 + (x1 - x0) * i / n, y + h / 2, z);
  }
  for (final dy in [h * .52, h]) {
    _box(parts, x1 - x0, .06, .06, _metal, (x0 + x1) / 2, y + dy, z);
  }
}

void _shelter(List<Part> parts, double x, double z, double y,
    {double w = 4.2, double d = 2.0}) {
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(parts, .09, 2.05, .09, _metalDark, x + sx * (w / 2 - .15), y + 1.025,
          z + sz * (d / 2 - .15));
    }
  }
  _box(parts, w + .3, .12, d + .3, _glass, x, y + 2.12, z, 0, 0, -.04);
}

// ========================= buildTsugakuro ====================================
//
// ひばり台五丁目 -- the houses behind the 通学路.
//
// PORTED:
//   - Bakery extract duct (cylinder + elbow + cowl) on こむぎ's flank.
//   - Plain two-storey detached house (makeHouse, gable roof, face 'x+').
//
// DEFERRED:
//   - Lane, links, cross link, 抜け道 surfaces (lane/pad/groundMats).
//   - All housing: makeWalkup (staff block), makeAtticHouse (二階半),
//     makeTerrace (連棟 二戸).
//   - All props, poles, planting, shop backs, service strip clutter.
//   - All plot utilities (plotBox, plotCollide, plotWall, dressPlot, etc.).
//   - Ground furniture: gutters, bollards, signs, mirrors, hedges.

List<Tri> buildTsugakuro({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extraTris = <List<Tri>>[];
  const Y = 1.05;

  // The narrow north-south lane, its school-route link, drop-off bay, and the
  // service cut-through between the two shops.
  _pad(parts, -21.8, -46.9, 3.2, 32.6, Y, _asphaltWorn, .05);
  _pad(parts, -11.1, -41.4, 19.4, 2.6, Y, _asphaltWorn, .05);
  _pad(parts, -5.2, -39.2, 5.0, 2.6, Y, _asphalt, .08);
  _pad(parts, -11.6, -53.8, 17.6, 2.0, Y, _concreteMid, .06);
  _pad(parts, -21.2, -62.0, 5.2, 2.6, Y, _asphaltWorn, .06);
  _pad(parts, -21.8, -30.5, 4.4, 1.8, .655, _concrete, .06);
  // Covered drain and repeated grate seams down the plot side.
  _box(parts, .48, .07, 31.0, _concreteMid, -23.14, Y + .055, -46.9);
  for (double z = -61.6; z < -31.6; z += .9) {
    _box(parts, .40, .012, .055, _metalDark, -23.14, Y + .10, z);
  }

  // -- Bakery extract duct on こむぎ's flank (tsugakuro.js buildServiceStrip) --
  {
    const PAN_X = -11.45;
    // vertical cylinder
    _cyl(parts, 0.14, 0.14, 3.0, 8, _metalDark, PAN_X - 0.3, Y + 1.5, -60.0);
    // horizontal elbow
    _cyl(parts, 0.14, 0.14, 0.9, 8, _metalDark, PAN_X - 0.3, Y + 3.0, -59.55,
        math.pi / 2, 0, 0);
    // cowl cap
    _box(parts, 0.42, 0.2, 0.42, _metalDark, PAN_X - 0.3, Y + 3.16, -59.2);
  }

  // -- Plain two-storey detached house (tsugakuro.js buildHouses) --
  // tsugakuro.js HOUSE = { x: -28.6, z: -53.4, w: 6.2, d: 5.6, face: 'x+' }
  extraTris.add(makeHouse(HouseOpts(
    x: -28.6,
    z: -53.4,
    y: Y,
    w: 6.2,
    d: 5.6,
    floors: 2,
    face: 'x+',
    seed: 8748,
    wall: 5,
    roof: 2,
    roofKind: 'gable',
  )));

  // グリーンハイツ, the attic house, and the connected two-unit terrace.
  extraTris.add(makeHouse(const HouseOpts(
      x: -28.0,
      z: -36.6,
      y: Y,
      w: 7.2,
      d: 6.4,
      floors: 3,
      face: 'x+',
      seed: 8731,
      wall: 2,
      roof: 3,
      roofKind: 'flat')));
  extraTris.add(makeHouse(const HouseOpts(
      x: -28.4,
      z: -45.6,
      y: Y,
      w: 6.4,
      d: 6.0,
      floors: 2,
      face: 'x+',
      seed: 8741,
      wall: 3,
      roof: 1,
      roofKind: 'gable')));
  for (var i = 0; i < 2; i++) {
    extraTris.add(makeHouse(HouseOpts(
        x: -28.4,
        z: -61.85 + i * 2.9,
        y: Y,
        w: 5.8,
        d: 2.9,
        floors: 2,
        face: 'x+',
        seed: 8754 + i,
        wall: 2,
        roof: 3,
        roofKind: 'gable')));
  }
  _shelter(parts, -24.1, -38.8, Y + .08, w: 3, d: 1.4);
  extraTris.add(makePlanter(
      x: -2.5, y: Y + .08, z: -40.6, r: .26, flower: true, seed: 8721, n: 5));
  extraTris
      .add(makeMirror(x: -19.6, y: Y + .06, z: -42.9, ry: 2.4, h: 2.4, r: .4));
  extraTris.add(makeCone(x: -18.8, y: Y, z: -62.8, ry: .4));

  extraTris.add(buildSakura(const [
    SakuraSpot(
        x: -24.2,
        z: -37.8,
        y: Y,
        scale: 1.16,
        seed: 8771,
        lean: .1,
        leanDir: 4.5),
    SakuraSpot(
        x: -24.3,
        z: -55.0,
        y: Y,
        scale: 1.22,
        seed: 8772,
        lean: .11,
        leanDir: 1.6),
    SakuraSpot(
        x: -19.6,
        z: -63.4,
        y: Y,
        scale: 1.08,
        seed: 8773,
        lean: .09,
        leanDir: 3.0),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extraTris.add(buildGrove(const [
    GroveSpot(x: -33.4, z: -38.6, y: Y, scale: 1.55, seed: 8774, spread: 1.15),
    GroveSpot(x: -33.8, z: -48.0, y: Y, scale: 1.45, seed: 8775, spread: 1.1),
    GroveSpot(x: -33.2, z: -57.6, y: Y, scale: 1.6, seed: 8776, spread: 1.2),
    GroveSpot(x: -25.0, z: -64.8, y: Y, scale: 1.4, seed: 8777, spread: 1.1),
  ]));
  extraTris.add(buildShrubs(const [
    ShrubSpot(
        x: -32.6, z: -43.4, y: Y, r: .5, count: 4, spread: 1.3, seed: 8778),
    ShrubSpot(
        x: -32.8, z: -53.0, y: Y, r: .46, count: 3, spread: 1.15, seed: 8779),
  ]));

  return [...bake(parts), ...extraTris.expand((t) => t)];
}

// ========================= buildUramachi ======================================
//
// 桜守裏町 -- the back street behind the shrine.
//
// PORTED:
//   - Shrine base stone + moss on north face.
//   - Hedge gap posts + caps (two posts either side of the gap).
//
// DEFERRED:
//   - Lane, arm, mouth, corner surfaces (lane/pad/groundMats).
//   - All housing: makeTimberHouse (木造平屋), makeNagaya (長屋 四戸).
//   - All props, poles, planting, back land surfaces, plot utilities.

List<Tri> buildUramachi({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];
  const Y = 0.45;

  _pad(parts, -9.95, 48.9, 3.5, 2.4, Y, _concreteMid);
  _pad(parts, -10.3, 56.3, 2.3, 14.2, Y, _concreteMid, .05);
  _pad(parts, -5.425, 64.8, 12.05, 2.3, Y, _concreteMid, .05);
  _pad(parts, -10.3, 63.9, 2.3, 4.1, Y, _concreteMid, .11);
  _pad(parts, -1.6, 59.95, 1.9, 2.4, Y, _stone, .07);
  _pad(parts, -1.6, 62.4, 1.8, 3.4, Y, _gravel, .05);
  // Old open drain with regular cross-grates.
  _box(parts, .42, .10, 13.2, _concreteMid, -11.21, Y + .02, 56.3);
  for (double z = 50; z < 63; z += .8) {
    _box(parts, .38, .025, .06, _metalDark, -11.21, Y + .08, z);
  }

  // -- Shrine base (祠) at the corner where the mouth meets the lane --
  {
    const sx = -11.9, sz = 50.9;
    _box(parts, 1.0, 0.22, 0.9, _stone, sx, Y + 0.11, sz);
    // moss on the north face of the stone base
    _box(parts, 0.94, 0.06, 0.1, _moss, sx, Y + 0.2, sz - 0.42);
  }

  // -- Hedge gap posts + caps (uramachi.js buildStreets) --
  {
    const GAP_X = -1.6;
    const HEDGE_Z = 59.95;
    for (final s in [-1.0, 1.0]) {
      final px = GAP_X + s * 1.0;
      _box(parts, 0.16, 1.15, 0.16, _stone, px, Y + 0.605, HEDGE_Z);
      _box(parts, 0.22, 0.05, 0.22, _concrete, px, Y + 1.2, HEDGE_Z);
    }
  }

  // 木造平屋 and the four-door row house at the arm.
  extra.add(makeHouse(const HouseOpts(
      x: -13.0,
      z: 68.2,
      y: Y,
      w: 4.2,
      d: 3.0,
      floors: 1,
      face: 'z-',
      seed: 8921,
      wall: 4,
      roof: 2,
      roofKind: 'gable')));
  for (var i = 0; i < 4; i++) {
    extra.add(makeHouse(HouseOpts(
        x: -9.5 + i * 2.6,
        z: 68.6,
        y: Y,
        w: 2.6,
        d: 4.6,
        floors: 1,
        face: 'z-',
        seed: 8931 + i,
        wall: 5,
        roof: 1,
        roofKind: 'gable')));
  }
  // Drying/back-land strip and small front-garden details.
  _pad(parts, -7.8, 74.0, 17.0, 5.2, Y - .02, _grass, .05);
  extra.add(makePlanter(
      x: -11.85, y: Y, z: 50.1, r: .20, flower: true, seed: 8912, n: 5));
  extra.add(makeBicycle(
      x: -8.8, y: Y + .06, z: 65.4, ry: -.2, lean: .05, color: 0x6d7e92));
  extra.add(buildSakura(const [
    SakuraSpot(
        x: -.6,
        z: 67.4,
        y: Y,
        scale: 1.18,
        seed: 8971,
        lean: .12,
        leanDir: 2.1),
    SakuraSpot(
        x: -16.4,
        z: 66.8,
        y: Y,
        scale: 1.06,
        seed: 8972,
        lean: .1,
        leanDir: 4.8),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildGrove(const [
    GroveSpot(x: -16.8, z: 70.6, y: Y, scale: 1.5, seed: 8973, spread: 1.15),
    GroveSpot(x: -8.2, z: 78.0, y: Y, scale: 1.45, seed: 8974, spread: 1.1),
    GroveSpot(x: -2.4, z: 78.6, y: Y, scale: 1.55, seed: 8975, spread: 1.2),
  ]));
  extra.add(buildShrubs(const [
    ShrubSpot(
        x: -9.6, z: 70.6, y: Y, r: .46, count: 3, spread: 1.1, seed: 8976),
    ShrubSpot(
        x: -17.6, z: 67.8, y: Y, r: .5, count: 3, spread: 1.2, seed: 8977),
  ]));

  return [...bake(parts), ...extra.expand((list) => list)];
}

// ========================= buildGakkomae ======================================
//
// 学校前通り -- the 通学路 itself, from こばと橋 to the school gate.
//
// PORTED:
//   - Bridge head stair rail (cyl posts + handrail).
//   - Two asphalt patch slabs in the carriageway.
//
// DEFERRED:
//   - All surfaces: bridge square, school verge, aprons, yards (pad/lane/
//     groundMats/steps).
//   - All housing: makeShop x2 (bungu + ringyo), makeBikeShelter x2.
//   - Guardrail, vending machines, all props.
//   - Flight of steps down to towpath (steps from ground.js).
//   - Poles, planting, street furniture, signs, mirrors, notice boards.
//   - All plot utilities.

List<Tri> buildGakkomae({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];
  const Y = 1.05;
  const BANK_Y = 0.655;

  // Bridge-head square and the long school arrival verge.
  _pad(parts, 9.15, -32.55, 2.9, 3.3, Y, _concrete, .08);
  _pad(parts, 9.10, -49.0, 2.72, 28.0, Y, _concrete, .07);
  _pad(parts, -5.4, -59.5, 5.6, 7.2, Y, _concreteMid, .07);
  _pad(parts, -16.0, -54.9, 6.2, 7.0, Y, _gravel, .06);
  _shelter(parts, 9.35, -38.0, Y + .07, w: 4.6, d: 2.1);
  _shelter(parts, 9.35, -58.7, Y + .07, w: 4.6, d: 2.1);
  _railX(parts, 7.65, 8.15, -31.6, Y, .9);

  // -- Bridge head stair rail (gakkomae.js buildBridgeHead) --
  {
    const RISE = (Y + 0.08 - BANK_Y) / 3; // ~0.158
    // four posts along the open side of the flight
    for (int i = 0; i <= 3; i++) {
      _cyl(parts, 0.035, 0.035, 0.95, 7, _metal, 8.25,
          BANK_Y + i * RISE + 0.475, -29.9 - i * 0.33);
    }
    // handrail (tilted cylinder along the flight)
    _cyl(parts, 0.04, 0.04, 1.12, 8, _metal, 8.25, BANK_Y + 0.95 + 1.5 * RISE,
        -30.4, -math.atan2(0.99, 3 * RISE), 0, 0);
  }

  // -- Two asphalt patch slabs in the carriageway (buildStreetFurniture) --
  for (final entry in <List<double>>[
    [0.6, -47.0, 1.6, 2.0],
    [5.2, -57.6, 1.4, 1.8],
  ]) {
    final px = entry[0], pz = entry[1];
    final pw = entry[2], pd = entry[3];
    final g = planeGeometry(pw, pd);
    final mx = trs(px, Y + 0.018, pz, -math.pi / 2, 0, 0);
    parts.add(Part(g, mx, _concreteMid));
  }

  // 文具店 and 林業用品店: exact footprints and frontage directions. The
  // shared house generator retains doors, windows, eaves, meters, and ACs.
  extra.add(makeHouse(const HouseOpts(
      x: -5.4,
      z: -62.7,
      y: Y,
      w: 3.6,
      d: 4.8,
      floors: 2,
      face: 'x+',
      seed: 9131,
      wall: 1,
      roof: 3,
      roofKind: 'flat')));
  extra.add(makeHouse(const HouseOpts(
      x: -16.0,
      z: -58.2,
      y: Y,
      w: 5.4,
      d: 5.0,
      floors: 2,
      face: 'x-',
      seed: 9141,
      wall: 3,
      roof: 2,
      roofKind: 'gable')));
  extra.add(makeVendingMachine(
      x: 10.0, y: Y + .08, z: -33.4, ry: -math.pi / 2, variant: 2, seed: 57));
  extra.add(
      makeBicycle(x: 8.5, y: Y + .08, z: -32.4, lean: .06, color: 0x4c6a86));
  for (final spot in const [
    (8.1, -31.5, .26, 9112),
    (7.95, -34.4, .22, 9113),
    (-2.3, -30.6, .24, 9114),
  ]) {
    extra.add(makePlanter(
        x: spot.$1,
        y: Y,
        z: spot.$2,
        r: spot.$3,
        flower: true,
        seed: spot.$4,
        n: 5));
  }
  // Notice boards and repeated school-way plates are geometric panels rather
  // than host-font textures.
  for (final z in [-36.2, -46.8, -55.8, -64.0]) {
    _box(parts, .07, 1.85, .07, _metalDark, 8.2, Y + .925, z);
    _box(parts, .68, .48, .06, _concrete, 8.2, Y + 1.5, z);
    _box(parts, .48, .07, .012, _red, 8.2, Y + 1.55, z - .036);
  }
  extra.add(buildSakura(const [
    SakuraSpot(
        x: 9.5,
        z: -42.6,
        y: Y,
        scale: 1.14,
        seed: 9171,
        lean: .11,
        leanDir: 1.7),
    SakuraSpot(
        x: 9.5,
        z: -55.4,
        y: Y,
        scale: 1.20,
        seed: 9172,
        lean: .09,
        leanDir: 4.4),
    SakuraSpot(
        x: 9.4,
        z: -63.2,
        y: Y,
        scale: 1.10,
        seed: 9173,
        lean: .12,
        leanDir: 2.9),
    SakuraSpot(
        x: -3.2,
        z: -60.0,
        y: Y,
        scale: 1.06,
        seed: 9174,
        lean: .1,
        leanDir: 3.4),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildGrove(const [
    GroveSpot(x: 12.6, z: -28.6, y: Y, scale: 1.5, seed: 9175, spread: 1.15),
  ]));
  extra.add(buildShrubs(const [
    ShrubSpot(
        x: 10.9, z: -30.9, y: Y, r: .44, count: 3, spread: 1.05, seed: 9176),
    ShrubSpot(
        x: 10.4, z: -26.4, y: Y, r: .5, count: 4, spread: 1.3, seed: 9178),
    ShrubSpot(
        x: -9.4, z: -64.4, y: Y, r: .46, count: 3, spread: 1.1, seed: 9177),
  ]));

  return [...bake(parts), ...extra.expand((list) => list)];
}

// ========================= buildKawabata ======================================
//
// 川端の道 -- the lane between the canal and the school's back wall.
//
// PORTED:
//   - Ramp slab + kerb upstand (down to the towpath).
//   - Ramp handrail posts + rail.
//
// DEFERRED:
//   - Lane surface, verge pads, slot pads, east end pad (lane/pad/groundMats).
//   - Canal edge railing (railing from ground.js).
//   - All housing: makeNagaya (長屋), makeTimberHouse x2 (木造平屋 + 木造二階建),
//     makeTerrace (連棟 二戸), makeAtticHouse (二階半).
//   - All props, poles, planting, benches, planter, flower beds, signs,
//     mirrors, notice boards, refuse, bollards, step stones.
//   - All plot utilities.
//   - The ramp's eight invisible height platforms (ctx.platform).

List<Tri> buildKawabata({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];
  const Y = 1.05;
  const BANK_Y = 0.655;

  _pad(parts, 37.5, -32.2, 36.2, 2.8, Y, _asphaltWorn, .05);
  _pad(parts, 14.4, -30.95, 7.6, 1.4, Y, _concreteMid);
  _pad(parts, 14.4, -40.05, 7.6, 1.4, Y, _concreteMid);
  _pad(parts, 30.0, -30.75, 21.4, .9, Y, _concrete);
  _pad(parts, 48.6, -30.75, 13.6, .9, Y, _concrete);
  _box(parts, 34.0, .07, .45, _concreteMid, 37.4, Y + .055, -33.34);
  for (double x = 21; x < 55; x += .9) {
    _box(parts, .055, .012, .38, _metalDark, x, Y + .10, -33.34);
  }
  _railX(parts, 19.2, 46.1, -30.45, Y, .95);
  _railX(parts, 51.7, 55.9, -30.45, Y, .95);

  // -- Ramp down to the towpath (kawabata.js buildCanalEdge) --
  {
    const RP_X0 = 46.4;
    const RP_X1 = 51.4;
    const RP_Z = -29.6;
    const RP_W = 2.4;
    const TOP = Y + 0.05;

    // Raked slab
    final len = RP_X1 - RP_X0;
    final rake = math.atan2(TOP - BANK_Y, len); // ~0.089 rad, 1:11
    final slabLen = len / math.cos(rake) + 0.1;
    _box(parts, slabLen, 0.3, RP_W, _concrete, (RP_X0 + RP_X1) / 2,
        (TOP + BANK_Y) / 2 - 0.15, RP_Z, 0, 0, -rake);

    // Kerb upstand down the water side
    _box(parts, RP_X1 - RP_X0, 0.14, 0.16, _concreteMid, (RP_X0 + RP_X1) / 2,
        Y - 0.36, RP_Z - RP_W / 2 + 0.08);

    // Handrail posts (following the ramp slope)
    for (int i = 0; i <= 5; i++) {
      final x = RP_X0 + ((RP_X1 - RP_X0) * i) / 5;
      final top = TOP - ((TOP - BANK_Y) * i) / 5;
      _cyl(parts, 0.035, 0.035, 0.92, 7, _metal, x, top + 0.46,
          RP_Z + RP_W / 2 - 0.1);
    }
    // Continuous handrail (tilted to follow slope)
    final railLen = math.sqrt(len * len + (TOP - BANK_Y) * (TOP - BANK_Y));
    _cyl(
        parts,
        0.04,
        0.04,
        railLen,
        8,
        _metal,
        (RP_X0 + RP_X1) / 2,
        TOP - (TOP - BANK_Y) / 2 + 0.9,
        RP_Z + RP_W / 2 - 0.1,
        0,
        0,
        math.pi / 2 - 0.088);
  }

  // Five-building row against the school wall. Connected types are split at
  // their party walls so their repeated entrances remain legible.
  for (var i = 0; i < 3; i++) {
    extra.add(makeHouse(HouseOpts(
        x: 21.0 + i * 2.5,
        z: -37.9,
        y: Y,
        w: 2.5,
        d: 4.6,
        floors: 1,
        face: 'z+',
        seed: 9331 + i,
        wall: 5,
        roof: 2,
        roofKind: 'gable')));
  }
  extra.add(makeHouse(const HouseOpts(
      x: 33.4,
      z: -37.9,
      y: Y,
      w: 4.8,
      d: 4.4,
      floors: 1,
      face: 'z+',
      seed: 9341,
      wall: 4,
      roof: 2,
      roofKind: 'gable')));
  for (var i = 0; i < 2; i++) {
    extra.add(makeHouse(HouseOpts(
        x: 37.85 + i * 2.9,
        z: -37.9,
        y: Y,
        w: 2.9,
        d: 5.0,
        floors: 2,
        face: 'z+',
        seed: 9346 + i,
        wall: 6,
        roof: 1,
        roofKind: 'gable')));
  }
  extra.add(makeHouse(const HouseOpts(
      x: 46.0,
      z: -37.8,
      y: Y,
      w: 5.6,
      d: 5.0,
      floors: 2,
      face: 'z+',
      seed: 9351,
      wall: 3,
      roof: 3,
      roofKind: 'gable')));
  extra.add(makeHouse(const HouseOpts(
      x: 52.6,
      z: -37.9,
      y: Y,
      w: 5.4,
      d: 4.8,
      floors: 2,
      face: 'z+',
      seed: 9361,
      wall: 4,
      roof: 2,
      roofKind: 'gable')));
  _pad(parts, 58.6, -34.4, 6.0, 11.4, Y - .02, _grass, .05);
  _shelter(parts, 44.8, -40.0, Y + .05, w: 3.2, d: 1.5);
  for (final x in [25.4, 37.2, 49.6]) {
    _bench(parts, x, -30.95, Y + .06, math.pi);
    extra.add(makePlanter(
        x: x + 1.3,
        y: Y + .06,
        z: -30.9,
        r: .24,
        flower: true,
        seed: 9300 + x.round(),
        n: 5));
  }
  extra.add(buildSakura(const [
    SakuraSpot(
        x: 22.6,
        z: -30.9,
        y: Y,
        scale: 1.12,
        seed: 9371,
        lean: .12,
        leanDir: 1.5),
    SakuraSpot(
        x: 35.0,
        z: -30.9,
        y: Y,
        scale: 1.22,
        seed: 9372,
        lean: .10,
        leanDir: 4.6),
    SakuraSpot(
        x: 44.2,
        z: -30.9,
        y: Y,
        scale: 1.08,
        seed: 9373,
        lean: .13,
        leanDir: 2.7),
    SakuraSpot(
        x: 54.6,
        z: -30.8,
        y: Y,
        scale: 1.16,
        seed: 9374,
        lean: .09,
        leanDir: 3.8),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildShrubs(const [
    ShrubSpot(
        x: 28.4, z: -31.0, y: Y, r: .44, count: 3, spread: 1.05, seed: 9375),
    ShrubSpot(
        x: 40.0, z: -30.9, y: Y, r: .42, count: 3, spread: 1.0, seed: 9376),
    ShrubSpot(
        x: 57.4, z: -35.8, y: Y, r: .46, count: 3, spread: 1.1, seed: 9385),
    ShrubSpot(
        x: 56.2, z: -30.4, y: Y, r: .42, count: 3, spread: 1.0, seed: 9386),
  ]));
  extra.add(buildGrove(const [
    GroveSpot(x: 59.4, z: -33.0, y: Y, scale: 1.55, seed: 9383, spread: 1.15),
    GroveSpot(x: 58.6, z: -37.6, y: Y, scale: 1.4, seed: 9384, spread: 1.1),
  ]));

  return [...bake(parts), ...extra.expand((list) => list)];
}
