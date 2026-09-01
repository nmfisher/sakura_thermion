/// Dart port of the reference `src/world/shop.js::buildShop` -- the corner shop
/// (青空商店) by the crossing: two-storey volume with set-back upper floor,
/// red-and-white striped awning, shopfront glass, shutter recess, upper-storey
/// windows with balcony, wall clutter (AC, pipes, ladder, crates, baskets, bin).
///
/// Deferred: textures (shop sign, shutter slats, posters, banner, meter box,
/// warning plate, vending machines) -- all rendered as solid-colour geometry.
/// Skipped: hullOutline, interactive hitboxes, shutter animation state, vending
/// machines (separate module).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'street.dart';

// ── Materials (shop.js local palette, mapped to const Mat) ──────────────────

const _wall2Mat = Mat(0xfaf6ef, tint: 0x6f6790, bands: '3'); // PAL.wallWhite
const _tileMat = Mat(0xe9edf0, tint: 0x6f6790, bands: '3');
const _roofMat = Mat(0x59617a, tint: 0x544e74, bands: '3'); // PAL.roofSlate
const _metalMat = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _metalDarkMat =
    Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _glassMat =
    Mat(0x9dc0d4, unlit: true); // PAL.glass (flat, transparent deferred)
const _glassDarkMat = Mat(0x53627a, unlit: true); // PAL.glassDark
const _shutterMat = Mat(0x6e6a7a, tint: 0x4b4560, bands: '3'); // PAL.shutter
const _shutterRecessMat = Mat(0x9c95a6, tint: 0x6b6488, bands: '2');
const _interiorMat = Mat(0xe8dfc8, tint: 0x6f6790, bands: '3');
const _shelfMat = Mat(0xbdb3a0, tint: 0x6f6790, bands: '2');
const _acMat = Mat(0xe4e2e6, tint: 0x6f6790, bands: '3');
const _frostMat = Mat(0xc4d2dc, tint: 0x6f6790, bands: '3');
const _crateMat = Mat(0x3f7fbf, tint: 0x4a4a92, bands: '3'); // PAL.crate
const _crateAltMat = Mat(0xe25a4a, tint: 0x7a4060, bands: '3'); // PAL.crateAlt
const _crateRimMat = Mat(0x2f3140, tint: 0x4a4a92, bands: '2');
const _basketMat = Mat(0xdb5a4a, tint: 0x6f6790, bands: '3'); // PAL.basket
const _metalWarmMat =
    Mat(0xc9c0b4, tint: 0x6f6790, bands: '3'); // PAL.metalWarm
const _binMat = Mat(0x5d8fb8, tint: 0x4a4a92, bands: '3'); // PAL.bin
const _signMat =
    Mat(0xfaf6ef, tint: 0x6f6790, bands: '3'); // sign board (texture deferred)
const _wallGrayMat = Mat(0xdedee6, tint: 0x6f6790, bands: '3'); // PAL.wallGray
const _posterMat =
    Mat(0xf0f0f0, tint: 0x6f6790, bands: '2'); // poster (texture deferred)
const _bannerMat =
    Mat(0xf2e8d6, tint: 0x6f6790, bands: '2'); // banner (texture deferred)

// Fruit colours for produce baskets.
const _fruitCols = <int>[0xf0a63c, 0x8fbf4a, 0xe0574a];

// Towel colours: [width, height, colour]
const _towels = <List<dynamic>>[
  [0.34, 0.6, 0xd6e3ee], // wallBlue
  [0.28, 0.48, 0xfbc6d8], // blossom
  [0.3, 0.54, 0xfaf6ef], // wallWhite
];

const _walkH = 0.135; // WALK_H from street.js

