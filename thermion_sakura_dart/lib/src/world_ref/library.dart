/// Geometry port of the community library from the reference `library.js`.
///
/// The structural geometry, openings, entrance sequence and forecourt use the
/// reference dimensions. Canvas-backed signs/interior plates are represented
/// by their dominant colours until the common texture path is available.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'make_props.dart';
import 'street.dart';

const _x0 = 11.0;
const _x1 = 20.6;
const _z0 = 50.6;
const _z1 = 57.6;
const _h1 = 3.4;
const _h2 = 2.9;
const _h = _h1 + _h2;
const _rec = 0.8;
const _bay0 = 12.0;
const _bay1 = 16.2;
const _rise = 0.30;
const _voidDepth = 2.2;

const _wall = Mat(0xf6f2e8, tint: 0x6f6790, bands: '3');
const _band = Mat(0xd6d2ca, tint: 0x6a6288, bands: '3');
const _wood = Mat(0xd2bb98, tint: 0x6f5680, bands: '3');
const _woodDark = Mat(0xa88a64, tint: 0x5c5680, bands: '3');
const _roof = Mat(0x59617a, tint: 0x514b70, bands: '3');
const _trim = Mat(0x8b8496, tint: 0x5c5680, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _stoneWarm = Mat(0xcfc6bc, tint: 0x655d80, bands: '3');
const _glass = Mat(0x9dc0d4, unlit: true);
const _interior = Mat(0x9a94a4, unlit: true);
const _warmLight = Mat(0xfff1d4, unlit: true);

void _add(List<Part> parts, ThreeGeom geo, Matrix4 matrix, Mat mat) {
  parts.add(Part(geo, matrix, mat));
}

/// Build the reference library and its immediately adjacent paved corner.
List<Tri> buildLibrary() {
  final parts = <Part>[];
  final y = groundY((_z0 + _z1) / 2);
  final fy = y + 0.07;
  final fl = fy + _rise;

  _buildForecourt(parts, y, fy);
  _buildBuilding(parts, y, fl);
  _buildEntrance(parts, y, fy, fl);
  _dressForecourt(parts, y, fy);
  _buildCorner(parts);
  return bake(parts);
}

void _buildForecourt(List<Part> p, double y, double fy) {
  _add(p, boxGeometry(12.6, 0.07, 3.8), trs(15.9, y + 0.035, 48.8), _concrete);
  _add(p, boxGeometry(12.6, 0.07, 1.1), trs(15.9, y + 0.04, 50.15), _stoneWarm);

  // The separate street-corner paving at the lane junction.
  final cy = groundY(48.0);
  _add(p, boxGeometry(5.0, 0.07, 2.6), trs(4.2, cy + 0.035, 48.1), _concrete);
  _add(p, boxGeometry(0.3, 0.05, 0.7), trs(2.05, cy + 0.102, 47.6),
      const Mat(0x6d687a, tint: 0x5d5878, bands: '3'));
}

void _buildBuilding(List<Part> p, double y, double fl) {
  const w = _x1 - _x0;
  const d = _z1 - _z0;
  const cx = (_x0 + _x1) / 2;
  const cz = (_z0 + _z1) / 2;
  const bz = _z0 + _rec;
  const vz = bz + _voidDepth;

  _add(p, boxGeometry(w + .24, .34, d + .24), trs(cx, y + .17, cz), _band);
  _add(p, boxGeometry(_bay0 - _x0, _h1, d),
      trs((_x0 + _bay0) / 2, y + _h1 / 2, cz), _wall);
  _add(p, boxGeometry(_x1 - _bay1, _h1, d),
      trs((_bay1 + _x1) / 2, y + _h1 / 2, cz), _wall);
  _add(p, boxGeometry(_bay1 - _bay0, _h1, _z1 - vz),
      trs((_bay0 + _bay1) / 2, y + _h1 / 2, (vz + _z1) / 2), _wall);
  for (final bounds in [(_bay0, _bay0 + .3), (_bay1 - .3, _bay1)]) {
    _add(p, boxGeometry(bounds.$2 - bounds.$1, _h1, _voidDepth),
        trs((bounds.$1 + bounds.$2) / 2, y + _h1 / 2, (bz + vz) / 2), _wall);
  }

  _add(
      p,
      boxGeometry(_bay1 - _bay0, _h1 - 2.92, _rec + _voidDepth),
      trs((_bay0 + _bay1) / 2, y + _h1 - (_h1 - 2.92) / 2, (_z0 + vz) / 2),
      _wood);
  _add(p, boxGeometry(_bay1 - _bay0 + .02, .08, _rec),
      trs((_bay0 + _bay1) / 2, y + 2.88, _z0 + _rec / 2), _wood);
  for (final bounds in [(_bay0, _bay0 + .16), (_bay1 - .16, _bay1)]) {
    _add(
        p,
        boxGeometry(bounds.$2 - bounds.$1, 2.9, _rec),
        trs((bounds.$1 + bounds.$2) / 2, y + 1.45, _z0 + _rec / 2 - .01),
        _wood);
  }
  _add(p, boxGeometry(_bay1 - _bay0 - 1.4, .05, .26),
      trs((_bay0 + _bay1) / 2, y + 2.82, _z0 + .3), _warmLight);

  _add(p, boxGeometry(_bay1 - _bay0, .1, _rec + _voidDepth + .1),
      trs((_bay0 + _bay1) / 2, fl - .05, (_z0 + vz) / 2 + .05), _band);
  _add(p, boxGeometry(w + .16, .16, d + .16), trs(cx, y + _h1, cz), _band);
  _add(p, boxGeometry(w, _h2, d), trs(cx, y + _h1 + _h2 / 2, cz), _wall);
  _add(
      p, boxGeometry(w + .06, .62, d + .06), trs(cx, y + _h1 + .42, cz), _wood);
  _add(p, boxGeometry(w + .5, .28, d + .5), trs(cx, y + _h + .14, cz), _band);
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(w + .3, .45, .18),
        trs(cx, y + _h + .51, cz + s * ((d + .3) / 2 - .09)), _wall);
    _add(p, boxGeometry(.18, .45, d + .3),
        trs(cx + s * ((w + .3) / 2 - .09), y + _h + .51, cz), _wall);
    _add(p, boxGeometry(w + .42, .07, .3),
        trs(cx, y + _h + .76, cz + s * ((d + .3) / 2 - .09)), _band);
    _add(p, boxGeometry(.3, .07, d + .42),
        trs(cx + s * ((w + .3) / 2 - .09), y + _h + .76, cz), _band);
  }
  _add(p, boxGeometry(w + .2, .12, d + .2), trs(cx, y + _h + .34, cz), _roof);

  // Rooftop plant.
  for (final dx in [-1.9, -.6]) {
    _add(p, boxGeometry(1, .7, .44), trs(cx + dx, y + _h + .75, cz + 1.6),
        _trim);
    _add(p, boxGeometry(1.04, .05, .5), trs(cx + dx, y + _h + 1.12, cz + 1.6),
        _metal);
  }
  _add(p, cylGeometry(.16, .16, .9, 10), trs(cx + 2.4, y + _h + .85, cz + 1.2),
      _metal);
  _add(p, cylGeometry(.2, .2, .08, 10), trs(cx + 2.4, y + _h + 1.32, cz + 1.2),
      _metal);

  for (var i = 0; i < 3; i++) {
    _window(p, x: _bay1 + .95 + i * 1.28, y: y + 1.95, z: _z0, w: 1, h: 2.1);
  }
  _window(p, x: _x0, y: y + 1.95, z: _z0 + 2.6, w: 1, h: 2, nx: -1, nz: 0);
  for (var i = 0; i < 5; i++) {
    _window(p,
        x: _x0 + w * (i + 1) / 6, y: y + _h1 + 1.72, z: _z0, w: 1.34, h: 1.72);
  }
  for (final zc in [_z0 + 2.2, _z0 + 4.8]) {
    _window(p, x: _x1, y: y + _h1 + 1.72, z: zc, w: 1.3, h: 1.7, nx: 1, nz: 0);
    _window(p, x: _x0, y: y + _h1 + 1.72, z: zc, w: 1.3, h: 1.7, nx: -1, nz: 0);
  }

  _buildGlazedFront(p, fl, bz);
  _buildVestibule(p, fl, bz, vz);

  // Name light box. The texture face is presently its exact warm base colour.
  _add(p, boxGeometry(4.14, .82, .18),
      trs((_bay0 + _bay1) / 2, y + 3.18, _z0 - .08), _metalDark);
  _add(
      p,
      boxGeometry(4, .62, .24),
      trs((_bay0 + _bay1) / 2, y + 3.18, _z0 - .15),
      const Mat(0xfff0d2, unlit: true));
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(.2, .07, .42),
        trs((_bay0 + _bay1) / 2 + s * 1.5, y + 3.66, _z0 - .19), _metalDark);
    _add(p, boxGeometry(.16, .04, .16),
        trs((_bay0 + _bay1) / 2 + s * 1.5, y + 3.62, _z0 - .37), _warmLight);
  }
}

