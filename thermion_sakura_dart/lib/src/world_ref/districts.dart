/// Faithful Dart port of five residential/commercial district modules from the
/// reference (`northblock.js`, `alleys.js`, `restcorner.js`, `ichome.js`,
/// `nichome.js`).  These fill the mid-ground with housing density: houses,
/// fences, lane furniture, walls, bollards, poles, and planting positions.
///
/// CONVENTIONS (matching make_house.dart / shop.dart / street.dart):
///   - Return `List<Tri>`, no context object.
///   - Inline material colours as `const Mat(0x..., ...)` from PAL.
///   - Canvas textures are represented with native geometry where they carry
///     essential scene identity; `hullOutline` is handled by the shared pass.
///   - `RngKit(seed)` mirrors `rngKit`.
///   - Import `makeHouse` / `HouseOpts` for detached houses.
///   - Static visible equivalents of the source's lane, housing, shop, vending,
///     fence, street-furniture, and planting factories are authored directly
///     from the geometry substrate. Runtime collision and interaction metadata
///     are outside this renderer's scope.
///
/// Each exported function returns world-space triangles positioned against
/// `groundY(z)` from street.dart.
library;

import 'dart:math' as math;

import '../geom/three_geom.dart';
import 'details.dart' show makeVendingMachine;
import 'make_house.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart';

// ---------------------------------------------------------------------------
// Shared material palette (const, matching palette.js PAL values).
// ---------------------------------------------------------------------------

const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3'); // PAL.concrete
const _concreteMid =
    Mat(0xc2bdc8, tint: 0x6a6288, bands: '3'); // PAL.concreteMid
const _concreteDark =
    Mat(0xa7a2b0, tint: 0x655d84, bands: '3'); // PAL.concreteDark
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _drain = Mat(0x6d687a, tint: 0x5d5878, bands: '3'); // PAL.drain
const _wood = Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');
const _woodDark = Mat(0x74563f, tint: 0x554e74, bands: '3');
const _stone = Mat(0xc6c0cb, tint: 0x655d80, bands: '3'); // PAL.stone
const _red = Mat(0xe0453f, tint: 0x7a4060, bands: '3'); // PAL.red
const _soil = Mat(0x8f7a62, tint: 0x615a80, bands: '3');
const _algae = Mat(0x6e7a62, tint: 0x5b6f8c, bands: '2');
const _wallGray = Mat(0xdedee6, tint: 0x6f6790, bands: '3'); // PAL.wallGray
const _curb = Mat(0xc7c2d0, tint: 0x6f6790, bands: '3'); // PAL.curb
const _sidewalk = Mat(0xdcd8e2, tint: 0x6f6790, bands: '3'); // PAL.sidewalk
const _gravel = Mat(0xa9a3ab, tint: 0x6f6790, bands: '3'); // PAL.gravel
const _glassDark = Mat(0x53627a, unlit: true, noOutline: true);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Shorthand: add a box part to [parts].
void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

/// Shorthand: add a cylinder part to [parts].
void _cyl(List<Part> parts, double rt, double rb, double h, int seg, Mat mat,
    double x, double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(cylGeometry(rt, rb, h, seg), trs(x, y, z, rx, ry, rz), mat));
}

/// Slotted drain channel segments along a straight run.
void _drainChannel(List<Part> parts, double x, double z0, double z1,
    {double pitch = 0.9, double yOff = 0.055}) {
  final n = ((z1 - z0) / pitch).round();
  for (int i = 0; i < n; i++) {
    final z = z0 + (i + 0.5) * ((z1 - z0) / n);
    _box(parts, 0.28, 0.04, 0.7, _drain, x, groundY(z) + yOff, z);
  }
}

/// Slotted drain channel along world X (the source helper's axis='x' case).
void _drainChannelX(List<Part> parts, double z, double x0, double x1,
    {double pitch = .9, double y = 0}) {
  final n = ((x1 - x0) / pitch).round();
  for (var i = 0; i < n; i++) {
    final x = x0 + (i + .5) * ((x1 - x0) / n);
    _box(parts, .7, .04, .28, _drain, x, y + .055, z);
  }
}

/// Simple wall run (box segments with pier caps).
void _wallRun(List<Part> parts, double axis, double at, double from, double to,
    double y, double h, double t,
    {double panel = 2.4, Mat? mat, Mat? capMat}) {
  final m = mat ?? _concreteMid;
  final cm = capMat ?? _concrete;
  final len = to - from;
  final nPanels = (len / panel).floor();
  for (int i = 0; i < nPanels; i++) {
    final cz = from + (i + 0.5) * panel;
    if (axis == 0) {
      // z axis
      _box(parts, t, h, panel, m, at, y + h / 2, cz);
    } else {
      // x axis
      _box(parts, panel, h, t, m, cz, y + h / 2, at);
    }
  }
  // Pier caps at panel joints
  for (int i = 0; i <= nPanels; i++) {
    final cz = from + i * panel;
    if (cz > to + 0.01) continue;
    if (axis == 0) {
      _box(parts, t + 0.12, 0.09, 0.1, cm, at, y + h, cz);
    } else {
      _box(parts, 0.1, 0.09, t + 0.12, cm, cz, y + h, at);
    }
  }
}

/// Railing (posts + top rail + mid rail).
void _railing(List<Part> parts, double axis, double at, double from, double to,
    double y, double h,
    {double spacing = 1.4, Mat? mat}) {
  final m = mat ?? _metal;
  final n = ((to - from) / spacing).ceil();
  for (int i = 0; i < n; i++) {
    final p = from + i * spacing;
    if (p > to + 0.01) continue;
    if (axis == 0) {
      _cyl(parts, 0.035, 0.035, h, 6, m, at, y + h / 2, p);
    } else {
      _cyl(parts, 0.035, 0.035, h, 6, m, p, y + h / 2, at);
    }
  }
  // top rail
  final cx = axis == 0 ? at : (from + to) / 2;
  final cz = axis == 0 ? (from + to) / 2 : at;
  final rw = axis == 0 ? 0.06 : (to - from);
  final rd = axis == 0 ? (to - from) : 0.06;
  _box(parts, rw, 0.06, rd, m, cx, y + h, cz);
  // mid rail
  _box(parts, rw, 0.05, rd, m, cx, y + h * 0.5, cz);
}

// ========================= buildNorthBlock =================================
//
// The north block (hibari-dai 3-chome): a residential lane with a corner
// shop, coin parking, attic house, walk-up apartment, terrace, and shed house.
//
// PORTED:
//   - The lane surface (box slab).
//   - The slotted drain channel down one side + manhole covers.
//   - Two patched asphalt squares.
//   - The shed house (makeHouse, 'shed' roof).
//   - The lane lamp post (pole + shade).
//   - Three bollards at the lane mouth.
//   - The dead-end railing at the south end.
//   - The coin parking surface, wheel stops, payment machine, chain-fence posts.
//   - The block garden wall around the shed house.
//
// DEFERRED:
//   - Corner shop (makeShop from shops.js).
//   - Carport (makeCarport from housing.js).
//   - Bike shelter (makeBikeShelter from housing.js).
//   - All props: bicycles, planters, aircons, post boxes, crates, etc.
//   - Timber/block fences (makeTimberFence / makeBlockFence from buildings.js).
//   - Poles and cabling (makePoleLite, sagCurve from plots.js / util.js).
//   - Vending machine.
//   - Sign posts with texture plates.

