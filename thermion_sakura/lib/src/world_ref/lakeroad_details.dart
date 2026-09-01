/// Structures and foot access belonging to 湖畔道路 and the reservoir dam.
///
/// The road surfaces and spillway are built in `water.dart`; this companion
/// supplies the source module's rail systems, lay-by, dam apparatus,
/// management yard, 見晴台 trail, and overlook platform.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillSurfaceY;
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';

const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _concreteDark = Mat(0xa7a2b0, tint: 0x655d84, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _white = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2');
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _roof = Mat(0x59617a, tint: 0x514b70, bands: '3');
const _shutter = Mat(0x6e6a7a, tint: 0x5c5680, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _path = Mat(0xa29a83, tint: 0x6a6288, bands: '3');
const _pathEdge = Mat(0x8f887d, tint: 0x6f6790, bands: '3');
const _rock = Mat(0xb4aeb6, tint: 0x6f6790, bands: '3');
const _inside = Mat(0x2b2833, unlit: true, noOutline: true);
const _red = Mat(0xe0453f, unlit: true);
const _sign = Mat(0xf8f3df, unlit: true);
const _signInk = Mat(0x3d5f78, unlit: true);

final _unitCylinder = cylGeometry(1, 1, 1, 7);

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _member(List<Part> parts, Vector3 a, Vector3 b, double radius, Mat mat) {
  final d = b - a;
  if (d.length < 1e-4) return;
  parts.add(Part(
      _unitCylinder,
      composePRS(
          (a + b) * .5,
          quatFromUnitVectors(Vector3(0, 1, 0), d.normalized()),
          Vector3(radius, d.length, radius)),
      mat));
}

void _groundRail(List<Part> parts, List<(double, double)> points,
    {double height = .9,
    double spacing = 2.2,
    Mat mat = _metal,
    double Function(double x, double z)? yAt}) {
  yAt ??= hillSurfaceY;
  final railPoints = <Vector3>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
    final n = math.max(1, (math.sqrt(dx * dx + dz * dz) / spacing).ceil());
    for (var k = 0; k < n; k++) {
      final t = k / n;
      railPoints.add(Vector3(
          a.$1 + dx * t, yAt(a.$1 + dx * t, a.$2 + dz * t), a.$2 + dz * t));
    }
  }
  final last = points.last;
  railPoints.add(Vector3(last.$1, yAt(last.$1, last.$2), last.$2));
  for (final point in railPoints) {
    _member(parts, point, point + Vector3(0, height, 0), .038, mat);
  }
  for (var i = 0; i + 1 < railPoints.length; i++) {
    for (final dy in [height * .52, height]) {
      _member(parts, railPoints[i] + Vector3(0, dy, 0),
          railPoints[i + 1] + Vector3(0, dy, 0), .038, mat);
    }
  }
}

void _bench(List<Part> parts, double x, double y, double z, double yaw,
    [double length = 1.7]) {
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(length, .08, .42), q * trs(0, .45), _timber))
    ..add(Part(boxGeometry(length, .08, .12), q * trs(0, .83, -.28), _timber));
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(.10, .45, .10),
        q * trs(side * (length / 2 - .22), .23), _timberDark));
  }
}

void _panel(List<Part> parts, double x, double y, double z, double yaw,
    {double width = 1, double height = .45, double postHeight = 2}) {
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  for (final side in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(.07, postHeight, .07),
        q * trs(side * width * .38, postHeight / 2), _metalDark));
  }
  parts
    ..add(Part(boxGeometry(width, height, .06),
        q * trs(0, postHeight - height * .65), _sign))
    ..add(Part(boxGeometry(width * .72, .055, .012),
        q * trs(0, postHeight - height * .58, .036), _signInk));
}

List<Tri> _trailRibbon(List<(double, double)> points, double width) {
  final parts = <Part>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
    final length = math.sqrt(dx * dx + dz * dz);
    if (length < .1) continue;
    final steps = math.max(1, (length / .8).ceil());
    for (var k = 0; k < steps; k++) {
      final t0 = k / steps, t1 = (k + 1) / steps;
      final x0 = a.$1 + dx * t0, z0 = a.$2 + dz * t0;
      final x1 = a.$1 + dx * t1, z1 = a.$2 + dz * t1;
      final y0 = hillSurfaceY(x0, z0) + .04;
      final y1 = hillSurfaceY(x1, z1) + .04;
      final yaw = math.atan2(dx, dz);
      final pitch = -math.atan2(
          y1 - y0, math.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0)));
      _box(parts, width, .08, length / steps + .04, _path, (x0 + x1) / 2,
          (y0 + y1) / 2, (z0 + z1) / 2, pitch, yaw);
    }
  }
  return bake(parts);
}