void _window(
  List<Part> p, {
  required double x,
  required double y,
  required double z,
  required double w,
  required double h,
  double nx = 0,
  double nz = -1,
}) {
  final along = nx != 0;
  (double, double) at(double depth) => (x + nx * depth, z + nz * depth);
  ThreeGeom bx(double t, double ww, double hh) =>
      along ? boxGeometry(t, hh, ww) : boxGeometry(ww, hh, t);

  var q = at(-.02);
  _add(p, bx(.14, w + .16, h + .16), trs(q.$1, y, q.$2), _trim);
  q = at(.055);
  _add(p, bx(.015, w, h), trs(q.$1, y, q.$2), _interior);
  q = at(.085);
  _add(p, bx(.04, w, h), trs(q.$1, y, q.$2), _glass);
  q = at(.1);
  _add(p, bx(.09, .06, h), trs(q.$1, y, q.$2), _metal);
  _add(p, bx(.09, w, .07), trs(q.$1, y + h * .22, q.$2), _metal);
  _add(p, bx(.1, w + .12, .08), trs(q.$1, y + h / 2 + .04, q.$2), _metal);
  q = at(.11);
  _add(p, bx(.24, w + .24, .1), trs(q.$1, y - h / 2 - .1, q.$2), _band);
}

void _buildGlazedFront(List<Part> p, double fl, double bz) {
  const ow = _bay1 - _bay0 - .6;
  const ox = (_bay0 + _bay1) / 2;
  const oh = 2.42;
  final oy = fl + oh / 2;
  _add(p, boxGeometry(ow + .16, .12, .16), trs(ox, fl + oh + .06, bz), _metal);
  _add(p, boxGeometry(ow + .16, .1, .16), trs(ox, fl + .02, bz), _metal);
  for (var i = 0; i <= 4; i++) {
    final t = -ow / 2 + ow / 4 * i;
    _add(p, boxGeometry(i == 1 || i == 3 ? .1 : .06, oh, .14),
        trs(ox + t, oy, bz), _metal);
  }
  _add(p, boxGeometry(ow, oh, .04), trs(ox, oy, bz + .02), _glass);
  for (final s in [-1.0, 1.0]) {
    _add(p, cylGeometry(.018, .018, .9, 6),
        trs(ox + s * (ow / 8 + .06), fl + 1.15, bz - .09), _metalDark);
  }
}