/// Build the corner shop geometry as a triangle soup.
///
/// Signature: `List<Tri> buildShop()` -- no context or scene graph.
/// Returns world-space triangles positioned along the street at the crossing.
List<Tri> buildShop(
    {bool shutterGrooves = false,
    int redColor = 0xe0453f,
    int redSoftColor = 0xef6a60,
    int wallColor = 0xf2e7d3}) {
  final rng = RngKit(3311);
  final redMat = Mat(redColor, tint: 0x7a4060, bands: '3');
  final redSoftMat = Mat(redSoftColor, tint: 0x7a4060, bands: '3');
  final wallMat = Mat(wallColor, tint: 0x6f6790, bands: '3');

  // ── Positioning (shop.js constants) ───────────────────────────────────────
  const zNear = 4.55;
  const zFar = 12.6;
  const zMid = (zNear + zFar) / 2; // 8.575
  const xFront = 0.0 + roadHalf + walkW + 0.12; // centerX(8.575)≈0
  const depth = 7.2;
  const y0 = 0.0; // groundY(8.575)≈0

  const h1 = 3.15; // ground floor height
  const h2 = 2.75; // upper floor height

  final parts = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, mx, m));

  // ── Main volume ───────────────────────────────────────────────────────────
  // ground floor
  add(boxGeometry(depth, h1, zFar - zNear),
      trs(xFront + depth / 2, y0 + h1 / 2, zMid), wallMat);
  // upper storey, set back
  add(
      boxGeometry(depth - 0.5, h2, zFar - zNear - 0.3),
      trs(xFront + 0.35 + (depth - 0.5) / 2, y0 + h1 + h2 / 2, zMid),
      _wall2Mat);
  // parapet + roof cap
  add(
      boxGeometry(depth - 0.4, 0.22, zFar - zNear - 0.2),
      trs(xFront + 0.4 + (depth - 0.5) / 2, y0 + h1 + h2 + 0.11, zMid),
      _roofMat);
  // string course between floors
  add(boxGeometry(depth + 0.06, 0.18, zFar - zNear + 0.06),
      trs(xFront + depth / 2, y0 + h1 + 0.05, zMid), _roofMat);

  // ── Tiled base along the front ──────────────────────────────────────────
  add(boxGeometry(0.1, 0.55, zFar - zNear), trs(xFront - 0.04, y0 + 0.27, zMid),
      _tileMat);

  // ── Shutter ───────────────────────────────────────────────────────────────
  const zc = zNear + 4.35;
  const sw = 3.0;
  // top guide rail
  add(boxGeometry(0.18, 0.34, sw + 0.3), trs(xFront - 0.02, y0 + h1 - 0.22, zc),
      _metalDarkMat);
  // side guide rails
  for (final s in [-1.0, 1.0]) {
    add(
        boxGeometry(0.2, h1 - 0.4, 0.14),
        trs(xFront - 0.03, y0 + (h1 - 0.4) / 2, zc + s * (sw / 2 + 0.07)),
        _metalDarkMat);
  }
  // recessed doorway behind shutter
  add(boxGeometry(0.5, h1 - 0.5, sw),
      trs(xFront + 0.3, y0 + (h1 - 0.5) / 2, zc), _shutterRecessMat);
  // shutter slat (texture deferred → solid shutter colour, partially open)
  const sh = h1 - 0.55;
  const shTop = y0 + sh;
  // start 18% open like the reference
  final sy = math.max(0.08, 1.0 - 0.18 * 0.92);
  add(boxGeometry(0.07, sh * sy, sw),
      trs(xFront - 0.055, shTop - (sh * sy) / 2, zc), _shutterMat);
  if (shutterGrooves) {
    // Geometry fallback for shutterTex(26): the texture modulates the entire
    // shutter into alternating dark slats, with each row boundary still
    // available to the depth-ink pass.
    const rows = 26;
    final shutterH = sh * sy;
    final shutterBottom = shTop - shutterH;
    final step = shutterH / rows;
    const slatMats = [
      Mat(0x3a3846, unlit: true),
      Mat(0x3c3a4b, unlit: true),
    ];
    for (var i = 0; i < rows; i++) {
      add(
          boxGeometry(.012, step, sw),
          trs(xFront - .096, shutterBottom + (i + .5) * step, zc),
          slatMats[i % 2]);
    }
  }
  // bottom rail
  add(boxGeometry(0.11, 0.11, sw + 0.02),
      trs(xFront - 0.055, shTop - sh * sy + 0.05, zc), _metalDarkMat);

  // ── Shopfront glass ─────────────────────────────────────────────────────
  const glassZ = zFar - 1.15;
  const glassW = 1.9;
  const glassH = h1 - 0.9;
  const glassY = y0 + 0.45 + glassH / 2;
  // glass pane
  add(boxGeometry(0.12, glassH, glassW), trs(xFront - 0.05, glassY, glassZ),
      _glassMat);
  // mullions
  for (final dz in [-1.0, 0.0, 1.0]) {
    add(boxGeometry(0.16, h1 - 0.85, 0.09),
        trs(xFront - 0.06, glassY, glassZ + dz), _metalMat);
  }
  // tile base below glass
  add(boxGeometry(0.2, 0.45, glassW + 0.1),
      trs(xFront - 0.06, y0 + 0.22, glassZ), _tileMat);
  // metal top rail
  add(boxGeometry(0.2, 0.16, glassW + 0.1),
      trs(xFront - 0.06, y0 + h1 - 0.5, glassZ), _metalMat);
  // warm interior glimpse
  add(boxGeometry(0.5, h1 - 1.1, glassW - 0.3),
      trs(xFront + 0.35, y0 + 0.5 + (h1 - 1.1) / 2, glassZ), _interiorMat);
  // shelving silhouettes inside
  for (var i = 0; i < 3; i++) {
    add(boxGeometry(0.3, 0.08, glassW - 0.5),
        trs(xFront + 0.2, y0 + 0.8 + i * 0.55, glassZ), _shelfMat);
  }

  // ── Awning ──────────────────────────────────────────────────────────────
  const zA = zNear + 2.95;
  const zB = zFar + 0.05;
  const aLen = zB - zA;
  const aOut = 1.85;
  const yA = y0 + h1 - 0.18;
  const drop = 0.42;
  final slope = math.atan2(drop, aOut);
  const stripes = 18;
  const sw2 = aLen / stripes;
  // edge position after rotation
  final edgeX = xFront - aOut * math.cos(slope);
  final edgeY = yA - aOut * math.sin(slope);

  // sloping canvas: alternating red / redSoft stripes baked into two merged meshes
  final partsA = <Part>[];
  final partsB = <Part>[];
  for (var i = 0; i < stripes; i++) {
    final localZ = zA + sw2 * (i + 0.5) - (zA + zB) / 2;
    final stripeGeo = boxGeometry(aOut, 0.07, sw2);
    // Position relative to group origin, then rotate group
    // group origin = (xFront, yA, (zA+zB)/2), rotation.z = slope
    final mx = trs(-aOut / 2, 0, localZ);
    (i % 2 == 0 ? partsA : partsB).add(Part(stripeGeo, mx, redMat));
  }
  // Build awning group: translate + rotate
  final groupTr = trs(xFront, yA, (zA + zB) / 2, 0, 0, slope);
  for (final p in partsA) {
    parts.add(Part(p.geo, groupTr * p.matrix, redMat));
  }
  for (final p in partsB) {
    parts.add(Part(p.geo, groupTr * p.matrix, redSoftMat));
  }

  // front fascia
  add(boxGeometry(0.08, 0.34, aLen),
      trs(edgeX + 0.03, edgeY - 0.15, (zA + zB) / 2), redMat);
  // scallops along the bottom edge of the fascia
  final scallops = (aLen / 0.55).round();
  for (var i = 0; i < scallops; i++) {
    final scGeo = cylGeometry(0.16, 0.16, 0.01, 12);
    // CylinderGeometry is Y-aligned; rotate its thin axis onto X, then place
    // it directly on the outward fascia plane.  The previous multiplied TRS
    // rotated the translation itself and sent every scallop out of frame.
    add(
        scGeo,
        trs(edgeX - 0.012, edgeY - 0.32, zA + (aLen / scallops) * (i + 0.5), 0,
            0, math.pi / 2),
        redMat);
  }

  // support arms
  for (final zArm in [zA + 0.5, (zA + zB) / 2, zB - 0.5]) {
    // arm (rotated to follow slope)
    add(
        applyMatrix(
            boxGeometry(aOut * 1.02, 0.07, 0.07),
            trs(xFront - (aOut / 2) * math.cos(slope),
                yA - (aOut / 2) * math.sin(slope) - 0.08, zArm, 0, 0, slope)),
        Matrix4.identity(),
        _metalDarkMat);
    // vertical strut
    add(
        applyMatrix(boxGeometry(0.06, 0.78, 0.06),
            trs(xFront - 0.14, yA - 0.4, zArm, 0, 0, -0.42)),
        Matrix4.identity(),
        _metalDarkMat);
  }

  // ── Shop sign ────────────────────────────────────────────────────────────
  const signZ = zMid + 0.1;
  const signLen = 5.6;
  // board (texture deferred → white)
  add(boxGeometry(0.14, 0.78, signLen),
      trs(xFront - 0.06, y0 + h1 + 0.62, signZ), _signMat);
  // metal bracket above sign
  add(boxGeometry(0.2, 0.1, signLen + 0.1),
      trs(xFront - 0.06, y0 + h1 + 1.05, signZ), _metalMat);

  // ── Upper storey windows ──────────────────────────────────────────────────
  const xWall = xFront + 0.35;
  const yW = y0 + h1 + 1.38;
  for (final zWin in [zNear + 2.0, zNear + 4.6, zFar - 1.1]) {
    // frame
    add(boxGeometry(0.16, 1.44, 1.66), trs(xWall + 0.05, yW, zWin), _metalMat);
    // glass
    add(boxGeometry(0.05, 1.26, 1.5), trs(xWall - 0.035, yW, zWin),
        _glassDarkMat);
    // mullion
    add(boxGeometry(0.05, 1.26, 0.07), trs(xWall - 0.07, yW, zWin), _metalMat);
    // sill
    add(boxGeometry(0.2, 0.09, 1.74), trs(xWall, yW - 0.78, zWin), _metalMat);
  }

  // balcony over the middle window
  const bz = zNear + 4.6;
  const bx = xFront + 0.02;
  add(boxGeometry(0.42, 0.09, 2.2), trs(bx + 0.18, y0 + h1 + 0.62, bz),
      _metalDarkMat);
  // balcony rail top and bottom bars
  for (final by in [0.44, 0.9]) {
    add(boxGeometry(0.06, 0.06, 2.2), trs(bx, y0 + h1 + 0.62 + by, bz),
        _metalMat);
  }
  // balcony vertical balusters
  for (var i = 0; i <= 9; i++) {
    add(boxGeometry(0.04, 0.52, 0.04),
        trs(bx, y0 + h1 + 0.9, bz - 1.05 + i * 0.233), _metalMat);
  }
  // clothesline
  add(boxGeometry(0.04, 0.04, 1.9), trs(bx + 0.05, y0 + h1 + 1.62, bz),
      _metalMat);
  // towels hanging to dry (flat panels, double-sided look via thin boxes)
  for (var i = 0; i < _towels.length; i++) {
    final t = _towels[i];
    final tw = t[0] as double, th = t[1] as double, tc = t[2] as int;
    final towelMat = Mat(tc, tint: 0x6f6790, bands: '2');
    add(
        applyMatrix(boxGeometry(0.03, th, tw),
            trs(bx + 0.05, y0 + h1 + 1.6 - th / 2, bz - 0.62 + i * 0.62)),
        Matrix4.identity(),
        towelMat);
  }

  // ── Wall clutter and services ────────────────────────────────────────────
  // air-conditioning unit
  add(boxGeometry(0.62, 0.62, 0.95),
      trs(xFront + 0.3, y0 + h1 + 0.45, zFar - 0.75), _acMat);
  // AC fan grille (cylinder on its side)
  add(
      applyMatrix(
          cylGeometry(0.22, 0.22, 0.06, 12), trs(0, 0, 0, 0, 0, math.pi / 2)),
      trs(xFront - 0.02, y0 + h1 + 0.45, zFar - 0.75),
      _metalDarkMat);

  // pipes running down the wall
  for (final entry in [
    [zFar - 0.2, h1],
    [zNear + 0.35, h1 + 1.2],
  ]) {
    final pz = (entry[0] as num).toDouble(), ph = (entry[1] as num).toDouble();
    add(cylGeometry(0.05, 0.05, ph, 8), trs(xFront - 0.06, y0 + ph / 2, pz),
        _metalMat);
    final nClamps = (ph / 1.1).floor();
    for (var i = 0; i < nClamps; i++) {
      add(boxGeometry(0.1, 0.06, 0.1),
          trs(xFront - 0.04, y0 + 0.6 + i * 1.1, pz), _metalDarkMat);
    }
  }

  // electricity meter box (texture deferred → grey)
  add(boxGeometry(0.14, 0.5, 0.36), trs(xFront - 0.06, y0 + 1.75, zNear + 0.75),
      _wallGrayMat);

  // posters beside the door (texture deferred → off-white flat planes as thin boxes)
  for (var i = 0; i < 3; i++) {
    add(
        applyMatrix(
            boxGeometry(0.03, 0.58, 0.42),
            trs(xFront - 0.055, y0 + 1.92 - (i % 2) * 0.12,
                zNear + 2.55 + i * 0.48, 0, rng.range(-0.03, 0.03), 0)),
        Matrix4.identity(),
        _posterMat);
  }

  // hanging vertical banner (texture deferred → cream)
  add(boxGeometry(0.03, 1.7, 0.42),
      trs(xFront - 1.6, y0 + h1 - 1.35, zNear + 0.55), _bannerMat);
  // banner pole
  add(boxGeometry(0.04, 0.04, 0.5),
      trs(xFront - 1.6, y0 + h1 - 0.5, zNear + 0.55), _metalDarkMat);

  // security-camera plate (texture deferred → white)
  add(boxGeometry(0.03, 0.6, 0.3), trs(xFront - 0.055, y0 + 2.55, zNear + 1.0),
      _posterMat);

  // ── North gable (back face) clutter ──────────────────────────────────────
  const zN = zFar + 0.01;
  // string course on gable
  add(boxGeometry(depth - 0.6, 0.16, 0.14),
      trs(xFront + 0.4 + depth / 2 - 0.3, y0 + 1.55, zN), _roofMat);
  // pipes on gable
  for (final xo in [1.5, 4.9]) {
    add(cylGeometry(0.05, 0.05, h1 + 0.4, 8),
        trs(xFront + xo, y0 + (h1 + 0.4) / 2, zN + 0.04), _metalMat);
    for (var i = 0; i < 3; i++) {
      add(boxGeometry(0.11, 0.06, 0.11),
          trs(xFront + xo, y0 + 0.7 + i * 1.1, zN + 0.08), _metalDarkMat);
    }
  }
  // small frosted window, upper storey on gable
  add(boxGeometry(1.05, 0.95, 0.14),
      trs(xFront + 2.9, y0 + h1 + 1.5, zN - 0.02), _metalMat);
  add(boxGeometry(0.9, 0.8, 0.06), trs(xFront + 2.9, y0 + h1 + 1.5, zN + 0.05),
      _frostMat);
  add(boxGeometry(0.06, 0.8, 0.07), trs(xFront + 2.9, y0 + h1 + 1.5, zN + 0.08),
      _metalMat);
  // access ladder
  for (final dx in [0.0, 0.42]) {
    add(
        boxGeometry(0.05, h2 + 0.5, 0.05),
        trs(xFront + 5.6 + dx, y0 + h1 + (h2 + 0.5) / 2, zN + 0.12),
        _metalDarkMat);
  }
  for (var i = 0; i < 7; i++) {
    add(
        boxGeometry(0.46, 0.035, 0.035),
        trs(xFront + 5.81, y0 + h1 + 0.25 + i * 0.42, zN + 0.12),
        _metalDarkMat);
  }
  // posters on gable
  for (var i = 0; i < 2; i++) {
    add(
        applyMatrix(
            boxGeometry(0.44, 0.6, 0.03),
            trs(xFront + 0.75 + i * 0.55, y0 + 1.05, zN + 0.05,
                rng.range(-0.02, 0.02), 0, 0)),
        Matrix4.identity(),
        _posterMat);
  }

  // ── Pavement clutter ─────────────────────────────────────────────────────
  const walkY = y0 + _walkH;

  // stacked drink crates
  const cw = 0.52, ch = 0.29, cd = 0.36;
  const crateLayout = [
    [0.0, 0, 0.0],
    [0.0, 1, 0.0],
    [0.0, 2, 0.0],
    [0.58, 0, 0.05],
    [0.58, 1, 0.05],
    [-0.05, 0, 0.42],
  ];
  final cratePos = [xFront + 0.55, walkY, zFar - 0.85];
  for (var i = 0; i < crateLayout.length; i++) {
    final cl = crateLayout[i];
    final dx = cl[0] as double, ly = cl[1] as int, dz = cl[2] as double;
    add(
        boxGeometry(cw, ch, cd),
        trs(cratePos[0] + dx, cratePos[1] + ch / 2 + ly * ch, cratePos[2] + dz),
        i % 2 != 0 ? _crateMat : _crateAltMat);
    // hollow rim
    add(
        boxGeometry(cw - 0.06, 0.05, cd - 0.06),
        trs(cratePos[0] + dx, cratePos[1] + ch - 0.01 + ly * ch,
            cratePos[2] + dz),
        _crateRimMat);
  }

  // produce baskets by the door
  for (var i = 0; i < 3; i++) {
    final bx2 = xFront - 0.7 + i * 0.05;
    final bz2 = zFar - 2.9 + i * 0.52;
    // table top is walkY + 0.305; add half basket height
    add(cylGeometry(0.24, 0.19, 0.16, 10), trs(bx2, walkY + 0.385, bz2),
        i == 1 ? _basketMat : _crateMat);
    // fruit contents
    for (var k = 0; k < 3; k++) {
      final fruitMat = Mat(_fruitCols[k], tint: 0x6f6790, bands: '2');
      add(
          icosahedronGeometry(0.075, 0),
          trs(
              bx2 + rng.range(-0.1, 0.1),
              walkY + 0.385 + 0.16 / 2 + 0.075 + 0.01,
              bz2 + rng.range(-0.1, 0.1)),
          fruitMat);
    }
  }

  // trestle table under the baskets
  add(boxGeometry(0.6, 0.05, 1.7), trs(xFront - 0.68, walkY + 0.28, zFar - 2.4),
      _metalWarmMat);
  for (final dz in [-0.7, 0.7]) {
    add(boxGeometry(0.05, 0.28, 0.05),
        trs(xFront - 0.68, walkY + 0.14, zFar - 2.4 + dz), _metalDarkMat);
  }

  // bin beside the shutter
  const binZ = zNear + 0.12;
  add(cylGeometry(0.24, 0.21, 0.72, 12), trs(xFront - 0.62, walkY + 0.36, binZ),
      _binMat);
  add(cylGeometry(0.26, 0.26, 0.06, 12), trs(xFront - 0.62, walkY + 0.74, binZ),
      _metalDarkMat);

  // ── Bake ──────────────────────────────────────────────────────────────────
  return bake(parts);
}