void _buildRoadFurniture(List<Part> parts, List<Tri> out) {
  _groundRail(
      parts, const [(112, -33.4), (120, -33.2), (130, -33.8), (139, -34.8)]);
  _groundRail(
      parts, const [(132.4, -66), (131, -73), (131, -80), (132.6, -87)]);
  for (final spot in const [
    (122.0, -34.4, -1.62),
    (133.0, -35.0, -1.62),
    (140.6, -50.6, 1.52),
    (91.4, -37.6, -1.05),
    (155.2, -39.6, 2.2),
  ]) {
    _panel(parts, spot.$1, hillSurfaceY(spot.$1, spot.$2), spot.$2, spot.$3,
        width: .68, height: .55, postHeight: 2.3);
  }
  const px = 152.4, pz = -32.4;
  final y = hillSurfaceY(px, pz);
  _box(parts, 6.4, .07, 4.6, _gravel, px, y + .035, pz);
  for (final side in [-1.0, 1.0]) {
    _box(parts, 1.5, .14, .16, _concreteDark, px + side * 1.6, y + .07,
        pz - 1.7);
  }
  _bench(parts, px + 1.2, y, pz - 1, math.pi);
  _panel(parts, px - 1.8, y, pz - 1.9, math.pi,
      width: 2, height: 1.3, postHeight: 2.2);
  out.addAll(
      makeMirror(x: 138.2, y: hillSurfaceY(138.2, -33.4), z: -33.4, ry: -2.3));
  out.addAll(makeMirror(x: 133.4, y: hillSurfaceY(133.4, -62), z: -62, ry: .9));
  out.addAll(
      makeCone(x: 143.2, y: hillSurfaceY(143.2, -34.6), z: -34.6, ry: .3));
  out.addAll(
      makeCone(x: 144.6, y: hillSurfaceY(144.6, -35.2), z: -35.2, ry: -.4));
}

