/// Composition-first port of `nanachome.js` (ひばり台七丁目).
///
/// This module concentrates on the street-level supermarket view: the exact
/// building envelope and recessed entrance, shopfront glazing, fascia and
/// canopy, plus the busy forecourt that makes the large shed read as a local
/// food market. The roof deck and rear service yard can be filled out without
/// changing this owned Dart facade geometry.
library;

import 'dart:math' as math;

import '../geom/three_geom.dart';
import 'details.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'petals.dart';
import 'sign_atlas.dart';

const _y = .45;
const _wall = Mat(0xf6f1e4, tint: 0x6f6790, bands: '3');
const _wallUnlit = Mat(0xfbf9f3, unlit: true);
const _wallGrey = Mat(0xe2e0e4, tint: 0x6f6790, bands: '3');
const _band = Mat(0x59617a, tint: 0x514b70, bands: '3');
const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _concreteDark = Mat(0xa7a2b0, tint: 0x655d84, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
// Opaque approximation of the reference's 42%-alpha blue glazing over its
// warm interior texture.
const _glass = Mat(0xbcc5c7, unlit: true, noOutline: true);
const _glassDark = Mat(0x59627a, tint: 0x4b4560, bands: '3');
const _warm = Mat(0xffedc5, unlit: true, noOutline: true);
const _white = Mat(0xfaf6ef, tint: 0x8e86ad, bands: '2');
const _wood = Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');
const _benchWood = Mat(0xb29678, tint: 0x6f6790, bands: '3');
const _soil = Mat(0x8f7a62, tint: 0x615a80, bands: '3');
const _cartBasket = Mat(0xb6bcc6, tint: 0x666090, bands: '3');
const _crateBlue = Mat(0x3f7fbf, tint: 0x4a4a92, bands: '3');
const _asphaltWorn = Mat(0x9a95a6, tint: 0x5b5677, bands: '3');
const _lineWhite = Mat(0xf4f2f6, unlit: true, noOutline: true);
const _lineYellow = Mat(0xf4c033, unlit: true, noOutline: true);
const _gravel = Mat(0xa9a394, tint: 0x625c78, bands: '3');

void _box(List<Part> p, double w, double h, double d, Mat m, double x, double y,
    double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  p.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), m));
}

void _cyl(List<Part> p, double r, double h, int n, Mat m, double x, double y,
    double z) {
  p.add(Part(cylGeometry(r, r, h, n), trs(x, y, z), m));
}

void _trolleys(List<Part> p, double x, double z, int count) {
  const baseY = _y + .09;
  for (var i = 0; i < count; i++) {
    final dz = i * .30;
    _box(p, .48, .34, .62, _cartBasket, x, baseY + .62, z + dz);
    _box(p, .50, .05, .05, _metal, x, baseY + .94, z + dz + .30);
    for (final side in [-1.0, 1.0]) {
      p.add(Part(cylGeometry(.018, .018, .62, 6),
          trs(x + side * .21, baseY + .31, z + dz + .24, .14), _metal));
      p.add(Part(cylGeometry(.018, .018, .50, 6),
          trs(x + side * .21, baseY + .25, z + dz - .24), _metal));
      for (final wheelZ in [-.24, .24]) {
        p.add(Part(
            cylGeometry(.05, .05, .04, 8),
            trs(x + side * .20, baseY + .05, z + dz + wheelZ, 0, 0, 1.5708),
            _metalDark));
      }
    }
  }
}

void _shopWindow(List<Part> p, double x0, double x1) {
  const sill = 1.07, head = 4.05, z = 82.11;
  final cx = (x0 + x1) / 2;
  final w = x1 - x0;
  // The exact glazed source artwork is appended after the solid facade bake;
  // this helper now owns only the glass thickness and mullion geometry.
  _box(p, w, head - sill, .045, _glass, cx, (head + sill) / 2, z + .035);
  final panes = (w / 1.8).round();
  for (var i = 0; i <= panes; i++) {
    _box(p, .095, head - sill + .12, .11, _metalDark, x0 + i * w / panes,
        (head + sill) / 2, z + .09);
  }
  _box(p, w + .1, .13, .12, _metalDark, cx, head, z + .09);
  _box(p, w + .1, .13, .12, _metalDark, cx, sill, z + .09);
  // Rendered plinth below the glazing.  The source carries this separate
  // 460 mm band in front of the building mass; omitting it left the windows
  // apparently floating on the apron and removed a long facade edge.
  _box(p, w + .24, sill - _y - .16, .14, _concrete, cx, (_y + .16 + sill) / 2,
      z + .03);
}

void _priceSheet(List<Part> p, double x, double y, int variant) {
  const z = 82.205;
  _box(p, .62, .88, .035, _white, x, y, z);
  _box(p, .54, .11, .025, _metal, x, y + .29, z + .025);
  for (var row = 0; row < 3; row++) {
    final count = 2 + ((row + variant) % 3);
    for (var i = 0; i < count; i++) {
      _box(p, .07 + ((i + variant) % 2) * .035, .035, .02, _concreteDark,
          x - .18 + i * .13, y + .10 - row * .13, z + .03);
    }
  }
}

