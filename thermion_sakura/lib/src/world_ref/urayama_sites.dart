/// Authored rooms along the 裏山 trail network.
///
/// Completes the site pass from `urayama.js`: the viewing deck, wayside stone
/// hokora, main and crest glades, rest platform, gully bridges, benches, and
/// fingerposts. The trail ribbons themselves live in `urayama.dart`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillSurfaceY;
import 'make_sakura.dart';
import 'make_trees_other.dart';

const _pathEdge = Mat(0x8f887d, tint: 0x6f6790, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _stone = Mat(0xb4aeb6, tint: 0x6f6790, bands: '3');
const _stoneDark = Mat(0x87818b, tint: 0x655d84, bands: '3');
const _concrete = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _timberPale = Mat(0xb89a72, tint: 0x665a79, bands: '3');
const _logTop = Mat(0xc2a47b, tint: 0x746480, bands: '3');
const _torii = Mat(0xb84b3f, tint: 0x704d70, bands: '3');
const _inside = Mat(0x2e2b38, unlit: true, noOutline: true);

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

void _bench(List<Part> parts, double x, double z, double yaw,
    [double length = 1.7, double? y]) {
  y ??= hillSurfaceY(x, z);
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(length, .08, .42), q * trs(0, .45, 0), _timber))
    ..add(Part(
        boxGeometry(length, .08, .12), q * trs(0, .83, -.28, -.12), _timber));
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(.10, .45, .10),
        q * trs(side * (length / 2 - .22), .23, 0), _timberDark));
  }
}

void _fingerpost(List<Part> parts, double x, double z, double yaw) {
  final y = hillSurfaceY(x, z);
  _box(parts, .11, 2.0, .11, _timberDark, x, y + 1, z);
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(1.25, .24, .08), q * trs(.42, 1.55, 0), _timber))
    ..add(Part(boxGeometry(.75, .20, .075), q * trs(-.25, 1.25, 0), _timber));
}

void _gullyBridge(
    List<Part> parts, double x, double z, double yaw, double length) {
  final y = hillSurfaceY(x, z) + .10;
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  final boards = math.max(4, (length / .24).round());
  for (var k = 0; k < boards; k++) {
    parts.add(Part(boxGeometry(1.35, .065, length / boards * .85),
        q * trs(0, .04, -length / 2 + (k + .5) * length / boards), _timber));
  }
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(.11, .18, length + .3),
        q * trs(side * .52, -.08, 0), _timberDark));
  }
}

