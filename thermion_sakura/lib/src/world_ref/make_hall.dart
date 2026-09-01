/// Procedural Dart port of `blocks.js::makeHall`.
///
/// The hall is authored facing +Z, like the reference. Canvas-painted Japanese
/// text is represented by shallow geometric marks until texture materials are
/// available in the single-material triangle pipeline.
library;

import 'dart:math' as math;

import '../geom/three_geom.dart';
import 'sign_atlas.dart';

const _wall = Mat(0xf2e7d3, tint: 0x6f6790, bands: '3');
const _trim = Mat(0x8b8496, tint: 0x5c5680, bands: '3');
const _roof = Mat(0x59617a, tint: 0x514b70, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _concrete = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _door = Mat(0x5f6f7a, tint: 0x5c5680, bands: '3');
const _woodPale = Mat(0xb79a72, tint: 0x5c5680, bands: '3');
// Source panes are PAL.glass at 26% over the violet lobby. The packed renderer
// has no transparency, so store the resulting composite rather than the raw
// saturated glass colour.
const _glass = Mat(0x7a8a9f, unlit: true, noOutline: true);
const _glassDark = Mat(0x53627a, unlit: true, noOutline: true);
const _lobby = Mat(0x8f8a9c, unlit: true, noOutline: true);
const _paper = Mat(0xfffbec, unlit: true, noOutline: true);
const _paperWarm = Mat(0xfff0cf, unlit: true, noOutline: true);

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _cyl(List<Part> parts, double r, double h, int segments, Mat mat, double x,
    double y, double z) {
  parts.add(Part(cylGeometry(r, r, h, segments), trs(x, y, z), mat));
}

/// Build the ひばり台 community hall at the reference placement.
List<Tri> makeHall({
  double x = 13.4,
  double y = .45,
  double z = 61.6,
  double w = 9.2,
  double d = 6.6,
  double porchAt = -1.4,
}) {
  const wallHeight = 3.35;
  const porchWidth = 2.9;
  const porchDepth = 1.25;
  final front = d / 2;
  final parts = <Part>[];

  void addBox(double bw, double bh, double bd, Mat mat, double lx, double ly,
          double lz,
          [double rx = 0, double ry = 0, double rz = 0]) =>
      _box(parts, bw, bh, bd, mat, x + lx, y + ly, z + lz, rx, ry, rz);

  void addCyl(double r, double h, int segments, Mat mat, double lx, double ly,
          double lz) =>
      _cyl(parts, r, h, segments, mat, x + lx, y + ly, z + lz);

  addBox(w + .3, .38, d + .3, _concrete, 0, .19, 0);
  addBox(w, wallHeight, d, _wall, 0, .38 + wallHeight / 2, 0);
  addBox(w + .14, .16, d + .14, _trim, 0, .38 + 2.32, 0);

  final roofY = .38 + wallHeight;
  const fall = .5;
  final roofDepth = d + .4;
  final tilt = math.atan2(fall, roofDepth);
  addBox(w + .4, .15, roofDepth / math.cos(tilt), _roof, 0,
      roofY + fall / 2 + .08, -.1, tilt);
  addBox(w + .56, .22, .44, _trim, 0, roofY + fall + .06, front + .02);
  for (final side in [-1.0, 1.0]) {
    addBox(.3, .22, roofDepth, _trim, side * (w / 2 + .2),
        roofY + fall / 2 + .2, -.1);
  }
  addBox(w + .3, .11, .13, _metal, 0, roofY + .06, -roofDepth / 2 + .06);
  addCyl(.06, wallHeight + .5, 6, _metal, w / 2 - .18, (wallHeight + .5) / 2,
      -front + .16);
  addCyl(.2, .44, 10, _metal, w * .28, roofY + .5, -d * .2);
  addCyl(.24, .07, 10, _metalDark, w * .28, roofY + .74, -d * .2);
  addBox(1.5, .5, .9, _trim, -w * .2, roofY + .62, -d * .16);

  // Porch and public name board.
  addBox(porchWidth + .5, .2, porchDepth + .4, _concrete, porchAt, .1,
      front + porchDepth / 2 + .1);
  for (final side in [-1.0, 1.0]) {
    addBox(.12, 2.62, .12, _metal, porchAt + side * porchWidth / 2, 1.51,
        front + porchDepth - .06);
  }
  addBox(porchWidth + .6, .16, porchDepth + .34, _trim, porchAt, 2.9,
      front + porchDepth / 2 + .06);
  addBox(porchWidth + .66, .06, porchDepth + .4, _metal, porchAt, 2.99,
      front + porchDepth / 2 + .06);
  final boardZ = front + porchDepth + .02;
  addBox(2.5, .46, .12, _paper, porchAt, 2.62, boardZ);
  for (final side in [-1.0, 1.0]) {
    addBox(.05, .05, .3, _metalDark, porchAt + side * 1.42, 2.7,
        front + porchDepth + .12);
    addBox(.2, .14, .2, _paperWarm, porchAt + side * 1.42, 2.64,
        front + porchDepth + .26);
  }

  // Glazed double doors and the lobby detail behind them.
  const doorWidth = 1.9;
  addBox(doorWidth + .3, 2.44, .16, _trim, porchAt, 1.54, front - .06);
  addBox(doorWidth, 2.0, .04, _lobby, porchAt, 1.48, front - .12);
  for (final side in [-1.0, 1.0]) {
    final doorX = porchAt + side * doorWidth / 4;
    addBox(doorWidth / 2, 2.2, .07, _metal, doorX, 1.48, front + .02);
    addBox(doorWidth / 2 - .16, 1.86, .035, _glass, doorX, 1.54, front + .065);
    addBox(.05, .9, .05, _metal, porchAt + side * .16, 1.44, front + .09);
  }
  for (final shelfY in [.72, 1.06]) {
    addBox(1.5, .06, .3, _woodPale, porchAt + .1, shelfY, front - .24);
  }
  for (var i = 0; i < 3; i++) {
    addBox(.06, 1.5, .7, _trim, porchAt - .72 + i * .1, 1.13, front - .4);
  }
  addBox(1.4, .05, .1, _paperWarm, porchAt, 2.48, front - .2);

  // Identical high windows along the frontage.
  final windowX0 = porchAt + porchWidth / 2 + .9;
  final available = w / 2 - .6 - windowX0;
  final count = math.max(2, (available / 1.55).floor());
  for (var i = 0; i < count; i++) {
    final windowX = windowX0 + available / count * (i + .5);
    addBox(1.4, 1.32, .14, _trim, windowX, 2.38, front - .03);
    addBox(1.24, 1.16, .05, i == count - 1 ? _paperWarm : _glassDark, windowX,
        2.38, front + .055);
    addBox(.06, 1.16, .08, _metal, windowX, 2.38, front + .08);
    addBox(1.34, .06, .08, _metal, windowX, 2.99, front + .08);
    addBox(1.48, .08, .2, _trim, windowX, 1.72, front + .06);
  }
  addBox(.9, .86, .14, _trim, w / 2 - .5, 2.28, front - .02);
  addBox(.76, .72, .05, _glass, w / 2 - .5, 2.28, front + .05);

  // Service flank and the glazed notice case visible from the lane.
  addBox(.09, 1.98, .9, _door, -w / 2 - .02, 1.37, -d * .16);
  addBox(.14, 2.16, 1.14, _trim, -w / 2 - .03, 1.42, -d * .16);
  addBox(.22, .62, .44, _metal, -w / 2 - .11, 1.3, d * .16);
  final caseX = porchAt - porchWidth / 2 - 1.0;
  addBox(1.3, .98, .14, _metalDark, caseX, 1.62, front + .06);
  addBox(1.14, .82, .035, _paper, caseX, 1.62, front + .145);
  final artZ = front + .168;

  final scene = bake(parts);
  appendSignAtlasPlane(scene, hallPlateRegion,
      width: 2.5,
      height: .46,
      matrix: trs(x + porchAt, y + 2.62, z + boardZ + .061));
  appendSignAtlasPlane(scene, hallNoticeRegion,
      width: 1.14,
      height: .82,
      matrix: trs(x + caseX, y + 1.62, z + artZ + .002));
  return scene;
}