List<Tri> _store() {
  final p = <Part>[];
  const sx0 = -48.6, sx1 = -27.0, sz0 = 65.6, sz1 = 82.0;
  const rec0 = -41.4, rec1 = -33.4, rec = 1.6;
  const deck = 6.2;
  final cx = (sx0 + sx1) / 2;

  // The solid volume is split around the recessed automatic doors.
  _box(p, sx1 - sx0, 5.65, sz1 - sz0 - rec, _wall, cx, _y + 2.825,
      (sz0 + sz1 - rec) / 2);
  _box(p, rec0 - sx0, 5.65, rec, _wall, (sx0 + rec0) / 2, _y + 2.825,
      sz1 - rec / 2);
  _box(p, sx1 - rec1, 5.65, rec, _wall, (rec1 + sx1) / 2, _y + 2.825,
      sz1 - rec / 2);
  _box(p, rec1 - rec0, 1.75, rec, _wall, (rec0 + rec1) / 2, 5.225,
      sz1 - rec / 2);
  _box(p, rec1 - rec0, .3, rec, _wallGrey, (rec0 + rec1) / 2, 4.20,
      sz1 - rec / 2);
  _box(p, rec1 - rec0 + .2, .12, rec + .12, _concrete, (rec0 + rec1) / 2,
      _y + .11, sz1 - rec / 2 + .06);

  // Four-part facade banding and the roof-car-park parapet.
  _box(p, sx1 - sx0 + .44, 1.10, .24, _band, cx, _y + 4.85, sz1 + .12);
  _box(p, sx1 - sx0 + .30, .14, .16, _wallGrey, cx, _y + 4.23, sz1 + .08);
  _box(p, sx1 - sx0 + .16, .65, .10, _wallGrey, cx, _y + 5.52, sz1 + .05);
  _box(p, sx1 - sx0, .80, .28, _wallGrey, cx, deck + .40, sz1 - .14);
  _box(p, sx1 - sx0 + .12, .12, .40, _band, cx, deck + .86, sz1 - .14);
  _box(p, sx1 - sx0 + .22, .16, sz1 - sz0 + .22, _concrete, cx, _y + .08,
      (sz0 + sz1) / 2);

  _shopWindow(p, sx0 + .9, rec0 - .3);
  _shopWindow(p, rec1 + .3, sx1 - .9);
  for (final sheet in const <(double, double, int)>[
    (-46.2, 2.30, 0),
    (-44.5, 2.00, 1),
    (-31.6, 2.25, 2),
    (-29.6, 1.95, 3),
  ]) {
    _priceSheet(p, sheet.$1, sheet.$2, sheet.$3);
  }

  // Lobby interior, two sliding leaves, side lights, mat and lit soffit.
  const ez = sz1 - rec;
  _box(p, rec1 - rec0 - .3, .07, .50, _warm, (rec0 + rec1) / 2, 4.24,
      ez + rec / 2);
  for (final s in [-1.0, 1.0]) {
    _box(p, 1.55, 3.18, .06, _glass, (rec0 + rec1) / 2 + s * 1.62, 2.24,
        ez + .12);
    for (final edge in [-.80, .80]) {
      _box(p, .09, 3.30, .12, _metalDark, (rec0 + rec1) / 2 + s * (1.62 + edge),
          2.30, ez + .14);
    }
    final sw = (rec1 - rec0) / 2 - 2.42;
    _box(p, sw, 3.18, .05, _glass, (rec0 + rec1) / 2 + s * (2.42 + sw / 2),
        2.24, ez + .10);
  }
  _box(p, rec1 - rec0 - .2, .16, .18, _metalDark, (rec0 + rec1) / 2, 3.89,
      ez + .14);
  _box(p, rec1 - rec0 - .2, .10, .12, _metalDark, (rec0 + rec1) / 2, 3.55,
      ez + .18);
  _box(p, rec1 - rec0 - .2, .12, .16, _metalDark, (rec0 + rec1) / 2, .65,
      ez + .14);
  _box(p, 2.4, .035, .9, _glassDark, (rec0 + rec1) / 2, _y + .19, 81.30);

  // Full-depth entrance reveals.  These are visible as the shaded vertical
  // returns on either side of the recessed automatic doors.
  for (final x in [rec0 + .06, rec1 - .06]) {
    _box(p, .12, 3.90, rec, _wallGrey, x, _y + 1.95, sz1 - rec / 2);
  }

  // Cream sign face set over the blue-grey building band.
  _box(p, 12.8, 1.60, .18, _wallUnlit, (rec0 + rec1) / 2, 5.35, sz1 + .30);
  for (final s in [-1.0, 1.0]) {
    final lx = (rec0 + rec1) / 2 + s * 4.6;
    _box(p, .08, .08, .62, _metalDark, lx, _y + 5.40 + .34, sz1 + .42);
    _box(p, .46, .14, .20, _metal, lx, _y + 5.40 + .28, sz1 + .70);
  }

  // Canopy: four posts, paired beams, purlins and a gently falling roof.
  const cx0 = sx0 + .6, cx1 = sx1 - .6, frontZ = sz1 + 2.90;
  for (var i = 0; i < 4; i++) {
    final x = cx0 + 1.4 + i * ((cx1 - cx0 - 2.8) / 3);
    _box(p, .17, 3.57, .17, _metalDark, x, _y + 1.785, frontZ - .34);
    _box(p, .34, .10, .34, _metal, x, _y + .05, frontZ - .34);
  }
  _box(p, cx1 - cx0 + .2, .26, .18, _metalDark, (cx0 + cx1) / 2, 3.94,
      frontZ - .34);
  _box(p, cx1 - cx0 + .2, .22, .16, _metalDark, (cx0 + cx1) / 2, 4.29,
      sz1 + .14);
  for (var i = 0; i <= 10; i++) {
    _box(p, .09, .14, 2.95, _metal, cx0 + (cx1 - cx0) * i / 10, 3.785,
        (sz1 + frontZ) / 2, .112);
  }
  _box(
      p,
      cx1 - cx0 + .24,
      .16,
      2.94,
      const Mat(0xdfe4ea, tint: 0x6f6790, bands: '3'),
      (cx0 + cx1) / 2,
      4.215,
      (sz1 + frontZ) / 2,
      .112);
  _box(
      p, cx1 - cx0 + .3, .15, .17, _metal, (cx0 + cx1) / 2, 3.79, frontZ + .06);
  for (final x in [cx0 + 1.4, cx1 - 1.4]) {
    _cyl(p, .055, 3.20, 8, _metal, x + .16, _y + 1.60, frontZ + .06);
  }

  final out = bake(p);
  appendSignAtlasPlane(out, superInteriorCheckoutRegion,
      width: 6.0, height: 2.98, matrix: trs(-44.7, 2.56, 82.205));
  appendSignAtlasPlane(out, superInteriorChillerRegion,
      width: 5.2, height: 2.98, matrix: trs(-30.5, 2.56, 82.205));
  appendSignAtlasPlane(out, superInteriorCheckoutRegion,
      width: 7.6, height: 3.32, matrix: trs(-37.4, 2.25, 80.556));
  appendSignAtlasPlane(out, superFasciaRegion,
      width: 12.8, height: 1.6, matrix: trs(-37.4, 5.35, 82.3901));
  appendSignAtlasPlane(out, superHoursRegion,
      width: .52, height: .70, matrix: trs(rec0 - .62, _y + 1.62, 82.205));
  const posterRegions = [
    superPoster0Region,
    superPoster1Region,
    superPoster2Region,
    superPoster3Region,
  ];
  const posterPositions = [
    (-46.2, 2.30),
    (-44.5, 2.00),
    (-31.6, 2.25),
    (-29.6, 1.95),
  ];
  for (var i = 0; i < posterRegions.length; i++) {
    appendSignAtlasPlane(out, posterRegions[i],
        width: .62,
        height: .88,
        matrix: trs(posterPositions[i].$1, posterPositions[i].$2, 82.206, 0, 0,
            i.isOdd ? .012 : -.012));
  }
  const bannerRegions = [
    superBannerSpecialRegion,
    superBannerProduceRegion,
    superBannerPointsRegion,
  ];
  for (var i = 0; i < bannerRegions.length; i++) {
    final bx = cx0 + 3.4 + i * ((cx1 - cx0 - 6.8) / 2);
    appendSignAtlasPlane(out, bannerRegions[i],
        width: 3.10, height: .58, matrix: trs(bx, 3.33, frontZ - .42, .04));
  }
  return out;
}