void _buildVestibule(List<Part> p, double fl, double bz, double vz) {
  const bx = (_bay0 + _bay1) / 2;
  _add(p, boxGeometry(_bay1 - _bay0 - .6, 2.5, .02),
      trs(bx, fl + 1.3, vz - .03), _interior);
  _add(p, boxGeometry(_bay1 - _bay0 - .6, .08, _voidDepth - .1),
      trs(bx, fl + 2.6, bz + _voidDepth / 2), _band);
  _add(p, boxGeometry(1.5, .04, .34), trs(bx, fl + 2.54, bz + .9), _warmLight);
  _add(p, boxGeometry(2.4, 1.02, .5), trs(bx + .5, fl + .51, vz - .4), _wood);
  _add(p, boxGeometry(2.56, .07, .62), trs(bx + .5, fl + 1.05, vz - .4), _band);
  for (final s in [-1.0, 1.0]) {
    final sx = bx + s * ((_bay1 - _bay0) / 2 - .5);
    _add(p, boxGeometry(.36, 1.9, 1.5), trs(sx, fl + .95, bz + 1), _woodDark);
    for (var row = 0; row < 4; row++) {
      _add(p, boxGeometry(.4, .05, 1.5), trs(sx, fl + .34 + row * .44, bz + 1),
          _wood);
    }
  }
}

