/// Geometry port of the summer-festival setup ground from `matsuri.js`.
///
/// Structural geometry and deterministic placement follow the reference. The
/// canvas-backed banners, flags and stall lettering use their dominant panel
/// colours until the shared procedural-texture path is available.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'make_trees_other.dart';
import 'street.dart';

const _x0 = -45.0;
const _x1 = -31.4;
const _z0 = 13.8;
const _z1 = 25.0;
const _cx = (_x0 + _x1) / 2;
const _cz = (_z0 + _z1) / 2;

const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _dark = Mat(0x453f4f, tint: 0x4b4560, bands: '2');
const _wood = Mat(0xb09a76, tint: 0x5c5680, bands: '3');
const _woodDark = Mat(0x8a6f52, tint: 0x554e74, bands: '3');
const _cream = Mat(0xefe6d2, tint: 0x6f6790, bands: '3');
const _red = Mat(0xb5322f, tint: 0x7a4060, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _tarp = Mat(0xdcd4c0, tint: 0x6f6790, bands: '3');
const _dirt = Mat(0xc9bfae, tint: 0x6f6790, bands: '3');
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');

void _add(List<Part> parts, ThreeGeom geo, Matrix4 matrix, Mat mat) {
  parts.add(Part(geo, matrix, mat));
}

void _tube(List<Part> parts, Vector3 a, Vector3 b, double radius, Mat mat,
    {int segments = 6}) {
  final direction = b - a;
  final length = direction.length;
  if (length <= 1e-7) return;
  final mid = (a + b) * .5;
  final rotation = quatFromUnitVectors(Vector3(0, 1, 0), direction);
  _add(parts, cylGeometry(1, 1, 1, segments),
      composePRS(mid, rotation, Vector3(radius, length, radius)), mat);
}

void _sagLine(
    List<Part> parts, Vector3 a, Vector3 b, double sag, double radius, Mat mat,
    {int steps = 8}) {
  Vector3 point(int i) {
    final t = i / steps;
    final p = a + (b - a) * t;
    p.y -= math.sin(math.pi * t) * sag;
    return p;
  }

  var previous = point(0);
  for (var i = 1; i <= steps; i++) {
    final next = point(i);
    _tube(parts, previous, next, radius, mat, segments: 4);
    previous = next;
  }
}

/// Build the festival clearing and all of its setup-day props.
List<Tri> buildMatsuri() {
  final parts = <Part>[];
  final y = groundY(_cz);

  _add(parts, boxGeometry(_x1 - _x0, .06, _z1 - _z0), trs(_cx, y + .03, _cz),
      _dirt);
  _add(
      parts, boxGeometry(3.2, .06, 4.6), trs(_x1 - 1.6, y + .035, 18), _gravel);
  for (final z in [15.9, 23.1]) {
    _dashedLine(parts, Vector3(_x0 + 1.4, y + .071, z),
        Vector3(_x1 - 2.4, y + .071, z));
  }
  _dashedLine(parts, Vector3(_x0 + 1.2, y + .071, _z0 + 1.4),
      Vector3(_x0 + 1.2, y + .071, _z1 - 1.4));

  _buildEntrance(parts, y);
  _buildStalls(parts, y);
  _buildStage(parts, y);
  _buildLighting(parts, y);
  _buildTemporaries(parts, y);

  final out = bake(parts);
  out.addAll(buildGrove(const [
    GroveSpot(x: _x0 - 2.6, z: 17.2, scale: 1.75, seed: 9410, spread: 1.2),
    GroveSpot(x: _x0 - 1.8, z: 24.2, scale: 1.5, seed: 9411, spread: 1.1),
  ]));
  out.addAll(buildShrubs([
    for (var i = 0; i < 5; i++)
      ShrubSpot(
          x: _x0 + 1 + i * 3.1,
          z: _z1 + .8,
          r: .5,
          count: 3,
          spread: 1.3,
          seed: 9420 + i),
    for (var i = 0; i < 3; i++)
      ShrubSpot(
          x: _x0 + 2.2 + i * 4.4,
          z: _z0 - .9,
          r: .46,
          count: 3,
          spread: 1.2,
          seed: 9430 + i),
  ]));
  return out;
}

void _dashedLine(List<Part> p, Vector3 a, Vector3 b) {
  final delta = b - a;
  final length = delta.length;
  final count = (length / 1.8).ceil();
  for (var i = 0; i < count; i++) {
    final start = i * 1.8;
    final segment = math.min(.9, length - start);
    if (segment <= 0) continue;
    final center = a + delta.normalized() * (start + segment / 2);
    final angle = math.atan2(delta.x, delta.z);
    _add(p, boxGeometry(.035, .012, segment),
        trs(center.x, center.y, center.z, 0, angle), _cream);
  }
}

void _buildEntrance(List<Part> p, double y) {
  const bx = _x1 - .2, z0 = 15.7, z1 = 20.4;
  for (final z in [z0, z1]) {
    _add(p, cylGeometry(.07, .08, 4, 8), trs(bx, y + 2, z), _metal);
    _add(p, cylGeometry(.2, .24, .16, 8), trs(bx, y + .08, z), _concreteMid);
    final stake = Vector3(bx + 1.5, y + .05, z + (z == z0 ? -1.1 : 1.1));
    _sagLine(p, Vector3(bx, y + 3.6, z), stake, .06, .012, _metalDark);
    _add(p, cylGeometry(.02, .02, .3, 5), trs(stake.x, y + .12, stake.z),
        _metalDark);
  }
  _add(p, boxGeometry(.09, .09, z1 - z0 + .4), trs(bx, y + 3.72, (z0 + z1) / 2),
      _metal);
  // Six panels preserve the banner's shallow central cloth sag.
  const width = z1 - z0 - .1;
  for (var i = 0; i < 6; i++) {
    final z = z0 + .05 + width * (i + .5) / 6;
    final sag = .09 * (1 - ((i + .5) / 3 - 1).abs());
    _add(
        p,
        planeGeometry(width / 6 + .015, .72),
        trs(bx - .025, y + 3.28 - sag, z, 0, -math.pi / 2),
        i.isEven ? _cream : _red);
  }
  // Programme board and A-frame.
  const px = _x1 - 1.3, pz = 21.9;
  _add(p, boxGeometry(.1, 1.4, 1.02), trs(px, y + 1.35, pz, 0, -.22), _cream);
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(.1, 1.7, .1), trs(px + .12, y + .85, pz + s * .44),
        _woodDark);
    _add(p, boxGeometry(.08, 1.1, .08),
        trs(px + .42, y + .55, pz + s * .44, 0, 0, .5), _woodDark);
  }
  _add(p, boxGeometry(.1, .1, 1.1), trs(px + .12, y + 1.98, pz), _woodDark);
}