/// The supermarket's roof parking and the two-flight 1:6 access ramp.
///
/// Traffic already places six vehicles at deck level, so omitting this module
/// left them suspended over the store. The dimensions here follow
/// `nanachome.js::buildRamp/buildDeck`, including the landing arithmetic that
/// lets the second flight meet the roof through the south parapet opening.
List<Tri> _roofParkingAndRamp() {
  final p = <Part>[];
  const deck = 6.20;
  const rw = 4.60;
  const ex0 = -27.0, ex1 = -22.4, ex = -24.7;
  const southZ0 = 61.0, southZ1 = 65.6, southZ = 63.3;
  const rampFootZ = 84.2;
  const cornerY = 3.55;
  const rampTopX = -42.9;
  const entryX0 = -47.5;
  const slabT = .34;

  void rampFlight({
    required String axis,
    required double from,
    required double to,
    required double at,
    required double y0,
    required double y1,
  }) {
    final run = (to - from).abs();
    final rise = y1 - y0;
    final dir = (to - from).sign;
    final tilt = math.atan2(rise, run);
    final len = math.sqrt(run * run + rise * rise);
    final mid = (from + to) / 2;
    final yMid = (y0 + y1) / 2;
    final rx = axis == 'z' ? -tilt * dir : 0.0;
    final rz = axis == 'x' ? tilt * dir : 0.0;
    _box(
        p,
        axis == 'x' ? len : rw,
        slabT,
        axis == 'x' ? rw : len,
        _concrete,
        axis == 'x' ? mid : at,
        yMid - slabT / 2,
        axis == 'x' ? at : mid,
        rx,
        0,
        rz);

    for (final side in [-1.0, 1.0]) {
      _box(
          p,
          axis == 'x' ? len : .30,
          .62,
          axis == 'x' ? .30 : len,
          _concreteDark,
          axis == 'x' ? mid : at + side * (rw / 2 - .15),
          yMid + .25,
          axis == 'x' ? at + side * (rw / 2 - .15) : mid,
          rx,
          0,
          rz);
    }

    // Sparse structural piers at the same quarter points as the source's
    // collider segmentation. They make both elevated legs read as supported.
    for (final t in [.28, .53, .78]) {
      final along = from + (to - from) * t;
      final top = y0 + rise * t - slabT;
      if (top - _y < 1.4) continue;
      _box(p, .44, top - _y, .44, _concreteDark, axis == 'x' ? along : at,
          (_y + top) / 2, axis == 'x' ? at : along);
      _box(p, .66, .18, .66, _concrete, axis == 'x' ? along : at, _y + .09,
          axis == 'x' ? at : along);
    }
  }

  void landing(double x0, double x1, double z0, double z1, double y,
      List<String> walls) {
    _box(p, x1 - x0, slabT, z1 - z0, _concrete, (x0 + x1) / 2, y - slabT / 2,
        (z0 + z1) / 2);
    for (final side in walls) {
      if (side == 'z-') {
        _box(p, x1 - x0, .62, .30, _concreteDark, (x0 + x1) / 2, y + .25,
            z0 + .15);
      } else if (side == 'x+') {
        _box(p, .30, .62, z1 - z0, _concreteDark, x1 - .15, y + .25,
            (z0 + z1) / 2);
      } else if (side == 'x-') {
        _box(p, .30, .62, z1 - z0, _concreteDark, x0 + .15, y + .25,
            (z0 + z1) / 2);
      }
    }
    if (y - slabT - _y > 1.4) {
      for (final x in [x0 + .7, x1 - .7]) {
        for (final z in [z0 + .7, z1 - .7]) {
          final h = y - slabT - _y;
          _box(p, .50, h, .50, _concreteDark, x, _y + h / 2, z);
          _box(p, .74, .18, .74, _concrete, x, _y + .09, z);
        }
      }
    }
  }

  rampFlight(
      axis: 'z', from: rampFootZ, to: southZ1, at: ex, y0: _y, y1: cornerY);
  landing(ex0, ex1, southZ0, southZ1, cornerY, const ['z-', 'x+']);
  rampFlight(
      axis: 'x', from: ex0, to: rampTopX, at: southZ, y0: cornerY, y1: deck);
  landing(entryX0, rampTopX, southZ0, southZ1, deck, const ['z-', 'x-']);

  // Transverse anti-slip grooves are the strongest depth cue on the long
  // slopes. Their y positions follow the exact one-in-six surface.
  for (var i = 1; i < (rampFootZ - southZ1) / .42; i++) {
    final z = rampFootZ - i * .42;
    final y = _y + (rampFootZ - z) / 6;
    _box(p, rw - .66, .02, .09, _concreteDark, ex, y + .02, z);
  }
  for (var i = 1; i < (ex0 - rampTopX) / .42; i++) {
    final x = ex0 - i * .42;
    final y = cornerY + (ex0 - x) / 6;
    _box(p, .09, .02, rw - .66, _concreteDark, x, y + .02, southZ);
  }

  // 制限高 2.1 m gantry at the apron mouth.
  const barZ = 85.60;
  for (final side in [-1.0, 1.0]) {
    _cyl(p, .08, 2.62, 8, _metalDark, ex + side * (rw / 2 - .10), _y + 1.31,
        barZ);
  }
  _box(p, rw - .1, .16, .10, _metalDark, ex, _y + 2.55, barZ);
  _box(p, rw - .6, .12, .13, _lineYellow, ex, _y + 2.10, barZ - .06);
  for (var i = 0; i < 7; i++) {
    _box(p, .34, .22, .03, _metalDark, ex - rw / 2 + .5 + i * .6, _y + 1.93,
        barZ - .06);
  }

  // Asphalt roof slab over the complete store footprint.
  _box(p, 21.6, .10, 16.4, _asphaltWorn, -37.8, deck - .05, 73.8);

  const x0 = -48.32, x1 = -27.28, z0 = 65.88, z1 = 81.72;
  const bayD = 5.0, bayW = 2.4, accessibleW = 3.4;
  const serviceX1 = -45.90;
  final north = <(double, double)>[];
  var nx = serviceX1;
  north.add((nx, nx + accessibleW));
  nx += accessibleW;
  for (var i = 0; i < 6; i++) {
    north.add((nx, nx + bayW));
    nx += bayW;
  }
  final south = <(double, double)>[];
  var sx = rampTopX + .30;
  for (var i = 0; i < 5; i++) {
    south.add((sx, sx + bayW));
    sx += bayW;
  }
  for (final row in [north, south]) {
    final isNorth = identical(row, north);
    final near = isNorth ? z1 - bayD : z0;
    final far = isNorth ? z1 : z0 + bayD;
    for (final bay in row) {
      for (final x in [bay.$1, bay.$2]) {
        _box(p, .11, .022, bayD, _lineWhite, x, deck + .022, (near + far) / 2);
      }
      _box(p, bay.$2 - bay.$1, .022, .11, _lineWhite, (bay.$1 + bay.$2) / 2,
          deck + .022, isNorth ? far - .12 : near + .12);
    }
  }
  // Dashed aisle centreline.
  for (double x = x0 + 1.4; x < x1 - 1.4; x += 2.0) {
    _box(p, 1.0, .022, .10, _lineWhite, x + .5, deck + .024, 73.8);
  }
  // Yellow hatch at the ramp throat.
  for (var i = 0; i < 6; i++) {
    _box(p, .10, .022, 3.0, _lineYellow, entryX0 + .5 + i * .78, deck + .024,
        z0 + 1.6, 0, .62);
  }

  // Stair/plant penthouse in the reserved north-west deck zone.
  final hutX = (x0 + serviceX1) / 2;
  final hutZ = z1 - 2.5;
  _box(
      p, serviceX1 - x0 - .12, 2.45, 4.80, _wallGrey, hutX, deck + 1.225, hutZ);
  _box(p, serviceX1 - x0 + .18, .18, 5.10, _wallGrey, hutX, deck + 2.44, hutZ);
  _box(p, 1.10, 2.05, .10, _glassDark, hutX, deck + 1.03, hutZ - 2.44);
  _box(p, 1.26, .16, .16, _metal, hutX, deck + 2.14, hutZ - 2.50);

  void railingX(double z) {
    _box(p, x1 - x0 - .4, .055, .055, _metal, (x0 + x1) / 2, deck + 1.17, z);
    _box(p, x1 - x0 - .4, .045, .045, _metal, (x0 + x1) / 2, deck + .97, z);
    for (double x = x0 + .2; x <= x1 - .2; x += 2.1) {
      _box(p, .055, .42, .055, _metal, x, deck + .96, z);
    }
  }

  void railingZ(double x) {
    _box(p, .055, .055, z1 - z0 - .4, _metal, x, deck + 1.17, (z0 + z1) / 2);
    _box(p, .045, .045, z1 - z0 - .4, _metal, x, deck + .97, (z0 + z1) / 2);
    for (double z = z0 + .2; z <= z1 - .2; z += 2.1) {
      _box(p, .055, .42, .055, _metal, x, deck + .96, z);
    }
  }

  railingX(z1 - .14);
  railingZ(x0 + .14);
  railingZ(x1 - .14);

  // Four parapet lamp columns.
  for (final lamp in const <(double, double, bool)>[
    (-42.50, z1 - .22, true),
    (-32.90, z1 - .22, true),
    (-35.40, z0 + .22, false),
    (-40.20, z0 + .22, false),
  ]) {
    _cyl(p, .068, 3.30, 8, _metalDark, lamp.$1, deck + 1.65, lamp.$2);
    final dz = lamp.$3 ? -.58 : .58;
    _box(p, .34, .13, .72, _warm, lamp.$1, deck + 3.20, lamp.$2 + dz);
  }
  return bake(p);
}