List<Tri> buildNorthBlock() {
  final parts = <Part>[];
  final extraTris = <List<Tri>>[];

  // Lane constants (northblock.js).
  const lnX = 32.4;
  const lnW = 3.2;
  const lnZ0 = 46.4;
  const lnZ1 = 63.0;

  const Y = 0.45; // groundY(52)

  // -- Lane surface (the main residential lane) --
  _box(parts, lnW, 0.09, lnZ1 - lnZ0, _concreteMid, lnX, Y + 0.045,
      (lnZ0 + lnZ1) / 2);

  // -- East arm connecting to the main street --
  _box(parts, 8.6, 0.09, 3.4, _concreteMid, 44.3, groundY(45.2) + 0.045, 45.2);

  // -- Slotted drain channel down the west side of the lane --
  _drainChannel(parts, lnX - lnW / 2 + 0.24, lnZ0, lnZ1,
      pitch: 0.9, yOff: 0.055);

  // -- Manhole covers --
  for (final z in [49.6, 57.4]) {
    _cyl(
        parts, 0.3, 0.3, 0.04, 12, _metalDark, lnX + 0.5, groundY(z) + 0.07, z);
  }

  // -- Patched asphalt squares --
  for (final entry in <List<double>>[
    [lnX - 0.5, 53.4, 1.5, 1.9],
    [lnX + 0.6, 60.2, 1.2, 1.4],
  ]) {
    final px = entry[0], pz = entry[1];
    final pw = entry[2], pd = entry[3];
    _box(parts, pw, 0.02, pd, _concreteMid, px, groundY(pz) + 0.065, pz);
  }

  // -- The shed house (片流れの平屋): single-storey, shed roof --
  // northblock.js SHED = { x: 45.8, z: 51.7, w: 5.6, d: 5.4 }
  extraTris.add(makeHouse(HouseOpts(
    x: 45.8,
    z: 51.7,
    y: Y,
    w: 5.6,
    d: 5.4,
    face: 'z-',
    floors: 1,
    seed: 7741,
    wall: 5,
    roof: 3,
    roofKind: 'shed',
    shedDir: -1,
    porch: true,
    shutters: true,
  )));

  // The three large residential masses were formerly deferred with their
  // housing.js factories. Preserve the measured, orientation-adjusted
  // envelopes here and add the walk-up's defining access galleries. They are
  // prominent behind the community hall and along the eastern road views.
  extraTris.add(makeHouse(const HouseOpts(
      x: 39.2,
      z: 51.4,
      y: Y,
      w: 6.6,
      d: 7.2,
      floors: 2,
      face: 'x-',
      seed: 7711,
      wall: 6,
      roof: 0,
      roofKind: 'gable')));
  extraTris.add(makeHouse(const HouseOpts(
      x: 26.4,
      z: 58.2,
      y: Y,
      w: 7.0,
      d: 8.0,
      floors: 3,
      face: 'x+',
      seed: 7721,
      wall: 4,
      roof: 0,
      roofKind: 'flat')));
  for (final floorY in [3.12, 5.84]) {
    _box(parts, .82, .12, 7.8, _concrete, 30.0, Y + floorY, 58.2);
    for (var i = 0; i <= 10; i++) {
      _box(parts, .045, .82, .045, _metalDark, 30.39, Y + floorY + .45,
          54.4 + i * .76);
    }
    _box(parts, .055, .055, 7.8, _metalDark, 30.39, Y + floorY + .84, 58.2);
  }
  // Sunward balconies on the opposite face are what the hall camera sees.
  for (final floorY in [2.62, 5.34, 8.06]) {
    _box(parts, .82, .10, 7.75, _concrete, 22.52, Y + floorY, 58.2);
    for (var i = 0; i < 4; i++) {
      _box(parts, .05, 1.28, 1.34, _glassDark, 22.84, Y + floorY - .78,
          55.25 + i * 1.95);
    }
    for (var i = 0; i <= 10; i++) {
      _box(parts, .045, .86, .045, _metalDark, 22.12, Y + floorY + .46,
          54.4 + i * .76);
    }
    _box(parts, .055, .055, 7.8, _metalDark, 22.12, Y + floorY + .88, 58.2);
  }
  extraTris.add(makeHouse(const HouseOpts(
      x: 42.3,
      z: 60.4,
      y: Y,
      w: 6.2,
      d: 8.7,
      floors: 2,
      face: 'x-',
      seed: 7731,
      wall: 7,
      roof: 1,
      roofKind: 'gable')));

  // -- The lane's lamp post (halfway down) --
  {
    const px = lnX - lnW / 2 - 0.35;
    const pz = 54.6;
    _cyl(parts, 0.055, 0.075, 4.6, 8, _metalDark, px, Y + 2.3, pz);
    _cyl(parts, 0.13, 0.16, 0.18, 8, _concreteMid, px, Y + 0.09, pz);
    _box(parts, 0.06, 0.06, 0.72, _metalDark, px, Y + 4.56, pz + 0.34);
    // shade (open cone approximated as a small box)
    _box(parts, 0.22, 0.22, 0.22, _metal, px, Y + 4.33, pz + 0.66);
  }

  // -- Three bollards at the lane mouth --
  {
    final yB = groundY(46.9) + 0.39;
    for (int i = 0; i < 3; i++) {
      final bx = lnX - lnW / 2 + 0.5 + i * 1.0;
      _cyl(parts, 0.055, 0.065, 0.78, 8, _metal, bx, yB, 46.9);
      _cyl(parts, 0.06, 0.06, 0.12, 8, _red, bx, yB + 0.32, 46.9);
    }
  }

  // -- Dead-end railing at the south end --
  _railing(parts, 1, lnZ1 - 0.2, lnX - lnW / 2 - 0.3, lnX + lnW / 2 + 0.3,
      groundY(lnZ1) + 0.05, 0.92,
      spacing: 1.4, mat: _metal);

  // -- Coin parking (ひばり駐車場) --
  {
    const parkX0 = 23.2, parkX1 = 30.4;
    const parkZ0 = 47.3, parkZ1 = 52.0;
    final cy = groundY((parkZ0 + parkZ1) / 2);
    final cw = parkX1 - parkX0;
    final cd = parkZ1 - parkZ0;

    // gravel surface
    _box(parts, cw, 0.06, cd, _gravel, (parkX0 + parkX1) / 2, cy + 0.03,
        (parkZ0 + parkZ1) / 2);

    // wheel stops at far end of each bay (3 bays)
    const bays = 3;
    final pitch2 = (cw - 0.4) / bays;
    for (int i = 0; i < bays; i++) {
      final bx = parkX0 + 0.2 + (i + 0.5) * pitch2;
      _box(parts, 1.4, 0.11, 0.16, _concreteMid, bx, cy + 0.12, parkZ1 - 0.9);
      // coin plate
      _box(parts, 0.62, 0.16, 0.5, _wallGray, bx, cy + 0.14, parkZ1 - 1.7, 0.5,
          0, 0);
      // machine base
      _box(parts, 0.5, 0.1, 0.3, _metalDark, bx, cy + 0.06, parkZ1 - 2.1);
    }

    // payment machine
    const mx = parkX1 - 0.7, mz = parkZ0 + 0.7;
    _box(parts, 0.44, 1.4, 0.5, _concrete, mx, cy + 0.7, mz);

    // chain-fence posts along the back
    for (int i = 0; i <= bays; i++) {
      _cyl(parts, 0.05, 0.055, 0.6, 7, _metalDark, parkX0 + 0.2 + i * pitch2,
          cy + 0.3, parkZ1 - 0.35);
    }

    // block wall on the west boundary
    _wallRun(parts, 0, parkX0 - 0.2, parkZ0, parkZ1, cy, 1.35, 0.2,
        panel: 2.3, mat: _concreteMid);
  }

  extraTris.add(buildGrove([
    for (var i = 0; i < 4; i++)
      GroveSpot(
          x: lnX - 2.4 + i * 2.0,
          z: lnZ1 + 2.2 + (i % 2) * 1.6,
          y: groundY(lnZ1 + 3),
          scale: 1.45 + (i % 3) * .18,
          seed: 7750 + i,
          spread: 1.1),
  ]));

  return [...bake(parts), ...extraTris.expand((t) => t)];
}
//
// The back streets: two alleys behind the shopping street (さくら坂裏路地)
// and the station back path (駅裏の小径).
//
// PORTED:
//   - Slotted drain channels + manhole covers.
//   - Patched asphalt squares.
//   - Block wall runs (west side of shop-back alley).
//   - Gate posts in the wall gap.
//   - Block walls on both sides of the station path.
//   - Bollards at the station path ends.
//   - Pipe stacks on the station path wall.
//
// DEFERRED:
//   - Ground surfaces (lane from ground.js).
//   - All props: aircons, bicycles, crates, tap posts, planters, etc.
//   - Shop back doors, fans, gas meters (texture-dependent).
//   - Posters (textures).
//   - Ivy, bike shelter, storage sheds.
//   - Laundry poles, pot shelves.

// ========================= buildAlleys =====================================