void _buildStalls(List<Part> p, double y) {
  const specs = [
    (-43.4, 23.4, math.pi, false, true, 0),
    (-39.0, 23.4, math.pi, true, true, 1),
    (-34.6, 23.4, math.pi, false, false, 3),
    (-42.0, 15.4, 0.0, false, true, 2),
    (-35.8, 15.4, 0.0, true, false, 4),
  ];
  for (final s in specs) {
    p.addAll(_stallParts(s.$1, y, s.$2,
        ry: s.$3, rolled: s.$4, sides: s.$5, sign: s.$6));
  }
}

List<Part> _stallParts(double x, double y, double z,
    {required double ry,
    required bool rolled,
    required bool sides,
    required int sign}) {
  const w = 2.6, d = 1.1, h = 2.15, counter = .9;
  final q = <Part>[];
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _add(q, cylGeometry(.032, .036, h, 7),
          trs(sx * (w / 2 - .08), h / 2, sz * (d / 2 - .06)), _metal);
      _add(q, boxGeometry(.11, .03, .11),
          trs(sx * (w / 2 - .08), .015, sz * (d / 2 - .06)), _dark);
    }
    _add(q, cylGeometry(.028, .028, d, 6),
        trs(sx * (w / 2 - .08), counter, 0, math.pi / 2), _metal);
  }
  for (final yy in [counter, h - .06]) {
    for (final sz in [-1.0, 1.0]) {
      _add(q, cylGeometry(.028, .028, w - .16, 6),
          trs(0, yy, sz * (d / 2 - .06), 0, 0, math.pi / 2), _metal);
    }
  }
  _add(q, boxGeometry(w, .05, d + .14), trs(0, counter + .025), _wood);
  _add(q, boxGeometry(w + .04, .3, .04), trs(0, counter - .15, d / 2 + .06),
      _wood);
  _add(q, boxGeometry(w - .2, .04, d - .2), trs(0, .38), _wood);

  if (rolled) {
    _add(q, cylGeometry(.14, .14, w - .1, 10),
        trs(0, h + .06, d / 2 - .02, 0, 0, math.pi / 2), _tarp);
  } else {
    const out = 1.0, drop = .3, stripes = 7;
    final angle = math.atan2(drop, out);
    for (var i = 0; i < stripes; i++) {
      final sw = w / stripes;
      final local = trs(-w / 2 + sw * (i + .5), 0, out / 2);
      final canopy = trs(0, h + .02, d / 2, angle) * local;
      _add(q, boxGeometry(sw, .05, out), canopy, i.isEven ? _red : _cream);
    }
  }
  _add(q, planeGeometry(w - .4, .34), trs(0, h - .3, d / 2 + .07),
      sign.isEven ? _cream : _red);
  if (sides) {
    for (final sx in [-1.0, 1.0]) {
      _add(
          q,
          planeGeometry(d + .1, h - counter - .12),
          trs(sx * (w / 2 - .07), (counter + h) / 2 - .02, 0, 0, math.pi / 2),
          _tarp);
    }
  }
  final transform = trs(x, y, z, 0, ry);
  return [
    for (final part in q) Part(part.geo, transform * part.matrix, part.mat)
  ];
}