void _buildDeck(List<Part> parts) {
  const x = 34.5, z = -128.2, width = 5.4, depth = 4.6, height = 2.8;
  final ground = hillSurfaceY(x, z);
  final deckY = ground + height;
  for (var ix = -1; ix <= 1; ix++) {
    for (var iz = -1; iz <= 1; iz++) {
      final px = x + ix * (width / 2 - .35);
      final pz = z + iz * (depth / 2 - .35);
      final py = hillSurfaceY(px, pz);
      _box(parts, .60, .30, .60, _concrete, px, py + .08, pz);
      _box(parts, .20, deckY - py - .10, .20, _timberDark, px,
          (deckY + py + .10) / 2 - .05, pz);
    }
  }
  for (final side in [-1.0, 1.0]) {
    _box(parts, width + .2, .22, .16, _timberDark, x, deckY - .12,
        z + side * (depth / 2 - .1));
    _box(parts, .16, .22, depth + .2, _timberDark, x + side * (width / 2 - .08),
        deckY - .12, z);
  }
  final boards = (depth / .19).round();
  for (var k = 0; k < boards; k++) {
    _box(parts, width + .24, .055, .165, _timber, x, deckY + .03,
        z - depth / 2 + .1 + k * (depth - .2) / (boards - 1));
  }

  // Four-sided balustrade, with the south-east stair opening.
  void rail(double ax, double az, double bx, double bz,
      {double gap0 = -1, double gap1 = -1}) {
    final dx = bx - ax, dz = bz - az;
    final length = math.sqrt(dx * dx + dz * dz);
    final count = math.max(2, (length / 1.3).round());
    for (var k = 0; k <= count; k++) {
      final t = k / count;
      if (gap0 >= 0 && t > gap0 && t < gap1) continue;
      _box(parts, .11, 1.05, .11, _timber, ax + dx * t, deckY + .525,
          az + dz * t);
    }
    final segments = gap0 < 0 ? [(0.0, 1.0)] : [(0.0, gap0), (gap1, 1.0)];
    for (final segment in segments) {
      if (segment.$2 - segment.$1 < .02) continue;
      final a =
          Vector3(ax + dx * segment.$1, deckY + 1.0, az + dz * segment.$1);
      final b =
          Vector3(ax + dx * segment.$2, deckY + 1.0, az + dz * segment.$2);
      _member(parts, a, b, .045, _timber);
      _member(parts, Vector3(a.x, deckY + .53, a.z),
          Vector3(b.x, deckY + .53, b.z), .038, _timber);
    }
  }

  final x0 = x - width / 2, x1 = x + width / 2;
  final z0 = z - depth / 2, z1 = z + depth / 2;
  rail(x0, z1, x1, z1);
  rail(x0, z0, x1, z0, gap0: .55, gap1: .86);
  rail(x0, z0, x0, z1);
  rail(x1, z0, x1, z1);

  // Fifteen-tread south stair and its raked handrails.
  const stairCount = 15, rise = height / stairCount, run = .34;
  const stairX = x + .9;
  final topZ = z0 - .25;
  for (var k = 0; k < stairCount; k++) {
    final treadZ = topZ - (stairCount - 1 - k) * run;
    final treadY = ground + rise * (k + 1);
    _box(parts, 1.5, .06, run + .06, _timber, stairX, treadY, treadZ);
  }
  for (final side in [-1.0, 1.0]) {
    final a = Vector3(
        stairX + side * .80, ground + .95, topZ - (stairCount - 1) * run);
    final b = Vector3(stairX + side * .80, deckY + .95, topZ);
    _member(parts, a, b, .045, _timber);
  }
  _bench(parts, x - 1.4, z - 1.2, 0, 1.7, deckY + .06);
  _bench(parts, x + 1.5, z - 1.2, 0, 1.4, deckY + .06);
  // View panel on the west half of the north rail.
  _box(parts, 1.9, .90, .09, _timberPale, x - 1.2, deckY + .92,
      z + depth / 2 - .40, .42);
}

void _buildHokora(List<Part> parts) {
  const x = -38.5, z = -112.5;
  final base = hillSurfaceY(x + 1.6, z + .6);
  const platformY = .32;
  final y = base + platformY;
  _box(parts, 3.4, .08, 3.0, _gravel, x - .6, y - .04, z);
  // Three treads from the spur.
  for (var k = 0; k < 3; k++) {
    final h = .16 * (k + 1);
    _box(parts, .42, h, 1.6, _stone, x + 1.5 - (k + .5) * .42,
        base - .16 + h / 2, z + .4);
  }
  // 1.4 m vermilion torii.
  const toriiX = x + .5, toriiWidth = 1.15, toriiHeight = 1.5;
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(cylGeometry(.065, .078, toriiHeight, 8),
        trs(toriiX, y + toriiHeight / 2, z + side * toriiWidth / 2), _torii));
  }
  _box(parts, .13, .10, toriiWidth + .5, _torii, toriiX, y + toriiHeight - .28,
      z);
  _box(parts, .20, .11, toriiWidth + .72, _torii, toriiX, y + toriiHeight + .08,
      z);

  // Stone box, niche, stepped cap, and offering shelf.
  const shrineX = x - 1.35;
  _box(parts, 1.1, .42, 1.0, _stoneDark, shrineX, y + .21, z);
  _box(parts, .68, .72, .60, _stone, shrineX, y + .78, z);
  _box(parts, .16, .44, .30, _inside, shrineX + .28, y + .76, z);
  _box(parts, .86, .10, .78, _stone, shrineX, y + 1.19, z);
  parts.add(Part(icosahedronGeometry(.60, 0),
      trs(shrineX, y + 1.42, z, 0, math.pi / 4, 0, 1, .50, .85), _stoneDark));
  _box(parts, .66, .12, .40, _stone, shrineX + .72, y + .40, z);
  for (final side in [-1.0, 1.0]) {
    final lz = z + side * 1.05;
    _box(parts, .34, .14, .34, _stone, x + .4, y + .07, lz);
    parts.add(
        Part(cylGeometry(.075, .09, .42, 8), trs(x + .4, y + .35, lz), _stone));
    _box(parts, .25, .24, .25, _stone, x + .4, y + .75, lz);
    parts.add(Part(icosahedronGeometry(.28, 0),
        trs(x + .4, y + .98, lz, 0, math.pi / 4, 0, 1, .45, 1), _stoneDark));
  }
}

