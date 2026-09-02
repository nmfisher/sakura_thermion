/// Composition-first port of `rokuchome.js` (ひばり台六丁目).
///
/// Recreates the end-of-line view: the bus street and turning bulb, waiting
/// island, minibus and parked vehicles, small shops, north-side housing,
/// utility poles, and the planted bank that closes the district horizon.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../geom/three_geom.dart';
import 'details.dart';
import 'make_house.dart';
import 'make_pole.dart';
import 'make_props.dart'
    show
        makeBicycle,
        makeBroom,
        makeCone,
        makeCrates,
        makeGuardrail,
        makeKeiTruck,
        makeMilkCrate,
        makeRecycleBox,
        makeUmbrellaStand;
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'petals.dart';
import 'sign_atlas.dart';

const _y = .513;
const _asphalt = Mat(0x5c6075, tint: 0x5b5677, bands: '3');
const _asphaltWorn = Mat(0x858092, tint: 0x5b5677, bands: '3');
const _sidewalk = Mat(0xc8c4cd, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xb8b3c0, tint: 0x6a6288, bands: '3');
const _concreteDark = Mat(0x96909f, tint: 0x655d84, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _shutter = Mat(0x6e6a7a, tint: 0x4b4560, bands: '3');
const _drain = Mat(0x6d687a, tint: 0x5d5878, bands: '3');
const _roof = Mat(0x4f6b70, tint: 0x514b70, bands: '3');
const _wood = Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');
const _glass = Mat(0x53627a, unlit: true, noOutline: true);
const _warm = Mat(0xffe2a3, unlit: true, noOutline: true);
const _white = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3');
const _line = Mat(0xf8f5ed, unlit: true, noOutline: true);
const _yellow = Mat(0xf4c033, unlit: true, noOutline: true);
const _greenAwning = Mat(0x3f7f60, tint: 0x4e6570, bands: '3');

int _shadeColor(int color, double factor) {
  final r = (((color >> 16) & 0xff) * factor).round();
  final g = (((color >> 8) & 0xff) * factor).round();
  final b = ((color & 0xff) * factor).round();
  return (r << 16) | (g << 8) | b;
}

void _box(List<Part> p, double w, double h, double d, Mat m, double x, double y,
    double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  p.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), m));
}

void _cyl(List<Part> p, double r, double h, int n, Mat m, double x, double y,
    double z) {
  p.add(Part(cylGeometry(r, r, h, n), trs(x, y, z), m));
}

List<Tri> _projectRoadShadow(List<Tri> caster) {
  const planeY = _y + .026;
  const shadow = Mat(0x5b6183, unlit: true, noOutline: true);

  // SUN_LOCAL=(-52,62,56): light travels toward (-x,+y,+z), so a point's
  // ground projection advances in +x and -z. Ratios avoid normalising first.
  project(v) {
    final p = v.clone();
    final h = p.y - planeY;
    p
      ..x += 52 / 62 * h
      ..y = planeY
      ..z -= 56 / 62 * h;
    return p;
  }

  final out = <Tri>[];
  for (final tri in caster) {
    if (math.max(tri.a.y, math.max(tri.b.y, tri.c.y)) < _y + 1.0) continue;
    final a = project(tri.a);
    final b = project(tri.b);
    final c = project(tri.c);
    final cx = (a.x + b.x + c.x) / 3;
    final cz = (a.z + b.z + c.z) / 3;
    // The rectangular approach is the only receiver visible from this camera.
    if (cx < 49.35 || cx > 65.65 || cz < 49.65 || cz > 54.75) continue;
    out.add(Tri(a, b, c, tri.normal, shadow));
  }
  return out;
}