void _buildStage(List<Part> p, double y) {
  const cx = -42.4, cz = 19.4, w = 3.6, h = .82;
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _add(
          p,
          boxGeometry(.14, h, .14),
          trs(cx + sx * (w / 2 - .14), y + h / 2, cz + sz * (w / 2 - .14)),
          _woodDark);
    }
  }
  const boards = 12;
  for (var i = 0; i < boards; i++) {
    _add(p, boxGeometry(w, .07, w / boards - .02),
        trs(cx, y + h + .035, cz - w / 2 + w * (i + .5) / boards), _wood);
  }
  // Red/white fascia on three visible sides.
  for (var i = 0; i < 12; i++) {
    final mat = i.isEven ? _red : _cream;
    for (final sz in [-1.0, 1.0]) {
      _add(
          p,
          boxGeometry(w / 12, .34, .05),
          trs(cx - w / 2 + w * (i + .5) / 12, y + h - .14,
              cz + sz * (w / 2 + .02)),
          mat);
    }
    _add(
        p,
        boxGeometry(.05, .34, w / 12),
        trs(cx - w / 2 - .02, y + h - .14, cz - w / 2 + w * (i + .5) / 12),
        mat);
  }
  // Three east-side steps.
  for (var i = 0; i < 3; i++) {
    final rise = (h + .07) / 3;
    _add(p, boxGeometry(.34, rise * (i + 1), 1.2),
        trs(cx + w / 2 + .17 + i * .34, y + rise * (i + 1) / 2, cz), _woodDark);
  }
  // Stage posts and overhead lantern frame.
  final posts = [
    (cx - w / 2 + .1, cz - w / 2 + .1),
    (cx + w / 2 - .1, cz - w / 2 + .1),
    (cx - w / 2 + .1, cz + w / 2 - .1),
    (cx + w / 2 - .1, cz + w / 2 - .1),
  ];
  for (final post in posts) {
    _add(p, boxGeometry(.1, 2.6, .1), trs(post.$1, y + h + .07 + 1.3, post.$2),
        _woodDark);
  }
  for (final z in [cz - w / 2 + .1, cz + w / 2 - .1]) {
    _add(p, boxGeometry(w - .2, .1, .1), trs(cx, y + h + .07 + 2.6, z),
        _woodDark);
  }
  // Taiko and stand.
  _add(
      p,
      cylGeometry(.42, .42, .5, 16),
      trs(cx, y + h + .79, cz, 0, 0, math.pi / 2),
      const Mat(0x9c5a3c, tint: 0x6f5680, bands: '3'));
  for (final sx in [-1.0, 1.0]) {
    _add(p, cylGeometry(.44, .44, .03, 16),
        trs(cx + sx * .26, y + h + .79, cz, 0, 0, math.pi / 2), _cream);
    _add(p, boxGeometry(.07, .9, .07),
        trs(cx + sx * .3, y + h + .41, cz, 0, 0, sx * .42), _woodDark);
  }
}