void _buildEntrance(List<Part> p, double y, double fy, double fl) {
  const rampW = 1.3;
  const rampZ = 49.9;
  const tx0 = 11.7, tx1 = 17.8;
  const tz1 = _z0 + .225;
  const tz0 = tz1 - rampW;
  _add(p, boxGeometry(tx1 - tx0, .1, rampW),
      trs((tx0 + tx1) / 2, fl - .05, (tz0 + tz1) / 2), _stoneWarm);
  _add(p, boxGeometry(tx1 - tx0, _rise, .12),
      trs((tx0 + tx1) / 2, fy + _rise / 2, tz0 + .005), _band);

  const stepX = (_bay0 + _bay1) / 2;
  const stepRun = .44;
  const stepZ = tz0 - 2 * stepRun + .05;
  for (var i = 0; i < 2; i++) {
    final hh = _rise / 2 * (i + 1);
    _add(p, boxGeometry(rampW, hh, stepRun),
        trs(stepX, fy + hh / 2, stepZ + stepRun * (i + .5)), _stoneWarm);
  }
  for (final s in [-1.0, 1.0]) {
    _add(
        p,
        boxGeometry(.16, _rise + .06, .94),
        trs(stepX + s * (rampW / 2 + .08), fy + (_rise + .06) / 2,
            stepZ + stepRun),
        _band);
  }

  const rx0 = 20.6;
  const rx1 = tx1 - .4;
  const len = rx0 - rx1;
  final tilt = math.atan2(_rise, len);
  _add(
      p,
      boxGeometry(len / math.cos(tilt), .12, rampW),
      trs((rx0 + rx1) / 2, fy + _rise / 2 - .02, rampZ, 0, 0, -tilt),
      _concrete);
  _add(
      p,
      boxGeometry(len / math.cos(tilt), .2, .14),
      trs((rx0 + rx1) / 2, fy + _rise / 2 + .06, rampZ - rampW / 2 - .07, 0, 0,
          -tilt),
      _band);
  const railH = .88;
  for (var i = 0; i <= 4; i++) {
    final t = i / 4;
    _add(
        p,
        cylGeometry(.026, .03, railH, 6),
        trs(rx0 - len * t, fy + _rise * t + railH / 2, rampZ - rampW / 2 - .07),
        _metal);
  }
  for (final dy in [railH - .02, railH * .52]) {
    _add(
        p,
        cylGeometry(.028, .028, math.sqrt(len * len + _rise * _rise) + .1, 6),
        trs((rx0 + rx1) / 2, fy + _rise / 2 + dy, rampZ - rampW / 2 - .07, 0, 0,
            math.pi / 2 - tilt),
        _metal);
  }

  const cw = _bay1 - _bay0 + .5;
  const cx = (_bay0 + _bay1) / 2;
  const canopyZ = 49.3;
  _add(p, boxGeometry(cw, .14, _z0 - canopyZ + .1),
      trs(cx, y + 2.86, (canopyZ + _z0) / 2), _band);
  _add(p, boxGeometry(cw - .16, .04, _z0 - canopyZ - .06),
      trs(cx, y + 2.78, (canopyZ + _z0) / 2), _wood);
  _add(p, boxGeometry(cw + .06, .24, .1), trs(cx, y + 2.82, canopyZ - .02),
      _wall);
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(.12, 2.8, .12),
        trs(cx + s * (cw / 2 - .22), y + 1.4, canopyZ + .14), _metal);
    _add(p, boxGeometry(.22, .1, .22),
        trs(cx + s * (cw / 2 - .22), y + .05, canopyZ + .14), _band);
  }
  _add(p, cylGeometry(.045, .045, 2.8, 6),
      trs(cx - cw / 2 + .06, y + 1.4, canopyZ + .06), _metal);
}