List<Tri> _shop({
  required double x,
  required double z,
  required double w,
  required double d,
  required int seed,
  required bool green,
  double h1 = 3.05,
  double shutter = 0,
}) {
  final p = <Part>[];
  final rng = RngKit(seed);
  final wallColor = green ? 0xdedee6 : 0xf2e7d3;
  final wall = Mat(_shadeColor(wallColor, .55), tint: 0x5c5680, bands: '3');
  final recess = green ? .80 : .85;
  final openW = green ? 2.30 : 2.50;
  final front = d / 2;

  // Source shops.js volume: the body stops behind a real recessed frontage,
  // with piers and a header completing the street face.
  _box(p, w, h1, d - recess, wall, 0, h1 / 2, -recess / 2);
  _box(p, w + .16, .40, d + .16,
      const Mat(0x8b8496, tint: 0x5c5680, bands: '3'), 0, .20, 0);
  final pierW = (w - openW) / 2;
  for (final s in [-1.0, 1.0]) {
    _box(p, pierW, h1, recess, wall, s * (w - pierW) / 2, h1 / 2,
        front - recess / 2);
    _box(p, pierW + .04, .62, .06, _white, s * (w - pierW) / 2, .31,
        front + .02);
  }
  final headerH = h1 - 2.55;
  _box(
      p, openW, headerH, recess, wall, 0, h1 - headerH / 2, front - recess / 2);
  _box(p, openW, .10, recess, const Mat(0x8b8496, tint: 0x5c5680, bands: '3'),
      0, 2.50, front - recess / 2);
  _box(p, openW, .10, recess + .10, _white, 0, .05, front - recess / 2 + .05);

  // Dark painted interior, glazing and the exact mullion cadence.
  _box(
      p,
      openW - .10,
      2.20,
      .035,
      const Mat(0x8b8598, unlit: true, noOutline: true),
      0,
      1.35,
      front - recess + .03);
  _box(p, openW, 2.30, .04, _glass, 0, 1.35, front - .07);
  final panes = math.max(2, (openW / 1.3).round());
  for (var i = 0; i <= panes; i++) {
    _box(p, .08, 2.35, .10, _metal, -openW / 2 + openW * i / panes, 1.35,
        front - .07);
  }
  _box(p, openW + .10, .10, .14, _metal, 0, 2.50, front - .07);
  _box(p, openW + .10, .14, .16, _metal, 0, .20, front - .07);

  // 雑貨 まるみ is between shifts: its source shutter hangs 22% closed.
  // Keep the curtain and both rails at the exact shops.js dimensions.
  if (shutter > 0) {
    final shutterH = 2.55 * shutter;
    _box(p, openW - .10, shutterH, .06, _shutter, 0, 2.55 - shutterH / 2,
        front - .16);
    _box(p, openW + .14, .28, .20, _metalDark, 0, 2.66, front - .16);
    _box(p, openW, .10, .10, _metalDark, 0, 2.55 - shutterH, front - .16);
  }

  // Flat roof and ink-catching parapet.
  _box(p, w + .30, .20, d + .30, _roof, 0, h1 + .10, -.20);
  for (final s in [-1.0, 1.0]) {
    _box(p, w + .30, .34, .14, _roof, 0, h1 + .37, -.20 + s * (d / 2 + .14));
    _box(p, .14, .34, d + .30, _roof, s * (w / 2 + .14), h1 + .37, -.20);
  }

  // The fascia is above the roof in the source, not across the shop window.
  _box(p, w - .20, .72, .12, _white, 0, h1 + .44, front + .02);
  _box(p, w - .14, .10, .20, _metal, 0, h1 + .86, front + .02);

  // Sloped 1.5 m awning with alternating source stripes and its front valance.
  const out = 1.50, drop = .40;
  final awningY = h1 - .16;
  final tilt = math.atan2(drop, out);
  final stripeCount = math.max(6, (w / .42).round());
  final stripeW = w / stripeCount;
  final awningColor =
      green ? _greenAwning : const Mat(0xf0dfbf, tint: 0x6f5680, bands: '3');
  for (var i = 0; i < stripeCount; i++) {
    _box(p, stripeW, .07, out, i.isEven ? awningColor : _white,
        -w / 2 + stripeW * (i + .5), awningY - drop / 2, front + out / 2, tilt);
  }
  final edgeZ = front + out * math.cos(tilt);
  final edgeY = awningY - out * math.sin(tilt);
  _box(p, w, .30, .07, awningColor, 0, edgeY - .13, edgeZ - .03);
  // Ten-sided discs sit with their centres on the valance's lower edge, so
  // only their lower halves show as the source awning's scalloped fringe.
  final scallops = (w / .5).round();
  for (var i = 0; i < scallops; i++) {
    p.add(Part(
        cylGeometry(.14, .14, .025, 10),
        trs(-w / 2 + w * (i + .5) / scallops, edgeY - .28, edgeZ - .01,
            math.pi / 2),
        awningColor));
  }
  for (final side in [-1.0, 1.0]) {
    _box(p, .06, .06, out, _metalDark, side * (w / 2 - .3),
        awningY - .05 - drop / 2, front + out / 2, tilt);
  }

  // Door paper and tenant accents remain visible under the awning.
  _box(p, .55, 1.70, .04, _white, -openW / 2 + .34, 1.22, front - .035);
  _box(p, .42, .15, .035, _warm, -openW / 2 + .34, 1.62, front - .01);
  for (var i = 0; i < 3; i++) {
    _box(p, .24, .08, .035, _warm, -.32 + i * .32 + rng.range(-.02, .02), 2.12,
        front + .01);
  }
  final local = bake(p);
  appendSignAtlasPlane(
      local, green ? shopFasciaZakkaRegion : shopFasciaBentoRegion,
      width: w - .20, height: .72, matrix: trs(0, h1 + .44, front + .081));
  final world = trs(x, _y, z);
  return [
    for (final t in local)
      Tri(world.transformed3(t.a), world.transformed3(t.b),
          world.transformed3(t.c), t.normal, t.mat,
          uvA: t.uvA, uvB: t.uvB, uvC: t.uvC),
  ];
}