void _logSeat(List<Part> parts, double x, double y, double z) {
  parts
    ..add(Part(cylGeometry(.24, .26, .44, 9), trs(x, y + .22, z), _timberDark))
    ..add(Part(cylGeometry(.245, .245, .03, 9), trs(x, y + .45, z), _logTop));
}

void _buildGlades(List<Part> parts) {
  const x = -17.0, z = -127.0;
  final y = hillSurfaceY(x, z);
  _box(parts, 8, .06, 7, _pathEdge, x, y - .03, z);
  // Three-sided post-and-rail fence; north remains open to the spur.
  for (final run in const [
    (-21.0, -130.5, -13.0, -130.5),
    (-13.0, -130.5, -13.0, -123.5),
    (-21.0, -123.5, -17.6, -123.5),
  ]) {
    final a = Vector3(run.$1, hillSurfaceY(run.$1, run.$2) + .82, run.$2);
    final b = Vector3(run.$3, hillSurfaceY(run.$3, run.$4) + .82, run.$4);
    _member(parts, a, b, .045, _timberDark);
    final length = (b - a).length;
    final count = math.max(2, (length / 1.6).round());
    for (var k = 0; k <= count; k++) {
      final p = a + (b - a) * (k / count);
      _member(parts, Vector3(p.x, p.y - .82, p.z), p, .05, _timberDark);
    }
  }
  // Stone table and five log stools.
  const tableX = x + 1, tableZ = z + .4;
  parts.add(Part(
      cylGeometry(.78, .72, .16, 9), trs(tableX, y + .50, tableZ), _stone));
  parts.add(Part(
      cylGeometry(.28, .34, .44, 8), trs(tableX, y + .22, tableZ), _stoneDark));
  for (var k = 0; k < 5; k++) {
    final angle = k / 5 * math.pi * 2 + .6;
    final sx = tableX + math.cos(angle) * 1.7;
    final sz = tableZ + math.sin(angle) * 1.7;
    _logSeat(parts, sx, hillSurfaceY(sx, sz), sz);
  }
  _bench(parts, x - 2.8, z + 1.8, -.9, 1.8);

  // Crest clearing with its unused fire ring and log circle.
  const crestX = 8.0, crestZ = -138.4;
  final crestY = hillSurfaceY(crestX, crestZ);
  _box(parts, 5, .06, 4.4, _pathEdge, crestX, crestY - .03, crestZ);
  for (final offset in const [
    (-1.5, -.9),
    (-.5, -1.5),
    (1.4, -.6),
    (1, 1.2),
    (-1.2, 1.3),
  ]) {
    final sx = crestX + offset.$1, sz = crestZ + offset.$2;
    _logSeat(parts, sx, hillSurfaceY(sx, sz), sz);
  }
  const ringSegments = 14;
  for (var k = 0; k < ringSegments; k++) {
    final a0 = k / ringSegments * math.pi * 2;
    final a1 = (k + 1) / ringSegments * math.pi * 2;
    _member(
        parts,
        Vector3(crestX + math.cos(a0) * .55, crestY + .10,
            crestZ + math.sin(a0) * .55),
        Vector3(crestX + math.cos(a1) * .55, crestY + .10,
            crestZ + math.sin(a1) * .55),
        .11,
        _stoneDark);
  }
}