/// Delivery yard west of the store and the older six-bay coin park opposite.
List<Tri> _serviceYardAndCoinPark() {
  final p = <Part>[];
  const yardX0 = -56.0, yardX1 = -48.6;
  const yardZ0 = 66.0, yardZ1 = 82.0;
  const dockX = -48.6, dockZ0 = 71.0, dockZ1 = 77.8, dockH = 1.05;

  // Yard slab and its 4.4 m service drive to 七丁目通り.
  _box(p, yardX1 - yardX0, .06, yardZ1 - yardZ0, _asphaltWorn,
      (yardX0 + yardX1) / 2, _y + .03, (yardZ0 + yardZ1) / 2);
  _box(p, 4.4, .06, 6.6, _asphaltWorn, -52.3, _y + .03, 85.3);

  // 2.1 m screen wall, split around the delivery gate.
  void wallX(double from, double to, double z) {
    _box(p, to - from, 2.10, .26, _concreteDark, (from + to) / 2, _y + 1.05, z);
    for (double x = from + 3.2; x < to; x += 3.2) {
      _box(p, .07, 2.0, .30, _metalDark, x, _y + 1.0, z);
    }
  }

  wallX(yardX0, -54.6, yardZ1);
  wallX(-50.0, yardX1, yardZ1);
  wallX(yardX0, yardX1, yardZ0);
  _box(p, .26, 2.10, yardZ1 - yardZ0, _concreteDark, yardX0, _y + 1.05,
      (yardZ0 + yardZ1) / 2);
  for (final x in [-54.6, -50.0]) {
    _box(p, .52, 2.46, .52, _concreteDark, x, _y + 1.23, yardZ1);
    _box(p, .68, .12, .68, _concrete, x, _y + 2.49, yardZ1);
  }

  // Loading dock, yellow edges, shutter, canopy and north-end steps.
  _box(p, 3.0, dockH, dockZ1 - dockZ0, _concreteDark, dockX - 1.5,
      _y + dockH / 2, (dockZ0 + dockZ1) / 2);
  _box(p, 3.0, .10, .14, _lineYellow, dockX - 1.5, _y + dockH + .05,
      dockZ0 + .07);
  _box(p, .14, .10, dockZ1 - dockZ0, _lineYellow, dockX - 2.95,
      _y + dockH + .05, (dockZ0 + dockZ1) / 2);
  for (var i = 0; i < 4; i++) {
    _box(p, .18, .34, .30, _glassDark, dockX - 3.02, _y + .62,
        dockZ0 + 1.0 + i * 1.6);
  }
  _box(p, .16, 3.10, 3.70, _metalDark, dockX - .04, _y + dockH + 1.55,
      (dockZ0 + dockZ1) / 2 - .4);
  _box(p, .08, 2.90, 3.40, _metal, dockX - .13, _y + dockH + 1.45,
      (dockZ0 + dockZ1) / 2 - .4);
  for (var i = 0; i < 20; i++) {
    _box(p, .025, .025, 3.32, _metalDark, dockX - .178,
        _y + dockH + .09 + i * .142, (dockZ0 + dockZ1) / 2 - .4);
  }
  _box(p, 2.20, .14, 4.20, const Mat(0xdfe4ea, tint: 0x6f6790, bands: '3'),
      dockX - 1.1, _y + dockH + 3.05, (dockZ0 + dockZ1) / 2 - .4, 0, 0, -.06);
  for (var i = 0; i < 5; i++) {
    final h = dockH / 5 * (i + 1);
    _box(p, 1.4, h, .34, _concrete, dockX - 1.5, _y + h / 2,
        dockZ1 + .2 + i * .34);
  }

  // Cold-store plant, pallets, roll cages and carton/recycling stacks.
  _box(p, 2.60, 1.85, 1.10, _metalDark, -50.3, _y + .06 + .925, 68.6);
  _box(p, 2.76, .10, 1.24, _metal, -50.3, _y + .06 + 1.90, 68.6);
  for (var layer = 0; layer < 3; layer++) {
    _box(
        p, 1.10, .045, .90, _wood, -54.9, _y + .16 + layer * .14, 69.6, 0, .12);
    for (final dz in [-.35, 0.0, .35]) {
      _box(p, 1.10, .045, .14, _wood, -54.9, _y + .26 + layer * .14, 69.6 + dz,
          0, .12);
    }
  }
  for (final cage in const <(double, double, double)>[
    (-52.6, 79.0, .3),
    (-51.6, 80.0, -.5),
  ]) {
    for (final side in [-1.0, 1.0]) {
      _box(p, .04, 1.55, .72, _metal, cage.$1 + side * .34, _y + .06 + .80,
          cage.$2, 0, cage.$3);
    }
    _box(p, .72, 1.55, .04, _metal, cage.$1, _y + .06 + .80, cage.$2 - .36, 0,
        cage.$3);
    for (var i = 0; i < 3; i++) {
      _box(p, .68, .04, .70, _metal, cage.$1, _y + .30 + i * .44, cage.$2, 0,
          cage.$3);
    }
  }
  for (var i = 0; i < 7; i++) {
    _box(
        p,
        1.05,
        .22,
        .70,
        const Mat(0xc8a97e, tint: 0x6f6790, bands: '3'),
        -55.2 + (i % 2) * .06,
        _y + .17 + i * .22,
        79.4 + (i % 3) * .04,
        0,
        .06);
  }

  // Six-bay gravel coin park north of the road.
  const coinX0 = -46.0, coinX1 = -31.0;
  const coinZ0 = 96.0, coinZ1 = 101.6;
  _box(p, coinX1 - coinX0, .07, coinZ1 - coinZ0, _gravel, (coinX0 + coinX1) / 2,
      _y + .035, (coinZ0 + coinZ1) / 2);
  for (var i = 0; i < 6; i++) {
    final cx = coinX0 + 1.25 + i * 2.5;
    for (final x in [cx - 1.2, cx + 1.2]) {
      _box(p, .08, .018, 5.0, _lineWhite, x, _y + .078, coinZ0 + 2.6);
    }
    for (final x in [cx - .675, cx + .675]) {
      _box(p, .58, .18, .18, _concreteDark, x, _y + .16, coinZ1 - 1.15);
    }
  }
  // Payment machine beside the mouth.
  _box(p, .46, 1.20, .36, _metalDark, coinX1 - .6, _y + .67, coinZ0 + 1.9);
  _box(p, .50, .10, .40, _metal, coinX1 - .6, _y + 1.31, coinZ0 + 1.9);
  _box(p, .34, .26, .04, _glassDark, coinX1 - .6, _y + .99, coinZ0 + 1.71);

  // Low clipped hedge along the park's north edge.
  final hedgeRng = RngKit(7801);
  for (double x = coinX0; x <= coinX1; x += .72) {
    final r = hedgeRng.range(.40, .55);
    p.add(Part(
        icosahedronGeometry(1, 0),
        trs(x + hedgeRng.range(-.12, .12), _y + r * .82, coinZ1 + .40,
            hedgeRng.range(0, 2), hedgeRng.range(0, 2), 0, r, r, r * .82),
        const Mat(0x4f8f68, tint: 0x4f6680, bands: '3')));
  }
  return bake(p);
}