List<Tri> _walkup(double x, double z, double w, double d, int floors, int units,
    int wallColor) {
  final p = <Part>[];
  const fh = 2.68;
  final height = floors * fh;
  final wall = Mat(_shadeColor(wallColor, .50), tint: 0x5c5680, bands: '3');
  _box(p, w, height, d, wall, 0, height / 2, 0);
  _box(p, w + .3, .16, d + .35, _roof, 0, height + .08, 0);
  for (var floor = 0; floor < floors; floor++) {
    final gy = floor * fh + .28;
    _box(p, w + .15, .11, 1.05, _concreteMid, 0, gy, -d / 2 - .35);
    _box(p, w + .2, .08, .08, _metalDark, 0, gy + 1.02, -d / 2 - .83);
    for (var i = 0; i <= units * 2; i++) {
      _box(p, .055, .95, .055, _metalDark, -w / 2 + w * i / (units * 2),
          gy + .56, -d / 2 - .83);
    }
    for (var i = 0; i < units; i++) {
      final dx = -w / 2 + w * (i + .5) / units;
      _box(p, .72, 1.92, .07, _wood, dx, floor * fh + 1.2, -d / 2 - .04);
      _box(p, .42, .55, .04, _warm, dx, floor * fh + 1.52, -d / 2 - .09);
    }
  }
  for (var i = 0; i < floors * 11; i++) {
    final t = i / (floors * 11);
    _box(p, .95, .12, .35, _concreteMid, w / 2 + .55,
        .12 + t * (height - .45), -d / 2 + .2 + t * 2.3);
  }
  final world = trs(x, _y, z);
  return [
    for (final t in bake(p))
      Tri(world.transformed3(t.a), world.transformed3(t.b),
          world.transformed3(t.c), t.normal, t.mat,
          uvA: t.uvA, uvB: t.uvB, uvC: t.uvC)
  ];
}

List<Tri> _shelter() {
  final p = <Part>[];
  const x = 65.95, z = 58.45;
  _box(p, 2.82, 1.42, .08, _concreteMid, x, _y + .82, z + .66);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(p, .09, 2.25, .09, _metalDark, x + sx * 1.37, _y + 1.23,
          z + sz * .63);
    }
  }
  _box(p, 3.16, .09, 1.76, _roof, x, _y + 2.39, z, -.13);
  _box(p, 1.55, .12, .45, _wood, x, _y + .58, z - .15);
  for (final sx in [-1.0, 1.0]) {
    _box(p, .1, .58, .1, _metalDark, x + sx * .65, _y + .3, z - .15);
  }
  return bake(p);
}

