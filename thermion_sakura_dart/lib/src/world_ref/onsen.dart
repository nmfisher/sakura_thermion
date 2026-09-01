/// Composition-first Dart port of `onsen.js` (湯の坂).
///
/// Covers the full terrace and street composition: five authored frontages,
/// stone paving, central hot-water channel and bridge, footbath shelter,
/// lantern run, street furniture, and the reference's seeded cherry trees.
/// Canvas2D sign artwork and secondary garden clutter are deferred.
library;

import 'dart:math' as math;

import '../geom/three_geom.dart';
import 'details.dart';
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'petals.dart';
import 'sign_atlas.dart';
import 'street.dart' show groundY;

const _y = 3.20;
const _stone = Mat(0xc6c0cb, tint: 0x655d80, bands: '3');
const _stoneDark = Mat(0xa49dab, tint: 0x605878, bands: '3');
const _stoneWarm = Mat(0xcfc6bc, tint: 0x655d80, bands: '3');
const _slab = Mat(0xc6bfc1, tint: 0x6a6288, bands: '3');
const _plaster = Mat(0xe8dfcf, tint: 0x6f6790, bands: '3');
// Inverse-calibrated for Thermion's linear toon path so the graded result
// lands on the reference's d9cdba plaster rather than drifting cool/bright.
const _plasterAlt = Mat(0xd6c8b7, tint: 0x6f6790, bands: '3');
const _wood = Mat(0x76563f, tint: 0x5c5680, bands: '3');
const _woodDark = Mat(0x4e3a2c, tint: 0x50466a, bands: '3');
const _woodPale = Mat(0xc4a074, tint: 0x6f5680, bands: '3');
// The display is fully under a deep canopy. Thermion's grouped shadow pass
// double-darkens it relative to the reference, so retain the source cedar as
// an unlit presentation colour for this one exposed comparison surface.
const _displayWood = Mat(0xcea67a, unlit: true);
const _mappedGlowOff = Mat(0x9a94a6, unlit: true, noOutline: true);
const _mappedLanternOff = Mat(0x9a94a6, unlit: true);
const _stoneLanternLit = Mat(0xf6dfae, unlit: true, noOutline: true);
const _stoneLanternOff = Mat(0xb6afbe, unlit: true, noOutline: true);
const _tile = Mat(0x484755, tint: 0x494268, bands: '3');
const _tileEdge = Mat(0x353441, tint: 0x494268, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _glass = Mat(0x9dc0d4, tint: 0x6f6790, bands: '2', noOutline: true);
const _vendTeal = Mat(0x2e9a98, tint: 0x5c5680, bands: '3');
const _paper = Mat(0xffedc7, unlit: true, noOutline: true);
const _milkCrate = Mat(0xd8d4dc, tint: 0x6a6288, bands: '3');
const _milkCrateTrim = Mat(0x9a94a6, tint: 0x6f6790, bands: '2');
const _milkBottle = Mat(0xf6f2ea, tint: 0x9c93b8, bands: '2');
const _water = Mat(0x82c7c1, unlit: true, noOutline: true);
const _drain = Mat(0x6d687a, tint: 0x5d5878, bands: '3');
const _bamboo = Mat(0x94b06b, tint: 0x5b6f8c, bands: '3');
const _bambooDeep = Mat(0x6f8c50, tint: 0x5b6f8c, bands: '3');

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _cyl(List<Part> parts, double top, double bottom, double h, int segments,
    Mat mat, double x, double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(
      cylGeometry(top, bottom, h, segments), trs(x, y, z, rx, ry, rz), mat));
}

class _Unit {
  const _Unit({
    required this.x,
    required this.z,
    required this.w,
    required this.d,
    required this.face,
    required this.kind,
    this.floors = 2,
    this.h1 = 3,
    this.h2 = 2.6,
    this.roofH = 1.2,
    this.hip = false,
    this.doorW = 1.5,
    this.doorAt = 0,
    this.windows = 2,
    this.wallAlt = false,
    this.balcony = false,
    this.awningOut = .9,
    this.interior = 0,
    this.hollow = 0,
    this.eave = .62,
    this.blade = false,
    this.bladeSide = 1,
    this.bladeH = 1.9,
    this.noren,
  });

  final double x,
      z,
      w,
      d,
      face,
      h1,
      h2,
      roofH,
      doorW,
      doorAt,
      awningOut,
      bladeH,
      hollow,
      eave;
  final int floors, windows;
  final String kind;
  final String? noren;
  final bool hip, wallAlt, balcony, blade;
  final int interior;
  final int bladeSide;
}