void _buildDam(List<Part> parts, List<Tri> out) {
  const ax = 143.0, az = -44.0, bx = 157.0, bz = -37.0;
  final dx = bx - ax, dz = bz - az;
  final length = math.sqrt(dx * dx + dz * dz);
  final ux = dx / length, uz = dz / length;
  final nx = uz, nz = -ux; // lake/upstream side
  final rng = RngKit(90211);

  // Upstream riprap follows the real height field down to the water line.
  for (var i = 0; i < 360; i++) {
    final t = rng.range(-.06, 1.06), side = rng.range(3.0, 9.8);
    final x = ax + dx * t + nx * side, z = az + dz * t + nz * side;
    final y = hillSurfaceY(x, z);
    final r = rng.range(.16, .44);
    parts.add(Part(
        icosahedronGeometry(1, 0),
        trs(x, y + r * .3, z, rng.range(-.4, .4), rng.range(0, 3),
            rng.range(-.4, .4), r, r * rng.range(.45, .72), r),
        _rock));
  }
  _groundRail(
      parts,
      [
        for (var i = 0; i <= 6; i++)
          (ax + dx * i / 6 - nx * 2.7, az + dz * i / 6 - nz * 2.7),
      ],
      height: 1.1,
      spacing: 2.4,
      mat: _white);
  _groundRail(parts, const [(153.2, -36.6), (158.0, -33.4)],
      height: .95, spacing: 1.2, mat: _white);

  // Inclined intake and the narrow five-bay maintenance catwalk.
  final ix = ax + dx * .62 + nx * 8.6;
  final iz = az + dz * .62 + nz * 8.6;
  final bed = hillSurfaceY(ix, iz) - .8;
  final waterY = 4.435;
  final h = math.max(1.8, waterY + 1.15 - bed);
  _box(parts, .52, h, .52, _timberDark, ix, bed + h / 2, iz, .30,
      math.atan2(nx, nz));
  _box(parts, 1.5, .7, 1.5, _concreteMid, ix, bed + .2, iz, 0,
      math.atan2(nx, nz));
  for (var k = 0; k < 6; k++) {
    parts.add(Part(
        cylGeometry(.085, .085, .20, 8),
        trs(ix - nx * k * .16, bed + .5 + k * .42, iz - nz * k * .16,
            math.pi / 2),
        _metalDark));
  }
  final rootX = ax + dx * .62 + nx * 3.6;
  final rootZ = az + dz * .62 + nz * 3.6;
  final walkY = waterY + .55;
  const bays = 5;
  for (var k = 0; k <= bays; k++) {
    final t = k / bays, x = rootX + (ix - rootX) * t;
    final z = rootZ + (iz - rootZ) * t;
    for (final side in [-1.0, 1.0]) {
      final qx = x + ux * side * .38, qz = z + uz * side * .38;
      final ground = hillSurfaceY(qx, qz);
      _box(parts, .13, walkY - ground + .1, .13, _timberDark, qx,
          (walkY + ground) / 2, qz);
    }
  }
  final walkLength =
      math.sqrt((ix - rootX) * (ix - rootX) + (iz - rootZ) * (iz - rootZ));
  final boardN = math.max(1, (walkLength / .2).round());
  for (var k = 0; k < boardN; k++) {
    final t = (k + .5) / boardN;
    _box(parts, .95, .055, .17, _timber, rootX + (ix - rootX) * t, walkY,
        rootZ + (iz - rootZ) * t, 0, math.atan2(nx, nz));
  }
  _groundRail(
      parts, [(rootX + ux * .5, rootZ + uz * .5), (ix + ux * .5, iz + uz * .5)],
      height: .95, spacing: 1.4, yAt: (_, __) => walkY);

  // Downstream bottom outlet and stilling basin.
  const ox = 150.6, oz = -30.2;
  final oy = hillSurfaceY(ox, oz) - .2;
  _box(parts, 3.6, .9, 3.0, _concrete, ox, oy - .3, oz);
  for (final side in [-1.0, 1.0]) {
    _box(parts, 3.6, .9, .26, _concrete, ox, oy + .3, oz + side * 1.4);
  }
  _box(parts, .3, 1.4, 3, _concrete, ox + 1.8, oy + .35, oz);
  parts
    ..add(Part(cylGeometry(.34, .34, .7, 12),
        trs(ox + 1.7, oy + .34, oz, 0, 0, math.pi / 2), _concreteDark))
    ..add(Part(cylGeometry(.27, .27, .3, 12),
        trs(ox + 1.9, oy + .34, oz, 0, 0, math.pi / 2), _inside));

  // Management yard, hut, warning lamp, notice board, and stored equipment.
  const yardX = 146.0, yardZ = -30.0;
  final yardY = hillSurfaceY(yardX, yardZ);
  _box(parts, 11, .07, 7.2, _gravel, yardX, yardY + .035, yardZ);
  const hutX = yardX - 2.6, hutZ = yardZ - 1.2;
  _box(parts, 3.4, 2.5, 2.7, _concrete, hutX, yardY + 1.25, hutZ, 0, .1);
  _box(parts, 3.8, .16, 3.1, _roof, hutX, yardY + 2.6, hutZ, 0, .1);
  _box(parts, 1.5, 1.9, .08, _shutter, hutX + .2, yardY + .95, hutZ + 1.38, 0,
      .1);
  _box(parts, .42, .56, .16, _metal, hutX - 1.2, yardY + 1.5, hutZ + 1.4);
  parts.add(Part(cylGeometry(.11, .11, .16, 10),
      trs(hutX + 1.3, yardY + 2.76, hutZ), _red));
  _panel(parts, yardX + 2.4, yardY, yardZ + 2.2, math.pi,
      width: 1.9, height: 1.25, postHeight: 2.2);
  out.addAll(makeCrates(
      x: yardX + 3.6, y: yardY, z: yardZ - 1.6, n: 3, seed: 9211, ry: .2));
  out.addAll(makeCone(x: yardX - 5, y: yardY, z: yardZ + 2.4, ry: .2));
}