List<Tri> _cornerNode() {
  final p = <Part>[];
  const py = _y;

  // Recycling cage beside the vending machine.
  _cyl(p, .24, .86, 10, const Mat(0x168588, tint: 0x5c5680, bands: '3'), 62.3,
      py + .43, 48.15);
  _cyl(p, .26, .06, 10, _metalDark, 62.3, py + .89, 48.15);
  for (final dx in [-.10, .10]) {
    _cyl(p, .08, .03, 8, const Mat(0x2f3140, bands: '2'), 62.3 + dx, py + .92,
        48.15);
  }
  _box(p, .30, .11, .02, _white, 62.3, py + .62, 48.385);

  // Source notice board, including its two posts, cork field and rain hood.
  final boardMx = trs(60.95, py, 47.15, 0, .1);
  void boardPart(ThreeGeom geo, Matrix4 mx, Mat mat) {
    p.add(Part(geo, boardMx * mx, mat));
  }

  const boardWood = Mat(0x8a6f52, tint: 0x5c5680, bands: '3');
  for (final s in [-1.0, 1.0]) {
    boardPart(boxGeometry(.11, 1.97, .11), trs(s * .7, .985), boardWood);
  }
  boardPart(boxGeometry(1.6, 1.05, .09), trs(0, 1.345), boardWood);
  boardPart(boxGeometry(1.70, .09, .14), trs(0, 1.91), boardWood);
  boardPart(boxGeometry(1.84, .06, .34), trs(0, 2.03, .10, -.2), _roof);
  for (final sheet in const <(double, double, double, double)>[
    (-.40, 1.365, .40, .54),
    (.08, 1.325, .40, .54),
    (.56, 1.345, .42, .32),
  ]) {
    boardPart(boxGeometry(sheet.$3, sheet.$4, .018),
        trs(sheet.$1, sheet.$2, .056), _white);
  }

  // Timber bench rotated toward the street.
  final benchMx = trs(63.55, py, 48.30, 0, 2.85);
  for (var i = 0; i < 3; i++) {
    p.add(Part(boxGeometry(1.5, .05, .13),
        benchMx * trs(0, .44, -.16 + i * .16), _wood));
  }
  for (var i = 0; i < 2; i++) {
    p.add(Part(boxGeometry(1.5, .13, .05),
        benchMx * trs(0, .66 + i * .17, -.22), _wood));
  }
  for (final s in [-1.0, 1.0]) {
    p.add(Part(boxGeometry(.07, .52, .07),
        benchMx * trs(s * .60, .66, -.24, .12), _metalDark));
    p.add(Part(boxGeometry(.08, .44, .42), benchMx * trs(s * .60, .22, -.04),
        _metalDark));
  }

  // The small three-plant flower bed behind the bench.
  _box(p, 1.5, .16, .8, const Mat(0x8f7a62, tint: 0x615a80, bands: '3'), 62.75,
      py + .08, 47.05);
  for (final s in [-1.0, 1.0]) {
    _box(p, 1.6, .22, .09, _wood, 62.75, py + .11, 47.05 + s * .4);
    _box(p, .09, .22, .9, _wood, 62.75 + s * .75, py + .11, 47.05);
  }
  final rng = RngKit(9781);
  const leafMats = [
    Mat(0x5aa578, tint: 0x5b6f8c, bands: '3'),
    Mat(0x3f7f60, tint: 0x5b6f8c, bands: '3'),
    Mat(0x84bd97, tint: 0x5b6f8c, bands: '3'),
  ];
  for (var i = 0; i < 3; i++) {
    final r = rng.range(.09, .16);
    final x = 62.75 + rng.range(-.495, .495);
    final z = 47.05 + rng.range(-.36, .36);
    p.add(Part(
        icosahedronGeometry(1, 0),
        trs(x, py + .18 + r * .7, z, rng.range(0, 3), rng.range(0, 3),
            rng.range(0, 3), r, r * .8, r),
        leafMats[i]));
  }

  // Concrete tree pit beneath the already-present corner cherry.
  _box(p, 1.05, .04, 1.05, _concreteDark, 64.30, py + .021, 47.10);
  return bake(p);
}