List<Tri> buildAlleys() {
  final parts = <Part>[];

  // -- Shop-back alley (さくら坂裏路地) --
  // A1: narrow stretch
  const a1x = 13.5, a1w = 2.1, a1z0 = 15.9;
  // a1z1 = 33.8 -- implied by a2z0
  // A2: widening
  const a2x = 12.7, a2w = 3.4, a2z0 = 33.4, a2z1 = 43.9;

  // Drains
  for (double z = a1z0 + 0.5; z < a2z1; z += 0.9) {
    final wide = z > a2z0;
    final cx = (wide ? a2x - a2w / 2 : a1x - a1w / 2) + 0.22;
    _box(parts, 0.28, 0.04, 0.7, _drain, cx, groundY(z) + 0.055, z);
  }

  // Manhole covers
  for (final z in [19.4, 28.6, 38.2]) {
    final wide = z > a2z0;
    final cx = wide ? a2x + 0.6 : a1x + 0.4;
    _cyl(parts, 0.28, 0.28, 0.04, 12, _metalDark, cx, groundY(z) + 0.065, z);
  }

  // Patched asphalt
  for (final entry in <List<double>>[
    [22.6, 1.2, 1.5],
    [31.4, 1.0, 1.2],
    [40.8, 1.6, 1.8],
  ]) {
    final pz = entry[0], pw = entry[1], pd = entry[2];
    final wide = pz > a2z0;
    final px = (wide ? a2x : a1x) + 0.15;
    _box(parts, pw, 0.02, pd, _concreteMid, px, groundY(pz) + 0.062, pz);
  }

  // West wall runs (block wall with gap at z ~24.7)
  final wx = a1x - a1w / 2 - 0.02;
  _wallRun(parts, 0, wx, a1z0 + 0.6, 24.0, groundY(19), 1.55, 0.2,
      panel: 2.4, mat: _concreteMid);
  _wallRun(parts, 0, wx, 25.4, 33.2, groundY(29), 1.55, 0.2,
      panel: 2.4, mat: _concreteMid);

  // Gate posts in the gap
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.16, 1.7, 0.16, _concreteMid, wx, groundY(24.7) + 0.85,
        24.7 + s * 0.7);
  }
  // gate metal panel
  _box(parts, 0.06, 1.36, 1.3, _metal, wx + 0.02, groundY(24.7) + 0.72, 24.7);

  // -- Station back path (駅裏の小径) --
  const bx = 15.1, bw = 2.6, bz0 = -19.5, bz1 = -5.8;

  // Block walls both sides (two runs each with a gap)
  for (final s in [-1.0, 1.0]) {
    final at = bx + s * (bw / 2 + 0.1);
    _wallRun(parts, 0, at, bz0 + 0.4, -12.6, groundY(-16), 1.5, 0.19,
        panel: 2.4, mat: _concreteMid);
    _wallRun(parts, 0, at, -11.6, bz1 - 0.6, groundY(-9), 1.5, 0.19,
        panel: 2.4, mat: _concreteMid);
  }

  // Drain channel
  for (double z = bz0 + 0.5; z < bz1; z += 0.9) {
    _box(parts, 0.28, 0.04, 0.7, _drain, bx + bw / 2 - 0.24, groundY(z) + 0.055,
        z);
  }

  // Manhole covers
  for (final z in [-17.0, -10.2]) {
    _cyl(parts, 0.28, 0.28, 0.04, 12, _metalDark, bx - 0.5, groundY(z) + 0.065,
        z);
  }

  // Patch
  _box(parts, 1.4, 0.02, 1.7, _concreteMid, bx + 0.2, groundY(-13.4) + 0.062,
      -13.4);

  // Bollards at the canal end
  for (final s in [-1.0, 1.0]) {
    final bxBoll = bx + s * 0.7;
    final yBoll = groundY(bz0 + 0.2) + 0.41;
    _cyl(parts, 0.05, 0.06, 0.72, 8, _metal, bxBoll, yBoll, bz0 + 0.2);
    _cyl(parts, 0.055, 0.055, 0.1, 8, _red, bxBoll, yBoll + 0.29, bz0 + 0.2);
  }

  // Pipe stacks on the west house flank
  {
    final hx = bx - bw / 2 - 0.26;
    for (final zc in [-18.4, -13.4]) {
      _cyl(parts, 0.055, 0.055, 5.2, 6, _metal, hx, groundY(zc) + 2.6, zc);
      for (int i = 0; i < 3; i++) {
        _box(parts, 0.12, 0.05, 0.12, _metalDark, hx,
            groundY(zc) + 0.9 + i * 1.7, zc);
      }
    }
  }

  return bake(parts);
}

// ========================= buildRestCorner ==================================
//
// The vending-machine rest corner (自販機の休み処): a pocket between the
// shop and a house, with three vending machines, a bench, a lean-to canopy,
// drain, and a cherry tree.
//
// PORTED:
//   - Concrete paving slabs (ground pad).
//   - Slab joints.
//   - Drain channel + kerbs + gully.
//   - Low concrete wall (the back for the machines).
//   - Canopy frame: posts, head beams, purlins.
//   - Canopy corrugated sheet (alternating ribs).
//   - Gutter + downpipe.
//   - Bench (seat boards, back rail, legs).
//   - Lamp bracket on the shop's flank.
//   - Stepping stones.
//   - Gate posts for the block garden wall.
//
// DEFERRED:
//   - Water stain (transparent flat mesh).
//   - Shop flank clutter (makeAircon, gas meter, posters, name plate).
//   - Corner signage plate (texture).
//   - Props: crates, bucket, planter, umbrella stand, post box, vend bin.
//   - Fallen leaves (circles).
//   - Loose paper.

