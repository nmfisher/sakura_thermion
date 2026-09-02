/// Native Dart composition of `kohan.js`, the ひばり湖 shore district.
///
/// The water, reeds, and principal pier live in `water.dart`; this module owns
/// the land-side rooms around them: park plaza and pavilion, boat station,
/// lakeside cafe, campground, bird hide, and 水神様.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillSurfaceY;
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart' show groundY, terrainDrop;

const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _stone = Mat(0xb4aeb6, tint: 0x6f6790, bands: '3');
const _stoneDark = Mat(0x87818b, tint: 0x655d84, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberPale = Mat(0xb89a72, tint: 0x665a79, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _roof = Mat(0x58627c, tint: 0x504b70, bands: '3');
const _roofBlue = Mat(0x657c91, tint: 0x535776, bands: '3');
const _wall = Mat(0xe7e0d4, tint: 0x7a7396, bands: '3');
const _glass = Mat(0x789aaa, unlit: true, noOutline: true);
const _inside = Mat(0x403a45, unlit: true, noOutline: true);
const _warm = Mat(0xffe4a6, unlit: true, noOutline: true);
const _orange = Mat(0xd88032, tint: 0x8f7050, bands: '3');
const _red = Mat(0xb94c4c, tint: 0x704d70, bands: '3');
const _blue = Mat(0x547a9b, tint: 0x555f80, bands: '3');
const _yellow = Mat(0xd3a934, tint: 0x846d77, bands: '3');
const _green = Mat(0x69885d, tint: 0x5b6f75, bands: '3');
const _rope = Mat(0xc1a16b, tint: 0x77647f, bands: '3');

double get _waterY => groundY(-88) + 3.40 - terrainDrop;

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _member(List<Part> parts, Vector3 a, Vector3 b, double radius, Mat mat) {
  final direction = b - a;
  if (direction.length < 1e-4) return;
  final rotation =
      quatFromUnitVectors(Vector3(0, 1, 0), direction.normalized());
  parts.add(Part(
      cylGeometry(radius, radius, 1, 7),
      composePRS(
          (a + b) * .5, rotation, Vector3(radius, direction.length, radius)),
      mat));
}

void _steps(List<Part> parts, double x, double z, double lowY, double highY,
    int count, double width,
    {bool alongX = true, double direction = 1}) {
  final rise = (highY - lowY) / count;
  const run = .42;
  for (var k = 0; k < count; k++) {
    final h = rise * (k + 1);
    final offset = direction * (k + .5) * run;
    _box(parts, alongX ? run : width, h, alongX ? width : run, _stone,
        alongX ? x + offset : x, lowY + h / 2, alongX ? z : z + offset);
  }
}

void _timberDeck(
    List<Part> parts, double x, double y, double z, double width, double depth,
    {bool boardsAlongX = true}) {
  final count = math.max(2, ((boardsAlongX ? depth : width) / .22).round());
  for (var k = 0; k < count; k++) {
    final t = (k + .5) / count - .5;
    _box(
        parts,
        boardsAlongX ? width : (boardsAlongX ? width : width / count) * .9,
        .055,
        boardsAlongX ? depth / count * .88 : depth,
        _timberPale,
        x + (boardsAlongX ? 0 : t * width),
        y + .03,
        z + (boardsAlongX ? t * depth : 0));
  }
  for (final side in [-1.0, 1.0]) {
    _box(
        parts,
        boardsAlongX ? width : .14,
        .18,
        boardsAlongX ? .14 : depth,
        _timberDark,
        x + (boardsAlongX ? 0 : side * (width / 2 - .25)),
        y - .10,
        z + (boardsAlongX ? side * (depth / 2 - .25) : 0));
  }
}

void _picnicTable(List<Part> parts, double x, double y, double z, double yaw) {
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(1.9, .08, .86), q * trs(0, .72, 0), _timber))
    ..add(Part(boxGeometry(1.9, .07, .32), q * trs(0, .44, -.72), _timber))
    ..add(Part(boxGeometry(1.9, .07, .32), q * trs(0, .44, .72), _timber));
  for (final sx in [-.78, .78]) {
    parts.add(
        Part(boxGeometry(.10, .72, 1.7), q * trs(sx, .36, 0), _timberDark));
  }
}