void _buildLighting(List<Part> p, double y) {
  const posts = [
    (_x0 + 1.2, _z0 + 1.4, 4.2),
    (_x0 + 1.2, _z1 - 1.4, 4.2),
    (_x1 - 2.6, _z0 + 1.4, 4.0),
    (_x1 - 2.6, _z1 - 1.4, 4.0),
  ];
  for (final post in posts) {
    _add(p, cylGeometry(.065, .08, post.$3, 8),
        trs(post.$1, y + post.$3 / 2, post.$2), _wood);
    _add(p, cylGeometry(.18, .22, .14, 8), trs(post.$1, y + .07, post.$2),
        _concreteMid);
  }
  Vector3 top((double, double, double) s) =>
      Vector3(s.$1, y + s.$3 - .45, s.$2);
  final stage = Vector3(-42.4, y + 3.49, 19.4);
  final tree = Vector3(-37.6, y + 4.15, 19.6);
  final runs = [
    (top(posts[0]), stage),
    (top(posts[1]), stage),
    (top(posts[2]), tree),
    (top(posts[3]), tree),
    (stage, tree),
    (top(posts[0]), top(posts[1])),
    (top(posts[2]), top(posts[3])),
  ];
  for (final run in runs) {
    final distance = (run.$2 - run.$1).length;
    final sag = math.min(.55, distance * .045);
    _sagLine(p, run.$1, run.$2, sag, .015, _dark, steps: 12);
    final count = math.max(2, (distance / 2.6).round());
    for (var i = 1; i <= count; i++) {
      final t = i / (count + 1);
      final q = run.$1 + (run.$2 - run.$1) * t;
      q.y -= math.sin(math.pi * t) * sag;
      _lantern(p, q.x, q.y - .16, q.z, i.isEven);
    }
  }
  // North-edge festival flags.
  final a = Vector3(_x0 + 1.2, y + 2.9, _z0 + .5);
  final b = Vector3(_x1 - 2.6, y + 2.9, _z0 + .5);
  _sagLine(p, a, b, .3, .013, _dark, steps: 12);
  for (var i = 1; i <= 11; i++) {
    final t = i / 12;
    final q = a + (b - a) * t;
    q.y -= math.sin(math.pi * t) * .3;
    _add(
        p,
        planeGeometry(.3, .42),
        trs(q.x, q.y - .24, q.z),
        i % 3 == 0
            ? _red
            : (i % 3 == 1 ? _cream : const Mat(0xf4c033, unlit: true)));
  }
}