List<Tri> buildRestCorner({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];

  // Pocket bounds (restcorner.js).
  const x0 = 12.10, x1 = 18.25;
  const z0 = 4.30, z1 = 13.30;
  const wallX = 17.55;
  final Y = groundY((z0 + z1) / 2);

  // -- Concrete paving pad --
  _box(parts, x1 - x0 - 0.2, 0.08, z1 - z0, _concrete, (x0 + x1) / 2 + 0.1,
      Y + 0.04, (z0 + z1) / 2);

  // -- Asphalt patch along the west side --
  _box(parts, 1.5, 0.09, z1 - z0 - 2.4, _concreteMid, x0 + 0.85, Y + 0.045,
      (z0 + z1) / 2 + 0.6);

  // -- Slab joints --
  for (double z = z0 + 1.2; z < z1; z += 1.2) {
    _box(parts, x1 - x0 - 0.2, 0.02, 0.05, _concreteMid, (x0 + x1) / 2 + 0.1,
        Y + 0.085, z);
  }

  // -- Drain channel --
  {
    const dx = x0 + 1.9;
    final n = ((z1 - z0 - 1.0) / 0.62).round();
    for (int i = 0; i < n; i++) {
      _box(parts, 0.26, 0.04, 0.5, _drain, dx, Y + 0.075, z0 + 0.7 + i * 0.62);
    }
    // kerbs either side
    for (final s in [-1.0, 1.0]) {
      _box(parts, 0.07, 0.06, z1 - z0 - 1.0, _concreteMid, dx + s * 0.165,
          Y + 0.09, (z0 + z1) / 2 + 0.35);
    }
    // gully
    _box(parts, 0.4, 0.05, 0.4, _metalDark, dx, Y + 0.075, z0 + 0.45);
    for (int i = 0; i < 4; i++) {
      _box(
          parts, 0.34, 0.03, 0.04, _drain, dx, Y + 0.095, z0 + 0.32 + i * 0.09);
    }
  }

  // -- Low concrete wall (back for machines) --
  {
    const wFrom = z0 + 0.6, wTo = z1 - 0.4;
    final nPanels = ((wTo - wFrom) / 2.4).floor();
    for (int i = 0; i < nPanels; i++) {
      final cz = wFrom + (i + 0.5) * 2.4;
      _box(parts, 0.2, 1.15, 2.4, _concreteMid, wallX, Y + 1.15 / 2, cz);
    }
    for (int i = 0; i <= nPanels; i++) {
      final cz = wFrom + i * 2.4;
      if (cz > wTo + 0.01) continue;
      _box(parts, 0.32, 0.09, 0.1, _concrete, wallX, Y + 1.15, cz);
    }
  }

  // Three-machine bank: white, red, then the older teal unit. This is the
  // feature that gives the pocket its name in the source scene.
  const machineX = wallX - .52;
  for (var i = 0; i < 3; i++) {
    extra.add(makeVendingMachine(
        x: machineX,
        z: z0 + 2.15 + i * 1.2,
        y: Y + .08,
        ry: -math.pi / 2,
        variant: i,
        seed: 60 + i));
  }

  // -- Canopy --
  {
    final zA = z0 + 1.45, zB = z0 + 5.30;
    final xHigh = wallX - 0.1, xLow = wallX - 2.55;
    final yHigh = Y + 2.72, yLow = Y + 2.46;

    // Posts: two tall against wall, two short in pocket
    for (final pz in [zA, zB]) {
      _cyl(
          parts,
          0.045,
          0.05,
          yHigh - Y - 0.02,
          7,
          Mat(0x8a8f86, tint: 0x5a5678, bands: '3'),
          xHigh,
          (Y + yHigh) / 2,
          pz);
      _cyl(parts, 0.05, 0.055, yLow - Y - 0.02, 7,
          Mat(0x8a8f86, tint: 0x5a5678, bands: '3'), xLow, (Y + yLow) / 2, pz);
      // base plates
      _box(parts, 0.16, 0.03, 0.16, Mat(0x8a8f86, tint: 0x5a5678, bands: '3'),
          xLow, Y + 0.1, pz);
    }

    // Head beams
    _box(parts, 0.08, 0.1, zB - zA + 0.5,
        Mat(0x8a8f86, tint: 0x5a5678, bands: '3'), xHigh, yHigh, (zA + zB) / 2);
    _box(parts, 0.09, 0.11, zB - zA + 0.5,
        Mat(0x8a8f86, tint: 0x5a5678, bands: '3'), xLow, yLow, (zA + zB) / 2);

    // Purlins
    final runX = xHigh - xLow;
    final dropY = yHigh - yLow;
    final slope = math.atan2(dropY, runX);
    final sheetLen = math.sqrt(runX * runX + dropY * dropY) + 0.3;
    final np = ((zB - zA) / 1.25).round();
    for (int i = 0; i <= np; i++) {
      final pz = zA + ((zB - zA) / np) * i;
      _box(
          parts,
          sheetLen - 0.2,
          0.06,
          0.06,
          Mat(0x8a8f86, tint: 0x5a5678, bands: '3'),
          (xHigh + xLow) / 2,
          (yHigh + yLow) / 2 - 0.06,
          pz,
          0,
          0,
          slope);
    }

    // Corrugated sheet (alternating ribs)
    final nrib = ((zB - zA + 0.5) / 0.19).round();
    final canopyMat = Mat(0xbfc4bb, tint: 0x64607f, bands: '3');
    for (int i = 0; i < nrib; i++) {
      final pz = zA - 0.25 + (i + 0.5) * ((zB - zA + 0.5) / nrib);
      final ribH = i % 2 != 0 ? 0.05 : 0.035;
      _box(parts, sheetLen, ribH, ((zB - zA + 0.5) / nrib) * 0.86, canopyMat,
          (xHigh + xLow) / 2, (yHigh + yLow) / 2 + 0.03, pz, 0, 0, slope);
    }

    // Gutter along the low edge
    _box(parts, 0.13, 0.09, zB - zA + 0.5, _metal, xLow - 0.12, yLow - 0.07,
        (zA + zB) / 2);

    // Downpipe
    _cyl(parts, 0.035, 0.035, yLow - Y - 0.15, 6, _metal, xLow - 0.12,
        (Y + yLow) / 2 - 0.02, zA - 0.18);
    _box(parts, 0.16, 0.06, 0.16, _metalDark, xLow - 0.12, Y + 0.13, zA - 0.18);
  }

  // -- Bench --
  {
    final bx = x0 + 0.62, bz = z0 + 3.4;
    final by = Y + 0.08;
    // seat boards
    for (int i = 0; i < 3; i++) {
      final bm = i == 1 ? _woodDark : _wood;
      _box(parts, 0.42, 0.05, 1.86, bm, bx + i * 0.16 - 0.16, by + 0.44, bz);
    }
    // back rail
    for (int i = 0; i < 2; i++) {
      final bm = i != 0 ? _wood : _woodDark;
      _box(parts, 0.045, 0.16, 1.86, bm, bx - 0.24, by + 0.66 + i * 0.2, bz);
    }
    // legs
    for (final s in [-1.0, 1.0]) {
      _box(parts, 0.5, 0.44, 0.07, _metalDark, bx, by + 0.22, bz + s * 0.82);
      _box(parts, 0.06, 0.42, 0.07, _metalDark, bx - 0.24, by + 0.6,
          bz + s * 0.82);
      _box(parts, 0.56, 0.05, 0.12, _metalDark, bx, by + 0.03, bz + s * 0.82);
    }
  }

  // -- Lamp --
  {
    const lx = x0 + 0.14, lz = z0 + 6.4;
    _box(parts, 0.1, 0.5, 0.1, _metalDark, lx, Y + 3.3, lz);
    _box(parts, 0.62, 0.07, 0.07, _metal, lx + 0.32, Y + 3.52, lz);
    // shade (approximated)
    _box(parts, 0.22, 0.22, 0.22, Mat(0x8a8f86, tint: 0x5a5678, bands: '3'),
        lx + 0.6, Y + 3.42, lz);
    // conduit
    _box(parts, 0.045, 2.0, 0.045, _metal, lx, Y + 2.3, lz + 0.1);
    _box(parts, 0.16, 0.22, 0.09, _metalDark, lx + 0.05, Y + 1.35, lz + 0.1);
  }

  // -- Sign board on low wall (deferred texture, white box) --
  _box(parts, 0.07, 0.34, 1.15, _wallGray, wallX - 0.14, Y + 1.42, z1 - 2.1);
  // sign support posts
  for (final s in [-1.0, 1.0]) {
    _box(parts, 0.05, 0.34, 0.05, _metalDark, wallX - 0.11, Y + 1.15,
        z1 - 2.1 + s * 0.5);
  }

  extra.add(buildSakura([
    SakuraSpot(
        x: x0 + 2.5,
        z: z1 - 1.1,
        y: Y,
        scale: 1.06,
        seed: 8831,
        lean: .13,
        leanDir: 1.1),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildShrubs([
    ShrubSpot(
        x: wallX - .7,
        z: z1 - 1.4,
        y: Y + .08,
        r: .34,
        count: 3,
        spread: .9,
        seed: 8832),
  ]));

  return [...bake(parts), ...extra.expand((t) => t)];
}

// ========================= buildIchome ======================================
//
// The old quarter (1-chome) along the railway: a 2.4 m back lane with a
// masking wall, old houses, passages south to the canal, walk-up, nagaya
// row houses, and terrace.
//
// PORTED:
//   - The lane surface (flat box at Y=0, 63 m long, axis='x').
//   - The gutter along the south edge (drain channel).
//   - Manhole covers.
//   - Patched asphalt squares.
//   - The masking wall: piers, caps, weep holes, algae tide line, damp line.
//   - Wall plates (texture deferred -- plain gray boxes).
//   - Notice case box (texture deferred).
//   - Shut timber gate (dead-end alley 3).
//   - Dead-end railing at the west end.
//   - Bollards at the threshold.
//   - Alley surfaces + railings.
//   - Block walls for the station alley gaps.
//   - Stepping stones.
//
// DEFERRED:
//   - Houses A-E (placed by district.js housing sweep, not in this module).
//   - plotBox / plotCollide / plotWall / dressPlot (from plots.js).
//   - poleRun / sagCurve (from plots.js / util.js).
//   - Ivy, makeBench, makeBicycle, makeBikeRack, props.
//   - Textures: warningPlate, hallNotice, poster, corkBoard.
//   - flights/steps (from ground.js).
//   - Drying rack, kitchen garden, kid bike, scooter, etc.

List<Tri> buildIchome({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];

  // Lane constants (ichome.js).
  const lnZ = -6.9;
  const lnW = 2.4;
  const lnX0 = -76.0;
  const lnX1 = -12.4;
  const lnS = lnZ - lnW / 2; // -8.10
  const lnN = lnZ + lnW / 2; // -5.70
  const maskZ = -4.975;
  const maskX0 = -75.5;
  const maskX1 = -30.2;

  const Y = 0.0; // groundY(-6.9) = 0

  // -- Lane surface (63 m, axis='x') --
  _box(parts, lnX1 - lnX0, 0.05, lnW, _concreteMid, (lnX0 + lnX1) / 2,
      Y + 0.025, lnZ);

  // -- Spur from the road gap --
  _box(parts, 2.0, 0.05, 4.6, _concreteMid, -12.9, Y + 0.025,
      (-12.6 + -8.0) / 2);

  // -- Gutter down the south side --
  _drainChannelX(parts, lnS + .25, -75.0, -13.2, pitch: .95, y: Y + .02);

  // -- Manhole covers --
  for (final x in [-50.0, -24.4]) {
    _cyl(parts, 0.3, 0.3, 0.05, 12, _metalDark, x, Y + 0.045, lnS + .25);
  }

  // -- Patched squares --
  for (final entry in <List<double>>[
    [-63.0, -7.2, 2.2, 1.5],
    [-33.6, -6.4, 1.8, 1.3],
    [-19.4, -7.4, 1.5, 1.2],
  ]) {
    final px = entry[0], pz = entry[1];
    final pw = entry[2], pd = entry[3];
    _box(parts, pw, 0.02, pd, _concreteMid, px, Y + 0.04, pz);
  }

  // -- Bollards at the threshold --
  for (int i = 0; i < 2; i++) {
    final bx = -13.55 + i * 1.0;
    _cyl(parts, 0.05, 0.06, 0.72, 8, _metal, bx, Y + 0.02 + 0.36, -12.72);
  }

  // -- Masking wall: piers, caps, weep holes, algae --
  for (double x = maskX0; x <= maskX1; x += 4.5) {
    // pier
    _box(parts, 0.44, 2.24, 0.16, _concreteMid, x, 1.12, maskZ - 0.08);
    // cap
    _box(parts, 0.56, 0.09, 0.26, _concrete, x, 2.28, maskZ - 0.1);
    // weep hole between piers
    final wx = x + 2.25;
    if (wx > maskX1) continue;
    _box(parts, 0.16, 0.11, 0.07, _concreteDark, wx, 0.46, maskZ - 0.03);
    _box(parts, 0.13, 0.42, 0.03, _algae, wx, 0.24, maskZ - 0.035);
  }
  // continuous damp line
  _box(parts, maskX1 - maskX0, 0.13, 0.03, _algae, (maskX0 + maskX1) / 2, 0.09,
      maskZ - 0.03);

  // -- Wall plates (texture deferred: plain gray boxes) --
  for (final px in [-58.6, -35.2]) {
    _box(parts, 0.3, 0.6, 0.05, _wallGray, px, 1.62, maskZ - 0.025);
  }

  // -- Notice case at x=-43.0 --
  _box(parts, 1.2, 0.9, 0.14, _metalDark, -43.0, 1.6, maskZ - 0.07);
  // backing board
  _box(parts, 1.1, 0.8, 0.02, _concrete, -43.0, 1.6, maskZ - 0.07 + 0.01);
  // glass (deferred: solid)
  _box(parts, 1.12, 0.82, 0.03, _concreteMid, -43.0, 1.6, maskZ - 0.07 - 0.02);
  // hasp
  _box(parts, 0.09, 0.13, 0.05, _metal, -43.0 + 0.62, 1.6, maskZ - 0.09);
  // drip hood
  _box(parts, 1.34, 0.05, 0.22, _metal, -43.0, 1.6 + 0.49, maskZ - 0.13);

  // -- Shut timber gate (dead-end alley 3) --
  {
    const gx = -32.05, gz = -10.38;
    // three boards
    for (int i = 0; i < 3; i++) {
      _box(parts, 0.92 / 3 - 0.02, 1.42, 0.035, _wood,
          gx - 0.92 / 2 + (0.92 / 3) * (i + 0.5), 1.42 / 2 + 0.06, gz);
    }
    // top and bottom rails
    for (final ry in [1.42 - 0.16, 0.28]) {
      _box(parts, 0.92, 0.09, 0.04, _woodDark, gx, ry + 0.06, gz - 0.035);
    }
    // diagonal brace
    final braceLen =
        math.sqrt(0.92 * 0.92 + (1.42 - 0.44) * (1.42 - 0.44)) + 0.04;
    _box(parts, braceLen, 0.07, 0.04, _woodDark, gx, 1.42 / 2 + 0.06,
        gz - 0.035, 0, 0, math.atan2(1.42 - 0.44, 0.92));
    // stiles
    for (final s in [-1.0, 1.0]) {
      _box(parts, 0.07, 1.42 + 0.12, 0.06, _woodDark,
          gx + s * (0.92 / 2 + 0.03), 1.42 / 2 + 0.06, gz - 0.02);
    }
    // latch
    _box(parts, 0.16, 0.06, 0.05, _metalDark, gx + 0.92 / 2 - 0.12, 1.42 * 0.58,
        gz - 0.05);
  }

  // -- Dead-end railing at the west --
  _railing(parts, 0, -76.3, lnS - 0.2, lnN + 0.2, 0.06, 0.92,
      spacing: 1.4, mat: _metal);

  // -- Alley 4 railing (widest passage) --
  _railing(parts, 0, -44.0, -16.4, -9.6, 0.02, 1.0,
      spacing: 2.1, mat: _concreteMid);

  // -- The three defining residential masses on the south side. --
  // The generic house builder preserves the exact envelopes and street-facing
  // elevations while keeping this renderer independent of Three.js.
  extra.add(makeHouse(const HouseOpts(
      x: -71.5,
      z: -13.2,
      y: Y,
      w: 8.0,
      d: 7.0,
      floors: 3,
      face: 'z+',
      seed: 8170,
      wall: 4,
      roof: 0,
      roofKind: 'flat')));
  // Access galleries facing the lane make the large block read as a walk-up.
  for (final floorY in [2.72, 5.44, 8.16]) {
    _box(parts, 7.75, .11, .82, _concrete, -71.5, Y + floorY, -9.30);
    for (var i = 0; i <= 10; i++) {
      _box(parts, .045, .84, .045, _metalDark, -75.35 + i * .77,
          Y + floorY + .45, -8.91);
    }
    _box(parts, 7.75, .055, .055, _metalDark, -71.5, Y + floorY + .87, -8.91);
  }
  _box(parts, 8.0, .07, 1.55, _concrete, -71.5, Y + .035, -8.925);

  // Four low nagaya homes beneath one continuous street-side rhythm.
  for (var i = 0; i < 4; i++) {
    final x = -59.0 - 5.4 + (i + .5) * 2.7;
    extra.add(makeHouse(HouseOpts(
        x: x,
        z: -11.9,
        y: Y,
        w: 2.7,
        d: 5.2,
        floors: 1,
        face: 'z+',
        seed: 8180 + i,
        wall: 3,
        roof: 2,
        roofKind: 'gable',
        porch: true)));
  }

  // Three attached terrace units and their shallow shared forecourt.
  _box(parts, 8.7, .07, 2.25, _concreteMid, -48.5, Y + .035, -9.275);
  for (var i = 0; i < 3; i++) {
    final x = -48.5 - 2.9 + (i + .5) * 2.9;
    extra.add(makeHouse(HouseOpts(
        x: x,
        z: -13.5,
        y: Y,
        w: 2.9,
        d: 6.2,
        floors: 2,
        face: 'z+',
        seed: 8190 + i,
        wall: 6,
        roof: 2,
        roofKind: 'gable',
        porch: true)));
    if (i > 0) {
      _box(parts, .055, .025, 1.8, _concrete, -52.85 + i * 2.9, Y + .085, -9.3);
    }
  }

  extra.add(buildSakura(const [
    SakuraSpot(
        x: -25.6, z: -4.68, scale: 1.06, seed: 8140, lean: .09, leanDir: 2.4),
    SakuraSpot(
        x: -52.3, z: -9.35, scale: 1.12, seed: 8197, lean: .11, leanDir: 2.9),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildGrove(const [
    GroveSpot(x: -77.6, z: -7.4, scale: 1.5, seed: 8141, spread: 1.1),
    GroveSpot(x: -77.4, z: -15.8, scale: 1.6, seed: 8142, spread: 1.15),
    GroveSpot(x: -50.5, z: -17.3, scale: 1.35, seed: 8143, spread: 1.05),
  ]));
  extra.add(buildShrubs(const [
    ShrubSpot(x: -73.2, z: -5.5, r: .34, count: 3, spread: .6, seed: 8133),
    ShrubSpot(x: -62.4, z: -5.5, r: .34, count: 3, spread: .6, seed: 8134),
    ShrubSpot(x: -48.6, z: -5.5, r: .34, count: 3, spread: .6, seed: 8135),
    ShrubSpot(x: -40.2, z: -5.5, r: .34, count: 3, spread: .6, seed: 8136),
    ShrubSpot(x: -32.4, z: -5.5, r: .34, count: 3, spread: .6, seed: 8137),
    ShrubSpot(x: -27.6, z: -4.3, r: .42, count: 4, spread: 1.1, seed: 8138),
    ShrubSpot(x: -16.2, z: -4.25, r: .4, count: 3, spread: 1.0, seed: 8139),
    ShrubSpot(x: -77.0, z: -6.4, r: .5, count: 4, spread: 1.4, seed: 8144),
    ShrubSpot(x: -32.0, z: -16.7, r: .42, count: 3, spread: 1.0, seed: 8158),
  ]));

  return [...bake(parts), ...extra.expand((t) => t)];
}

// ========================= buildNichome =====================================
//
// The newer half (2-chome): a kerbed spine road with car park, estate agent,
// clinic, pharmacy, coin laundry, walk-up block, private lane with terrace
// and garage house, and allotment.
//
// PORTED:
//   - The spine road surface (kerbed, 38 m).
//   - Edge lines (white strips).
//   - Gullies + manholes.
//   - Guardrail at the south end.
//   - T-junction pads.
//   - Bollards at the park link.
//   - Mirror post (box approximation).
//   - West footway + kerb face.
//   - Park gate posts.
//   - Tree pits (kerb ring + soil + stake).
//   - Car park surface + markings + wheel stops.
//   - Mesh fence posts (chain fence).
//   - Block wall for the private lane (私道) gutter.
//   - Bollards at the shido mouth.
//   - Allotment boundary (block walls).
//   - Kitchen garden beds (raised boxes).
//   - Tool rack canes.
//   - Stepping stones (cylinders).
//   - Extract ducts on the laundry.
//   - Block garden walls around terrace units.
//   - Ramp rails at the clinic.
//   - Sign posts (plain boxes, textures deferred).
//   - Block wall for party gap at pharmacy/clinic.
//   - Block wall for garage apron.
//
// DEFERRED:
//   - All props: benches, bicycles, bike racks, planters, aircons,
//     vending machines, crates, cones, etc.
//   - plotBox / plotCollide / plotWall / dressPlot / poleRun.
//   - Textures: parkingSign, warningPlate, hallNotice, noParking.
//   - Ivy and fallen-petal decals.
//   - makeChalkMarks, makeDryingRack, makeGasMeter, etc.

List<Tri> buildNichome({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final parts = <Part>[];
  final extra = <List<Tri>>[];

  // Spine road (nichome.js).
  const spX = 49.2;
  const spW = 3.6;
  const spZ0 = 6.8;
  const spZ1 = 45.2;
  const spE = spX + spW / 2; // 51.0
  const spWk = spX - spW / 2; // 47.4
  const linkZ = 16.25;
  const maskZ = 4.60;
  const gateZ = 24.2;
  const armZ = 45.2;

  // Private lane (私道).
  const sdZ = 31.0;
  const sdW = 2.0;
  const sdX0 = 51.2;
  const sdX1 = 65.6;

  // -- Spine road surface --
  _box(parts, spW, 0.05, spZ1 - spZ0, _concreteMid, spX,
      (groundY(spZ0) + groundY(spZ1)) / 2 + 0.025, (spZ0 + spZ1) / 2);

  // -- Edge lines (white strips) --
  _box(parts, 0.06, 0.01, spZ1 - spZ0 - 1.2, _wallGray, spWk + 0.26,
      groundY(spZ0) + 0.09, (spZ0 + 0.6 + spZ1 - 0.6) / 2);
  _box(parts, 0.06, 0.01, spZ1 - spZ0 - 1.2, _wallGray, spE - 0.26,
      groundY(spZ0) + 0.09, (spZ0 + 0.6 + spZ1 - 0.6) / 2);

  // -- Gullies --
  for (final z in [11.2, 20.6, 30.0, 39.4]) {
    _box(parts, 0.42, 0.05, 0.62, _drain, spE - 0.22, groundY(z) + 0.055, z);
  }
  // Manholes
  for (final z in [16.0, 35.2]) {
    _cyl(parts, 0.31, 0.31, 0.05, 12, _metalDark, spX + 0.8, groundY(z) + 0.06,
        z);
  }

  // -- Guardrail at south end --
  _box(parts, 4.6, 0.86, 0.08, _metal, spX, groundY(maskZ + 1.0) + 0.43,
      maskZ + 1.0);
  // posts
  for (final dz in [-2.1, -0.7, 0.7, 2.1]) {
    _box(parts, 0.08, 0.86, 0.08, _metalDark, spX, groundY(maskZ + 1.0) + 0.43,
        maskZ + 1.0 + dz);
  }
  // sign post (texture deferred)
  _box(parts, 0.08, 2.0, 0.08, _metal, spE + 0.5, groundY(maskZ + 1.5) + 1.0,
      maskZ + 1.5);
  _box(parts, 0.46, 0.62, 0.03, _wallGray, spE + 0.5,
      groundY(maskZ + 1.5) + 1.5, maskZ + 1.5);

  // -- Cone --
  _cyl(parts, 0.05, 0.15, 0.38, 12, _red, spWk + 0.5,
      groundY(maskZ + 1.5) + 0.19, maskZ + 1.5);

  // -- T-junction pad at 公園前 link --
  _box(parts, spW + 1.6, 0.08, 2.6, _concreteMid, spX - 0.2, 0.04, linkZ);

  // -- Bollards at the T --
  for (int i = 0; i < 3; i++) {
    final bz = 15.3 + i * 0.95;
    _cyl(parts, 0.05, 0.06, 0.72, 8, _metal, 47.05, 0.36, bz);
  }

  // -- North T pad --
  final armY = groundY(48.0);
  _box(parts, 4.4, 0.09, 3.4, _concreteMid, 50.0, armY - 0.045, armZ);

  // Mirror post (approximated as a box on a pole)
  _box(parts, 0.08, 2.5, 0.08, _metalDark, spE + 0.55, armY - 0.09 + 1.25,
      armZ - 1.5);
  _box(parts, 0.42, 0.42, 0.03, _concreteMid, spE + 0.55, armY - 0.09 + 2.5,
      armZ - 1.5);

  // lane line at north T
  _box(parts, 2.5, 0.01, 0.06, _wallGray, (48.4 + 50.9) / 2, armY + 0.02,
      armZ - 1.7);

  // -- West footway --
  _box(parts, 1.9, 0.11, 32.6, _sidewalk, 45.85, 0.055, 29.0);
  // kerb face
  _box(parts, 0.16, 0.13, 32.6, _curb, 46.88, 0.065, 29.0);

  // -- Park gate posts --
  for (final s in [-1.0, 1.0]) {
    final pz = gateZ + s * 0.86;
    final gy = groundY(43.6);
    _box(parts, 0.17, 1.34, 0.17, _concreteMid, 43.6, gy + 0.67, pz);
    _box(parts, 0.23, 0.05, 0.23, _concrete, 43.6, gy + 1.36, pz);
  }
  // park gate sign
  _box(parts, 0.08, 1.6, 0.08, _metal, 43.6 + 0.5, groundY(gateZ) + 0.8,
      gateZ + 1.5);
  _box(parts, 0.42, 0.56, 0.03, _wallGray, 43.6 + 0.5, groundY(gateZ) + 1.3,
      gateZ + 1.5);

  // -- Tree pits --
  for (final tz in [19.8, 28.6]) {
    final ty = groundY(tz);
    _box(parts, 1.04, 0.05, 1.04, _soil, 45.0, ty + 0.03, tz);
    // kerb ring
    for (final s in [-1.0, 1.0]) {
      _box(parts, 1.2, 0.11, 0.13, _curb, 45.0, ty + 0.055, tz + s * 0.535);
      _box(parts, 0.13, 0.11, 1.08, _curb, 45.0 + s * 0.535, ty + 0.055, tz);
    }
    // stake
    _cyl(parts, 0.045, 0.045, 1.7, 6, _woodDark, 45.0 - 0.3, ty + 0.85,
        tz + 0.16);
    _box(parts, 0.36, 0.05, 0.05, _wood, 45.0 - 0.14, ty + 1.45, tz + 0.16);
  }

  // -- Car park (月極駐車場) --
  {
    const parkX0 = 51.6, parkX1 = 61.8;
    const parkZ0 = 6.8, parkZ1 = 12.4;
    final cw = parkX1 - parkX0;
    final cd = parkZ1 - parkZ0;
    _box(parts, cw, 0.07, cd, _gravel, (parkX0 + parkX1) / 2, 0.035,
        (parkZ0 + parkZ1) / 2);

    // bay lines (4 bays)
    final xs = [53.0, 55.4, 57.8, 60.2];
    final bayZ0 = parkZ0 + 0.4;
    final bayZ1 = bayZ0 + 3.6;
    for (final x in xs) {
      for (final s in [-1.0, 1.0]) {
        _box(parts, 0.06, 0.01, bayZ1 - bayZ0, _wallGray, x + s * 1.15, 0.09,
            (bayZ0 + bayZ1) / 2);
      }
      // wheel stop
      _box(parts, 1.4, 0.11, 0.16, _concreteMid, x, 0.07, bayZ0 + 0.55);
      // bay number post
      _box(parts, 0.08, 0.62, 0.08, _metalDark, x - 1.15, 0.07 + 0.31,
          bayZ0 + 0.1);
      _box(parts, 0.26, 0.2, 0.03, _wallGray, x - 1.15, 0.07 + 0.52,
          bayZ0 + 0.1);
    }
    // north edge line
    _box(parts, 9.6, 0.01, 0.06, _wallGray, (51.9 + 61.5) / 2, 0.09, bayZ1);

    // mesh fence posts along south and east
    for (double x = parkX0; x <= parkX1; x += 2.2) {
      _box(parts, 0.08, 1.5, 0.08, _metalDark, x, 0.75, parkZ0 - 0.15);
    }
    for (double z = parkZ0; z <= parkZ1 - 1.4; z += 2.2) {
      _box(parts, 0.08, 1.5, 0.08, _metalDark, parkX1 + 0.15, 0.75, z);
    }
    // parking sign
    _box(parts, 0.08, 2.3, 0.08, _metal, 52.2, 0.07 + 1.15, parkZ1 - 0.5);
    _box(parts, 1.0, 0.74, 0.03, _wallGray, 52.2, 0.07 + 1.7, parkZ1 - 0.5);
  }

  // -- Services front aprons --
  // Estate agent (fudosan)
  _box(parts, 1.1, 0.09, 4.2, _concrete, 51.8 + 1.1 / 2, 0.045, 13.3 - 1.1 / 2);
  // Clinic
  _box(parts, 1.15, 0.09, 6.4, _concrete, 52.2 + 1.15 / 2, 0.045,
      18.4 - 1.15 / 2);
  // Pharmacy (yakkyoku)
  _box(parts, 1.15, 0.09, 4.4, _concrete, 52.2 + 1.15 / 2, 0.045,
      25.4 - 1.15 / 2);
  // Laundry
  _box(parts, 1.3, 0.09, 3.8, _concrete, 52.0 + 1.3 / 2, 0.045, 41.9 - 1.3 / 2);

  // -- Party gap mesh fence (clinic/pharmacy) --
  _box(parts, 0.08, 1.7, 0.08, _metalDark, 52.3, 0.85, 25.15);
  _box(parts, 0.08, 1.7, 0.08, _metalDark, 52.3, 0.85, 25.15 + 0.5);

  // -- Walk-up (コーポ みなみ) forecourt --
  _box(parts, 2.1, 0.09, 7.6 - 0.6, _concrete, 53.1 - 1.05,
      groundY(37.6) + 0.045, 37.6 + 0.5);

  // -- Extract ducts on laundry flank --
  {
    const lx = 56.62;
    for (int i = 0; i < 4; i++) {
      final z = 43.8 - 1.5 + i * 1.0;
      _cyl(parts, 0.11, 0.11, 3.3, 8, _metalDark, lx, groundY(z) + 1.65, z);
      _box(parts, 0.3, 0.16, 0.3, _metalDark, lx, groundY(z) + 3.36, z);
    }
  }

  // -- Private lane (私道) --
  _box(parts, sdX1 - sdX0, .06, sdW, _concreteMid, (sdX0 + sdX1) / 2,
      groundY(sdZ) + .03, sdZ);

  // lane gutter
  _drainChannelX(parts, sdZ - sdW / 2 + .26, sdX0 + 1.2, sdX1 - 1.0,
      pitch: .9, y: groundY(sdZ));

  // manholes
  for (final x in [55.4, 62.6]) {
    _cyl(parts, 0.3, 0.3, 0.05, 12, _metalDark, x, groundY(sdZ) + .045,
        sdZ - .5);
  }

  // bollards at shido mouth
  for (final s in [-1.0, 1.0]) {
    _cyl(parts, 0.05, 0.06, 0.72, 8, _metal, sdX0 + 0.3, groundY(58.0) + 0.36,
        sdZ + s * 0.75);
  }

  // -- Block garden walls around terrace units (3 units) --
  {
    final terraceZ = sdZ - sdW / 2 - 0.25;
    final ty = groundY(26.0);
    final unitW = 2.9;
    for (int i = 0; i < 3; i++) {
      final x0 = 57.85 + i * unitW;
      final x1 = x0 + unitW;
      final cx = (x0 + x1) / 2;
      // front wall (z- side)
      _box(parts, x1 - x0, 0.5, 0.2, _concreteMid, cx, ty + 0.25, terraceZ);
      // gate posts
      _box(parts, 0.14, 1.0, 0.14, _concreteMid, cx - 0.5, ty + 0.5, terraceZ);
      _box(parts, 0.14, 1.0, 0.14, _concreteMid, cx + 0.5, ty + 0.5, terraceZ);
    }
  }

  // -- Stepping stones (3 per unit) --
  {
    final ty = groundY(26.0);
    for (int i = 0; i < 3; i++) {
      final cx = 59.15 + i * 2.9;
      for (int j = 0; j < 3; j++) {
        final sz = 30.26 + 0.15 + j * 0.4;
        _cyl(parts, 0.22 + (j % 2) * 0.03, 0.22 + (j % 2) * 0.03, 0.08, 7,
            _stone, cx, ty + 0.04, sz);
      }
    }
  }

  // -- Garage house apron --
  _box(parts, 5.0 + 0.3, 0.06, 1.5, _concrete, 63.0, groundY(34.0) + 0.03,
      34.0 - 0.7);

  // -- Allotment (貸農園) --
  {
    const allotX0 = 67.2, allotX1 = 69.8;
    const allotZ0 = 24.0, allotZ1 = 32.6;
    final ay = groundY((allotX0 + allotX1) / 2 + (allotZ0 + allotZ1) / 2);
    final acx = (allotX0 + allotX1) / 2;
    final acz = (allotZ0 + allotZ1) / 2;

    // soil pad
    _box(parts, allotX1 - allotX0, 0.05, allotZ1 - allotZ0, _soil, acx,
        ay + 0.025, acz);

    // boundary walls (4 sides, with gate on west)
    // north wall
    _box(parts, allotX1 - allotX0, 1.4, 0.19, _concreteMid, acx, ay + 0.7,
        allotZ0);
    // south wall
    _box(parts, allotX1 - allotX0, 1.4, 0.19, _concreteMid, acx, ay + 0.7,
        allotZ1);
    // east wall
    _box(parts, 0.19, 1.4, allotZ1 - allotZ0, _concreteMid, allotX1, ay + 0.7,
        acz);
    // west wall (two runs either side of gate)
    _box(parts, 0.19, 1.4, sdZ - 0.1 - allotZ0 - 0.9, _concreteMid, allotX0,
        ay + 0.7, (allotZ0 + sdZ - 0.1 - 0.9) / 2);
    _box(parts, 0.19, 1.4, allotZ1 - (sdZ + 0.1 + 0.9), _concreteMid, allotX0,
        ay + 0.7, (allotZ1 + sdZ + 0.1 + 0.9) / 2);
    // gate posts
    _box(parts, 0.14, 1.4, 0.14, _concreteMid, allotX0, ay + 0.7,
        sdZ - 0.1 - 0.9);
    _box(parts, 0.14, 1.4, 0.14, _concreteMid, allotX0, ay + 0.7,
        sdZ + 0.1 + 0.9);

    // raised beds (4 beds)
    for (int i = 0; i < 4; i++) {
      final z = allotZ0 + 1.1 + i * 2.0;
      _box(parts, 2.4, 0.9, 0.9, _soil, acx - 0.45, ay + 0.05 + 0.45, z);
      // timber frame
      _box(parts, 2.4, 0.16, 0.05, _woodDark, acx - 0.45, ay + 0.05 + 0.08,
          z - 0.425);
      _box(parts, 2.4, 0.16, 0.05, _woodDark, acx - 0.45, ay + 0.05 + 0.08,
          z + 0.425);
      for (final s in [-1.0, 1.0]) {
        _box(parts, 0.05, 0.16, 0.9, _woodDark, acx - 0.45 + s * 1.175,
            ay + 0.05 + 0.08, z);
      }
    }

    // tool rack canes
    for (int i = 0; i < 5; i++) {
      _cyl(parts, 0.022, 0.022, 1.9, 5, _wood, allotX1 - 0.85 + i * 0.06,
          ay + 0.98, allotZ0 + 2.9 + i * 0.04, 0.14, 0, 0.1 - i * 0.02);
    }
  }

  // -- Walk-up outdoor units (3 stacked on south flank) --
  {
    final hx = 56.4 - 1.9;
    for (int i = 0; i < 3; i++) {
      _box(parts, 0.84, 0.58, 0.14, _concrete, hx,
          groundY(33.8) + 1.05 + i * 2.7, 33.8 - 0.24 - 0.07);
    }
  }

  // -- Street services. --
  // Source plots with x-facing fronts store frontage width in `w` and depth
  // in `d`; swap them for makeHouse's world-axis envelope.
  extra.add(makeHouse(HouseOpts(
      x: 54.4,
      z: 15.4,
      y: groundY(15.4),
      w: 5.2,
      d: 4.2,
      floors: 2,
      face: 'x-',
      seed: 8531,
      wall: 3,
      roof: 0,
      roofKind: 'flat')));
  extra.add(makeHouse(HouseOpts(
      x: 55.0,
      z: 21.6,
      y: groundY(21.6),
      w: 5.6,
      d: 6.4,
      floors: 2,
      face: 'x-',
      seed: 8533,
      wall: 0,
      roof: 0,
      roofKind: 'flat')));
  extra.add(makeHouse(HouseOpts(
      x: 54.6,
      z: 27.6,
      y: groundY(27.6),
      w: 4.8,
      d: 4.4,
      floors: 2,
      face: 'x-',
      seed: 8535,
      wall: 1,
      roof: 1,
      roofKind: 'flat')));
  extra.add(makeHouse(HouseOpts(
      x: 54.2,
      z: 43.8,
      y: groundY(43.8),
      w: 4.4,
      d: 3.8,
      floors: 1,
      face: 'x-',
      seed: 8538,
      wall: 4,
      roof: 0,
      roofKind: 'flat')));

  // コーポみなみ: three-storey walk-up, with galleries on the road face.
  final heightsY = groundY(37.6);
  extra.add(makeHouse(HouseOpts(
      x: 56.4,
      z: 37.6,
      y: heightsY,
      w: 6.6,
      d: 7.6,
      floors: 3,
      face: 'x-',
      seed: 8541,
      wall: 4,
      roof: 0,
      roofKind: 'flat')));
  for (final floorY in [2.72, 5.44, 8.16]) {
    _box(parts, .82, .11, 7.35, _concrete, 52.68, heightsY + floorY, 37.6);
    for (var i = 0; i <= 10; i++) {
      _box(parts, .045, .84, .045, _metalDark, 52.29, heightsY + floorY + .45,
          34.0 + i * .72);
    }
    _box(parts, .055, .055, 7.35, _metalDark, 52.29, heightsY + floorY + .87,
        37.6);
  }

  // Three attached homes south of the private lane.
  for (var i = 0; i < 3; i++) {
    final x = 62.2 - 2.9 + (i + .5) * 2.9;
    extra.add(makeHouse(HouseOpts(
        x: x,
        z: 26.0,
        y: groundY(26.0),
        w: 2.9,
        d: 6.2,
        floors: 2,
        face: 'z+',
        seed: 8551 + i,
        wall: 5,
        roof: 3,
        roofKind: 'gable',
        porch: true)));
  }
  extra.add(makeHouse(HouseOpts(
      x: 63.0,
      z: 37.0,
      y: groundY(37.0),
      w: 5.0,
      d: 6.0,
      floors: 2,
      face: 'z-',
      seed: 8561,
      wall: 6,
      roof: 1,
      roofKind: 'flat')));
  // The garage opening is the defining dark void of this narrow house.
  _box(parts, 3.15, 2.25, .10, _glassDark, 63.0, groundY(37.0) + 1.18, 33.95);
  _box(parts, 3.35, .16, .22, _metalDark, 63.0, groundY(37.0) + 2.34, 33.93);

  extra.add(buildSakura([
    const SakuraSpot(
        x: 45.0, z: 19.8, scale: 1.16, seed: 8513, lean: .1, leanDir: 4.6),
    const SakuraSpot(
        x: 45.0, z: 28.6, scale: 1.22, seed: 8514, lean: .1, leanDir: 4.6),
    SakuraSpot(
        x: 45.9,
        z: 33.4,
        y: groundY(33.4),
        scale: 1.24,
        seed: 8572,
        lean: .09,
        leanDir: 4.3),
    SakuraSpot(
        x: 51.9,
        z: 44.2,
        y: groundY(44.2),
        scale: 1.1,
        seed: 8573,
        lean: .12,
        leanDir: 2.6),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  extra.add(buildGrove([
    const GroveSpot(x: 68.6, z: 22.0, scale: 1.5, seed: 8574, spread: 1.15),
    GroveSpot(
        x: 68.9,
        z: 41.0,
        y: groundY(41.0),
        scale: 1.6,
        seed: 8575,
        spread: 1.2),
    GroveSpot(
        x: 63.4,
        z: 43.2,
        y: groundY(43.2),
        scale: 1.4,
        seed: 8576,
        spread: 1.1),
    const GroveSpot(x: 60.0, z: 16.4, scale: 1.35, seed: 8577, spread: 1.05),
    const GroveSpot(x: 71.2, z: 28.3, scale: 1.45, seed: 8588, spread: 1.15),
  ]));
  extra.add(buildShrubs([
    const ShrubSpot(x: 44.2, z: 9.6, r: .44, count: 3, seed: 8512),
    const ShrubSpot(
        x: 61.6, z: 13.4, r: .46, count: 3, spread: 1.15, seed: 8523),
    const ShrubSpot(x: 50.2, z: 6.4, r: .42, count: 3, seed: 8524),
    ShrubSpot(
        x: 60.6,
        z: 41.4,
        y: groundY(41.4),
        r: .46,
        count: 3,
        spread: 1.1,
        seed: 8547),
    ShrubSpot(
        x: 52.6,
        z: 32.2,
        y: groundY(32.2),
        r: .4,
        count: 3,
        spread: .95,
        seed: 8548),
    const ShrubSpot(
        x: 63.8, z: 19.6, r: .5, count: 4, spread: 1.35, seed: 8578),
    ShrubSpot(
        x: 58.4,
        z: 44.2,
        y: groundY(44.2),
        r: .46,
        count: 3,
        spread: 1.15,
        seed: 8579),
    const ShrubSpot(
        x: 66.3, z: 31.2, r: .44, count: 3, spread: 1.05, seed: 8587),
  ]));

  return [...bake(parts), ...extra.expand((t) => t)];
}