void _buildOverlook(List<Part> parts, List<Tri> out) {
  const route = [
    (86.0, -95.4),
    (92.0, -95.6),
    (98.0, -95.8),
    (102.6, -96.8),
    (106.0, -99.2),
    (109.0, -96.6),
    (112.4, -94.8),
    (115.0, -97.4),
    (117.6, -100.2),
    (120.6, -98.0),
    (123.2, -100.8),
    (124.6, -104.4),
    (123.8, -112.2),
    (127.4, -112.0),
    (130.4, -110.6),
    (133.0, -109.0),
    (134.8, -107.6),
    (137.0, -108.6),
    (139.0, -110.4),
    (141.6, -111.4),
    (143.8, -109.8),
    (145.0, -106.4),
  ];
  out.addAll(_trailRibbon(route, 1.5));
  _groundRail(parts, const [(102.6, -95.6), (106, -98), (109, -95.4)],
      height: .9, spacing: 1.6, mat: _timber);
  _groundRail(parts, const [(136.6, -111), (140.4, -112.4), (143.4, -110.6)],
      height: .9, spacing: 1.6, mat: _timber);
  const restX = 113.4, restZ = -94.2;
  final restY = hillSurfaceY(restX, restZ);
  _box(parts, 3.4, .06, 3, _pathEdge, restX, restY + .03, restZ);
  _bench(parts, restX, restY + .06, restZ - .8, 0, 1.8);
  _panel(parts, restX + 1.5, restY, restZ + 1.2, -1.2,
      width: .8, postHeight: 2.1);

  // 見晴台, six posts, plank deck, four-sided rail with a south stair opening.
  const x = 124.0, z = -108.0, width = 5.0, depth = 4.2, height = 1.1;
  final ground = hillSurfaceY(x, z), deckY = ground + height;
  for (var ix = -1; ix <= 1; ix++) {
    for (final iz in [-1.0, 1.0]) {
      final px = x + ix * (width / 2 - .35);
      final pz = z + iz * (depth / 2 - .35);
      final py = hillSurfaceY(px, pz);
      _box(parts, .55, .28, .55, _concreteMid, px, py + .07, pz);
      _box(parts, .19, deckY - py - .1, .19, _timberDark, px,
          (deckY + py + .1) / 2 - .05, pz);
    }
  }
  for (var k = 0; k < (depth / .19).round(); k++) {
    _box(parts, width + .24, .055, .165, _timber, x, deckY + .03,
        z - depth / 2 + .1 + k * (depth - .2) / ((depth / .19).round() - 1));
  }
  final x0 = x - width / 2, x1 = x + width / 2;
  final z0 = z - depth / 2, z1 = z + depth / 2;
  _groundRail(parts, [(x1, z0), (x1, z1)],
      height: 1.02, spacing: 1.3, mat: _timber, yAt: (_, __) => deckY);
  _groundRail(parts, [(x0, z1), (x1, z1)],
      height: 1.02, spacing: 1.3, mat: _timber, yAt: (_, __) => deckY);
  _groundRail(parts, [(x0, z0), (x0, z1)],
      height: 1.02, spacing: 1.3, mat: _timber, yAt: (_, __) => deckY);
  _groundRail(parts, [(x0, z0), (x - .9, z0)],
      height: 1.02, spacing: 1.3, mat: _timber, yAt: (_, __) => deckY);
  _groundRail(parts, [(x + 1.4, z0), (x1, z0)],
      height: 1.02, spacing: 1.3, mat: _timber, yAt: (_, __) => deckY);
  for (var k = 0; k < 5; k++) {
    final stepY = ground + height * (k + 1) / 5;
    _box(
        parts, 1.9, .06, .46, _concreteMid, x + .25, stepY, z0 - 1.9 + k * .42);
  }
  _bench(parts, x - 1.1, deckY + .06, z + 1.3, -math.pi / 2, 1.6);
  _bench(parts, x - 1.1, deckY + .06, z - 1.3, -math.pi / 2, 1.6);
  _box(parts, .09, .85, 1.8, _sign, x1 - .34, deckY + .9, z - 1.45, 0, 0, -.4);
}

List<Tri> buildLakeRoadDetails({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[], out = <Tri>[];
  _buildRoadFurniture(parts, out);
  _buildDam(parts, out);
  _buildOverlook(parts, out);
  out.addAll(buildGrove([
    GroveSpot(
        x: 157,
        z: -31,
        y: hillSurfaceY(157, -31),
        scale: 1.4,
        seed: 9101,
        spread: 1.1),
    GroveSpot(
        x: 138,
        z: -39,
        y: hillSurfaceY(138, -39),
        scale: 1.45,
        seed: 9231,
        spread: 1.1),
    GroveSpot(
        x: 162.6,
        z: -34.6,
        y: hillSurfaceY(162.6, -34.6),
        scale: 1.5,
        seed: 9232,
        spread: 1.15),
    GroveSpot(
        x: 110.4,
        z: -92,
        y: hillSurfaceY(110.4, -92),
        scale: 1.5,
        seed: 9301,
        spread: 1.1),
    for (final spot in const [
      (-6.6, 4.4, 1.5, 9401),
      (-7.4, -3.6, 1.44, 9402),
      (-3, 5.6, 1.38, 9403),
      (-2.4, -6, 1.5, 9404)
    ])
      GroveSpot(
          x: (124 + spot.$1).toDouble(),
          z: (-108 + spot.$2).toDouble(),
          y: hillSurfaceY(
              (124 + spot.$1).toDouble(), (-108 + spot.$2).toDouble()),
          scale: spot.$3,
          seed: spot.$4,
          spread: 1.12),
  ]));
  out.addAll(buildSakura([
    SakuraSpot(
        x: 159.6,
        z: -47.4,
        y: hillSurfaceY(159.6, -47.4),
        scale: 1.2,
        seed: 9241,
        lean: .12,
        leanDir: 2),
    SakuraSpot(
        x: 118.6,
        z: -107,
        y: hillSurfaceY(118.6, -107),
        scale: 1.22,
        seed: 9411,
        lean: .11,
        leanDir: 4.2),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  out.addAll(buildShrubs([
    ShrubSpot(
        x: 151.4,
        z: -27.4,
        y: hillSurfaceY(151.4, -27.4),
        r: .5,
        count: 4,
        spread: 1.6,
        seed: 9221),
  ]));
  return [...bake(parts), ...out];
}