void _buildPark(List<Part> parts) {
  final upperY = hillSurfaceY(133.4, -76);
  final lowerY = hillSurfaceY(141, -78.4);
  _box(parts, 9, .08, 12, _concrete, 133.4, upperY - .04, -76);
  _box(parts, 5, .08, 9, _stone, 140, lowerY - .04, -78.4);
  _steps(parts, 138.1, -76, lowerY, upperY, 3, 4.2, direction: -1);

  // Raked pram ramp beside the steps, including its authored outer railing.
  // The collision-only eight-box staircase in Three.js is represented by the
  // visible solid here; it is the missing silhouette at the left of the pier.
  const rampX0 = 138.1, rampX1 = 137.4;
  const rampZ = -71.2;
  final rampRun = rampX1 - rampX0;
  final rampLength =
      math.sqrt(rampRun * rampRun + (lowerY - upperY) * (lowerY - upperY));
  _box(
      parts,
      rampLength + .2,
      .16,
      2.4,
      _concrete,
      (rampX0 + rampX1) / 2,
      (upperY + lowerY) / 2 - .04,
      rampZ,
      0,
      0,
      -math.atan2(lowerY - upperY, rampRun));

  const railZ = -69.9;
  final railBase = lowerY + .3;
  final railCount = math.max(2, (rampRun.abs() / 1.35).round());
  for (var k = 0; k <= railCount; k++) {
    final x = rampX0 + rampRun * k / railCount;
    _box(parts, .08, .9, .08, _metal, x, railBase + .45, railZ);
  }
  for (final h in [.45, .9]) {
    _box(parts, rampRun.abs(), .065, .065, _metal, (rampX0 + rampX1) / 2,
        railBase + h, railZ);
  }

  // 東屋, kept behind the fidelity camera at its surveyed position.
  const px = 132.0, pz = -70.6, width = 4.0, depth = 3.4, height = 2.35;
  final py = hillSurfaceY(px, pz);
  _box(parts, width + .5, .09, depth + .5, _stone, px, py - .045, pz);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(parts, .16, height, .16, _timberDark, px + sx * (width / 2 - .2),
          py + height / 2, pz + sz * (depth / 2 - .2));
      _box(parts, .32, .20, .32, _stoneDark, px + sx * (width / 2 - .2),
          py + .10, pz + sz * (depth / 2 - .2));
    }
  }
  for (final sz in [-1.0, 1.0]) {
    _box(parts, width - .24, .18, .13, _timberDark, px, py + height - .09,
        pz + sz * (depth / 2 - .2));
  }
  _box(parts, .13, .16, depth - .24, _timberDark, px, py + height - .26, pz);
  const roofHeight = .85;
  for (final sz in [-1.0, 1.0]) {
    _box(
        parts,
        width + .9,
        .10,
        depth / 2 + .6,
        _roofBlue,
        px,
        py + height + roofHeight / 2,
        pz + sz * (depth / 4 + .16),
        sz * -math.atan2(roofHeight, depth / 2 + .5));
  }
  _box(parts, width * .42, .14, .30, _roofBlue, px,
      py + height + roofHeight + .02, pz);

  // Fixed benches around three sides of the pavilion.
  _box(parts, width - 1.2, .07, .42, _timber, px, py + .44,
      pz - (depth / 2 - .55));
  for (final side in [-1.0, 1.0]) {
    _box(parts, .42, .07, depth - 1.2, _timber, px + side * (width / 2 - .5),
        py + .44, pz);
  }
  _picnicTable(parts, 135.6, hillSurfaceY(135.6, -83.4), -83.4, .3);
  _picnicTable(parts, 136.8, hillSurfaceY(136.8, -87.6), -87.6, -.2);
}

void _boat(List<Part> parts, double x, double z, double yaw, Mat color,
    [double yOffset = -.10]) {
  final y = _waterY + yOffset;
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(icosahedronGeometry(1, 1),
        q * trs(0, .16, 0, 0, 0, 0, 1.35, .28, .58), color))
    ..add(Part(icosahedronGeometry(1, 1),
        q * trs(0, .29, 0, 0, 0, 0, .92, .18, .38), _inside))
    ..add(Part(boxGeometry(1.45, .05, .08), q * trs(0, .40, 0), _timberPale));
}