List<Tri> _buildUnit(_Unit o) {
  final p = <Part>[];
  final height = o.h1 + (o.floors == 2 ? o.h2 : 0);
  final front = o.d / 2;
  final wall = o.wallAlt ? _plasterAlt : _plaster;
  final woodDark = o.kind == 'sakuraan'
      ? const Mat(0x513a28, tint: 0x50466a, bands: '3')
      : _woodDark;
  final doorCenter = o.doorAt * o.w;

  _box(
      p, o.w + .2, .36, o.d + .2 - o.hollow, _stoneWarm, 0, .18, -o.hollow / 2);
  _box(p, o.w, o.h1 - .36, o.d - o.hollow, wall, 0, .36 + (o.h1 - .36) / 2,
      -o.hollow / 2);
  if (o.floors == 2) {
    _box(p, o.w, o.h2, o.d - .24, wall, 0, o.h1 + o.h2 / 2, -.12);
    _box(p, o.w + .18, .16, o.d + .06, _wood, 0, o.h1 + .02, 0);
  }

  final eave = o.eave;
  final roofWidth = o.w + eave * 2;
  final roofDepth = o.d - (o.floors == 2 ? .24 : 0) + eave * 2;
  final roofZ = o.floors == 2 ? -.12 : 0.0;
  final slope = math.atan2(o.roofH, roofDepth / 2);
  for (final side in [-1.0, 1.0]) {
    _box(
        p,
        o.hip ? roofWidth * .82 : roofWidth,
        .16,
        math.sqrt(math.pow(roofDepth / 2, 2) + math.pow(o.roofH, 2)) + .1,
        _tile,
        0,
        height + o.roofH / 2,
        roofZ + side * roofDepth / 4,
        side * slope);
  }
  if (o.hip) {
    final sideSlope = math.atan2(o.roofH, roofWidth / 2);
    for (final side in [-1.0, 1.0]) {
      _box(
          p,
          math.sqrt(math.pow(roofWidth / 2, 2) + math.pow(o.roofH, 2)) + .1,
          .16,
          roofDepth * .5,
          _tile,
          side * roofWidth / 4,
          height + o.roofH / 2,
          roofZ,
          0,
          0,
          -side * sideSlope);
    }
    _box(p, roofWidth * .44, .22, .3, _tileEdge, 0, height + o.roofH + .03,
        roofZ);
  } else {
    _box(p, roofWidth + .08, .24, .32, _tileEdge, 0, height + o.roofH + .04,
        roofZ);
    final gable = triangularPrismGeometry(o.w, o.roofH * .86, .14);
    for (final side in [-1.0, 1.0]) {
      p.add(Part(
          gable,
          trs(0, height,
              roofZ + side * ((o.floors == 2 ? o.d - .24 : o.d) / 2 - .06)),
          _wood));
    }
  }
  for (final side in [-1.0, 1.0]) {
    _box(p, roofWidth + .06, .13, .16, _tileEdge, 0, height - .04,
        roofZ + side * (roofDepth / 2 - .02));
  }

  // Ground-floor timber frame and lattice screens.
  const sill = .42;
  final head = o.h1 - .52;
  _box(p, o.w, .18, .3, woodDark, 0, sill, front + .08);
  _box(p, o.w, .22, .3, _wood, 0, head + .11, front + .08);
  for (final px in [-o.w / 2 + .08, o.w / 2 - .08]) {
    _box(p, .16, o.h1, .3, woodDark, px, o.h1 / 2, front + .08);
  }
  final doorLeft = doorCenter - o.doorW / 2;
  final doorRight = doorCenter + o.doorW / 2;
  void lattice(double from, double to) {
    final width = to - from;
    if (width < .3) return;
    final center = (from + to) / 2;
    _box(p, width, head - sill, .08, woodDark, center, (sill + head) / 2,
        front + .04);
    final bars = math.max(2, (width / .135).round());
    for (var i = 0; i < bars; i++) {
      _box(p, .05, head - sill - .06, .09, _wood,
          from + width * (i + .5) / bars, (sill + head) / 2, front + .12);
    }
    _box(p, width, .06, .1, _wood, center, sill + (head - sill) * .62,
        front + .14);
  }

  lattice(-o.w / 2 + .16, doorLeft);
  lattice(doorRight, o.w / 2 - .16);
  if (o.hollow > 0) {
    final leftWidth = doorLeft + o.w / 2;
    final rightWidth = o.w / 2 - doorRight;
    if (leftWidth > .1) {
      _box(p, leftWidth, o.h1 - .36, o.hollow, wall, -o.w / 2 + leftWidth / 2,
          .36 + (o.h1 - .36) / 2, front - o.hollow / 2);
    }
    if (rightWidth > .1) {
      _box(p, rightWidth, o.h1 - .36, o.hollow, wall, o.w / 2 - rightWidth / 2,
          .36 + (o.h1 - .36) / 2, front - o.hollow / 2);
    }
    _box(p, o.doorW, o.h1 - head + .18, o.hollow, wall, doorCenter,
        (o.h1 + head - .18) / 2, front - o.hollow / 2);
  } else {
    _box(p, o.doorW, head - .18, .06, woodDark, doorCenter,
        (head - .18) / 2 + .09, front + .03);
  }
  _box(p, o.doorW + .5, .16, .62, _stoneWarm, doorCenter, .24, front + .36);
  _box(p, o.doorW + .12, .16, .2, _wood, doorCenter, head - .02, front + .12);
  if (o.noren != null) {
    _box(
        p, o.doorW + .30, .06, .06, _wood, doorCenter, head - .06, front + .26);
  }

  final fasciaRegion = switch (o.kind) {
    'yunoya' => onsenFasciaYunoyaRegion,
    'hourai' => onsenFasciaHouraiRegion,
    'sakuraan' => onsenFasciaSakuraanRegion,
    'yunoka' => onsenFasciaYunokaRegion,
    'kokeshi' => onsenFasciaKokeshiRegion,
    _ => onsenFasciaYunoyaRegion,
  };
  final fasciaWidth = o.w - .5;
  _box(p, fasciaWidth, .52, .12, woodDark, 0, head + .5, front + .14);
  if (o.blade) {
    final bladeX = o.bladeSide * (o.w / 2 - .12);
    final bladeY = o.h1 * .5 + .5;
    final bladeZ = front + .32;
    _box(p, .13, o.bladeH, .42, woodDark, bladeX, bladeY, bladeZ);
    for (final dy in [-.86, .86]) {
      _box(p, .05, .05, .30, _metalDark, bladeX, bladeY + dy, front + .14);
    }
  }
  final awningTilt = .26;
  _box(p, o.w + .24, .1, o.awningOut / math.cos(awningTilt), _tile, 0,
      head + .94, front + o.awningOut / 2, -awningTilt);
  _box(
      p,
      o.w + .29,
      .12,
      .12,
      _tileEdge,
      0,
      head + .94 - math.sin(awningTilt) * o.awningOut / 2 - .04,
      front + o.awningOut);
  for (final side in [-1.0, 1.0]) {
    final supportX = side * ((o.w + .24) / 2 - .14);
    _box(
        p,
        .09,
        .09,
        o.awningOut,
        _wood,
        supportX,
        head + .9 + math.sin(awningTilt) * o.awningOut / 2,
        front + o.awningOut / 2,
        -awningTilt);
    _box(p, .08, .5, .08, _wood, supportX, head + .66, front + .16, -.7);
  }

  if (o.floors == 2) {
    final windowY = o.h1 + o.h2 * .52;
    final span = o.w - 1;
    for (var i = 0; i < o.windows; i++) {
      final wx = -span / 2 + span * (i + .5) / o.windows;
      final ww = math.min(1.5, span / o.windows - .35);
      _box(p, ww + .22, 1.32, .12, wall, wx, windowY, front - .18);
      _box(p, ww, 1.18, .04, _glass, wx, windowY, front - .09);
      _box(p, .07, 1.28, .08, _wood, wx, windowY, front - .07);
      for (final wy in [windowY - .63, windowY + .63]) {
        _box(p, ww + .16, .09, .09, _wood, wx, wy, front - .07);
      }
      for (final side in [-1.0, 1.0]) {
        _box(p, .09, 1.3, .09, _wood, wx + side * (ww / 2 + .04), windowY,
            front - .07);
      }
    }
    if (o.balcony) {
      final balconyWidth = o.w - .6;
      _box(p, balconyWidth, .1, .62, _wood, 0, o.h1 + .42, front + .17);
      _box(
          p, balconyWidth + .06, .12, .1, woodDark, 0, o.h1 + .47, front + .46);
      for (var i = 0; i <= 5; i++) {
        _box(p, .06, .86, .06, _wood, -balconyWidth / 2 + balconyWidth * i / 5,
            o.h1 + .9, front + .46);
      }
      for (final by in [o.h1 + .86, o.h1 + 1.3]) {
        _box(p, balconyWidth + .1, .07, .08, _wood, 0, by, front + .46);
      }
      for (final side in [-1.0, 1.0]) {
        _box(p, .07, .86, .62, _wood, side * balconyWidth / 2, o.h1 + .9,
            front + .17);
      }
    }
  }

  final local = bake(p);
  if (o.interior > 0) {
    appendSignAtlasPlane(
        local, o.interior == 2 ? tatamiRoom1Region : tatamiRoom0Region,
        width: o.doorW - .14,
        height: head - .5,
        matrix: trs(doorCenter, (head - .5) / 2 + .16, front + .11),
        material: _mappedGlowOff);
  }
  if (o.noren != null) {
    final norenRegion = switch (o.noren) {
      'kanmi' => onsenNorenKanmiRegion,
      'kissa' => onsenNorenKissaRegion,
      _ => onsenNorenYunoyaRegion,
    };
    final isKanmi = o.noren == 'kanmi';
    appendSignAtlasPlane(local, norenRegion,
        width: o.doorW + (isKanmi ? .08 : .16),
        height: isKanmi ? .60 : .62,
        matrix:
            trs(doorCenter, head - .41 - (isKanmi ? .005 : 0), front + .261));
  }
  appendSignAtlasPlane(local, fasciaRegion,
      width: fasciaWidth, height: .52, matrix: trs(0, head + .5, front + .201));
  if (o.blade) {
    final bladeRegion = switch (o.kind) {
      'yunoya' => onsenBladeYunoyaRegion,
      'hourai' => onsenBladeHouraiRegion,
      'sakuraan' => onsenBladeSakuraanRegion,
      'yunoka' => onsenBladeYunokaRegion,
      'kokeshi' => onsenBladeKokeshiRegion,
      _ => onsenBladeYunoyaRegion,
    };
    final bladeX = o.bladeSide * (o.w / 2 - .12);
    final bladeY = o.h1 * .5 + .5;
    final bladeZ = front + .32;
    appendSignAtlasPlane(local, bladeRegion,
        width: .42,
        height: o.bladeH,
        matrix: trs(bladeX + .066, bladeY, bladeZ, 0, math.pi / 2));
    appendSignAtlasPlane(local, bladeRegion,
        width: .42,
        height: o.bladeH,
        matrix: trs(bladeX - .066, bladeY, bladeZ, 0, -math.pi / 2),
        flipU: true);
  }
  if (o.floors == 2) {
    final windowY = o.h1 + o.h2 * .52;
    final span = o.w - 1;
    for (var i = 0; i < o.windows; i++) {
      final wx = -span / 2 + span * (i + .5) / o.windows;
      final ww = math.min(1.5, span / o.windows - .35);
      appendSignAtlasPlane(
          local, i.isEven ? tatamiRoomGlazed0Region : tatamiRoomGlazed1Region,
          width: ww,
          height: 1.18,
          matrix: trs(wx, windowY, front - .117),
          material: _mappedGlowOff);
    }
  }
  final world = trs(o.x, _y, o.z, 0, o.face);
  final rotation = trs(0, 0, 0, 0, o.face);
  return [
    for (final t in local)
      Tri(world.transformed3(t.a), world.transformed3(t.b),
          world.transformed3(t.c), rotation.transformed3(t.normal), t.mat,
          uvA: t.uvA, uvB: t.uvB, uvC: t.uvC),
  ];
}