List<Tri> buildRokuchome({
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

  final ground = <Part>[];
  // Main bus street, turning bulb, connector and north lane.
  _box(ground, 16.2, .16, 5.0, _asphalt, 57.5, _y - .08, 52.2);
  _cyl(ground, 6.2, .16, 48, _asphalt, 70.6, _y - .08, 52.2);
  _box(ground, 3.5, .12, 10.0, _asphaltWorn, 51.15, _y - .06, 59.7);
  _box(ground, 3.2, .12, 3.0, _asphaltWorn, 51.0, _y - .06, 48.35);
  // Road edge and dashed center line.
  for (final z in [50.25, 54.15]) {
    _box(ground, 14.2, .025, .1, _line, 57.1, _y + .015, z);
  }
  for (var i = 0; i < 7; i++) {
    _box(ground, 1.0, .025, .11, _line, 51.8 + i * 1.9, _y + .018, 52.2);
  }
  for (final x in [55.0, 59.8, 63.4]) {
    _box(ground, .62, .05, .42, _drain, x, _y + .005, 49.92);
  }
  for (final x in [53.6, 58.2, 62.8]) {
    _box(ground, .62, .05, .42, _drain, x, _y + .005, 54.48);
  }
  for (final spec in const [(56.2, 52.2), (67.6, 50.2), (70.6, 56.2)]) {
    _cyl(ground, .31, .05, 12, _drain, spec.$1, _y + .01, spec.$2);
  }
  for (final spec in const [
    (53.8, 51.2, 2.2, 1.5),
    (61.2, 53.6, 1.8, 1.2),
    (69.4, 49.4, 2.4, 1.9),
  ]) {
    _box(ground, spec.$3, .02, spec.$4, _asphaltWorn, spec.$1, _y + .014,
        spec.$2);
  }
  // No-parking kerb line along the two shopfronts (kerbLine in the source).
  _box(ground, 4.2, .02, .11, _yellow, 55.3, _y + .034, 50.0);
  // Waiting island and the bus's yellow stopping box.
  _box(ground, 4.4, .11, 2.4, _sidewalk, 65.8, _y + .055, 58.1);
  for (final dz in [-1.4, 1.4]) {
    _box(ground, 6.6, .025, .12, _yellow, 69.2, _y + .018, 54.6 + dz);
  }
  for (final dx in [-3.3, 3.3]) {
    _box(ground, .12, .025, 2.8, _yellow, 69.2 + dx, _y + .018, 54.6);
  }
  // North parking forecourt and retaining wall.
  _box(ground, 7.6, .09, 4.2, const Mat(0xb8b09e, bands: '3'), 57.4, _y - .045,
      57.06);
  _box(ground, 30, 1.15, .3, _concreteMid, 64.2, _y + .575, 67.0);
  for (var i = 0; i < 10; i++) {
    _box(ground, .06, 1.0, .06, _metal, 50.1 + i * 3.15, _y + 1.65, 66.86);
  }
  _box(ground, 30.0, .07, .07, _metal, 64.2, _y + 2.15, 66.86);
  add(bake(ground), casts: false);

  add(_shop(
      x: 54.85,
      z: 47.45,
      w: 3.3,
      d: 3.0,
      seed: 9765,
      green: true,
      h1: 2.92,
      shutter: .22));
  add(_shop(x: 58.5, z: 47.0, w: 3.4, d: 3.4, seed: 9761, green: false));
  final shopCloths = <Part>[];

  // Exact source Canvas2D お弁当 noren, 0.16 m proud of the shop header.
  final mappedCloths = <Tri>[];
  appendSignAtlasPlane(mappedCloths, bentoNorenRegion,
      width: 2.10,
      height: .62,
      // The source places the rail at y=2.26 and offsets the cloth downward
      // by half its height from that pivot.
      matrix: trs(58.50, _y + 2.26 - .31, 48.879));
  _box(shopCloths, 2.24, .05, .05, _metalDark, 58.50, _y + 2.28, 48.86);

  // Exact source flags: the Zakka cloth hangs below a top pivot, while the
  // freestanding bento flag is offset from its pole and yawed locally.
  appendSignAtlasPlane(mappedCloths, shopFlag1Region,
      width: .42, height: .95, matrix: trs(53.55, _y + 2.50 - .475, 49.13));
  _box(shopCloths, .56, .05, .05, _metalDark, 53.55, _y + 2.52, 49.13);
  _cyl(shopCloths, .022, 1.90, 5, _metal, 57.05, _y + .95, 48.86);
  _cyl(shopCloths, .14, .10, 10, _concreteMid, 57.05, _y + .05, 48.86);
  appendSignAtlasPlane(mappedCloths, shopFlag0Region,
      width: .38,
      height: 1.0,
      matrix: trs(57.05, _y, 48.86) * trs(.20, 1.28, .02, 0, .12));
  add(bake(shopCloths));
  add(mappedCloths);
  add(_walkup(57.4, 63.6, 6.8, 4.4, 3, 3, 0xdedee6));
  add(_walkup(65.8, 63.3, 5.8, 4.6, 2, 2, 0xd6e3ee));
  add(_walkup(74.4, 62.6, 7.8, 5.2, 2, 3, 0xf2e7d3));
  add(makeHouse(const HouseOpts(
      x: 65.9,
      z: 43.4,
      y: _y,
      w: 4.2,
      d: 4.6,
      floors: 2,
      face: 'z+',
      seed: 9771,
      wall: 3,
      roof: 1,
      roofKind: 'gable')));
  add(_shelter());

  add(makeVehicle(
      kind: 'minibus', color: CAR.cream, x: 69.2, y: _y, z: 54.6, ry: math.pi));
  add(makeVehicle(
      kind: 'kei',
      color: CAR.white,
      x: 55.0,
      y: _y,
      z: 56.75,
      ry: -math.pi / 2));
  add(makeKeiTruck(
      color: CAR.mint,
      x: 59.8,
      y: _y,
      z: 56.79,
      ry: -math.pi / 2,
      load: 'empty'));
  add(makeVendingMachine(
      variant: 2, seed: 97, x: 61.3, y: _y, z: 48.3, ry: .18));
  add(_cornerNode());
  final cornerBollards = <Part>[];
  for (var i = 0; i < 4; i++) {
    final x = 60.7 + (64.5 - 60.7) * i / 3;
    _cyl(cornerBollards, .055, .78, 8, _metal, x, _y + .39, 49.09);
    _cyl(cornerBollards, .06, .12, 8,
        const Mat(0xe0453f, tint: 0x7a4060, bands: '3'), x, _y + .70, 49.09);
  }
  add(bake(cornerBollards));
  add(makeBicycle(
      x: 56.60,
      y: _y,
      z: 49.05,
      ry: math.pi / 2 + .06,
      lean: .07,
      color: 0x3f6f9c));
  add(makeCrates(x: 56.25, y: _y, z: 49.22, n: 3, seed: 9766, ry: .1));
  add(makeMilkCrate(x: 59.95, y: _y, z: 48.90, n: 2, ry: .2));
  add(makeRecycleBox(x: 60.35, y: _y, z: 46.20, ry: math.pi / 2));
  add(makeUmbrellaStand(x: 53.60, y: _y, z: 49.20, n: 4, seed: 9767));
  add(makeBroom(x: 53.32, y: _y, z: 49.05, ry: .3, tilt: .2));

  // Three short tangential runs protect the raised outer rim of the turning
  // bulb. They project as the continuous white rail that closes the street
  // behind the waiting bus in the reference view.
  const railRadius = 6.64;
  for (final angle in [-.5, 0.0, .5]) {
    add(makeGuardrail(
      x: 70.6 + railRadius * math.cos(angle),
      y: _y,
      z: 52.2 + railRadius * math.sin(angle),
      ry: -(math.pi / 2 + angle),
      len: 3.3,
    ));
  }

  // Frangible sight-line marker and the two cones kept at the north throat.
  final delineator = <Part>[];
  final delineatorMx = trs(64.6264, _y, 55.25, 0, 0, -.04);
  delineator.add(Part(
      cylGeometry(.032, .036, .80, 8),
      delineatorMx * trs(0, .40),
      const Mat(0xf0eee8, tint: 0x7d74a0, bands: '2')));
  delineator.add(Part(cylGeometry(.075, .095, .06, 10),
      delineatorMx * trs(0, .03), _metalDark));
  for (final y in [.70, .54]) {
    delineator.add(Part(
        cylGeometry(.039, .039, .06, 8),
        delineatorMx * trs(0, y),
        const Mat(0xef8a3c, tint: 0x8f6050, bands: '2')));
  }
  add(bake(delineator));
  add(makeCone(x: 74.9, y: _y, z: 55.9, ry: .3));
  add(makeCone(x: 75.3, y: _y, z: 54.6, ry: -.5, tilt: .05));

  // Exact source turnaround and no-parking plates at the throat.
  final signs = <Part>[];
  const signX = 64.20, signZ = 55.50, signRy = -1.9707963267948966;
  final signMx = trs(signX, _y, signZ, 0, signRy);
  signs.add(
      Part(cylGeometry(.045, .045, 2.30, 8), signMx * trs(0, 1.15), _metal));
  final mappedSigns = bake(signs);
  appendSignAtlasPlane(mappedSigns, turnaroundWarningRegion,
      width: .44, height: .72, matrix: signMx * trs(0, 1.78, .05));
  appendSignAtlasPlane(mappedSigns, noParkingRegion,
      width: .44, height: .44, matrix: signMx * trs(0, 1.22, .05));
  add(mappedSigns);

  for (final spec in const [
    (53.1, 55.3, 8.4, 9761, true, -1, math.pi),
    (61.3, 55.2, 8.2, 9762, false, -1, math.pi),
    (63.2, 59.6, 8.6, 9763, true, 1, -math.pi / 2),
    (49.75, 57.4, 8.2, 9764, false, 1, math.pi / 2),
    (49.75, 63.4, 8.0, 9765, true, 1, math.pi / 2),
  ]) {
    add(makePoleLite(PoleOpts(
        x: spec.$1,
        y: _y,
        z: spec.$2,
        h: spec.$3,
        seed: spec.$4,
        lamp: spec.$5,
        armDir: spec.$6,
        ry: spec.$7)));
  }

  final cherries = buildSakura(const [
    SakuraSpot(
        x: 64.3,
        z: 47.1,
        y: _y,
        scale: 1.1,
        seed: 9771,
        lean: .11,
        leanDir: 3.9),
    SakuraSpot(
        x: 50.3,
        z: 56.4,
        y: _y,
        scale: 1.04,
        seed: 9772,
        lean: .09,
        leanDir: 1.4),
    SakuraSpot(
        x: 78.0,
        z: 56.1,
        y: _y,
        scale: 1.02,
        seed: 9773,
        lean: .08,
        leanDir: 2.7),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  add(cherries);
  if (includeProjectedRoadShadow) {
    scene.addAll(_projectRoadShadow(buildSakura(const [
      SakuraSpot(
          x: 50.3,
          z: 56.4,
          y: _y,
          scale: 1.04,
          seed: 9772,
          lean: .09,
          leanDir: 1.4),
    ])));
  }
  final grove = buildGrove(const [
    GroveSpot(x: 51.8, z: 68.6, y: 1.0, scale: 1.55, seed: 9801, spread: 1.15),
    GroveSpot(x: 57.0, z: 69.8, y: 1.3, scale: 1.7, seed: 9802, spread: 1.25),
    GroveSpot(x: 62.6, z: 69.0, y: 1.1, scale: 1.5, seed: 9803, spread: 1.1),
    GroveSpot(x: 68.0, z: 70.2, y: 1.4, scale: 1.65, seed: 9804, spread: 1.2),
    GroveSpot(x: 73.6, z: 68.8, y: 1.0, scale: 1.45, seed: 9805, spread: 1.1),
    GroveSpot(x: 78.8, z: 70.0, y: 1.3, scale: 1.6, seed: 9806, spread: 1.2),
  ]);
  add(grove);
  add(buildShrubs(const [
    ShrubSpot(
        x: 46.3, z: 58.6, y: _y, r: .42, count: 3, spread: 1.0, seed: 9716),
    ShrubSpot(
        x: 53.4, z: 66.5, y: _y, r: .42, count: 3, spread: 1.1, seed: 9736),
    ShrubSpot(
        x: 55.2, z: 44.4, y: _y, r: .46, count: 3, spread: 1.2, seed: 9779),
    ShrubSpot(
        x: 62.2, z: 43.8, y: _y, r: .44, count: 3, spread: 1.1, seed: 9780),
    ShrubSpot(
        x: 54.4, z: 68.0, y: .9, r: .50, count: 4, spread: 1.5, seed: 9811),
    ShrubSpot(
        x: 60.2, z: 68.4, y: 1.0, r: .50, count: 4, spread: 1.5, seed: 9812),
    ShrubSpot(
        x: 65.8, z: 67.8, y: .9, r: .50, count: 4, spread: 1.5, seed: 9813),
    ShrubSpot(
        x: 71.4, z: 68.2, y: 1.0, r: .50, count: 4, spread: 1.5, seed: 9814),
    ShrubSpot(
        x: 76.6, z: 68.0, y: .9, r: .50, count: 4, spread: 1.5, seed: 9815),
  ]));
  // The reference hills module returns its planting separately from the terrain
  // mesh. Recreate the range edge that closes the turnaround view until that
  // world-wide planting pass is ported.
  add(buildGrove(const [
    GroveSpot(x: 78.0, z: 48.5, y: .72, scale: .78, seed: 9817, spread: 1.10),
    GroveSpot(x: 81.5, z: 52.0, y: .92, scale: .86, seed: 9818, spread: 1.12),
    GroveSpot(x: 84.8, z: 55.2, y: 1.18, scale: .80, seed: 9819, spread: 1.08),
    GroveSpot(x: 87.5, z: 50.4, y: 1.34, scale: .88, seed: 9820, spread: 1.10),
  ]));
  add(buildCedar(const [
    CedarSpot(x: 69.5, z: 44.2, y: .58, scale: .38, seed: 9821),
    CedarSpot(x: 73.0, z: 45.1, y: .64, scale: .42, seed: 9822),
    CedarSpot(x: 76.2, z: 43.8, y: .72, scale: .37, seed: 9823),
    CedarSpot(x: 79.4, z: 46.0, y: .82, scale: .40, seed: 9824),
  ]));
  scene.addAll(buildFallenPatches(const [
    PetalPatch(x: 67.0, z: 57.6, w: 4.0, d: 1.8, y: _y + .02, n: 30),
    PetalPatch(x: 63.4, z: 47.9, w: 3.0, d: 2.4, y: _y + .02, n: 40),
    PetalPatch(x: 49.8, z: 62.4, w: 1.2, d: 5.0, y: _y + .02, n: 40),
    PetalPatch(x: 55.0, z: 57.76, w: 2.2, d: 2.4, y: _y + .02, n: 26),
    PetalPatch(x: 56.9, z: 60.35, w: 7.6, d: 1.7, y: _y + .02, n: 34),
    PetalPatch(x: 74.4, z: 59.4, w: 7.8, d: 1.3, y: _y + .02, n: 40),
    PetalPatch(x: 57.2, z: 49.1, w: 6.2, d: .9, y: _y + .02, n: 26),
    PetalPatch(x: 65.9, z: 46.6, w: 3.4, d: 1.6, y: _y + .02, n: 24),
  ], skip: 11106));
  return scene;
}