void _buildBoatStation(List<Part> parts) {
  const siteX = 145.0, siteZ = -101.0;
  final apronY = hillSurfaceY(140, siteZ);
  _box(parts, 9, .07, 10, _gravel, siteX - 1.2, apronY - .035, siteZ);

  const shedX = 141.4, shedZ = -100.6;
  const length = 6.6, width = 4.8, height = 2.5, roofHeight = 1.0;
  _box(parts, length, height, .14, _timber, shedX, apronY + height / 2,
      shedZ - width / 2);
  _box(parts, length, height, .14, _timber, shedX, apronY + height / 2,
      shedZ + width / 2);
  _box(parts, .14, height, width, _timber, shedX - length / 2,
      apronY + height / 2, shedZ);
  _box(parts, .06, height - .2, width - .4, _inside, shedX + length / 2 - .2,
      apronY + (height - .2) / 2, shedZ);
  for (final side in [-1.0, 1.0]) {
    _box(
        parts,
        length + .7,
        .11,
        width / 2 + .5,
        _roof,
        shedX,
        apronY + height + roofHeight / 2,
        shedZ + side * (width / 4 + .14),
        side * -math.atan2(roofHeight, width / 2 + .4));
  }
  _box(parts, length + .8, .13, .26, _roof, shedX,
      apronY + height + roofHeight + .02, shedZ);

  // Oar rack and life-jacket rail on the working side.
  for (final side in [-1.0, 1.0]) {
    _box(parts, .10, 1.7, .10, _timberDark, 139, apronY + .85,
        siteZ - 1.2 + side * 1.1);
  }
  _box(parts, .09, .09, 2.3, _timberDark, 139, apronY + 1.5, siteZ - 1.2);
  for (var k = 0; k < 6; k++) {
    _member(
        parts,
        Vector3(139.1, apronY + .12, siteZ - 2.1 + k * .36),
        Vector3(139.42, apronY + 2.15, siteZ - 2.1 + k * .36),
        .028,
        _timberPale);
  }
  for (var k = 0; k < 5; k++) {
    _box(parts, .10, .52, .28, _orange, 139, apronY + 1.18,
        siteZ + 1.4 + k * .4);
  }

  // Floating dock and bank steps.
  final dockY = _waterY + .30;
  _timberDeck(parts, 149.8, dockY, siteZ, 7.2, 2.4);
  final stepCount = math.max(2, ((apronY - dockY) / .19).round());
  _steps(parts, 143.7, siteZ, dockY, apronY, stepCount, 2.2);
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(cylGeometry(.085, .10, .50, 8),
        trs(153.2, dockY + .28, siteZ + side), _timberDark));
  }
  _boat(parts, 150.6, siteZ - 3.2, -1.35, _wall);
  _boat(parts, 150.6, siteZ - 1.5, -1.40, _blue);
  _boat(parts, 150.6, siteZ + 1.6, -1.50, _red);
  _boat(parts, 150.6, siteZ + 3.3, -1.44, _yellow);
  _boat(parts, 144.4, siteZ + 4.2, .15, _green, .55);
}

void _buildCafe(List<Part> parts) {
  const x = 179.0, z = -145.2, width = 9.2, depth = 6.4, height = 3.5;
  final y = hillSurfaceY(x, z);
  _box(parts, width + 1.0, .12, 4.0, _timberPale, x, y + .02, z + 5.0);
  _box(parts, width, height, depth, _wall, x, y + height / 2, z);
  _box(parts, width - .8, 1.75, .08, _inside, x, y + 1.35, z + depth / 2 + .03);
  for (var k = 0; k < 5; k++) {
    _box(parts, 1.35, 1.45, .05, _glass, x - 3.4 + k * 1.7, y + 1.42,
        z + depth / 2 + .08);
  }
  _box(parts, 1.1, 2.15, .10, _timberDark, x + 3.45, y + 1.08,
      z + depth / 2 + .10);
  _box(parts, width + .8, .16, depth + .8, _roof, x, y + height + .08, z);
  _box(
      parts, 4.0, .50, .10, _timberPale, x - 1.0, y + 3.0, z + depth / 2 + .18);
  for (final tx in [x - 2.5, x, x + 2.5]) {
    _box(parts, 1.15, .07, .72, _timber, tx, y + .72, z + 5.0);
    _box(parts, .10, .70, .10, _timberDark, tx, y + .35, z + 5.0);
    parts.add(Part(icosahedronGeometry(.07, 0),
        trs(tx, y + .36, z + depth / 2 - .12), _warm));
  }
  // Four-space gravel car park behind the cafe.
  _box(parts, width + 2, .055, 5.6, _gravel, x, y - .02, z - 6.4);
  for (final px in [x - 3.6, x - 1.2, x + 1.2, x + 3.6]) {
    _box(parts, .09, .025, 4.6, _wall, px, y + .02, z - 6.4);
  }
}

void _buildCamp(List<Part> parts) {
  const cx = 206.0, cz = -150.0;
  final baseY = hillSurfaceY(cx, cz);
  _box(parts, 27, .05, 13, _gravel, cx, baseY - .025, cz);
  final tents = <(double, double, Mat)>[
    (197.5, -148.0, _yellow),
    (202.0, -152.0, _green),
    (206.5, -148.0, _orange),
    (211.0, -152.0, _blue),
    (215.0, -148.0, _red),
    (219.0, -152.0, _wall),
  ];
  for (final tent in tents) {
    final y = hillSurfaceY(tent.$1, tent.$2);
    for (final side in [-1.0, 1.0]) {
      _box(parts, 2.6, .06, 1.65, tent.$3, tent.$1, y + .78,
          tent.$2 + side * .55, side * -math.atan2(1.25, 1.65));
    }
    _box(parts, 2.7, .08, .12, _rope, tent.$1, y + 1.45, tent.$2);
  }
  _picnicTable(parts, 206, baseY, -156, .1);
}

