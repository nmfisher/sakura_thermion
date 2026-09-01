/// Authored civil works and bank life for the 用水路.
///
/// `water.dart` owns the continuous excavation, revetment, and water layers.
/// This module ports the visible structures and dressing from `canal.js`: both
/// named bridges, the field crossing, distribution gate, unequal culvert ends,
/// service paths, railings, the quiet corner, works store, reeds, flowers, and
/// bank planting.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'details.dart' show makeVendingMachine;
import 'make_props.dart' show makeCrates, makePlanter;
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart';

const _z = -24.0;
const _half = 2.5;
const _depth = 1.75;
const _wallIn = 2.16;
const _slabOut = 6.0;
const _pathOut = 4.6;
const _x0 = -98.0;
const _x1 = 106.0;
const _dressW = -58.0;
const _dressE = 44.0;
const _rd0 = -4.7;
const _rd1 = 7.9;
const _footX = -22.5;
const _crossX = 17.5;
const _sluiceX = 29.5;

const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _concreteDark = Mat(0xa7a2b0, tint: 0x655d84, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _rust = Mat(0x9c7a62, tint: 0x6a5a80, bands: '3');
const _white = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2');
const _grass = Mat(0x91ae72, tint: 0x5b6f8c, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _moss = Mat(0x7d9c74, tint: 0x5b6f8c, bands: '3');
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _inside = Mat(0x2e2c3a, tint: 0x4a4560, bands: '2');
const _red = Mat(0xe0453f, tint: 0x7a4060, bands: '3');
const _signBlue = Mat(0x3d78a8, unlit: true);
const _signCream = Mat(0xf8f3df, unlit: true);
const _reedA = Mat(0x94b874, tint: 0x6a86a0, bands: 'soft');
const _reedB = Mat(0x74a05c, tint: 0x6a86a0, bands: 'soft');
const _reedHead = Mat(0xcfbd94, tint: 0x8a7f9c, bands: 'soft');
const _flowerWhite = Mat(0xf6f2e8, tint: 0x8f7aa8, bands: '2');
const _flowerYellow = Mat(0xf0c341, tint: 0x8f7aa8, bands: '2');
const _flowerPink = Mat(0xf0a3c0, tint: 0x8f7aa8, bands: '2');
const _petal = Mat(0xf1c4d2, unlit: true, noOutline: true);

final _unitCylinder = cylGeometry(1, 1, 1, 7);

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _member(List<Part> parts, Vector3 a, Vector3 b, double radius, Mat mat) {
  final direction = b - a;
  if (direction.length < 1e-4) return;
  final q = quatFromUnitVectors(Vector3(0, 1, 0), direction.normalized());
  parts.add(Part(
      _unitCylinder,
      composePRS((a + b) * .5, q, Vector3(radius, direction.length, radius)),
      mat));
}

void _railingX(List<Part> parts, double x0, double x1, double z, double y,
    {double height = 1, double spacing = 2}) {
  final count = math.max(1, ((x1 - x0) / spacing).ceil());
  for (var i = 0; i <= count; i++) {
    final x = x0 + (x1 - x0) * i / count;
    _member(parts, Vector3(x, y, z), Vector3(x, y + height, z), .038, _white);
  }
  for (final dy in [height * .52, height]) {
    _member(
        parts, Vector3(x0, y + dy, z), Vector3(x1, y + dy, z), .038, _white);
  }
}

void _railingZ(List<Part> parts, double x, double z0, double z1, double y,
    {double height = 1, int posts = 5}) {
  for (var i = 0; i <= posts; i++) {
    final z = z0 + (z1 - z0) * i / posts;
    _member(parts, Vector3(x, y, z), Vector3(x, y + height, z), .038, _white);
  }
  for (final dy in [height * .52, height]) {
    _member(
        parts, Vector3(x, y + dy, z0), Vector3(x, y + dy, z1), .038, _white);
  }
}

List<(double, double)> _splitRuns(
    List<(double, double)> runs, List<(double, double)> holes) {
  var out = [...runs];
  for (final hole in holes) {
    final next = <(double, double)>[];
    for (final run in out) {
      if (hole.$2 <= run.$1 || hole.$1 >= run.$2) {
        next.add(run);
      } else {
        if (hole.$1 > run.$1) next.add((run.$1, hole.$1));
        if (hole.$2 < run.$2) next.add((hole.$2, run.$2));
      }
    }
    out = next;
  }
  return out.where((run) => run.$2 - run.$1 > .05).toList();
}

void _bench(List<Part> parts, double x, double y, double z, double yaw) {
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(boxGeometry(1.8, .09, .42), q * trs(0, .46, 0), _timber))
    ..add(Part(boxGeometry(1.8, .09, .13), q * trs(0, .85, -.28), _timber));
  for (final sx in [-.68, .68]) {
    parts.add(
        Part(boxGeometry(.11, .45, .11), q * trs(sx, .23, 0), _timberDark));
  }
}

void _sign(List<Part> parts, double x, double y, double z, double yaw,
    {double height = 1.7, double width = .56, double panelHeight = .42}) {
  final q = Matrix4.translation(Vector3(x, y, z)) * Matrix4.rotationY(yaw);
  parts
    ..add(Part(
        boxGeometry(.07, height, .07), q * trs(0, height / 2, 0), _metalDark))
    ..add(Part(boxGeometry(width, panelHeight, .055),
        q * trs(0, height - panelHeight * .55, 0), _signCream))
    ..add(Part(boxGeometry(width * .78, .055, .012),
        q * trs(0, height - panelHeight * .50, .034), _signBlue))
    ..add(Part(boxGeometry(width * .58, .045, .012),
        q * trs(0, height - panelHeight * .72, .034), _signBlue));
}

void _quietCorner(List<Part> parts, List<Tri> out, double y0) {
  final qz = _z - (_pathOut + .6);
  _box(parts, 11, .06, 1.9, _concrete, -27.6, y0 + .05, qz);
  final qy = y0 + .08;
  out.addAll(
      makeVendingMachine(x: -31.2, y: qy, z: qz - .2, variant: 0, seed: 41));
  _box(parts, .44, .74, .44, _metalDark, -30.05, qy + .37, qz - .2);
  _bench(parts, -27.8, qy, qz + .1, 0);
  _bench(parts, -24.4, qy, qz + .1, math.pi);
  _member(parts, Vector3(-33.8, qy, qz - .3), Vector3(-33.8, qy + 4.2, qz - .3),
      .065, _metalDark);
  _member(parts, Vector3(-33.8, qy + 4.18, qz - .3),
      Vector3(-33.8, qy + 4.18, qz + .4), .03, _metalDark);
  parts.add(Part(cylGeometry(0, .30, .24, 12, openEnded: true),
      trs(-33.8, qy + 4.04, qz + .4), _metal));
  _box(parts, .24, .05, .24, _signCream, -33.8, qy + 3.9, qz + .4);
  _sign(parts, -35.6, y0, qz + .2, .35, height: 2, width: .8, panelHeight: .6);
}

void _worksStore(List<Part> parts, List<Tri> out, double y0) {
  const x = 22.4;
  final z = _z - (_pathOut + .9);
  _box(parts, 5.2, .05, 1.7, _gravel, x, y0 + .045, z);
  for (var i = 0; i < 5; i++) {
    final row = i ~/ 3;
    parts.add(Part(
        cylGeometry(.21, .21, 1.1, 9),
        trs(x - 1.6 + (i % 3) * .46, y0 + .30 + row * .42,
            z + (row == 1 ? .06 : -.06), 0, 0, math.pi / 2),
        _concreteMid));
  }
  out.addAll(makeCrates(
      x: x + 1.5, y: y0 + .07, z: z - .1, n: 3, seed: 3382, ry: .22));
  _sign(parts, x + 2.4, y0 + .02, z + .5, 2.6,
      height: 1.7, width: .34, panelHeight: .68);
}

void _buildBanks(List<Part> parts, List<Tri> out, double y0) {
  const dressed = [(_dressW, _rd0), (_rd1, _dressE)];
  for (final side in [-1.0, 1.0]) {
    final pathZ = _z + side * ((_half + _pathOut) / 2);
    final grassZ = _z + side * ((_pathOut + _slabOut) / 2);
    for (final run in dressed) {
      _box(parts, run.$2 - run.$1, .06, _pathOut - _half, _concrete,
          (run.$1 + run.$2) / 2, y0 + .03, pathZ);
      _box(parts, run.$2 - run.$1, .05, _slabOut - _pathOut, _grass,
          (run.$1 + run.$2) / 2, y0 + .025, grassZ);
    }
    final railRuns = _splitRuns(dressed, const [
      (_footX - 2.6, _footX + 2.6),
      (_crossX - 2, _crossX + 2),
      (_sluiceX - 2.2, _sluiceX + 2.2),
    ]);
    for (final run in railRuns) {
      if (run.$2 - run.$1 >= 1.2) {
        _railingX(parts, run.$1, run.$2, _z + side * (_half + .26), y0 + .06);
      }
    }
  }

  // North natural ground is higher: retain it, preserving the school stair gap.
  for (final run in _splitRuns(dressed, const [(7.95, 10.45)])) {
    _box(parts, run.$2 - run.$1, .62, .30, _concrete, (run.$1 + run.$2) / 2,
        y0 + .31, _z - _slabOut);
  }
  for (final x in [7.95, 10.45]) {
    _box(parts, .30, .66, .62, _concrete, x, y0 + .33, _z - _slabOut - .16);
  }
  _quietCorner(parts, out, y0);
  _worksStore(parts, out, y0);
}

void _buildFootbridge(List<Part> parts, List<Tri> out, double y0) {
  const width = 3.0, rise = .5, span = _half * 2, segments = 7;
  final z0 = _z - span / 2;
  double profile(double u) => rise * math.sin(math.pi * u);
  for (var i = 0; i < segments; i++) {
    final u0 = i / segments, u1 = (i + 1) / segments;
    final a = profile(u0), b = profile(u1), length = span / segments;
    final tilt = math.atan2(b - a, length);
    _box(parts, width, .26, length / math.cos(tilt) + .02, _concrete, _footX,
        y0 + (a + b) / 2, z0 + span * (u0 + u1) / 2, tilt);
  }
  for (final side in [-1.0, 1.0]) {
    _box(parts, width + .5, 1.1, .8, _concreteMid, _footX, y0 - .45,
        _z + side * (_half + .1));
    final rx = _footX + side * (width / 2 - .12);
    const n = 9;
    for (var i = 0; i <= n; i++) {
      final u = i / n, zz = z0 + span * u;
      _member(parts, Vector3(rx, y0 + profile(u) + .13, zz),
          Vector3(rx, y0 + profile(u) + 1.13, zz), .038, _white);
      if (i < n) {
        final un = (i + 1) / n, zn = z0 + span * un;
        for (final h in [.62, 1.08]) {
          _member(parts, Vector3(rx, y0 + profile(u) + h, zz),
              Vector3(rx, y0 + profile(un) + h, zn), .038, _white);
        }
      }
    }
  }
  _box(parts, .5, _depth - .3, .9, _concreteDark, _footX,
      y0 - (_depth - .3) / 2 - .2, _z);
  _box(parts, .90, .24, .06, _signCream, _footX - 1.05, y0 + .9, _z + 2.52);
  _sign(parts, _footX + 2.4, y0 + .06, _z + 2.9, 0,
      height: 1.8, width: .32, panelHeight: .64);
  out.addAll(makePlanter(
      x: _footX - 2.1,
      y: y0 + .06,
      z: z0 - .3,
      r: .26,
      flower: true,
      seed: 71,
      n: 5));
  out.addAll(makePlanter(
      x: _footX + 2,
      y: y0 + .06,
      z: z0 + span + .4,
      r: .24,
      flower: true,
      seed: 72,
      n: 4));
}

void _buildRoadBridge(List<Part> parts, double y0) {
  const p0 = -27.4, p1 = -21.4;
  const segments = 9;
  for (var i = 0; i < segments; i++) {
    final za = p0 + (p1 - p0) * i / segments;
    final zb = p0 + (p1 - p0) * (i + 1) / segments;
    final zm = (za + zb) / 2;
    final x = centerX(zm), y = groundY(zm) - terrainDrop - .02;
    final width = roadHalf * 2 + walkW * 2 + .5;
    final tilt = math.atan2(groundY(zb) - groundY(za), zb - za);
    _box(parts, width, .42, (zb - za) / math.cos(tilt) + .02, _concrete, x,
        y - .21, zm, tilt);
  }
  // Low west pipe rail and the taller east name parapet follow the drifting road.
  for (var i = 0; i < 5; i++) {
    final za = p0 + (p1 - p0) * i / 5;
    final zb = p0 + (p1 - p0) * (i + 1) / 5;
    final xa = centerX(za) - (roadHalf + walkW - .12);
    final xb = centerX(zb) - (roadHalf + walkW - .12);
    final ya = groundY(za) + walkH, yb = groundY(zb) + walkH;
    _member(
        parts, Vector3(xa, ya, za), Vector3(xa, ya + 1.02, za), .038, _white);
    if (i == 4) {
      _member(
          parts, Vector3(xb, yb, zb), Vector3(xb, yb + 1.02, zb), .038, _white);
    }
    for (final h in [.52, 1.0]) {
      _member(parts, Vector3(xa, ya + h, za), Vector3(xb, yb + h, zb), .038,
          _white);
    }
    final ex = centerX((za + zb) / 2) + roadHalf + walkW + .18;
    final ey = groundY((za + zb) / 2) + walkH;
    _box(parts, .30, .92, zb - za + .04, _concrete, ex, ey + .34, (za + zb) / 2,
        0, -math.atan2(centerX(zb) - centerX(za), zb - za));
  }
  final plateZ = -21.9;
  _box(
      parts,
      .12,
      .26,
      .95,
      _signCream,
      centerX(plateZ) + roadHalf + walkW + .38,
      groundY(plateZ) + walkH + .5,
      plateZ);
  for (final zz in [p0 - .25, p1 + .25]) {
    for (final side in [-1.0, 1.0]) {
      final x = centerX(zz) + side * (roadHalf + walkW + .18);
      _member(parts, Vector3(x, groundY(zz), zz),
          Vector3(x, groundY(zz) + .95, zz), .057, _white);
      _box(parts, .13, .14, .13, _red, x, groundY(zz) + .82, zz);
    }
  }
}

void _buildSlabCrossing(List<Part> parts, double y0) {
  const width = 2.5, span = _half * 2 + 1.2;
  _box(parts, width, .30, span, _concrete, _crossX, y0 + .06, _z);
  for (final side in [-1.0, 1.0]) {
    _box(parts, .20, .20, span - .3, _concreteMid,
        _crossX + side * (width / 2 - .1), y0 + .31, _z);
    _box(parts, width + .4, .9, .7, _concreteMid, _crossX, y0 - .4,
        _z + side * (_half + .2));
  }
  _box(parts, .45, _depth - .3, .8, _concreteDark, _crossX,
      y0 - (_depth - .3) / 2 - .2, _z);
  _box(parts, .06, .20, .72, _signCream, _crossX + width / 2 - .02, y0 + .31,
      _z + _half + .1);
}

void _buildSluice(List<Part> parts, double y0) {
  const open = 1.5, pierH = _depth + .9;
  for (final side in [-1.0, 1.0]) {
    final pz = _z + side * ((open / 2 + _wallIn) / 2);
    final pd = _wallIn - open / 2;
    _box(parts, 1.1, pierH, pd, _concreteMid, _sluiceX, y0 + .28 - pierH / 2,
        pz);
    _box(parts, .16, _depth - .2, pd - .1, _concreteDark, _sluiceX - .48,
        y0 - _depth / 2, pz);
  }
  const length = _wallIn * 2 + .7;
  _box(parts, 1.4, .22, length, _concrete, _sluiceX, y0 + .19, _z);
  for (var i = 0; i < 11; i++) {
    _box(parts, 1.2, .04, .06, _metalDark, _sluiceX, y0 + .32,
        _z - 2.4 + i * .48);
  }
  for (final side in [-1.0, 1.0]) {
    _railingZ(parts, _sluiceX + side * .66, _z - length / 2, _z + length / 2,
        y0 + .30,
        height: .95, posts: 4);
  }
  _box(parts, .10, _depth - .35, open + .16, _rust, _sluiceX - .4,
      y0 - _depth / 2 - .05, _z);
  for (var i = 0; i < 3; i++) {
    _box(parts, .06, .08, open + .1, _metalDark, _sluiceX - .47,
        y0 - .45 - i * .45, _z);
  }
  for (final side in [-1.0, 1.0]) {
    _member(parts, Vector3(_sluiceX - .3, y0 + .5, _z + side * .34),
        Vector3(_sluiceX - .3, y0 + 2, _z + side * .34), .05, _metalDark);
  }
  _box(parts, .34, .14, .9, _metalDark, _sluiceX - .3, y0 + 2.02, _z);
  _member(parts, Vector3(_sluiceX - .3, y0 + .3, _z),
      Vector3(_sluiceX - .3, y0 + 2.2, _z), .035, _metal);
  // Handwheel in the horizontal plane.
  const wheelN = 14;
  for (var i = 0; i < wheelN; i++) {
    final a0 = i / wheelN * math.pi * 2, a1 = (i + 1) / wheelN * math.pi * 2;
    _member(
        parts,
        Vector3(_sluiceX - .3 + math.cos(a0) * .24, y0 + 2.16,
            _z + math.sin(a0) * .24),
        Vector3(_sluiceX - .3 + math.cos(a1) * .24, y0 + 2.16,
            _z + math.sin(a1) * .24),
        .026,
        _rust);
  }
  for (var i = 0; i < 4; i++) {
    final a = i / 4 * math.pi;
    _member(
        parts,
        Vector3(_sluiceX - .3 - math.cos(a) * .23, y0 + 2.16,
            _z - math.sin(a) * .23),
        Vector3(_sluiceX - .3 + math.cos(a) * .23, y0 + 2.16,
            _z + math.sin(a) * .23),
        .018,
        _rust);
  }
  _sign(parts, _sluiceX + .72, y0, _z - _wallIn - .1, math.pi / 2,
      height: 1.15, width: .52, panelHeight: .4);
}

void _buildHeadwall(List<Part> parts, bool west, double y0) {
  final dir = west ? 1.0 : -1.0;
  final xo = west ? _x0 : _x1;
  final xi = xo + dir * .75;
  final xc = (xo + xi) / 2;
  final sill = y0 - _depth + .28;
  final top = y0 + .10;
  const openW = 2.10, wallZ = _half;
  final face = west ? _concrete : _concreteMid;
  final rectH = west ? 1.34 : .34;
  final springY = sill + rectH;
  final base = y0 - _depth - .3;
  for (final side in [-1.0, 1.0]) {
    final za = _z + side * openW / 2, zb = _z + side * wallZ;
    _box(parts, .75, top - base, (zb - za).abs(), face, xc, (base + top) / 2,
        (za + zb) / 2);
  }
  if (west) {
    _box(parts, .75, top - springY, openW, face, xc, (springY + top) / 2, _z);
  } else {
    const n = 14, radius = openW / 2;
    for (var i = 0; i < n; i++) {
      final width = openW / n;
      final zc = _z - openW / 2 + (i + .5) * width;
      final dz = (zc - _z).abs();
      final openingTop =
          springY + math.sqrt(math.max(0, radius * radius - dz * dz));
      if (top - openingTop > .02) {
        _box(parts, .75, top - openingTop, width + .004, face, xc,
            (openingTop + top) / 2, zc);
      }
    }
    const ringN = 9;
    for (var i = 0; i < ringN; i++) {
      final a0 = math.pi * i / ringN, a1 = math.pi * (i + 1) / ringN;
      final a = (a0 + a1) / 2;
      _box(
          parts,
          .85,
          .30,
          radius * (a1 - a0) * 1.06,
          _concrete,
          xc + dir * .05,
          springY + math.sin(a) * (radius + .15),
          _z - math.cos(a) * (radius + .15),
          a - math.pi / 2);
    }
    _box(parts, .91, .14, openW + .08, _moss, xc + dir * .08, sill + .06, _z);
  }
  _box(parts, 2.4, rectH, openW, _inside, xo - dir * 1.2, sill + rectH / 2, _z);
  _box(parts, 1.09, .18, wallZ * 2 + .34, _concrete, xc, top + .09, _z);

  // Stepped, splayed wing walls tie the mouth into each bank.
  for (final side in [-1.0, 1.0]) {
    for (var i = 0; i < 3; i++) {
      final back = .55 + i * .95, out = wallZ + .34 + i * .50;
      final h = 1.30 - i * .34;
      _box(parts, 1.05, h, .62, face, xo - dir * back, y0 + .16 - h / 2,
          _z + side * out);
    }
  }

  if (west) {
    // Raked trash screen and its maintenance platform.
    const bars = 11;
    final h = rectH + .26;
    for (var i = 0; i < bars; i++) {
      final zz = _z - openW / 2 + .08 + i * ((openW - .16) / 10);
      final foot = Vector3(xi + dir * .26, sill, zz);
      final topPoint = Vector3(
          foot.x + dir * math.sin(.34) * h, sill + math.cos(.34) * h, zz);
      _member(parts, foot, topPoint, .025, _rust);
    }
    final px = xi + dir * 1.5, pz = _z - (wallZ + 1.05), py = y0 + .30;
    _box(parts, 2.9, .24, 2, _concrete, px, py - .12, pz);
    _railingX(parts, px - 1.45, px + 1.45, pz + 1, py, spacing: 1.45);
    _sign(parts, px + dir * .2, y0 + .02, pz - 1.5, math.pi / 2,
        height: 2, width: .72, panelHeight: .30);
  } else {
    final ax = xi + dir * 2.2;
    _box(parts, 4.4, .20, _wallIn * 2, _concreteMid, ax, sill - .02, _z);
    _box(parts, .24, .34, _wallIn * 2, _concreteMid, xi + dir * 4.4, sill + .09,
        _z);
    _box(parts, 4.4, .14, _wallIn * 2 - .1, _moss, ax, sill + .09, _z);
    _sign(parts, xi + dir * 1.1, y0 + .02, _z - wallZ - .6, -math.pi / 2,
        height: 1.9, width: .72, panelHeight: .30);
  }
}

void _buildBankLife(List<Part> parts, List<Tri> out, double y0,
    int blossomLightColor, int blossomColor, int blossomDeepColor) {
  final rng = RngKit(3371);
  final waterY = y0 - 1.15;
  bool clear(double x) =>
      (x - _footX).abs() > 2.8 &&
      (x - _crossX).abs() > 2.6 &&
      (x - _sluiceX).abs() > 2.8 &&
      (x < _rd0 - 1.4 || x > _rd1 + 1.4);
  void reeds(double x, double z, double y, int count, double scale) {
    _box(parts, .55 * scale, .13 * scale, .42 * scale, _moss, x,
        y + .065 * scale, z);
    for (var i = 0; i < count; i++) {
      final h = (1.05 + rng.range(-.25, .5)) * scale;
      final px = x + rng.range(-.4, .4), pz = z + rng.range(-.26, .26);
      final mat = i.isEven ? _reedA : _reedB;
      parts.add(Part(
          cylGeometry(0, .032, 1, 3),
          trs(px, y + h / 2, pz, rng.range(-.14, .14), 0, rng.range(-.14, .14),
              1, h, 1),
          mat));
      if (rng.chance(.35)) {
        parts.add(Part(
            cylGeometry(0, .028, .22, 4), trs(px, y + h + .1, pz), _reedHead));
      }
    }
  }

  for (double x = _dressW + 2; x < _dressE - 2; x += 2.4) {
    if (!clear(x)) continue;
    if (rng.chance(.74)) {
      reeds(x, _z - (_wallIn - .18), waterY - .06, rng.ints(5, 9),
          rng.range(.9, 1.4));
    }
    if (rng.chance(.62)) {
      reeds(x, _z + (_wallIn - .18), waterY - .06, rng.ints(4, 8),
          rng.range(.85, 1.3));
    }
  }
  for (var i = 0; i < 40; i++) {
    final side = rng.chance(.7) ? -1.0 : 1.0;
    final x = _dressW + 7 + rng.range(0, _dressE - _dressW - 14);
    if (x > _rd0 - 1 && x < _rd1 + 1) continue;
    reeds(x, _z + side * rng.range(_pathOut + .3, _slabOut - .3), y0 + .05,
        rng.ints(4, 8), rng.range(.6, 1));
  }
  for (var i = 0; i < 380; i++) {
    final side = rng.chance(.6) ? -1.0 : 1.0;
    final x = _dressW + 6 + rng.range(0, _dressE - _dressW - 12);
    if (x > _rd0 - .8 && x < _rd1 + .8) continue;
    final z = _z + side * rng.range(_pathOut + .2, _slabOut - .2);
    final r = rng.range(.035, .07);
    final mats = [_flowerWhite, _flowerYellow, _flowerPink];
    parts.add(Part(
        icosahedronGeometry(1, 0),
        trs(x, y0 + .05 + r + rng.range(.02, .18), z, rng.range(0, 3),
            rng.range(0, 3), rng.range(0, 3), r, r, r),
        mats[rng.ints(0, 2)]));
  }
  // Painted petals on both walking banks and in the quiet corner.
  for (final run in const [(_dressW, _rd0), (_rd1, _dressE)]) {
    final width = run.$2 - run.$1 - 4;
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < (width * 2.6).round(); i++) {
        final x = (run.$1 + run.$2) / 2 + rng.range(-width / 2, width / 2);
        final z = _z + side * (_half + 1.5) + rng.range(-.9, .9);
        _box(parts, .15, .008, .10, _petal, x, y0 + .08, z, 0,
            rng.range(0, math.pi * 2));
      }
    }
  }

  final sakura = <SakuraSpot>[];
  const northBank = _z - (_half + .6), southBank = _z + (_half + .6);
  for (var i = 0; i < 6; i++) {
    sakura.add(SakuraSpot(
        x: -49 + i * 7.6,
        z: northBank - 1.7,
        y: y0,
        scale: 1.16 + (i % 3) * .1,
        seed: 1010 + i,
        lean: .24,
        leanDir: math.pi));
  }
  for (var i = 0; i < 4; i++) {
    sakura.add(SakuraSpot(
        x: -45 + i * 9.4,
        z: southBank + 1.5,
        y: y0,
        scale: 1.1 + (i % 2) * .12,
        seed: 1020 + i,
        lean: .22,
        leanDir: 0));
  }
  for (final spot in const [
    (14.6, -1, 1.18, 1060),
    (24.0, -1, 1.24, 1061),
    (37.0, -1, 1.12, 1062),
    (19.4, 1, 1.14, 1063),
    (32.2, 1, 1.22, 1064),
  ]) {
    final side = spot.$2;
    sakura.add(SakuraSpot(
        x: spot.$1,
        z: side < 0 ? northBank - 1.7 : southBank + 1.5,
        y: y0,
        scale: spot.$3,
        seed: spot.$4,
        lean: .22,
        leanDir: side < 0 ? math.pi : 0));
  }
  out.addAll(buildSakura(sakura,
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  out.addAll(buildGrove([
    GroveSpot(
        x: -52,
        z: _z - 9.6,
        y: groundY(_z - 9.6),
        scale: 1.9,
        seed: 1031,
        spread: 1.2),
    GroveSpot(
        x: -42,
        z: _z - 10.4,
        y: groundY(_z - 10.4),
        scale: 1.7,
        seed: 1032,
        spread: 1.15),
    GroveSpot(
        x: -26.4,
        z: _z - 9.8,
        y: groundY(_z - 9.8),
        scale: 1.8,
        seed: 1033,
        spread: 1.2),
    GroveSpot(
        x: -56,
        z: _z + 7.6,
        y: groundY(_z + 7.6),
        scale: 1.75,
        seed: 1034,
        spread: 1.15),
    GroveSpot(
        x: 28.6,
        z: _z - 10.2,
        y: groundY(_z - 10.2),
        scale: 1.8,
        seed: 1035,
        spread: 1.2),
    GroveSpot(
        x: 40,
        z: _z + 8.4,
        y: groundY(_z + 8.4),
        scale: 1.7,
        seed: 1036,
        spread: 1.15),
  ]));
  final shrubs = <ShrubSpot>[];
  for (var i = 0; i < 7; i++) {
    shrubs.add(ShrubSpot(
        x: -50 + i * 6.4,
        z: _z - (_slabOut - .7),
        y: y0 + .05,
        r: .5,
        count: 4,
        spread: 1.6,
        seed: 1040 + i));
  }
  for (var i = 0; i < 5; i++) {
    shrubs.add(ShrubSpot(
        x: -46 + i * 9,
        z: _z + (_slabOut - .7),
        y: y0 + .05,
        r: .48,
        count: 3,
        spread: 1.5,
        seed: 1050 + i));
    shrubs.add(ShrubSpot(
        x: 11 + i * 6.2,
        z: _z + (_slabOut - .7),
        y: y0 + .05,
        r: .5,
        count: 4,
        spread: 1.6,
        seed: 1070 + i));
  }
  for (var i = 0; i < 4; i++) {
    shrubs.add(ShrubSpot(
        x: 15 + i * 8.6,
        z: _z - (_slabOut - .7),
        y: y0 + .05,
        r: .48,
        count: 3,
        spread: 1.5,
        seed: 1080 + i));
  }
  out.addAll(buildShrubs(shrubs));
}

List<Tri> buildCanalDetails({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final y0 = groundY(_z);
  final parts = <Part>[];
  final out = <Tri>[];
  _buildBanks(parts, out, y0);
  _buildFootbridge(parts, out, y0);
  _buildRoadBridge(parts, y0);
  _buildSlabCrossing(parts, y0);
  _buildSluice(parts, y0);
  _buildHeadwall(parts, true, y0);
  _buildHeadwall(parts, false, y0);
  _buildBankLife(
      parts, out, y0, blossomLightColor, blossomColor, blossomDeepColor);
  return [...bake(parts), ...out];
}