void _dressForecourt(List<Part> p, double y, double fy) {
  // Tree pits at the exact positions of the two reference street cherries.
  for (final spot in [(12.6, 48.0), (20.4, 48.4)]) {
    _add(p, boxGeometry(1.1, .06, 1.1), trs(spot.$1, fy + .012, spot.$2),
        const Mat(0x8f7a62, tint: 0x615a80, bands: '3'));
    for (final s in [-1.0, 1.0]) {
      _add(p, boxGeometry(1.24, .1, .14),
          trs(spot.$1, fy + .03, spot.$2 + s * .62), _concreteMid);
      _add(p, boxGeometry(.14, .1, 1.24),
          trs(spot.$1 + s * .62, fy + .03, spot.$2), _concreteMid);
    }
  }

  // Two simple reference-size benches.
  for (final x in [14.0, 16.4]) {
    _add(p, boxGeometry(1.8, .12, .42), trs(x, fy + .48, 47.4), _wood);
    _add(p, boxGeometry(1.8, .48, .1), trs(x, fy + .76, 47.58), _wood);
    for (final s in [-1.0, 1.0]) {
      _add(p, boxGeometry(.1, .48, .1), trs(x + s * .68, fy + .24, 47.4),
          _metalDark);
    }
  }

  // Forecourt lamp and its shallow cone shade.
  const lx = 18.7, lz = 47.5;
  _add(p, cylGeometry(.055, .07, 4, 8), trs(lx, fy + 2, lz), _metalDark);
  _add(p, cylGeometry(.13, .16, .18, 8), trs(lx, fy + .09, lz), _concreteMid);
  _add(p, boxGeometry(.06, .06, .62), trs(lx, fy + 3.96, lz - .28), _metalDark);
  _add(p, cylGeometry(0, .28, .22, 12, openEnded: true),
      trs(lx, fy + 3.86, lz - .56), _metal);
  _add(p, boxGeometry(.22, .05, .22), trs(lx, fy + 3.73, lz - .56), _warmLight);

  // Planters provide the small colour punctuation visible at this distance.
  for (final spec in [(12.3, 50.2, .26), (17.0, 47.0, .22)]) {
    p.addAll(_partsFromTris(makePlanter(
      x: spec.$1,
      y: fy,
      z: spec.$2,
      r: spec.$3,
      flower: true,
      seed: 5550 + (spec.$1 * 10).round(),
      n: 5,
    )));
  }
}

void _buildCorner(List<Part> p) {
  final y = groundY(48.0) + .07;
  // Phone booth structural shell, at the reference position/yaw.
  final booth = <Part>[];
  const red = Mat(0xe0453f, tint: 0x7a4060, bands: '3');
  const darkGlass = Mat(0x53627a, unlit: true);
  _add(booth, boxGeometry(1.0, .12, 1.0), trs(0, 2.6), red);
  _add(booth, boxGeometry(1.0, .12, 1.0), trs(0, .06), red);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _add(booth, boxGeometry(.1, 2.5, .1), trs(sx * .45, 1.31, sz * .45), red);
    }
  }
  _add(booth, boxGeometry(.78, 2.28, .025), trs(0, 1.31, -.49), darkGlass);
  _add(booth, boxGeometry(.025, 2.28, .78), trs(.49, 1.31, 0), darkGlass);
  final boothMx = trs(3.5, y, 48.6, 0, .34);
  for (final part in booth) {
    p.add(Part(part.geo, boothMx * part.matrix, part.mat));
  }

  p.addAll(_partsFromTris(
      makeGuardrail(x: 2.0, y: y, z: 48.4, ry: math.pi / 2, len: 3.4)));
  for (final spec in [
    (2.5, 47.2, .24, true, 5570),
    (2.4, 49.6, .2, false, 5571)
  ]) {
    p.addAll(_partsFromTris(makePlanter(
      x: spec.$1,
      y: y,
      z: spec.$2,
      r: spec.$3,
      flower: spec.$4,
      seed: spec.$5,
      n: spec.$4 ? 5 : 4,
    )));
  }
}

/// Convert already baked triangles back to identity parts so this module can
/// keep one final bake path without losing their material tags.
List<Part> _partsFromTris(List<Tri> tris) => [
      for (final tri in tris)
        Part(
          ThreeGeom(
            Float32List.fromList([
              tri.a.x,
              tri.a.y,
              tri.a.z,
              tri.b.x,
              tri.b.y,
              tri.b.z,
              tri.c.x,
              tri.c.y,
              tri.c.z,
            ]),
            Float32List.fromList([
              tri.normal.x,
              tri.normal.y,
              tri.normal.z,
              tri.normal.x,
              tri.normal.y,
              tri.normal.z,
              tri.normal.x,
              tri.normal.y,
              tri.normal.z,
            ]),
            const [0, 1, 2],
          ),
          Matrix4.identity(),
          tri.mat,
        ),
    ];