void _buildHide(List<Part> parts) {
  const x = 216.0, z = -146.0, width = 6.0, depth = 3.2;
  final y = hillSurfaceY(x, z);
  final deckY = y + .65;
  _timberDeck(parts, x, deckY, z, width + 1.2, depth + 1.4);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(parts, .16, .75, .16, _timberDark, x + sx * (width / 2 - .3),
          y + .30, z + sz * (depth / 2 - .3));
    }
  }
  _box(parts, width, 2.0, .18, _timber, x, deckY + 1.0, z - depth / 2);
  _box(parts, width, .65, .18, _timber, x, deckY + 1.68, z + depth / 2);
  _box(parts, width, .55, .18, _timber, x, deckY + .28, z + depth / 2);
  _box(parts, width - .7, .65, .04, _inside, x, deckY + .98,
      z + depth / 2 + .11);
  _box(parts, width + .7, .14, depth + .8, _roof, x, deckY + 2.12, z, 0, 0,
      -.04);
  _steps(parts, x - width / 2 - .2, z, y, deckY, 3, 1.4, direction: 1);
}

void _buildSuijin(List<Part> parts) {
  const x = 252.8, z = -91.4;
  final y = hillSurfaceY(x, z);
  _box(parts, 4.4, .22, 4.0, _stone, x, y + .11, z);
  // Compact stone hokora with deep opening and cap stones.
  _box(parts, 1.55, 1.45, 1.25, _stone, x, y + .95, z);
  _box(parts, .70, .78, .08, _inside, x, y + .90, z + .665);
  for (final side in [-1.0, 1.0]) {
    _box(parts, 1.25, .18, 1.0, _stoneDark, x + side * .42, y + 1.78, z, 0, 0,
        side * .20);
  }
  _box(parts, 1.85, .18, 1.55, _stone, x, y + 1.93, z);
  // Two lanterns and the four treads down toward the water.
  for (final side in [-1.0, 1.0]) {
    final lx = x + side * 1.55;
    _box(parts, .22, .85, .22, _stoneDark, lx, y + .53, z + .8);
    _box(parts, .48, .26, .48, _stone, lx, y + 1.02, z + .8);
    _box(parts, .38, .14, .38, _stoneDark, lx, y + 1.24, z + .8);
  }
  _steps(parts, x + 2.8, z, _waterY + .10, y, 4, 1.5, direction: -1);
}

List<Tri> buildKohan({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  _buildPark(parts);
  _buildBoatStation(parts);
  _buildCafe(parts);
  _buildCamp(parts);
  _buildHide(parts);
  _buildSuijin(parts);
  final out = bake(parts);

  // Site-owned planting from the reference keeps the rooms tied into the rim.
  out.addAll(buildSakura([
    for (final spot in const [
      (141.6, -63.6, 1.24, 9764, 1.9),
      (140.6, -67.2, 1.18, 9768, 2.2),
      (140.2, -86.4, 1.26, 9786, 4.1),
      (141.4, -90.4, 1.20, 9790, 4.4),
      (142.4, -94.4, 1.16, 9794, 4.6),
      (141.0, -107.6, 1.24, 9911, 4.6),
      (142.6, -93.6, 1.20, 9912, 4.2),
      (182.8, -151.2, 1.18, 10111, 3.8),
      (210.0, -157.0, 1.16, 10211, 4.1),
      (256.2, -94.4, 1.18, 10431, 3.4),
    ])
      SakuraSpot(
          x: spot.$1,
          z: spot.$2,
          y: hillSurfaceY(spot.$1, spot.$2),
          scale: spot.$3,
          seed: spot.$4,
          lean: .13,
          leanDir: spot.$5),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  out.addAll(buildGrove([
    for (final spot in const [
      (128.4, -82.6, 1.50, 9878),
      (127.8, -74.2, 1.44, 9874),
      (128.8, -91.6, 1.55, 9881),
      (137.0, -96.0, 1.50, 9921),
      (186.0, -151.0, 1.45, 10121),
      (217.0, -156.0, 1.50, 10221),
      (249.6, -88.4, 1.60, 10421),
    ])
      GroveSpot(
          x: spot.$1,
          z: spot.$2,
          y: hillSurfaceY(spot.$1, spot.$2),
          scale: spot.$3,
          seed: spot.$4,
          spread: 1.12),
  ]));
  return out;
}