void _lantern(List<Part> p, double x, double y, double z, bool alternate) {
  final mat = alternate ? _cream : _red;
  _add(p, cylGeometry(.13, .17, .26, 10), trs(x, y, z), mat);
  _add(p, cylGeometry(.08, .08, .035, 8), trs(x, y + .145, z), _metalDark);
  _add(p, cylGeometry(.08, .08, .035, 8), trs(x, y - .145, z), _metalDark);
}

void _buildTemporaries(List<Part> p, double y) {
  const bx = _x1 - 3.4, bz = _z1 - 1.6;
  _add(p, boxGeometry(1, .09, .8), trs(bx, y + .045, bz), _woodDark);
  _add(p, boxGeometry(.5, .7, .34), trs(bx, y + .44, bz),
      const Mat(0xc8ccd4, tint: 0x6a6288, bands: '3'));
  _add(p, boxGeometry(.56, .05, .4), trs(bx, y + .81, bz), _metalDark);
  _add(p, boxGeometry(.3, .24, .03), trs(bx, y + .52, bz - .18), _dark);
  final cable = [
    Vector3(bx - .3, y + .09, bz),
    Vector3(bx - 2.2, y + .05, bz - .6),
    Vector3(-38.6, y + .05, _z1 - 2.2),
    Vector3(-39, y + .05, 23),
    Vector3(-43.2, y + .05, 22.9),
  ];
  for (var i = 0; i + 1 < cable.length; i++) {
    _tube(p, cable[i], cable[i + 1], .026, _dark, segments: 5);
  }
  // Rope barrier, tags and cones at the apron.
  const ropeZ = 21.0;
  final ropePosts = <Vector3>[];
  for (var i = 0; i <= 3; i++) {
    final x = _x1 - 1 - i * 1.5;
    ropePosts.add(Vector3(x, y + .9, ropeZ));
    _add(p, cylGeometry(.03, .034, .95, 6), trs(x, y + .475, ropeZ), _metal);
    _add(
        p, cylGeometry(.13, .15, .06, 8), trs(x, y + .03, ropeZ), _concreteMid);
  }
  for (var i = 0; i + 1 < ropePosts.length; i++) {
    _sagLine(p, ropePosts[i], ropePosts[i + 1], .09, .014, _cream);
  }
  for (var i = 0; i < 6; i++) {
    _add(
        p,
        boxGeometry(.03, .2, .02),
        trs(_x1 - 1.4 - i * .75, y + .78, ropeZ, 0, 0, (i - 2.5) * .025),
        i.isEven ? _red : _cream);
  }
  // Folding tables and benches waiting to be placed.
  p.addAll(_foldingTable(-36.4, y, 20.6, .16));
  p.addAll(_foldingTable(-40.2, y, 17, -.4, folded: true));
  p.addAll(_foldingTable(-40, y, 17.5, -.32, folded: true));
}

List<Part> _foldingTable(double x, double y, double z, double ry,
    {bool folded = false}) {
  const w = 1.8, d = .6, h = .7;
  final q = <Part>[];
  if (folded) {
    final inner = trs(0, d / 2 * math.cos(.28) + .03, 0, math.pi / 2 - .28);
    _add(q, boxGeometry(w, .05, d), inner, _cream);
    for (final sx in [-1.0, 1.0]) {
      _add(q, boxGeometry(.05, .05, d - .14),
          inner * trs(sx * (w / 2 - .2), -.05), _metal);
    }
  } else {
    _add(q, boxGeometry(w, .05, d), trs(0, h), _cream);
    for (final sx in [-1.0, 1.0]) {
      for (final sz in [-1.0, 1.0]) {
        _add(q, cylGeometry(.02, .024, h, 6),
            trs(sx * (w / 2 - .16), h / 2, sz * (d / 2 - .1)), _metal);
      }
    }
  }
  final transform = trs(x, y, z, 0, ry);
  return [
    for (final part in q) Part(part.geo, transform * part.matrix, part.mat)
  ];
}