void _buildTrailFurniture(List<Part> parts) {
  for (final bench in const [
    (.4, -103.0, 3.0),
    (-27.8, -113.6, 1.2),
    (-3, -122.4, 3.0),
    (7.2, -126, 2.8),
    (-19.4, -134.6, 1.7),
  ]) {
    _bench(parts, bench.$1.toDouble(), bench.$2.toDouble(), bench.$3);
  }
  final restY = hillSurfaceY(-3, -122.4);
  _box(parts, 3.4, .07, 2.6, _pathEdge, -1.4, restY - .035, -120.6);
  _bench(parts, -.6, -119.8, .4, 1.6, restY);
  for (final sign in const [
    (-25.4, -111.6, .9),
    (-13.2, -119.2, 2.3),
    (23.8, -134.6, 3.0),
    (25.6, -136.4, 1.4),
    (12.6, -97.2, .2),
    (84.6, -95.4, -.8),
  ]) {
    _fingerpost(parts, sign.$1, sign.$2, sign.$3);
  }
  _gullyBridge(parts, -21, -108, .42, 3.4);
  _gullyBridge(parts, 11.4, -127.6, 1.15, 3.0);
}

List<Tri> buildUrayamaSites({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  _buildDeck(parts);
  _buildHokora(parts);
  _buildGlades(parts);
  _buildTrailFurniture(parts);
  final out = bake(parts);

  // Preserve each source record verbatim. These trees frame the deck, hokora,
  // and main glade; collapsing their distinct lean/spread values into one
  // approximate record changes every canopy face visible over the road.
  out.addAll(buildGrove([
    for (final spot in const [
      (27.1, -129.6, 1.50, 8501),
      (28.3, -133.2, 1.38, 8502),
      (41.7, -129.2, 1.44, 8503),
      (42.5, -133.8, 1.55, 8504),
    ])
      GroveSpot(
          x: spot.$1,
          z: spot.$2,
          y: hillSurfaceY(spot.$1, spot.$2) + .02,
          scale: spot.$3,
          seed: spot.$4,
          spread: 1.12,
          lean: .05,
          leanDir: (spot.$4 % 6).toDouble()),
    GroveSpot(
        x: -39.9,
        z: -110.4,
        y: hillSurfaceY(-39.9, -110.4),
        scale: 1.75,
        seed: 8601,
        spread: 1.2,
        lean: .04,
        leanDir: 1.4),
    for (final spot in const [
      (-22.6, -128.0, 1.60, 8631),
      (-11.2, -124.4, 1.50, 8632),
      (-18.0, -121.6, 1.66, 8633),
    ])
      GroveSpot(
          x: spot.$1,
          z: spot.$2,
          y: hillSurfaceY(spot.$1, spot.$2),
          scale: spot.$3,
          seed: spot.$4,
          spread: 1.15,
          lean: .04,
          leanDir: (spot.$4 % 6).toDouble()),
  ]));
  out.addAll(buildSakura([
    SakuraSpot(
        x: 31.1,
        z: -134.6,
        y: hillSurfaceY(31.1, -134.6) + .02,
        scale: 1.2,
        seed: 8511,
        lean: .11,
        leanDir: 2.4),
    SakuraSpot(
        x: -12.4,
        z: -131.2,
        y: hillSurfaceY(-12.4, -131.2),
        scale: 1.22,
        seed: 8641,
        lean: .10,
        leanDir: 4),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  return out;
}