List<Tri> _forecourt({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
}) {
  final p = <Part>[];

  // Apron and the strip of road/footway visible at the camera's feet.
  _box(p, 26.2, .09, 5.2, _concrete, -35.5, _y + .045, 84.6);
  _box(p, 42.4, .08, 6.0, const Mat(0x777487, tint: 0x5b5677, bands: '3'),
      -34.8, _y - .04, 91.6);
  _box(p, 42.4, .11, 1.4, const Mat(0xc8c4cd, tint: 0x6f6790, bands: '3'),
      -34.8, _y + .055, 87.9);

  // Jointed paving and the paired pedestrian guide line.
  for (double x = -46.2; x < -23.0; x += 2.4) {
    _box(p, .05, .014, 4.8, _concreteDark, x, _y + .102, 84.6);
  }
  for (final z in [84.2, 86.4]) {
    _box(p, 25.4, .014, .05, _concreteDark, -35.5, _y + .102, z);
  }
  for (final x in [-37.6, -35.2]) {
    _box(p, .08, .018, 4.5, _white, x, _y + .115, 84.8);
  }

  // West flower bed, benches and the two remaining bollards. This follows
  // props.js::makeFlowerBed, including its low foliage layer: an earlier
  // approximation lifted the soil and flowers by nearly half a metre.
  _box(p, 4.8, .16, 1.2, _soil, -42.25, _y + .09 + .08, 86.5);
  for (final x in [-44.65, -39.85]) {
    _box(p, .09, .22, 1.3, _wood, x, _y + .09 + .11, 86.5);
  }
  for (final z in [85.9, 87.1]) {
    _box(p, 4.9, .22, .09, _wood, -42.25, _y + .09 + .11, z);
  }
  final flowerRng = RngKit(7761);
  const leafColors = [0x5aa578, 0x3f7f60, 0x84bd97];
  const flowerColors = [0xd8564e, 0xf2cc43, 0xe598b9, 0xe9914d, 0x8b67a8];
  for (var i = 0; i < 18; i++) {
    final r = flowerRng.range(.09, .16);
    final localX = flowerRng.range(-.396, .396);
    final localZ = flowerRng.range(-2.43, 2.43);
    final rx = flowerRng.range(0, 3);
    final ry = flowerRng.range(0, 3);
    final rz = flowerRng.range(0, 3);
    final x = -42.25 + localZ;
    final z = 86.5 + localX;
    p.add(Part(
      icosahedronGeometry(1, 0),
      trs(x, _y + .09 + .18 + r * .7, z, rx, ry, rz, r, r * .8, r),
      Mat(leafColors[i % 3], tint: 0x5b6f8c, bands: '3'),
    ));
    if (i % 3 == 0) {
      final color =
          flowerColors[(flowerRng.next() * flowerColors.length).floor()];
      final fx = x - flowerRng.range(-.1, .1);
      final fz = z + flowerRng.range(-.1, .1);
      final fr = flowerRng.range(.045, .07);
      p.add(Part(
        icosahedronGeometry(1, 0),
        trs(fx, _y + .09 + .18 + r * 1.5, fz, 0, 0, 0, fr, fr, fr),
        Mat(color, tint: 0x8f7aa8, bands: '2'),
      ));
    }
  }
  for (final bx in [-42.88, -40.68]) {
    for (var i = 0; i < 3; i++) {
      _box(p, 1.6, .05, .13, _benchWood, bx, _y + .09 + .44,
          85.10 + .16 - i * .16);
    }
    for (var i = 0; i < 2; i++) {
      _box(p, 1.6, .13, .05, _benchWood, bx, _y + .09 + .66 + i * .17, 85.32);
    }
    for (final dx in [-.60, .60]) {
      _box(p, .07, .52, .07, _metalDark, bx + dx, _y + .09 + .66, 85.34, -.12);
      _box(p, .08, .44, .42, _metalDark, bx + dx, _y + .09 + .22, 85.14);
    }
  }
  for (final bx in [-39.10, -37.95]) {
    _cyl(p, .07, .72, 8, _metalDark, bx, _y + .46, 86.7);
    _box(
        p, .15, .10, .15, const Mat(0xd8564e, unlit: true), bx, _y + .80, 86.7);
  }

  // 本日特価 A-board, angled toward the road at the west edge of the doors.
  const boardX = -43.10, boardZ = 83.90, boardRy = .42;
  for (final s in [-1.0, 1.0]) {
    final ox = math.sin(boardRy) * s * .16;
    final oz = math.cos(boardRy) * s * .16;
    _box(p, .66, .92, .045, _glassDark, boardX + ox, _y + .09 + .52,
        boardZ + oz, -s * .17, boardRy);
  }
  _box(p, .05, .05, .62, _metalDark, boardX, _y + .19, boardZ, 0, boardRy);
  for (var row = 0; row < 4; row++) {
    _box(p, .34 - row * .035, .035, .025, _white, boardX,
        _y + .09 + .72 - row * .13, boardZ - .18, 0, boardRy);
  }

  // Parking warning beside the walking route.  Its plate is deliberately
  // nearly edge-on from the road, matching the slim framed silhouette in the
  // reference rather than becoming another billboard across the entrance.
  _cyl(p, .045, 2.10, 8, _metalDark, -35.4, _y + 1.05, 84.4);
  _box(p, .055, .86, .44, _metalDark, -35.4, _y + 1.60, 84.4);
  _box(p, .06, .68, .31, const Mat(0xd8c04f, tint: 0x776080, bands: '2'), -35.4,
      _y + 1.60, 84.4);

  // A compact trolley lean-to on the west and recycling rank on the east.
  _box(p, 2.4, .12, 4.8, const Mat(0xdfe4ea, tint: 0x6f6790, bands: '3'), -46.4,
      2.73, 84.65, 0, 0, .02);
  for (final x in [-47.35, -45.45]) {
    for (final z in [82.45, 86.85]) {
      _box(p, .10, 2.25, .10, _metalDark, x, 1.67, z);
    }
  }
  // Nested-trolley guide rails inside the lean-to.
  for (final x in [-47.18, -45.62]) {
    p.add(Part(cylGeometry(.045, .045, 4.4, 7),
        trs(x, _y + .09 + .92, 84.65, math.pi / 2), _metal));
    _box(p, .06, .92, 4.4, _metal, x, _y + .09 + .46, 84.65);
  }
  _trolleys(p, -46.4, 83.15, 6);
  _trolleys(p, -46.4, 85.35, 4);

  // The source keeps the blue drinks-crate cage at the opposite end of the
  // trolley bay, immediately against the west shop window.
  const cageX = -44.60, cageZ = 82.95, cageY = _y + .09;
  for (final side in [-1.0, 1.0]) {
    _box(p, .05, 1.10, .72, _metal, cageX + side * .44, cageY + .55, cageZ);
  }
  _box(p, .93, 1.10, .05, _metal, cageX, cageY + .55, cageZ - .36);
  _box(p, .93, .05, .72, _metal, cageX, cageY + .03, cageZ);
  for (var i = 0; i < 4; i++) {
    _box(p, .93, .04, .04, _metal, cageX, cageY + .22 + i * .26, cageZ + .34);
    _box(p, .84, .24, .60, _crateBlue, cageX, cageY + .18 + i * .25, cageZ);
  }
  for (var i = 0; i < 3; i++) {
    final colors = [0x4f8f68, 0x337bb0, 0x777b86];
    _box(p, .88, .76, .62, Mat(colors[i], tint: 0x5b6080, bands: '3'),
        -32.4 + i * 1.05, _y + .47, 83.05);
    _box(p, .56, .13, .04, _white, -32.4 + i * 1.05, _y + .53, 83.38);
  }

  // Basket stacks against the entrance bay's east return. These were moved
  // inside the covered recess in the source so they remain clear of the door
  // swing while still reading prominently through the side light.
  const basketX = -34.59, basketZ = 81.45, basketY = _y + .17;
  for (final stack in const <(double, int, int)>[
    (basketX, 9, 0xd8b24a),
    (basketX + .76, 6, 0xc4574c),
  ]) {
    final sx = stack.$1;
    _box(p, .70, .06, .50, _metal, sx, basketY + .30, basketZ);
    for (final dx in [-.30, .30]) {
      for (final dz in [-.20, .20]) {
        _cyl(p, .022, .30, 6, _metal, sx + dx, basketY + .15, basketZ + dz);
      }
    }
    final basketMat = Mat(stack.$3, tint: 0x6f6790, bands: '3');
    for (var i = 0; i < stack.$2; i++) {
      _box(p, .44, .10, .32, basketMat, sx, basketY + .38 + i * .075, basketZ);
    }
  }
  final out = bake(p);
  for (final z in [85.9, 83.6]) {
    appendSignAtlasPlane(out, pedestrianArrowRegion,
        width: 1.1,
        height: 1.1,
        matrix: trs(-36.4, _y + .125, z, -math.pi / 2));
  }
  appendSignAtlasPlane(out, superDealRegion,
      width: .66,
      height: .92,
      matrix:
          trs(boardX, _y + .09, boardZ, 0, boardRy) * trs(0, .52, .184, -.17));
  // Paving and paint receive shadows but do not cast them. Raised forecourt
  // furniture follows the source props' castShadow=true behaviour.
  final forecourtCasters = out
      .where((tri) =>
          !tri.mat.unlit && math.max(tri.a.y, math.max(tri.b.y, tri.c.y)) > .62)
      .toList();
  shadowCasters?.addAll(forecourtCasters);
  groupedShadowCasters?.addAll(forecourtCasters);
  return out;
}