List<Tri> buildOnsen({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
  int blossomLightColor = 0xf8e9ed,
  int blossomColor = 0xecb8cc,
  int blossomDeepColor = 0xe598b9,
}) {
  final surfaces = <Part>[];
  // Terrace and the cross-laid 4.8 m stone street.
  _box(surfaces, 28.2, .09, 19.0, _stoneWarm, -32.7, _y - .045, 50.1);
  // Source retaining wall around the raised shelf, panelled at the same
  // 3.8-m cadence as ground.js::wallRun and capped without a caster shadow.
  const terraceWallH = _y + .55;
  void terraceWall(String axis, double at, double from, double to) {
    final lo = math.min(from, to), hi = math.max(from, to);
    final panels = math.max(1, ((hi - lo) / 3.8).round());
    final step = (hi - lo) / panels;
    for (var i = 0; i < panels; i++) {
      final c = lo + step * (i + .5);
      if (axis == 'z') {
        _box(surfaces, .4, terraceWallH, step + .02, _stoneDark, at,
            terraceWallH / 2 - .05, c);
        _box(surfaces, .52, .10, step + .02, _stoneWarm, at, terraceWallH, c);
      } else {
        _box(surfaces, step + .02, terraceWallH, .4, _stoneDark, c,
            terraceWallH / 2 - .05, at);
        _box(surfaces, step + .02, .10, .52, _stoneWarm, c, terraceWallH, at);
      }
    }
  }

  terraceWall('x', 40.6, -46.8, -23.8);
  terraceWall('x', 40.6, -21.2, -18.6);
  terraceWall('z', -46.8, 40.6, 59.6);
  terraceWall('z', -18.6, 40.6, 47.6);
  terraceWall('z', -18.6, 50.2, 59.6);
  terraceWall('x', 59.6, -46.8, -27.0);
  terraceWall('x', 59.6, -19.6, -18.6);
  for (final pier in const [
    (-24.0, 40.6),
    (-21.0, 40.6),
    (-18.6, 47.4),
    (-18.6, 50.4),
  ]) {
    _box(surfaces, .72, terraceWallH + .34, .72, _stoneDark, pier.$1,
        (terraceWallH + .34) / 2 - .05, pier.$2);
    _box(surfaces, .90, .14, .90, _stoneWarm, pier.$1, terraceWallH + .36,
        pier.$2);
  }
  final streetX0 = -46.2, streetX1 = -19.2;
  const streetZ0 = 46.4, streetZ1 = 51.2;
  const courses = 29;
  for (var i = 0; i < courses; i++) {
    final width = (streetX1 - streetX0) / courses;
    _box(surfaces, width - .06, .05, streetZ1 - streetZ0 - .24, _slab,
        streetX0 + width * (i + .5), _y + .025, (streetZ0 + streetZ1) / 2);
    for (final side in [-1.0, 1.0]) {
      _box(
          surfaces,
          width - .06,
          .052,
          .34,
          _stoneDark,
          streetX0 + width * (i + .5),
          _y + .026,
          (streetZ0 + streetZ1) / 2 + side * 2.27);
    }
  }
  for (var i = 0; i < 13; i++) {
    _box(surfaces, .3, .04, .62, _drain, -44.4 + i * 2.0, _y + .055,
        (streetZ0 + streetZ1) / 2);
  }

  // Open hot-water channel and the cambered timber bridge.
  const channelX = -34.2, channelZ0 = 41.0, channelZ1 = 58.6;
  for (final side in [-1.0, 1.0]) {
    _box(surfaces, .34, 1.0, channelZ1 - channelZ0, _stoneDark,
        channelX + side * .89, _y - .5, (channelZ0 + channelZ1) / 2);
    _box(surfaces, .5, .12, channelZ1 - channelZ0, _stoneWarm,
        channelX + side * .91, _y + .03, (channelZ0 + channelZ1) / 2);
  }
  _box(surfaces, 1.44, .14, channelZ1 - channelZ0, _stoneWarm, channelX,
      _y - .93, (channelZ0 + channelZ1) / 2);
  _box(surfaces, 1.38, .025, channelZ1 - channelZ0 - .1, _water, channelX,
      _y - .61, (channelZ0 + channelZ1) / 2);
  const bridgeWidth = 5.2, bridgeSpan = 3.34, bridgeCenterZ = 48.8;
  for (var i = 0; i < 9; i++) {
    final t = (i + .5) / 9;
    _box(
        surfaces,
        bridgeSpan / 9 + .01,
        .14,
        bridgeWidth,
        _wood,
        channelX - bridgeSpan / 2 + bridgeSpan * t,
        _y + .06 + math.sin(t * math.pi) * .11,
        48.8);
  }
  for (final side in [-1.0, 1.0]) {
    _box(surfaces, bridgeSpan, .16, .18, _woodDark, channelX, _y - .04,
        bridgeCenterZ + side * (bridgeWidth / 2 - .3));
  }
  // Four low newels and two rails on each channel side. The source bridge's
  // parapet is deliberately below handrail height so the water stays visible.
  const newelOffsetX = bridgeSpan / 2 - .16;
  const newelOffsetZ = bridgeWidth / 2 - .12;
  for (final sx in [-1.0, 1.0]) {
    final px = channelX + sx * newelOffsetX;
    for (final sz in [-1.0, 1.0]) {
      final pz = bridgeCenterZ + sz * newelOffsetZ;
      _box(surfaces, .19, 1.06, .19, _woodDark, px, _y + .62, pz);
      _cyl(surfaces, .11, .13, .14, 8, _woodPale, px, _y + 1.20, pz);
    }
    for (final yy in [_y + .98, _y + .62]) {
      _cyl(surfaces, .05, .05, bridgeWidth - .24, 7, _wood, px, yy,
          bridgeCenterZ, math.pi / 2);
    }
  }
  // Paper lanterns over the two street-side newels.
  const bridgeLanternXs = [channelX - newelOffsetX, channelX + newelOffsetX];
  for (final px in bridgeLanternXs) {
    const pz = bridgeCenterZ - bridgeWidth / 2 + .12;
    _cyl(surfaces, .0672, .0672, .045, 10, _woodDark, px, _y + 1.62, pz);
    _cyl(surfaces, .0672, .0672, .045, 10, _woodDark, px, _y + 1.268, pz);
    _cyl(surfaces, .014, .014, .24, 4, _woodDark, px, _y + 1.74, pz);
  }

  final scene = bake(surfaces);
  const units = [
    _Unit(
        x: -41.3,
        z: 56.9,
        w: 9.4,
        d: 5.0,
        face: math.pi,
        kind: 'yunoya',
        h1: 3.2,
        h2: 2.8,
        roofH: 1.5,
        hip: true,
        doorW: 2.0,
        doorAt: -.149,
        windows: 3,
        balcony: true,
        interior: 1,
        eave: .78,
        awningOut: 1.1,
        blade: true,
        bladeSide: -1,
        bladeH: 2.2,
        noren: 'yunoya'),
    _Unit(
        x: -42.1,
        z: 43.8,
        w: 7.8,
        d: 5.2,
        face: 0,
        kind: 'hourai',
        floors: 1,
        h1: 4.3,
        roofH: 1.5,
        doorW: 2.9,
        wallAlt: true,
        hollow: 2.0,
        eave: .72,
        awningOut: 1.2),
    _Unit(
        x: -30.1,
        z: 53.6,
        w: 4.6,
        d: 4.8,
        face: math.pi,
        kind: 'sakuraan',
        h1: 2.9,
        h2: 2.3,
        roofH: 1.15,
        doorW: 1.4,
        doorAt: -.12,
        windows: 2,
        wallAlt: true,
        balcony: true,
        interior: 2,
        blade: true,
        noren: 'kanmi'),
    _Unit(
        x: -30.8,
        z: 44.1,
        w: 4.4,
        d: 4.6,
        face: 0,
        kind: 'yunoka',
        h1: 2.9,
        h2: 2.2,
        roofH: 1.1,
        doorW: 1.2,
        doorAt: .24,
        windows: 2,
        awningOut: 1.0,
        blade: true,
        bladeSide: -1,
        noren: 'kissa'),
    _Unit(
        x: -26.2,
        z: 44.2,
        w: 4.0,
        d: 4.4,
        face: 0,
        kind: 'kokeshi',
        floors: 1,
        h1: 3.1,
        roofH: 1.1,
        doorW: 1.6,
        wallAlt: true,
        awningOut: 1.15,
        blade: true),
  ];
  for (final unit in units) {
    final tris = _buildUnit(unit);
    scene.addAll(tris);
    shadowCasters?.addAll(tris);
    groupedShadowCasters?.addAll(tris);
  }

  // Bathhouse chimney, footbath and its timber shelter.
  final props = <Part>[];
  const bathX = -42.1, bathFrontZ = 46.4;
  _cyl(props, .44, .56, 10.5, 10,
      const Mat(0xa8756a, tint: 0x6f5680, bands: '3'), -44.3, _y + 5.25, 42.1);
  _cyl(props, .66, .66, .32, 10, _stoneDark, -44.3, _y + 10.6, 42.1);
  for (var i = 0; i < 4; i++) {
    _cyl(
        props,
        .58,
        .58,
        .15,
        10,
        const Mat(0x8f625c, tint: 0x6f5680, bands: '3'),
        -44.3,
        _y + 1.9 + i * 2.3,
        42.1);
  }

  // Bathhouse 唐破風: fourteen short tile members following the source's
  // compound cosine profile over the entrance, plus its two timber carriers.
  // This silhouette is visible between the nearer shop eaves in this view.
  const karahafuWidth = 3.9;
  const karahafuSegments = 14;
  double karahafuY(double t) =>
      math.cos((t - .5) * math.pi) * .42 +
      math.cos((t - .5) * math.pi * 3) * .1;
  for (var i = 0; i < karahafuSegments; i++) {
    final t0 = i / karahafuSegments;
    final t1 = (i + 1) / karahafuSegments;
    final ax = (t0 - .5) * karahafuWidth;
    final bx = (t1 - .5) * karahafuWidth;
    final ay = karahafuY(t0);
    final by = karahafuY(t1);
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    _box(props, len + .02, .14, 1.5, _tile, bathX + (ax + bx) / 2,
        _y + 3.5 + (ay + by) / 2, 47.08, 0, 0, math.atan2(by - ay, bx - ax));
  }
  for (final side in [-1.0, 1.0]) {
    _box(props, .14, 1.5, .14, _woodDark,
        bathX + side * (karahafuWidth / 2 - .2), _y + 2.7, 47.68);
  }

  // Framed mountain board and the paired bath curtains below it.
  _box(props, 4.78, 1.70, .10, _woodDark, bathX, _y + 3.05, 46.43);
  _box(props, 4.60, 1.52, .10, const Mat(0xdedee6, unlit: true), bathX,
      _y + 3.05, 46.49);
  for (final side in [-1.0, 1.0]) {
    _box(
        props, .30, .09, .44, _metalDark, bathX + side * 1.5, _y + 3.95, 46.64);
    _box(props, 1.50, .07, .07, _wood, bathX + side * .78, _y + 2.45, 46.64);
  }

  // Bath changing lobby.  These sit inside the two-metre hollow cut into the
  // unit above and are visible through the paired entrance curtains.
  _box(props, 3.6, .16, .44, const Mat(0xd8cdb8, tint: 0x6a6288, bands: '3'),
      bathX, _y + .08, bathFrontZ - .68);
  _box(props, 3.6, .20, .06, _wood, bathX, _y + .06, bathFrontZ - .47);
  for (var i = 0; i < 3; i++) {
    final lx = bathX - 1.7 + i * .62;
    _box(props, .58, 1.6, .34, const Mat(0xb99a72, tint: 0x6f5680, bands: '3'),
        lx, _y + 1.0, bathFrontZ - 1.7);
    for (var row = 0; row < 4; row++) {
      _box(
          props,
          .52,
          .035,
          .04,
          const Mat(0x8a6f52, tint: 0x5c5680, bands: '2'),
          lx,
          _y + .42 + row * .39,
          bathFrontZ - 1.52);
      _box(
          props,
          .05,
          .10,
          .03,
          const Mat(0x8a6f52, tint: 0x5c5680, bands: '2'),
          lx + .19,
          _y + .36 + row * .39,
          bathFrontZ - 1.52);
    }
  }
  // The low, backless lobby bench from props.js::makeBench.
  final lobbyBench = trs(bathX + .65, _y + .24, bathFrontZ - .55, 0, math.pi);
  for (var i = 0; i < 3; i++) {
    props.add(Part(boxGeometry(1.5, .05, .13),
        lobbyBench * trs(0, .44, -.16 + i * .16), _woodPale));
  }
  for (final side in [-1.0, 1.0]) {
    final lx = side * .6;
    props.add(Part(boxGeometry(.08, .44, .42), lobbyBench * trs(lx, .22, -.04),
        _metalDark));
  }
  // Old platform scale at the east side of the changing lobby.
  final scaleMx = trs(bathX + 1.6, _y + .16, bathFrontZ - 1.5, 0, -.3);
  props
      .add(Part(boxGeometry(.42, .10, .34), scaleMx * trs(0, .05), _metalDark));
  props.add(Part(boxGeometry(.36, .04, .28), scaleMx * trs(0, .12),
      const Mat(0x8a6a44, tint: 0x5c5680, bands: '3')));
  props.add(Part(cylGeometry(.022, .022, 1.0, 6), scaleMx * trs(0, .60, -.10),
      _metalDark));
  props.add(Part(cylGeometry(.17, .17, .06, 14),
      scaleMx * trs(0, 1.12, -.08, math.pi / 2 - .3), _metalDark));
  props.add(Part(
      cylGeometry(.14, .14, .008, 14),
      scaleMx * trs(0, 1.13, 0, math.pi / 2 - .3),
      const Mat(0xf4efe2, unlit: true, noOutline: true)));

  // ゆのか's wide ground-floor kissaten window, layered in the same order as
  // the reference: dark reveal, warm room plate, glass, mullion and rails.
  const yunokaWindowX = -31.5;
  const yunokaWindowY = _y + 1.5;
  const yunokaWindowW = 1.9;
  const yunokaWindowH = 1.25;
  _box(props, yunokaWindowW + .2, yunokaWindowH + .2, .14, _woodDark,
      yunokaWindowX, yunokaWindowY, 46.3);
  _box(props, yunokaWindowW, yunokaWindowH, .04, _glass, yunokaWindowX,
      yunokaWindowY, 46.395);
  _box(props, .06, yunokaWindowH, .07, _wood, yunokaWindowX, yunokaWindowY,
      46.42);
  for (final yy in [
    yunokaWindowY - yunokaWindowH / 2,
    yunokaWindowY + yunokaWindowH / 2
  ]) {
    _box(props, yunokaWindowW + .14, .07, .08, _wood, yunokaWindowX, yy, 46.42);
  }
  const footX = -36.4, footZ = 44.9;
  _box(props, 3.6, .05, 3.1, _stoneWarm, footX, _y + .025, footZ);
  for (final spec in const [
    (0.0, -0.5, 2.4, .22),
    (0.0, .5, 2.4, .22),
    (-1.2, 0.0, .22, 1.22),
    (1.2, 0.0, .22, 1.22),
  ]) {
    _box(props, spec.$3, .46, spec.$4, _stoneDark, footX + spec.$1, _y + .28,
        footZ - .3 + spec.$2);
  }
  _box(props, 2.2, .10, .90, _stoneWarm, footX, _y + .15, footZ - .3);
  _box(props, 2.16, .012, .86, _water, footX, _y + .406, footZ - .3);

  // Bamboo header, feed pipe and falling water at the east end of the trough.
  const spoutX = footX + 1.35;
  _box(props, .30, .80, .30, _stoneDark, spoutX, _y + .45, footZ - .3);
  _cyl(
      props,
      .055,
      .055,
      .90,
      7,
      const Mat(0x9a9f58, tint: 0x60704e, bands: '3'),
      spoutX - .4,
      _y + .9,
      footZ - .3,
      0,
      0,
      math.pi / 2 - .2);
  _cyl(props, .06, .06, .55, 7, const Mat(0x667442, tint: 0x4e5d48, bands: '3'),
      spoutX, _y + .62, footZ - .3);
  _box(props, .06, .42, .05, const Mat(0xdcecea, unlit: true, noOutline: true),
      spoutX - .78, _y + .60, footZ - .3);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(props, .14, 2.5, .14, _woodDark, footX + sx * 1.4, _y + 1.3,
          footZ + sz * 1.2);
    }
  }
  for (final sz in [-1.0, 1.0]) {
    _box(props, 3.0, .14, .12, _woodDark, footX, _y + 2.47, footZ + sz * 1.2);
  }
  _box(
      props, 3.7, .12, 3.4 / math.cos(.2), _tile, footX, _y + 2.74, footZ, -.2);
  _box(props, 3.8, .14, .14, _tileEdge, footX,
      _y + 2.74 - math.sin(.2) * 1.7 - .04, footZ + 1.7);

  // Towel rail and the 足湯 notice board complete the street-facing shelter.
  const railX = footX - 1.64;
  for (final dz in [-.7, .7]) {
    _cyl(props, .035, .035, 1.0, 6, _woodPale, railX, _y + .55, footZ + dz);
  }
  _cyl(props, .035, .035, 1.5, 6, _woodPale, railX, _y + 1.02, footZ,
      math.pi / 2);
  const noticeX = footX + 1.85, noticeZ = footZ + .5;
  for (final dz in [-.28, .28]) {
    _box(props, .08, 1.3, .08, _woodDark, noticeX, _y + .65, noticeZ + dz);
  }
  _box(props, .10, .90, .72, _woodPale, noticeX, _y + 1.28, noticeZ);
  _box(props, .16, .08, .86, _tileEdge, noticeX, _y + 1.76, noticeZ);
  // Galvanised wash bucket tucked under the towel rail.
  final bucketMx = trs(railX + .14, _y + .05, footZ + 1.05, .1, -.6);
  props.add(Part(cylGeometry(.14, .11, .24, 10), bucketMx * trs(0, .12),
      const Mat(0xb8bcc6, tint: 0x666090, bands: '3')));
  props.add(
      Part(cylGeometry(.11, .11, .02, 10), bucketMx * trs(0, .01), _metalDark));
  props.add(Part(
      cylGeometry(.145, .145, .02, 10), bucketMx * trs(0, .24), _metalDark));
  props.add(Part(torusGeometry(.13, .012, 4, 9, math.pi),
      bucketMx * trs(0, .24, 0, 0, math.pi / 2), _metalDark));

  // Kokeshi display table, benches and warm eave lanterns.
  _box(props, 3.0, .09, .72, _displayWood, -26.2, _y + .78, 47.02);
  // The near end occupies a separate dark toon band in Three.js.  The table
  // top is intentionally unlit in this port, so restore just that end face.
  _box(
      props,
      .008,
      .086,
      .72,
      const Mat(0x887060, unlit: true, noOutline: true),
      -24.696,
      _y + .78,
      47.02);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(props, .09, .78, .09, _woodDark, -26.2 + sx * 1.35, _y + .39,
          47.02 + sz * .26);
    }
  }
  const dollColors = [
    0xa5322f,
    0xd4a533,
    0x2c3a52,
    0xcbbfc0,
    0x804861,
    0x4f8f6a,
  ];
  // The reference draws these from buildOnsen's shared RNG after the ryokan,
  // bath and earlier shops have consumed it. These values are recovered from
  // the reference's wrapped vertex bounds so the silhouettes remain exact
  // without reproducing unrelated upstream RNG consumption here.
  const dollHeights = [
    .2942169,
    .2725885,
    .2633520,
    .2641832,
    .2746663,
    .2945090,
    .2167971,
    .1870591,
    .1982754,
    .2086330,
    .2611962,
  ];
  for (var i = 0; i < 11; i++) {
    final gx = -27.44 + (i % 6) * .5;
    final gz = 47.02 + (i < 6 ? -.16 : .18);
    final height = dollHeights[i];
    _cyl(
        props,
        .055,
        .075,
        height,
        8,
        Mat(dollColors[i % dollColors.length],
            tint: 0x6f6790, bands: '3', unlit: true),
        gx,
        _y + .83 + height / 2,
        gz);
    props.add(Part(
        sphereGeometry(.062, 7, 5),
        trs(gx, _y + .94 + height / 2, gz),
        const Mat(0xc1b5b3, tint: 0x6f6790, bands: '3', unlit: true)));
  }

  // Ryokan court gate: exact source posts and tiled hood. This closes the
  // bright gap behind the bridge and carries the inn's vertical name plate.
  const ryokanGateX = -39.9, ryokanGateZ = 51.3;
  for (final side in [-1.0, 1.0]) {
    _box(props, .20, 2.20, .20, _woodDark, ryokanGateX + side * .85, _y + 1.15,
        ryokanGateZ);
  }
  _box(props, 2.34, .16, .50, _tileEdge, ryokanGateX, _y + 2.30, ryokanGateZ);

  // Ryokan court and split-bamboo screen on either side of the gate.
  _box(props, 9.4, .05, 3.2, const Mat(0xa9a3ab, tint: 0x655d80, bands: '3'),
      -41.3, _y + .025, 52.8);
  void bambooFence(double from, double to) {
    final len = to - from;
    final count = math.max(2, (len / .11).round());
    for (var i = 0; i < count; i++) {
      final x = from + len * (i + .5) / count;
      _cyl(props, .042, .042, 1.05, 5, _bamboo, x, _y + .575, 51.3);
    }
    for (final yy in [.252, .777]) {
      _cyl(props, .05, .05, len, 6, _bambooDeep, (from + to) / 2, _y + .05 + yy,
          51.36, 0, 0, math.pi / 2);
    }
    for (final x in [from, to]) {
      _cyl(props, .07, .07, 1.21, 6, _bambooDeep, x, _y + .655, 51.3);
    }
  }

  bambooFence(-45.8, ryokanGateX - .85);
  bambooFence(ryokanGateX + .85, -36.8);

  // Porch roof, carriers and the two stone threshold treads.
  const porchX = -39.9;
  for (var i = 0; i < 2; i++) {
    final h = .14 * (i + 1);
    _box(props, 2.6, h, .42, _stone, porchX, _y + h / 2, 53.5 + .42 * (i + .5));
  }
  for (final side in [-1.0, 1.0]) {
    _box(props, .17, 2.7, .17, _woodDark, porchX + side * 1.6, _y + 1.35, 53.0);
  }
  _box(props, 4.1, .14, 2.0, _tile, porchX, _y + 2.78, 53.55);
  _box(props, 4.2, .16, .18, _tileEdge, porchX, _y + 2.72, 52.56);
  _box(props, 3.8, .10, 1.7, _woodPale, porchX, _y + 2.66, 53.55);
  for (final side in [-1.0, 1.0]) {
    final lampMx = trs(porchX + side * 1.56, _y + 2.3, 54.28, 0, math.pi);
    _box(props, .08, .20, .06, _metalDark, porchX + side * 1.56, _y + 2.3,
        54.25, 0, math.pi);
    props.add(Part(
        boxGeometry(.05, .05, .30), lampMx * trs(0, .06, .15), _metalDark));
    props.add(Part(
        boxGeometry(.20, .26, .20), lampMx * trs(0, -.06, .30), _woodDark));
    props.add(Part(
        boxGeometry(.28, .05, .28), lampMx * trs(0, .09, .30), _metalDark));
    props.add(Part(boxGeometry(.16, .20, .16), lampMx * trs(0, -.06, .30),
        _stoneLanternOff));
  }

  // The small pond and its scale-1.05 garden lantern, read through the fence.
  const pondX = -43.8, pondZ = 52.6;
  for (var i = 0; i < 10; i++) {
    final a = i / 10 * math.pi * 2;
    _box(props, .42, .16, .30, _stoneDark, pondX + math.cos(a) * 1.06, _y + .08,
        pondZ + math.sin(a) * .78, 0, -a);
  }
  props.add(Part(
      cylGeometry(1.0, 1.0, .018, 14),
      trs(pondX, _y + .079, pondZ, 0, 0, 0, 1, 1, .74),
      const Mat(0x8fb0b6, unlit: true, noOutline: true)));
  props.add(Part(
      cylGeometry(.34, .34, .006, 12),
      trs(pondX - .3, _y + .083, pondZ + .16, 0, 0, 0, 1, 1, .5),
      const Mat(0xadc8d3, unlit: true, noOutline: true)));
  const gardenLanternX = -42.3, gardenLanternZ = 51.9, gardenScale = 1.05;
  const gardenLanternRy = .4;
  _cyl(
      props,
      .24 * gardenScale,
      .30 * gardenScale,
      .16 * gardenScale,
      8,
      _stoneDark,
      gardenLanternX,
      _y + .05 + .08 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);
  _cyl(
      props,
      .10 * gardenScale,
      .12 * gardenScale,
      .72 * gardenScale,
      8,
      _stone,
      gardenLanternX,
      _y + .05 + .52 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);
  _cyl(
      props,
      .26 * gardenScale,
      .20 * gardenScale,
      .10 * gardenScale,
      8,
      _stoneDark,
      gardenLanternX,
      _y + .05 + .93 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);
  _cyl(
      props,
      .21 * gardenScale,
      .23 * gardenScale,
      .30 * gardenScale,
      6,
      _stone,
      gardenLanternX,
      _y + .05 + 1.13 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);
  _box(
      props,
      .15 * gardenScale,
      .17 * gardenScale,
      .012,
      _stoneLanternLit,
      gardenLanternX + math.sin(gardenLanternRy) * .20 * gardenScale,
      _y + .05 + 1.13 * gardenScale,
      gardenLanternZ + math.cos(gardenLanternRy) * .20 * gardenScale,
      0,
      gardenLanternRy);
  _box(
      props,
      .012,
      .17 * gardenScale,
      .15 * gardenScale,
      _stoneLanternOff,
      gardenLanternX + math.cos(gardenLanternRy) * .20 * gardenScale,
      _y + .05 + 1.13 * gardenScale,
      gardenLanternZ - math.sin(gardenLanternRy) * .20 * gardenScale,
      0,
      gardenLanternRy);
  _cyl(
      props,
      0,
      .36 * gardenScale,
      .24 * gardenScale,
      6,
      _stoneDark,
      gardenLanternX,
      _y + .05 + 1.40 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);
  _cyl(
      props,
      .05 * gardenScale,
      .07 * gardenScale,
      .14 * gardenScale,
      6,
      _stoneDark,
      gardenLanternX,
      _y + .05 + 1.57 * gardenScale,
      gardenLanternZ,
      0,
      gardenLanternRy);

  void gardenPine(double x, double z, double scale, double lean, double ry,
      {bool deep = false}) {
    final group = trs(x, _y + .05, z, 0, ry);
    const trunkMat = Mat(0x765f62, tint: 0x5c5680, bands: '3');
    final foliage = deep
        ? const Mat(0x2f5540, tint: 0x4a5f7a, bands: '3')
        : const Mat(0x3f6b52, tint: 0x4a5f7a, bands: '3');
    props.add(Part(cylGeometry(.05 * scale, .09 * scale, 1.0 * scale, 6),
        group * trs(0, .5 * scale, 0, 0, 0, lean), trunkMat));
    final tipX = -.5 * scale * math.sin(lean);
    final tipY = .5 * scale * math.cos(lean);
    final cushions = <(double, double, double, double)>[
      (tipX - .42 * scale, tipY * .62, .10 * scale, .46 * scale),
      (tipX + .34 * scale, tipY * 1.02, -.16 * scale, .40 * scale),
      (tipX * 1.2, tipY * 1.42, .06 * scale, .34 * scale),
    ];
    for (final cushion in cushions) {
      props.add(Part(
          sphereGeometry(cushion.$4, 7, 5),
          group * trs(cushion.$1, cushion.$2, cushion.$3, 0, 0, 0, 1, .52, 1),
          foliage));
      props.add(Part(
          cylGeometry(.022 * scale, .03 * scale, .30 * scale, 5),
          group *
              trs(cushion.$1 * .6, cushion.$2 - .1 * scale, cushion.$3 * .6),
          trunkMat));
    }
  }

  gardenPine(-45.7, 53.2, 1.5, .2, .7);
  gardenPine(-43.4, 51.75, 1.05, -.14, 2.4, deep: true);
  void gardenRock(double x, double z, double radius, double ry,
      {bool dark = false}) {
    props.add(Part(
        dodecahedronGeometry(radius),
        trs(x, _y + .05 + radius * .62 * .62, z, .1, ry, .08, 1, .62, 1.25),
        dark ? _stoneDark : _stone));
  }

  gardenRock(-45.3, 51.9, .46, .6);
  gardenRock(-44.7, 53.7, .30, 2.1, dark: true);
  gardenRock(-42.1, 53.5, .36, 4.0);

  // The inn's two-tier pot shelf, visible through the bamboo screen.
  const shelfW = 1.2, shelfD = .34;
  final shelfMx = trs(-37.5, _y + .05, 52.0, 0, math.pi);
  const shelfMetal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      props.add(Part(
          cylGeometry(.016, .016, .78, 5),
          shelfMx * trs(sx * (shelfW / 2 - .05), .39, sz * (shelfD / 2 - .04)),
          shelfMetal));
    }
  }
  for (final yy in [.36, .74]) {
    for (final sz in [-1.0, 1.0]) {
      props.add(Part(boxGeometry(shelfW, .022, .022),
          shelfMx * trs(0, yy, sz * (shelfD / 2 - .04)), shelfMetal));
    }
    const slats = 13;
    for (var i = 0; i <= slats; i++) {
      props.add(Part(boxGeometry(.014, .014, shelfD - .08),
          shelfMx * trs(-shelfW / 2 + shelfW / slats * i, yy), shelfMetal));
    }
  }
  final shelfRng = RngKit(9724);
  for (var i = 0; i < 5; i++) {
    final yy = i.isOdd ? .75 : .37;
    final radius = shelfRng.range(.07, .10);
    final px = -shelfW / 2 +
        .14 +
        (i % 3) * ((shelfW - .28) / 2) +
        shelfRng.range(-.03, .03);
    final pz = shelfRng.range(-.05, .05);
    props.add(Part(
        cylGeometry(radius, radius * .76, radius * 1.5, 9),
        shelfMx * trs(px, yy + radius * .75, pz),
        const Mat(0xc57a5a, tint: 0x6f5680, bands: '3')));
    if (shelfRng.chance(.78)) {
      for (var k = 0; k < 3; k++) {
        final leafRadius = radius * shelfRng.range(.5, .85);
        final lx = px + shelfRng.range(-radius * .6, radius * .6);
        final ly = yy + radius * 1.7 + shelfRng.range(0, radius * .6);
        final lz = pz + shelfRng.range(-radius * .5, radius * .5);
        props.add(Part(
            icosahedronGeometry(leafRadius, 0),
            shelfMx *
                trs(lx, ly, lz, shelfRng.range(0, 3), shelfRng.range(0, 3),
                    shelfRng.range(0, 3)),
            k == 0
                ? const Mat(0x3f7f60, tint: 0x5b6f8c, bands: '3')
                : const Mat(0x5aa578, tint: 0x5b6f8c, bands: '3')));
      }
    }
  }
  final broomMx = trs(-37.1, _y + .05, 53.6, .08, 1.2, -.2);
  props.add(Part(cylGeometry(.022, .026, 1.5, 6), broomMx * trs(0, .75),
      const Mat(0xc2a874, tint: 0x6f6790, bands: '3')));
  props.add(Part(cylGeometry(0, .18, .44, 7), broomMx * trs(0, .22),
      const Mat(0xa88a5e, tint: 0x6f6790, bands: '3')));
  props.add(Part(cylGeometry(.055, .05, .08, 7), broomMx * trs(0, .43),
      const Mat(0x8a6f52, bands: '2')));

  // ゆのか's street poster on the exact source timber post.
  const posterX = -29.0, posterZ = 47.1;
  _cyl(props, .045, .05, 1.30, 8, _woodDark, posterX, _y + .65, posterZ);
  _cyl(props, .10, .12, .14, 8, const Mat(0xc2bdc8, tint: 0x6a6288, bands: '3'),
      posterX, _y + .07, posterZ);
  _box(props, .42, .56, .05, const Mat(0xdedee6, unlit: true), posterX,
      _y + 1.0, posterZ - .058);

  // Wire recycling cage beside the bath's vending machine.
  const binX = -41.35, binZ = 47.4, binBase = _y + .05;
  _cyl(props, .24, .22, .86, 10, _vendTeal, binX, binBase + .43, binZ);
  _cyl(props, .26, .26, .06, 10, _metalDark, binX, binBase + .89, binZ);
  for (final side in [-1.0, 1.0]) {
    _cyl(props, .08, .08, .03, 8, _woodDark, binX + side * .10, binBase + .92,
        binZ);
  }
  _box(props, .30, .11, .02, _paper, binX, binBase + .62, binZ + .235);

  // Source timber benches at the gate and bath frontages.
  void bench(double x, double z, double ry, double len) {
    final q = trs(x, _y, z, 0, ry);
    for (var i = 0; i < 3; i++) {
      props.add(Part(boxGeometry(len, .05, .13),
          q * trs(0, .44, -.16 + i * .16), _woodPale));
    }
    for (var i = 0; i < 2; i++) {
      props.add(Part(boxGeometry(len, .13, .05),
          q * trs(0, .66 + i * .17, -.22), _woodPale));
    }
    for (final side in [-1.0, 1.0]) {
      final lx = side * (len - .3) / 2;
      props.add(Part(
          boxGeometry(.07, .52, .07), q * trs(lx, .66, -.24, .12), _metalDark));
      props.add(
          Part(boxGeometry(.08, .44, .42), q * trs(lx, .22, -.04), _metalDark));
    }
  }

  bench(-25.6, 50.45, math.pi, 1.8);
  bench(-23.4, 50.45, math.pi, 1.8);
  bench(-44.5, 47.0, 0, 1.3);

  // Two stacked milk crates and their returned bottles outside the bathhouse.
  // This is props.js::makeMilkCrate at the source placement (X1 - .7).
  const crateX = -38.9, crateZ = 46.8;
  for (var i = 0; i < 2; i++) {
    _box(props, .44, .24, .32, _milkCrate, crateX, _y + .12 + i * .24, crateZ,
        0, math.pi);
    _box(props, .38, .04, .26, _milkCrateTrim, crateX, _y + .23 + i * .24,
        crateZ, 0, math.pi);
  }
  for (var i = 0; i < 4; i++) {
    _cyl(props, .032, .032, .14, 8, _milkBottle, crateX + .14 - (i % 2) * .1,
        _y + .55, crateZ + .07 - (i ~/ 2) * .14);
  }

  // The sweet-shop's discarded cat box, immediately beyond its crate stack.
  const catBoxX = -27.5, catBoxZ = 50.5;
  final catBoxMx = trs(catBoxX, _y, catBoxZ, 0, -.7);
  const card = Mat(0xc9a878, tint: 0x6f6790, bands: '3');
  const cardIn = Mat(0xb08f62, tint: 0x6a6288, bands: '3');
  const fur = Mat(0xd8c9b4, tint: 0x7a6f96, bands: '3');
  props.add(Part(boxGeometry(.62, .04, .46), catBoxMx * trs(0, .02), cardIn));
  for (final side in [-1.0, 1.0]) {
    props.add(Part(
        boxGeometry(.62, .28, .03), catBoxMx * trs(0, .14, side * .23), card));
    props.add(Part(
        boxGeometry(.03, .28, .46), catBoxMx * trs(side * .31, .14), card));
  }
  props.add(
      Part(boxGeometry(.62, .03, .20), catBoxMx * trs(0, .28, .32, -.7), card));
  props.add(Part(sphereGeometry(.15, 10, 8),
      catBoxMx * trs(0, .16, -.02, 0, 0, 0, 1.15, .7, .95), fur));
  props.add(
      Part(sphereGeometry(.085, 10, 8), catBoxMx * trs(.12, .16, .08), fur));
  for (final side in [-1.0, 1.0]) {
    props.add(Part(cylGeometry(0, .04, .06, 4),
        catBoxMx * trs(.12, .23, .08 + side * .045, 0, 0, -.3), fur));
  }
  const tailFur = Mat(0xa8977f, tint: 0x6a5f86, bands: '3');
  props.add(Part(torusGeometry(.09, .022, 4, 10, math.pi * 1.1),
      catBoxMx * trs(-.06, .19, .07, math.pi / 2, 0, .4), tailFur));

  // The permanent lantern closes the street's westward sightline. Match the
  // source's scale-2 octagonal base, shaft and table, hexagonal firebox/cap.
  const headX = -45.9, headZ = 48.8;
  const headRy = .35;
  _box(props, 1.5, 1.1, 1.5, _stoneDark, headX, _y + .55, headZ);
  _box(props, 1.74, .16, 1.74, _stoneWarm, headX, _y + 1.18, headZ);
  _cyl(props, .48, .60, .32, 8, _stoneDark, headX, _y + 1.42, headZ, 0, headRy);
  _cyl(props, .20, .24, 1.44, 8, _stone, headX, _y + 2.30, headZ, 0, headRy);
  _cyl(props, .52, .40, .20, 8, _stoneDark, headX, _y + 3.12, headZ, 0, headRy);
  _cyl(props, .42, .46, .60, 6, _stone, headX, _y + 3.52, headZ, 0, headRy);
  _box(props, .30, .34, .025, _stoneLanternLit, headX + math.sin(headRy) * .40,
      _y + 3.52, headZ + math.cos(headRy) * .40, 0, headRy);
  _box(props, .025, .34, .30, _stoneLanternOff, headX + math.cos(headRy) * .40,
      _y + 3.52, headZ - math.sin(headRy) * .40, 0, headRy);
  _cyl(props, 0, .72, .48, 6, _stoneDark, headX, _y + 4.06, headZ, 0, headRy);
  _cyl(props, .10, .14, .28, 6, _stoneDark, headX, _y + 4.40, headZ, 0, headRy);
  for (final side in [-1.0, 1.0]) {
    _box(props, .22, .90, .22, _woodDark, headX + 1.4, _y + .45,
        headZ + side * 1.6);
    _box(props, .30, .10, .30, _tileEdge, headX + 1.4, _y + .94,
        headZ + side * 1.6);
  }
  const lanterns = [
    (-44.2, 46.7, 1),
    (-40.6, 46.7, 1),
    (-31.4, 46.7, 0),
    (-28.4, 46.7, 1),
    (-25.4, 46.7, 1),
    (-44.6, 50.9, 1),
    (-40.2, 50.9, 1),
    (-31.2, 50.9, 1),
    (-27.4, 50.9, 1),
  ];
  for (final lamp in lanterns) {
    _box(props, .06, .06, .42, _metalDark, lamp.$1, _y + 3.3,
        lamp.$2 + (lamp.$2 < 49 ? .2 : -.2));
    _cyl(props, .0672, .0672, .045, 10, _woodDark, lamp.$1, _y + 3.0, lamp.$2);
    _cyl(
        props, .0672, .0672, .045, 10, _woodDark, lamp.$1, _y + 2.648, lamp.$2);
    _cyl(props, .014, .014, .26, 4, _woodDark, lamp.$1, _y + 3.13, lamp.$2);
  }
  const frontageLanterns = [
    // x, z, radius, group-top y, glow-ramp position, texture variant. The
    // fifth source argument is not a rotation; it only staggers dusk lighting.
    (-32.05, 50.8, .15, 5.75, 29.1, 0),
    (-28.15, 50.8, .15, 5.75, 31.1, 0),
    (-27.85, 46.8, .15, 5.70, 26.2, 1),
    (-38.40, 46.75, .19, 6.10, 47.0, 2),
  ];
  for (final lamp in frontageLanterns) {
    final bottomY = lamp.$4 - lamp.$3 * 2.2;
    _cyl(props, lamp.$3 * .42, lamp.$3 * .42, .045, 10, _woodDark, lamp.$1,
        lamp.$4, lamp.$2);
    _cyl(props, lamp.$3 * .42, lamp.$3 * .42, .045, 10, _woodDark, lamp.$1,
        bottomY, lamp.$2);
    _cyl(props, .014, .014, .24, 4, _woodDark, lamp.$1, lamp.$4 + .12, lamp.$2);
  }
  final propTris = bake(props);
  for (final px in bridgeLanternXs) {
    appendSignAtlasCylinder(propTris, onsenLantern0Region,
        radius: .16,
        height: .352,
        segments: 12,
        matrix: trs(px, _y + 1.444, bridgeCenterZ - bridgeWidth / 2 + .12),
        material: _mappedLanternOff);
  }
  appendSignAtlasPlane(propTris, onsenBladeYunoyaRegion,
      width: .20,
      height: 1.0,
      matrix:
          trs(ryokanGateX - .85, _y + 1.40, ryokanGateZ - .101, 0, math.pi));
  appendSignAtlasPlane(propTris, onsenPoster2Region,
      width: .42,
      height: .56,
      matrix: trs(posterX, _y + 1.0, posterZ - .084, 0, math.pi));
  appendSignAtlasPlane(propTris, houraiFujiRegion,
      width: 4.6, height: 1.52, matrix: trs(bathX, _y + 3.05, 46.541));
  appendSignAtlasPlane(propTris, onsenNorenMaleRegion,
      width: 1.34, height: .68, matrix: trs(bathX - .78, _y + 2.10, 46.644));
  appendSignAtlasPlane(propTris, onsenNorenFemaleRegion,
      width: 1.34, height: .68, matrix: trs(bathX + .78, _y + 2.10, 46.644));
  appendSignAtlasPlane(propTris, ashiyuPlateRegion,
      width: .62,
      height: .82,
      matrix: trs(noticeX - .054, _y + 1.28, noticeZ, 0, -math.pi / 2));
  appendSignAtlasPlane(propTris, tatamiRoom1Region,
      width: yunokaWindowW,
      height: yunokaWindowH,
      matrix: trs(yunokaWindowX, yunokaWindowY, 46.365, 0, math.pi),
      material: _mappedGlowOff);
  for (final lamp in lanterns) {
    appendSignAtlasCylinder(
        propTris, lamp.$3 == 0 ? onsenLantern0Region : onsenLantern1Region,
        radius: .16,
        height: .352,
        segments: 12,
        matrix: trs(lamp.$1, _y + 2.824, lamp.$2),
        material: _mappedLanternOff);
  }
  for (final lamp in frontageLanterns) {
    final region = switch (lamp.$6) {
      0 => onsenLantern0Region,
      2 => onsenLantern2Region,
      _ => onsenLantern1Region,
    };
    appendSignAtlasCylinder(propTris, region,
        radius: lamp.$3,
        height: lamp.$3 * 2.2,
        segments: 12,
        matrix: trs(lamp.$1, lamp.$4 - lamp.$3 * 1.1, lamp.$2),
        material: _mappedLanternOff);
  }
  scene.addAll(propTris);
  shadowCasters?.addAll(propTris);
  groupedShadowCasters?.addAll(propTris);

  final bathVending = makeVendingMachine(
      variant: 1, seed: 9741, x: -40.1, y: _y, z: 46.95, ry: 0);
  scene.addAll(bathVending);
  shadowCasters?.addAll(bathVending);
  groupedShadowCasters?.addAll(bathVending);

  final sweetShopCrates =
      makeCrates(x: -28.3, y: _y, z: 50.65, n: 2, seed: 9752, ry: math.pi + .2);
  scene.addAll(sweetShopCrates);
  shadowCasters?.addAll(sweetShopCrates);
  groupedShadowCasters?.addAll(sweetShopCrates);

  scene.addAll(buildFallenPatches(const [
    PetalPatch(x: -34.2, z: 48.8, w: 3.34, d: 5.2, y: _y + .20, n: 34),
    PetalPatch(x: -35.0, z: 48.8, w: 22.0, d: 4.4, y: _y + .06, n: 150),
    PetalPatch(x: -42.0, z: 52.8, w: 8.0, d: 3.0, y: _y + .06, n: 70),
  ], skip: 7797));

  scene.addAll(makePlanter(
      x: -31.95, y: _y, z: 50.7, r: .24, flower: true, seed: 9753, n: 5));
  scene
      .addAll(makePlanter(x: -32.6, y: _y, z: 46.85, r: .22, seed: 9762, n: 4));
  scene.addAll(makePlanter(
      x: -45.5, y: _y, z: 46.9, r: .26, flower: true, seed: 9742, n: 5));
  final trees = buildSakura(const [
    SakuraSpot(
        x: -44.0,
        z: 54.0,
        y: _y + .05,
        scale: 1.06,
        seed: 9721,
        lean: .12,
        leanDir: 2.2),
    SakuraSpot(
        x: -30.6,
        z: 58.4,
        y: _y,
        scale: 1.16,
        seed: 9781,
        lean: .12,
        leanDir: 5.1),
    SakuraSpot(
        x: -35.0,
        z: 52.1,
        y: _y,
        scale: 1.1,
        seed: 9801,
        lean: .11,
        leanDir: 1.4),
    SakuraSpot(
        x: -24.0,
        z: 44.4,
        y: _y,
        scale: 1.18,
        seed: 9802,
        lean: .1,
        leanDir: 3.9),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  scene.addAll(trees);
  shadowCasters?.addAll(trees);
  groupedShadowCasters?.addAll(trees);

  // Deep-green screens on either end of the shelf. These dominate the
  // arrival view and make the terrace read as a street cut into woodland.
  final grove = buildGrove([
    // The neighboring shrine's sacred/backing grove is the canopy directly
    // beyond the onsen gate in this view. These source instances are shared
    // globally and were absent from the district-local Thermion build.
    GroveSpot(
        x: -20.8,
        z: 43.2,
        y: groundY(43.2),
        scale: 2.5,
        seed: 801,
        spread: 1.35,
        lean: .05,
        leanDir: 2.0),
    GroveSpot(
        x: -26.6,
        z: 45.8,
        y: groundY(45.8),
        scale: 1.9,
        seed: 802,
        spread: 1.2),
    GroveSpot(
        x: -31.4,
        z: 42.6,
        y: groundY(42.6),
        scale: 1.6,
        seed: 803,
        spread: 1.15),
    GroveSpot(
        x: -36.6,
        z: 42.0,
        y: groundY(42.0),
        scale: 1.45,
        seed: 804,
        spread: 1.1),
    GroveSpot(
        x: -39.6,
        z: 46.6,
        y: groundY(46.6),
        scale: 1.8,
        seed: 806,
        spread: 1.2),
    GroveSpot(
        x: -49.4,
        z: 43.0,
        y: .4,
        scale: 1.45,
        seed: 9810,
        spread: 1.15,
        lean: .06,
        leanDir: 0),
    GroveSpot(
        x: -51.6,
        z: 46.6,
        y: .4,
        scale: 1.6,
        seed: 9811,
        spread: 1.15,
        lean: .06,
        leanDir: 1.3),
    GroveSpot(
        x: -49.4,
        z: 50.2,
        y: .4,
        scale: 1.75,
        seed: 9812,
        spread: 1.15,
        lean: .06,
        leanDir: 2.6),
    GroveSpot(
        x: -51.6,
        z: 53.8,
        y: .4,
        scale: 1.45,
        seed: 9813,
        spread: 1.15,
        lean: .06,
        leanDir: 3.9),
    GroveSpot(
        x: -49.4,
        z: 57.4,
        y: .4,
        scale: 1.6,
        seed: 9814,
        spread: 1.15,
        lean: .06,
        leanDir: 5.2),
    for (var i = 0; i < 4; i++)
      GroveSpot(
          x: -15.2 + (i % 2) * 2.4,
          z: 52.0 + i * 3.4,
          y: .45,
          scale: 1.35 + (i % 2) * .2,
          seed: 9830 + i,
          spread: 1.1),
  ]);
  scene.addAll(grove);
  shadowCasters?.addAll(grove);
  groupedShadowCasters?.addAll(grove);
  final shrubs = buildShrubs(const [
    ShrubSpot(
        x: -41.4,
        z: 53.9,
        y: _y + .05,
        r: .4,
        count: 3,
        spread: .9,
        seed: 9722),
    ShrubSpot(
        x: -19.6, z: 52.6, y: _y, r: .46, count: 3, spread: 1.1, seed: 9840),
    ShrubSpot(
        x: -46.0, z: 44.4, y: _y, r: .5, count: 3, spread: 1.2, seed: 9841),
  ]);
  scene.addAll(shrubs);
  shadowCasters?.addAll(shrubs);
  groupedShadowCasters?.addAll(shrubs);
  final ryokanBamboo = buildBamboo(const [
    BambooClump(x: -45.3, z: 56.6, y: _y, n: 9, spread: 1.3, seed: 9723),
  ]);
  scene.addAll(ryokanBamboo);
  shadowCasters?.addAll(ryokanBamboo);
  groupedShadowCasters?.addAll(ryokanBamboo);

  return scene;
}