List<Tri> buildNanachome({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
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

  add(_store());
  add(_roofParkingAndRamp());
  add(_serviceYardAndCoinPark());
  add(
      _forecourt(
          shadowCasters: shadowCasters,
          groupedShadowCasters: groupedShadowCasters),
      casts: false);
  add(makeVehicle(
      kind: 'kei',
      color: CAR.skyblue,
      x: -31.2,
      y: _y + .09,
      z: 85.3,
      ry: 1.5707963267948966));
  add(buildSakura(const [
    SakuraSpot(
        x: -31.0,
        z: 82.9,
        y: _y + .15,
        scale: 1.14,
        seed: 7771,
        lean: .11,
        leanDir: 2.2),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // The road-verge cherry sits just behind the benchmark camera. Its visible
  // geometry also supplies its native shadow silhouette.
  final roadTree = buildSakura(const [
    SakuraSpot(
        x: -49.2,
        z: 98.2,
        y: _y,
        scale: 1.16,
        seed: 7805,
        lean: .12,
        leanDir: 1.6),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  add(roadTree);
  // The remaining returned planting completes adjacent viewpoints, but its
  // off-camera shadows exceed three.js's fitted shadow frustum in Filament.
  add(
      buildSakura(const [
        SakuraSpot(
            x: -21.4,
            z: 97.8,
            y: _y,
            scale: 1.10,
            seed: 7806,
            lean: .10,
            leanDir: 4.2),
        SakuraSpot(
            x: -2.6,
            z: 84.6,
            y: _y,
            scale: 1.12,
            seed: 7822,
            lean: .10,
            leanDir: 3.0),
        SakuraSpot(
            x: -20.8,
            z: 99.2,
            y: _y,
            scale: 1.14,
            seed: 7824,
            lean: .11,
            leanDir: 1.9),
      ],
          blossomLightColor: blossomLightColor,
          blossomColor: blossomColor,
          blossomDeepColor: blossomDeepColor),
      casts: false);
  add(
      buildShrubs(const [
        ShrubSpot(
            x: -47.4,
            z: 80.6,
            y: _y,
            r: .46,
            count: 3,
            spread: 1.1,
            seed: 7775),
        ShrubSpot(
            x: -25.6,
            z: 87.0,
            y: _y,
            r: .44,
            count: 3,
            spread: 1.0,
            seed: 7776),
        ShrubSpot(
            x: -52.0,
            z: 97.6,
            y: _y,
            r: .50,
            count: 4,
            spread: 1.4,
            seed: 7803),
        ShrubSpot(
            x: -27.6,
            z: 97.2,
            y: _y,
            r: .46,
            count: 3,
            spread: 1.2,
            seed: 7804),
        ShrubSpot(
            x: -12.0,
            z: 78.0,
            y: _y,
            r: .42,
            count: 3,
            spread: 1.0,
            seed: 7818),
        ShrubSpot(
            x: -12.4,
            z: 99.0,
            y: _y,
            r: .48,
            count: 3,
            spread: 1.2,
            seed: 7823),
        ShrubSpot(
            x: -20.0, z: 68.6, y: _y, r: .40, count: 3, spread: .9, seed: 7833),
      ]),
      casts: false);
  add(
      buildGrove(const [
        GroveSpot(
            x: -58.4, z: 68.0, y: _y, scale: 1.50, seed: 7810, spread: 1.2),
        GroveSpot(
            x: -60.6, z: 72.6, y: _y, scale: 1.68, seed: 7811, spread: 1.2),
        GroveSpot(
            x: -58.4, z: 77.2, y: _y, scale: 1.50, seed: 7812, spread: 1.2),
        GroveSpot(
            x: -60.6, z: 81.8, y: _y, scale: 1.68, seed: 7813, spread: 1.2),
        GroveSpot(
            x: -58.4, z: 86.4, y: _y, scale: 1.50, seed: 7814, spread: 1.2),
        GroveSpot(
            x: -50.0, z: 104.6, y: _y, scale: 1.45, seed: 7820, spread: 1.15),
        GroveSpot(
            x: -43.6, z: 107.0, y: _y, scale: 1.60, seed: 7821, spread: 1.15),
        GroveSpot(
            x: -37.2, z: 104.6, y: _y, scale: 1.75, seed: 7822, spread: 1.15),
        GroveSpot(
            x: -30.8, z: 107.0, y: _y, scale: 1.45, seed: 7823, spread: 1.15),
        GroveSpot(
            x: -24.0, z: 98.4, y: _y, scale: 1.50, seed: 7826, spread: 1.2),
        GroveSpot(
            x: -3.4, z: 97.8, y: _y, scale: 1.40, seed: 7827, spread: 1.1),
      ]),
      casts: false);
  scene.addAll(buildFallenPatches(const [
    PetalPatch(x: -34.0, z: 83.4, w: 8.0, d: 3.0, y: _y + .11, n: 90),
    PetalPatch(x: -45.6, z: 85.4, w: 4.6, d: 2.6, y: _y + .11, n: 55),
    PetalPatch(x: -40.0, z: 99.4, w: 5.0, d: 2.4, y: _y + .09, n: 55),
    PetalPatch(x: -11.4, z: 82.6, w: 2.0, d: 6.0, y: _y + .07, n: 55),
    PetalPatch(x: -20.0, z: 70.8, w: 2.4, d: 3.4, y: _y + .09, n: 45),
  ], skip: 11366));
  return scene;
}
