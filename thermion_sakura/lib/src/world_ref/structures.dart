/// Dart ports of five three.js structure modules from the sakura reference:
///   - buildApproach()    -- 通学路 school route green belt + crossing
///   - buildShrine()      -- 桜守神社 torii gates, hall, temizuya, lanterns
///   - buildShotengai()   -- さくら坂商店街 shopping street structure
///   - buildKoenmae()      -- 公園前 link footways + timber fence
///   - buildOverbridge()  -- 跨線橋 pedestrian overbridge deck, towers, stairs
///
/// Conventions: return List<Tri>, no ctx. Inline PAL colours as Mat(...).
/// Defer textures, skip hullOutline. RngKit mirrors rngKit.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'street.dart';

// ============================================================================
// APPROACH -- 通学路
// ============================================================================

/// Green belt strips along the school route, pedestrian crossing,
/// bollards, and a lineside equipment cabinet.
List<Tri> buildApproach() {
  final parts = <Part>[];

  // Green belt marking (two strips, one each side of the carriageway).
  final greenMat = const Mat(0x7c9c80, tint: 0x5b6f8c, bands: '3');
  const zTop = -65.0; // Z_MIN + 1.0
  for (final s in [-1, 1]) {
    final g = stripGeometry(
      zTop, -28.0, 1.4,
      (z) => Vector2(centerX(z) + s * (roadHalf - 0.86), groundY(z) + 0.017),
      (z) => Vector2(centerX(z) + s * (roadHalf - 0.05), groundY(z) + 0.017),
      flip: s < 0,
    );
    parts.add(Part(g, Matrix4.identity(), greenMat));
  }

  // Pedestrian crossing stripes at the school gate.
  const gateZ = -49.5;
  final gateCx = centerX(gateZ);
  final crossingMat = const Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2');
  for (var i = 0; i < 7; i++) {
    parts.add(Part(
      boxGeometry(0.46, 0.02, 3.6),
      trs(gateCx - roadHalf + 0.42 + i * 0.82, groundY(gateZ) + 0.03, gateZ),
      crossingMat,
    ));
  }

  // Bollards at the road end.
  const zEnd = -65.0;
  final cxEnd = centerX(zEnd);
  final yEnd = groundY(zEnd);
  const bollardMat = Mat(0xf4c033, tint: 0x8f7050, bands: '3'); // PAL.yellow
  const bollardCapMat = Mat(0x322e3b, tint: 0x4b4560, bands: '2'); // PAL.black
  for (final s in [-1.0, 1.0]) {
    parts.add(Part(
      cylGeometry(0.09, 0.1, 0.9, 8),
      trs(cxEnd + s * 2.6, yEnd + 0.45, zEnd + 0.7),
      bollardMat,
    ));
    parts.add(Part(
      cylGeometry(0.1, 0.1, 0.16, 8),
      trs(cxEnd + s * 2.6, yEnd + 0.62, zEnd + 0.7),
      bollardCapMat,
    ));
  }

  // Lineside equipment cabinet.
  const cabMat = Mat(0xd8d5da, tint: 0x6f6890, bands: '3'); // PAL.cabinet
  const cabTopMat = Mat(0xb6b2bc, tint: 0x6a6288, bands: '3'); // PAL.cabinetTop
  const cabZ = -41.6;
  final cabX = centerX(cabZ) + roadHalf + walkW - 0.5;
  parts.add(Part(
    boxGeometry(0.7, 1.1, 0.44),
    trs(cabX, groundY(cabZ) + walkW * 0.135 + 0.55, cabZ),
    cabMat,
  ));
  parts.add(Part(
    boxGeometry(0.78, 0.07, 0.52),
    trs(cabX, groundY(cabZ) + walkW * 0.135 + 1.13, cabZ),
    cabTopMat,
  ));

  return bake(parts);
}

// ============================================================================
// SHRINE -- 桜守神社
// ============================================================================

const _toriiMat = Mat(0xd8412f, tint: 0x7a4060, bands: '3'); // PAL.torii
const _toriiDeepMat = Mat(0xa72f23, tint: 0x7a4060, bands: '3'); // PAL.toriiDeep
const _shrineWoodMat = Mat(0xa9744f, tint: 0x5c5680, bands: '3'); // PAL.shrineWood
const _shrineWoodDarkMat = Mat(0x8a604a, tint: 0x554e74, bands: '3'); // PAL.shrineWoodDark
const _shrineRoofMat = Mat(0x69707e, tint: 0x4a4468, bands: '3'); // PAL.shrineRoof
const _stoneMat = Mat(0xc6c0cb, tint: 0x655d80, bands: '3'); // PAL.stone
const _stoneDarkMat = Mat(0xa39daf, tint: 0x605878, bands: '3'); // PAL.stoneDark
const _stoneWarmMat = Mat(0xcfc6bc, tint: 0x655d80, bands: '3'); // PAL.stoneWarm
const _ropeMat = Mat(0xf0e5ca, tint: 0x8a7f9c, bands: '3'); // PAL.rope
const _paperMat = Mat(0xfbf8f0, tint: 0x8e86ad, bands: '2');
const _shrineMetalMat = Mat(0xb8bcc6, tint: 0x666090, bands: '3'); // PAL.metal
const _shrineMetalDarkMat = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _bronzeMat = Mat(0x8f7448, tint: 0x6a5a80, bands: '3');
const _bambooMat = Mat(0x94b06b, tint: 0x5b6f8c, bands: '3'); // PAL.bamboo
const _bambooDeepMat = Mat(0x6f8c50, tint: 0x5b6f8c, bands: '3'); // PAL.bambooDeep
const _shrineBibMat = Mat(0xd8453f, tint: 0x7a4060, bands: '2'); // PAL.shrineBib
const _recessMat = Mat(0x4c4656, tint: 0x453f5c, bands: '2');

/// Shrine geometry: two torii gates, steps with cheeks and handrail,
/// the main hall (haiden), temizuya (ablution pavilion), stone lanterns,
/// fox statues, ema rack frame, and offertory box.
List<Tri> buildShrine() {
  final parts = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, mx, m));

  const laneX = -27.9;
  const axisX = -27.9;
  const stepZ0 = 20.5;
  const nSteps = 11;
  const rise = 0.19;
  const run = 0.46;
  final top = rise * nSteps; // 2.09
  const terZ0 = 25.4;

  // -- Stone post at alley mouth --
  add(boxGeometry(0.24, 1.5, 0.24), trs(laneX - 1.85, 0.75, 5.4), _stoneMat);
  add(boxGeometry(0.3, 0.07, 0.3), trs(laneX - 1.85, 1.53, 5.4), _stoneWarmMat);

  // -- Torii gates --
  _buildTorii(parts, x: axisX, z: 19.9, y: 0, w: 3.5, h: 3.4, plain: false);
  _buildTorii(parts, x: axisX, z: terZ0 + 1.5, y: top, w: 2.7, h: 2.7, plain: true);

  // -- Steps --
  for (final s in [-1.0, 1.0]) {
    for (var i = 0; i < nSteps; i++) {
      add(boxGeometry(0.3, rise * (i + 1) + 0.22, run),
        trs(axisX + s * 1.85, (rise * (i + 1) + 0.22) / 2, stepZ0 + run * (i + 0.5)), _stoneDarkMat);
    }
  }
  // Handrail up the west cheek.
  final handrailL = run * nSteps;
  final handrailLen = math.sqrt(handrailL * handrailL + top * top) + 0.3;
  final handrailAngle = math.pi / 2 - math.atan2(top, handrailL);
  add(applyMatrix(cylGeometry(0.032, 0.032, handrailLen, 7), trs(0, 0, 0, handrailAngle, 0, 0)),
      trs(axisX - 1.85, top / 2 + 0.95, stepZ0 + handrailL / 2), _shrineMetalDarkMat);
  for (var i = 0; i <= 3; i++) {
    final t = i / 3.0;
    add(cylGeometry(0.03, 0.03, 0.95, 6),
      trs(axisX - 1.85, rise * nSteps * t + 0.47, stepZ0 + handrailL * t), _shrineMetalDarkMat);
  }

  // -- Terrace platform --
  add(boxGeometry(16.0, 0.07, 14.6), trs(-28.0, top - 0.035, 32.7), _stoneWarmMat);

  // -- Retaining walls --
  const wallH = 2.9;
  final wallY = top + 0.5 - wallH;
  add(boxGeometry(14.5, wallH, 0.34), trs(-29.05, wallY + wallH / 2, terZ0), _stoneDarkMat);
  add(boxGeometry(14.5, wallH, 0.34), trs(-25.75, wallY + wallH / 2, terZ0), _stoneDarkMat);
  add(boxGeometry(0.34, wallH, 14.6), trs(-36.0, wallY + wallH / 2, 32.7), _stoneDarkMat);
  add(boxGeometry(0.34, wallH, 14.6), trs(-20.0, wallY + wallH / 2, 32.7), _stoneDarkMat);
  add(boxGeometry(4.4, wallH, 0.34), trs(-33.1, wallY + wallH / 2, 40.0), _stoneDarkMat);
  add(boxGeometry(15.0, wallH, 0.34), trs(-27.4, wallY + wallH / 2, 40.0), _stoneDarkMat);

  // -- Haiden (main hall) --
  _buildHaiden(parts, x: axisX, z: 36.2, y: top);

  // -- Temizuya (ablution pavilion) --
  _buildTemizuya(parts, x: -33.2, z: 29.4, y: top);

  // -- Stone lanterns --
  _buildStoneLantern(parts, x: axisX - 2.55, z: 19.4, y: 0.0, scale: 1.0);
  _buildStoneLantern(parts, x: axisX + 2.55, z: 19.4, y: 0.0, scale: 1.0);
  _buildStoneLantern(parts, x: axisX - 2.55, z: terZ0 + 2.6, y: top, scale: 0.95);
  _buildStoneLantern(parts, x: axisX + 2.55, z: terZ0 + 2.6, y: top, scale: 0.95);
  _buildStoneLantern(parts, x: axisX - 2.55, z: 33.0, y: top, scale: 1.05);
  _buildStoneLantern(parts, x: axisX + 2.55, z: 33.0, y: top, scale: 1.05);

  // -- Fox statues --
  _buildFox(parts, x: axisX - 2.9, z: 33.6, y: top, ry: -0.4);
  _buildFox(parts, x: axisX + 2.9, z: 33.6, y: top, ry: 0.4);

  // -- Ema rack frame --
  _buildEmaFrame(parts, x: -22.6, z: 31.6, y: top, ry: -math.pi / 2, len: 3.2);

  // -- Omikuji stand --
  _buildOmikujiStand(parts, x: -23.2, z: 28.0, y: top, ry: -math.pi / 2 + 0.2);

  return bake(parts);
}

void _buildTorii(List<Part> parts, {required double x, required double z, required double y, double w = 3.4, double h = 3.3, bool plain = false}) {
  final pr = 0.15 * (w / 3.4);
  final red = plain ? _toriiDeepMat : _toriiMat;
  final wt = trs(x, y, z);

  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, wt * mx, m));

  // Pillars, leaning inward.
  for (final s in [-1.0, 1.0]) {
    add(cylGeometry(pr * 0.9, pr, h, 10), trs(s * w / 2, h / 2, 0, 0, 0, s * 0.018), red);
    add(cylGeometry(pr * 1.5, pr * 1.7, 0.24, 10), trs(s * w / 2, 0.12, 0), _stoneDarkMat);
  }
  // Shimaki -- lower tie beam.
  add(boxGeometry(w + 0.5, 0.15, pr * 1.5), trs(0, h * 0.72, 0), _toriiDeepMat);
  // Shimagi -- flat beam under the lintel.
  add(boxGeometry(w + 1.0, 0.19, pr * 2.1), trs(0, h - 0.16, 0), _toriiDeepMat);
  // Kasagi -- three segments with upswept tips.
  add(boxGeometry(w * 0.6, 0.2, pr * 2.5), trs(0, h + 0.04, 0), red);
  for (final s in [-1.0, 1.0]) {
    final seg = (w + 1.15 - w * 0.6) / 2;
    add(boxGeometry(seg, 0.2, pr * 2.5), trs(s * (w * 0.3 + seg / 2), h + 0.04 + seg * 0.09, 0, 0, 0, -s * 0.19), red);
  }
  // Gakuzuka -- block between beams.
  add(boxGeometry(0.28, h * 0.24, pr * 1.7), trs(0, h * 0.85, 0), red);
}

void _buildHaiden(List<Part> parts, {required double x, required double z, required double y}) {
  // Collect parts in local space, then apply group transform.
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));

  const w = 5.4, d = 4.4;
  const ph = 0.66; // plinth
  const wh = 2.5; // wall height
  final yb = ph + 0.1;

  // Stone plinth.
  add(boxGeometry(w + 0.9, ph, d + 0.9), trs(0, ph / 2, 0), _stoneMat);
  add(boxGeometry(w + 1.1, 0.1, d + 1.1), trs(0, ph + 0.05, 0), _stoneMat);
  // Front steps.
  for (var i = 0; i < 3; i++) {
    final h = ph * ((3 - i) / 3);
    add(boxGeometry(2.6, h, 0.34), trs(0, h / 2, (d + 0.9) / 2 + 0.17 + i * 0.34), _stoneMat);
  }

  // Corner pillars.
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      add(cylGeometry(0.15, 0.16, wh, 8), trs(sx * (w / 2 - 0.15), yb + wh / 2, sz * (d / 2 - 0.15)), _shrineWoodDarkMat);
    }
    add(cylGeometry(0.13, 0.14, wh, 8), trs(sx * 0.95, yb + wh / 2, d / 2 - 0.15), _shrineWoodDarkMat);
  }

  // Back wall.
  add(boxGeometry(w - 0.2, wh, 0.16), trs(0, yb + wh / 2, -(d / 2 - 0.1)), _shrineWoodMat);
  // Side walls.
  for (final sx in [-1.0, 1.0]) {
    add(boxGeometry(0.16, wh, d - 0.2), trs(sx * (w / 2 - 0.1), yb + wh / 2, 0), _shrineWoodMat);
  }
  // Head beam.
  add(boxGeometry(w, 0.22, 0.2), trs(0, yb + wh - 0.11, d / 2 - 0.14), _shrineWoodDarkMat);
  // Sill beam.
  add(boxGeometry(w, 0.16, 0.24), trs(0, yb + 0.08, d / 2 - 0.14), _shrineWoodDarkMat);

  // Front latticed panels.
  for (final sx in [-1.0, 1.0]) {
    add(boxGeometry(1.3, wh - 0.4, 0.1), trs(sx * 1.85, yb + wh / 2, d / 2 - 0.14), _shrineWoodMat);
    for (var i = 0; i < 7; i++) {
      add(boxGeometry(0.05, wh - 0.5, 0.05), trs(sx * 1.85 - 0.55 + i * 0.18, yb + wh / 2, d / 2 - 0.07), _shrineWoodDarkMat);
    }
  }

  // Dark recess behind open bay.
  add(boxGeometry(1.9, wh - 0.4, 0.08), trs(0, yb + wh / 2 - 0.1, d / 2 - 0.7), _recessMat);
  // Mirror.
  add(applyMatrix(cylGeometry(0.24, 0.24, 0.05, 16), trs(0, 0, 0, math.pi / 2, 0, 0)),
      trs(0, yb + 1.35, d / 2 - 0.62), const Mat(0xb8b0a0, tint: 0x7d74a0, bands: '2'));
  // Mirror stand.
  add(boxGeometry(0.1, 0.5, 0.1), trs(0, yb + 0.95, d / 2 - 0.62), _shrineWoodDarkMat);

  // Roof: bracket band, rafters, two slabs, ridge, gable infill.
  const eave = 1.15;
  final rw = w + eave * 2;
  final rd = d + eave * 2;
  const rh = 1.55;
  final slope = math.atan2(rh, rw / 2);
  final slab = math.sqrt((rw / 2) * (rw / 2) + rh * rh) + 0.1;
  final yr = yb + wh;

  // Bracket band.
  add(boxGeometry(w + 0.7, 0.26, d + 0.7), trs(0, yr + 0.13, 0), _shrineWoodDarkMat);
  // Rafters.
  for (var i = 0; i < 13; i++) {
    add(boxGeometry(0.08, 0.14, rd - 0.4), trs(-rw / 2 + 0.4 + (i * (rw - 0.8)) / 12, yr + 0.34, 0), _shrineWoodDarkMat);
  }
  // Two roof slabs.
  for (final s in [-1.0, 1.0]) {
    add(boxGeometry(slab, 0.3, rd), trs(s * (rw / 4), yr + 0.4 + rh / 2, 0, 0, 0, -s * slope), _shrineRoofMat);
    // Upswept tip.
    add(boxGeometry(0.8, 0.26, rd), trs(s * (rw / 2 + 0.24), yr + 0.4 + 0.06, 0, 0, 0, -s * (slope - 0.34)), _shrineRoofMat);
  }
  // Ridge beam.
  add(boxGeometry(0.5, 0.34, rd + 0.2), trs(0, yr + 0.4 + rh + 0.1, 0), _shrineRoofMat);
  // Katsuogi billets.
  for (var i = 0; i < 4; i++) {
    add(cylGeometry(0.11, 0.11, 0.62, 8), trs(0, yr + 0.4 + rh + 0.34, -rd / 2 + 1.2 + i * ((rd - 2.4) / 3), 0, 0, math.pi / 2), _shrineWoodDarkMat);
  }
  // Chigi finials.
  for (final s in [-1.0, 1.0]) {
    for (final sx in [-1.0, 1.0]) {
      add(applyMatrix(boxGeometry(0.11, 1.5, 0.11), trs(0, 0, 0, 0, 0, sx * 0.28)),
          trs(sx * 0.34, yr + 0.4 + rh + 0.5, s * (rd / 2 - 0.3)), _shrineWoodDarkMat);
    }
  }
  // Gable infill (triangular extrusion).
  final triShape = <Vector2>[
    Vector2(-rw / 2 + 0.3, 0),
    Vector2(rw / 2 - 0.3, 0),
    Vector2(0, rh * 0.88),
  ];
  final triGeo = applyMatrix(extrudeGeometry(triShape, 0.14), trs(0, 0, -0.07));
  for (final s in [-1.0, 1.0]) {
    add(triGeo, trs(0, yr + 0.4, s * (rd / 2 - 0.07)), _shrineWoodMat);
  }

  // Bell.
  add(icosahedronGeometry(0.19, 1), trs(0, yb + wh - 0.78, d / 2 + 0.04), _bronzeMat);
  // Bell cord.
  add(cylGeometry(0.03, 0.03, 0.4, 5), trs(0, yb + wh - 0.52, d / 2 + 0.04), _shrineMetalDarkMat);
  add(cylGeometry(0.05, 0.06, 1.5, 6), trs(0, yb + wh - 1.7, d / 2 + 0.04), const Mat(0xc8503c, tint: 0x7a4060, bands: '3'));
  // Cord knots.
  for (var i = 0; i < 3; i++) {
    add(cylGeometry(0.07, 0.07, 0.05, 8), trs(0, yb + wh - 1.1 - i * 0.5, d / 2 + 0.04), const Mat(0xe0e0e0, tint: 0x8a7f9c, bands: '2'));
  }

  // Offertory box (賽銭箱).
  const bx = 0.0, bz = d / 2 + 1.15;
  const bw = 1.7, bd = 0.66, bh = 0.66;
  add(boxGeometry(bw, bh, bd), trs(bx, 0.33, bz), _shrineWoodDarkMat);
  add(boxGeometry(bw + 0.12, 0.07, bd + 0.12), trs(bx, bh + 0.03, bz), _shrineWoodMat);
  add(boxGeometry(bw - 0.2, 0.06, bd - 0.2), trs(bx, bh + 0.02, bz), const Mat(0x3c3746, tint: 0x453f5c, bands: '2'));
  // Slats.
  final ns = ((bw - 0.2) / 0.12).round();
  for (var i = 0; i < ns; i++) {
    add(boxGeometry(0.05, 0.1, bd - 0.16), trs(bx - (bw - 0.25) / 2 + i * ((bw - 0.25) / (ns - 1)), bh + 0.04, bz), _shrineWoodMat);
  }

  // Name board (texture deferred -> plain wood).
  add(boxGeometry(0.7, 1.9, 0.09), trs(-2.05, yb + wh + 0.5, d / 2 + 0.3), _shrineWoodMat);

  // Shimenawa rope across the bay.
  const ropeW = w - 1.0;
  const ropeThick = 0.11;
  add(boxGeometry(ropeW, ropeThick * 2, ropeThick * 2), trs(0, yb + wh - 0.34, d / 2 + 0.06), _ropeMat);
  // Bound tufts.
  for (var i = 0; i < 3; i++) {
    final u = 0.25 + i * 0.25;
    add(cylGeometry(ropeThick * 1.35, ropeThick * 1.35, ropeThick * 0.7, 8),
        trs(-ropeW / 2 + ropeW * u, yb + wh - 0.34, d / 2 + 0.06, 0, 0, math.pi / 2),
        const Mat(0xdfd2b4, tint: 0x8a7f9c, bands: '2'));
  }
  // Paper streamers.
  for (var i = 0; i < 5; i++) {
    final u = (i + 0.5) / 5;
    add(boxGeometry(0.085, 0.075, 0.01),
        trs(-ropeW / 2 + ropeW * u, yb + wh - 0.34 - ropeThick - 0.04, d / 2 + 0.06), _paperMat);
  }

  // Apply the group transform: the hall faces +Z in local space, then gets turned PI.
  final groupMat = trs(x, y, z, 0, math.pi, 0);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

void _buildTemizuya(List<Part> parts, {required double x, required double z, required double y}) {
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));
  const w = 2.7, d = 2.2, ph = 2.35;

  // Stone base slab.
  add(boxGeometry(w + 0.6, 0.16, d + 0.6), trs(0, 0.08, 0), _stoneMat);
  // Corner posts on stone bases.
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      add(cylGeometry(0.11, 0.12, ph, 8), trs(sx * (w / 2), 0.16 + ph / 2, sz * (d / 2)), _shrineWoodMat);
      add(cylGeometry(0.17, 0.19, 0.18, 8), trs(sx * (w / 2), 0.16 + 0.09, sz * (d / 2)), _stoneMat);
    }
  }
  // Top beams.
  for (final sx in [-1.0, 1.0]) {
    add(boxGeometry(0.13, 0.16, d + 0.2), trs(sx * (w / 2), 0.16 + ph - 0.08, 0), _shrineWoodMat);
  }
  add(boxGeometry(w + 0.3, 0.15, 0.13), trs(0, 0.16 + ph - 0.08, 0), _shrineWoodMat);

  // Hipped roof.
  final yr = 0.16 + ph;
  add(boxGeometry(w + 0.9, 0.2, d + 0.9), trs(0, yr + 0.1, 0), _shrineWoodMat);
  add(cylGeometry(0, 1 / math.sqrt2, 1, 4), trs(0, yr + 0.2 + 0.55, 0, 0, math.pi / 4, 0, w + 1.3, 1.1, d + 1.3), _shrineRoofMat);
  add(boxGeometry(w + 1.3, 0.18, d + 1.3), trs(0, yr + 0.24, 0), _shrineRoofMat);
  add(cylGeometry(0.09, 0.09, 0.34, 8), trs(0, yr + 1.42, 0), _shrineWoodMat);

  // Stone trough.
  const tw = 1.6, td = 0.9, th = 0.62;
  add(boxGeometry(tw, th, td), trs(0, 0.16 + th / 2, 0), _stoneMat);
  add(boxGeometry(tw + 0.14, 0.09, td + 0.14), trs(0, 0.16 + th, 0), _stoneMat);
  add(boxGeometry(tw - 0.26, 0.1, td - 0.26), trs(0, 0.16 + th - 0.06, 0), const Mat(0x8f8a9c, tint: 0x605878, bands: '2'));
  // Bamboo spout.
  add(applyMatrix(cylGeometry(0.045, 0.045, 0.7, 7), trs(0, 0, 0, 1.3, 0, 0)),
      trs(0, 0.16 + th + 0.42, -0.34), _bambooMat);
  add(cylGeometry(0.05, 0.05, 0.5, 7), trs(0, 0.16 + th + 0.3, -0.5), _bambooDeepMat);

  // Ladle rail uprights + rail.
  for (final s in [-1.0, 1.0]) {
    add(cylGeometry(0.026, 0.028, 0.30, 6), trs(s * (tw / 2 - 0.14), 0.16 + th + 0.19, 0.06), _bambooMat);
  }
  add(applyMatrix(cylGeometry(0.028, 0.028, tw - 0.1, 6), trs(0, 0, 0, 0, 0, math.pi / 2)),
      trs(0, 0.16 + th + 0.3, 0.06), _bambooMat);

  // Ladle bowls (hemisphere approximation).
  for (var i = 0; i < 3; i++) {
    final lx = -0.48 + i * 0.48;
    add(cylGeometry(0.085, 0.085, 0.08, 10), trs(lx, 0.16 + th + 0.28, -0.14), const Mat(0xb08f62, tint: 0x6f6790, bands: '3'));
    add(applyMatrix(cylGeometry(0.017, 0.017, 0.4, 5), trs(0, 0, 0, math.pi / 2, 0, 0)),
        trs(lx, 0.16 + th + 0.3, 0.1), _bambooMat);
  }

  // Apply world offset.
  final groupMat = trs(x, y, z);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

void _buildStoneLantern(List<Part> parts, {required double x, required double z, required double y, double scale = 1.0}) {
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));
  final S = scale;

  add(cylGeometry(0.34 * S, 0.4 * S, 0.2 * S, 8), trs(0, 0.1 * S, 0), _stoneMat);
  add(cylGeometry(0.15 * S, 0.19 * S, 0.9 * S, 8), trs(0, 0.65 * S, 0), _stoneMat);
  add(cylGeometry(0.3 * S, 0.22 * S, 0.14 * S, 8), trs(0, 1.17 * S, 0), _stoneMat);
  // Fire box corner posts.
  for (var i = 0; i < 4; i++) {
    final a = (i / 4) * math.pi * 2 + math.pi / 4;
    add(applyMatrix(boxGeometry(0.1 * S, 0.42 * S, 0.1 * S), trs(0, 0, 0, 0, -a, 0)),
        trs(math.cos(a) * 0.2 * S, 1.45 * S, math.sin(a) * 0.2 * S), _stoneMat);
  }
  add(cylGeometry(0.3 * S, 0.3 * S, 0.07 * S, 8), trs(0, 1.69 * S, 0), _stoneMat);
  // Roof cone.
  add(cylGeometry(0, 0.42 * S, 0.34 * S, 8), trs(0, 1.89 * S, 0), _stoneMat);
  // Finial.
  add(icosahedronGeometry(0.09 * S, 0), trs(0, 2.1 * S, 0), _stoneMat);
  // Dark fire box interior.
  add(cylGeometry(0.16 * S, 0.16 * S, 0.4 * S, 8), trs(0, 1.45 * S, 0), const Mat(0x4a4454, tint: 0x453f5c, bands: '2'));

  final groupMat = trs(x, y, z);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

void _buildFox(List<Part> parts, {required double x, required double z, required double y, double ry = 0}) {
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));

  // Plinth.
  add(boxGeometry(0.56, 0.62, 0.46), trs(0, 0.31, 0), _stoneDarkMat);
  add(boxGeometry(0.64, 0.07, 0.54), trs(0, 0.65, 0), _stoneMat);
  // Body.
  add(cylGeometry(0.11, 0.2, 0.5, 8), trs(0, 0.93, 0), _stoneMat);
  // Chest.
  add(icosahedronGeometry(0.14, 1), trs(0, 0.86, 0.11), _stoneMat);
  // Head.
  add(icosahedronGeometry(0.12, 1), trs(0, 1.26, 0.03), _stoneMat);
  // Muzzle.
  add(applyMatrix(cylGeometry(0, 0.07, 0.2, 6), trs(0, 0, 0, math.pi / 2 + 0.12, 0, 0)),
      trs(0, 1.22, 0.17), _stoneMat);
  // Ears + eyes + front legs.
  for (final s in [-1.0, 1.0]) {
    add(cylGeometry(0, 0.055, 0.16, 4), trs(s * 0.07, 1.4, -0.01, 0, 0, s * 0.16), _stoneMat);
    add(icosahedronGeometry(0.017, 0), trs(s * 0.05, 1.28, 0.11), _stoneDarkMat);
    add(cylGeometry(0.035, 0.042, 0.34, 6), trs(s * 0.075, 0.86, 0.15), _stoneMat);
  }
  // Tail (simplified as cylinder).
  add(cylGeometry(0.055, 0.055, 0.35, 6), trs(0, 1.06, -0.2, 0.5, 0, 0), _stoneMat);
  // Red bib.
  add(boxGeometry(0.22, 0.2, 0.03), trs(0, 1.06, 0.15, 0.2, 0, 0), _shrineBibMat);
  add(boxGeometry(0.2, 0.03, 0.03), trs(0, 1.16, 0.1), const Mat(0xb5322f, tint: 0x7a4060, bands: '2'));

  final groupMat = trs(x, y, z, 0, ry, 0);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

void _buildEmaFrame(List<Part> parts, {required double x, required double z, required double y, required double ry, double len = 3.0}) {
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));
  const h = 1.85;

  for (final s in [-1.0, 1.0]) {
    add(boxGeometry(0.13, h, 0.13), trs((s * len) / 2, h / 2, 0), _shrineWoodDarkMat);
    add(boxGeometry(0.2, 0.16, 0.5), trs((s * len) / 2, 0.08, 0), _shrineWoodDarkMat);
  }
  for (final yy in [h - 0.08, h * 0.55]) {
    add(boxGeometry(len + 0.3, 0.1, 0.12), trs(0, yy, 0), _shrineWoodDarkMat);
  }
  add(boxGeometry(len + 0.5, 0.08, 0.6), trs(0, h + 0.12, 0.06), _shrineWoodDarkMat);

  final groupMat = trs(x, y, z, 0, ry, 0);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

void _buildOmikujiStand(List<Part> parts, {required double x, required double z, required double y, required double ry}) {
  final local = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => local.add(Part(g, mx, m));

  // Body.
  add(boxGeometry(0.56, 0.72, 0.42), trs(0, 1.0, 0), _shrineWoodMat);
  // Corner posts.
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      add(boxGeometry(0.07, 0.64, 0.07), trs(sx * 0.24, 0.32, sz * 0.16), _shrineWoodDarkMat);
    }
  }
  // Top rail.
  add(boxGeometry(0.62, 0.06, 0.48), trs(0, 1.39, 0), _shrineWoodDarkMat);
  // Hexagonal draw box.
  add(cylGeometry(0.11, 0.13, 0.3, 6), trs(0, 1.57, 0), const Mat(0xb5322f, tint: 0x7a4060, bands: '3'));
  // Wire rack frame.
  for (final s in [-1.0, 1.0]) {
    add(cylGeometry(0.03, 0.03, 1.4, 6), trs(s * 0.9, 0.7, 0), _shrineMetalDarkMat);
  }
  add(applyMatrix(cylGeometry(0.02, 0.02, 1.85, 5), trs(0, 0, 0, 0, 0, math.pi / 2)), trs(0, 1.34, 0), _shrineMetalMat);
  add(applyMatrix(cylGeometry(0.02, 0.02, 1.85, 5), trs(0, 0, 0, 0, 0, math.pi / 2)), trs(0, 0.98, 0), _shrineMetalMat);

  final groupMat = trs(x, y, z, 0, ry, 0);
  for (final p in local) {
    parts.add(Part(p.geo, groupMat * p.matrix, p.mat));
  }
}

// ============================================================================
// SHOTENGAI -- さくら坂商店街
// ============================================================================

/// Shopping street structure: drainage channel, alley arch,
/// sento chimney, and south gable dressing wall.
List<Tri> buildShotengai() {
  final parts = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, mx, m));

  const x0 = 19.2;
  const x1 = 25.2;
  final cx = (x0 + x1) / 2;
  const zS = 16.3;
  const zN = 42.6;

  const drainMat = const Mat(0x6d687a, tint: 0x5d5878, bands: '3');
  const metalMat = const Mat(0xb8bcc6, tint: 0x666090, bands: '3');
  const metalDarkMat = const Mat(0x878b96, tint: 0x5c5680, bands: '3');
  const concreteMidMat = const Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');

  // Central drainage channel.
  final n = ((zN - zS) / 0.9).round();
  for (var i = 0; i < n; i++) {
    final dz = zS + (i + 0.5) * ((zN - zS) / n);
    add(boxGeometry(0.34, 0.04, 0.72), trs(cx, groundY(dz) + 0.055, dz), drainMat);
  }

  // Alley arch.
  const alleyZ = 15.1;
  const aw = 3.6, ah = 3.9;
  final archY = groundY(alleyZ);
  for (final s in [-1.0, 1.0]) {
    add(cylGeometry(0.13, 0.16, ah, 8), trs(5.6, archY + ah / 2, alleyZ + s * (aw / 2)), metalMat);
    add(cylGeometry(0.22, 0.26, 0.2, 8), trs(5.6, archY + 0.1, alleyZ + s * (aw / 2)), concreteMidMat);
  }
  // Arch fascia (texture deferred -> wallGray).
  add(boxGeometry(0.14, 0.95, aw + 0.5), trs(5.6, archY + ah - 0.3, alleyZ), const Mat(0xdedee6, tint: 0x6f6790, bands: '3'));
  add(boxGeometry(0.3, 0.12, aw + 0.7), trs(5.6, archY + ah + 0.22, alleyZ), metalDarkMat);

  // Sento chimney.
  const chx = 28.0 + 2.6;
  const chz = 35.4 + 1.6;
  final chy = groundY(39.4);
  add(cylGeometry(0.42, 0.5, 9.0, 10), trs(chx, chy + 4.5, chz), const Mat(0xb08272, tint: 0x6f5680, bands: '3'));
  add(cylGeometry(0.6, 0.6, 0.3, 10), trs(chx, chy + 9.1, chz), concreteMidMat);
  for (var i = 0; i < 3; i++) {
    add(cylGeometry(0.53, 0.53, 0.14, 10), trs(chx, chy + 2.2 + i * 2.4, chz), const Mat(0x9c7268, tint: 0x6f5680, bands: '3'));
  }

  // South gable wall dressing.
  const zw = 14.05;
  final wallY = groundY(zw);
  add(boxGeometry(1.0, 2.6, 0.12), trs(20.6, wallY + 3.3, zw + 0.06), const Mat(0xdedee6, tint: 0x6f6790, bands: '3'));
  add(boxGeometry(0.06, 0.06, 0.4), trs(20.6, wallY + 4.7, zw + 0.18), metalDarkMat);
  // Downpipes.
  for (final dx in [19.6, 23.4]) {
    add(cylGeometry(0.055, 0.055, 5.2, 6), trs(dx, wallY + 2.6, zw + 0.1), metalMat);
    for (var i = 0; i < 4; i++) {
      add(boxGeometry(0.11, 0.06, 0.11), trs(dx, wallY + 0.8 + i * 1.2, zw + 0.14), metalDarkMat);
    }
  }

  return bake(parts);
}

// ============================================================================
// KOENMAE -- 公園前
// ============================================================================

/// Park-front structures: link footway slabs, timber fence,
/// gap yard, gravel court, pocket square lane, service strip slabs.
List<Tri> buildKoenmae() {
  final parts = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, mx, m));

  final y0 = groundY(10.0);
  const concreteMat = const Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
  const concreteMidMat = const Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
  const slatMat = const Mat(0xb09a76, tint: 0x6f6790, bands: '3');
  const woodMat = const Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');

  // NS footway (leg 1).
  const nsX = 38.50, nsZ0 = 5.30, nsZ1 = 15.30;
  add(boxGeometry(2.20, 0.09, nsZ1 - nsZ0), trs(nsX, y0 + 0.045, (nsZ0 + nsZ1) / 2), concreteMat);

  // EW footway (leg 2).
  const ewZ = 16.25, ewX0 = 34.60, ewX1 = 47.35;
  add(boxGeometry(ewX1 - ewX0, 0.09, 2.20), trs((ewX0 + ewX1) / 2, y0 + 0.045, ewZ), concreteMat);

  // Spur under bridge.
  const spX0 = 38.40, spX1 = 43.50;
  add(boxGeometry(spX1 - spX0, 0.09, 2.20), trs((spX0 + spX1) / 2, y0 + 0.045, 8.30), concreteMat);

  // Gap yard slab.
  add(boxGeometry(2.40, 0.07, 3.40), trs(36.10, y0 + 0.035, 12.90), concreteMidMat);

  // Court gravel slab.
  add(boxGeometry(43.40 - 39.85, 0.06, 12.35 - 9.40), trs((39.85 + 43.40) / 2, y0 + 0.03, (9.40 + 12.35) / 2),
      const Mat(0xa9a3ab, tint: 0x6f6790, bands: '3'));

  // Pocket square lane.
  add(boxGeometry(44.30 - 32.30, 0.09, 3.60), trs((32.30 + 44.30) / 2, groundY(32.85) + 0.045, 32.85),
      const Mat(0x9a95a6, tint: 0x6a6288, bands: '3'));

  // East squeeze slab.
  add(boxGeometry(3.40, 0.08, 1.50), trs(45.70, groundY(31.75) + 0.04, 31.75), concreteMat);

  // Service strip slabs.
  final serviceRuns = [[35.20, 38.20], [38.10, 41.10], [41.00, 43.55]];
  for (final pair in serviceRuns) {
    final zc = (pair[0] + pair[1]) / 2;
    add(boxGeometry(3.80, 0.09, pair[1] - pair[0]), trs(45.00, groundY(zc) + 0.045, zc), concreteMat);
  }
  // Service link slab.
  add(boxGeometry(1.30, 0.08, 3.00), trs(43.75, groundY(33.90) + 0.04, 33.90), concreteMat);

  // Timber fence on back boundary.
  const bz = 12.05, fx0 = 43.30, fx1 = 47.25;
  final fenceLen = fx1 - fx0;
  final fenceNs = (fenceLen / 0.17).round();
  for (var i = 0; i < fenceNs; i++) {
    add(boxGeometry((fenceLen / fenceNs) * 0.72, 0.90, 0.05), trs(fx0 + (fenceLen / fenceNs) * (i + 0.5), y0 + 0.45, bz), slatMat);
  }
  // Frame posts.
  for (var i = 0; i <= 3; i++) {
    add(boxGeometry(0.12, 1.00, 0.12), trs(fx0 + (fenceLen / 3) * i, y0 + 0.50, bz), woodMat);
  }
  // Top rail.
  add(boxGeometry(fenceLen + 0.1, 0.07, 0.24), trs((fx0 + fx1) / 2, y0 + 0.96, bz), woodMat);

  return bake(parts);
}

// ============================================================================
// OVERBRIDGE -- 跨線橋
// ============================================================================

/// Pedestrian overbridge: deck slab, girders, cross beams, balustrades,
/// pier columns, head landings, flights of stairs, aprons, canopy ribs,
/// under-bridge ballast and equipment cabinets.
List<Tri> buildOverbridge() {
  final parts = <Part>[];
  void add(ThreeGeom g, Matrix4 mx, Mat m) => parts.add(Part(g, mx, m));

  const deckY = 7.20;
  const slabH = 0.28;
  const girderH = 0.60;
  const deckW = 2.30;
  const headW = 2.60;
  const rise = 0.18;
  const going = 0.28;
  const nFlight = 20;
  const flightW = 2.40;
  const railH = 1.15;
  const barGap = 0.11;
  const trackHalf = 2.25;

  const xC = 41.00;
  final xd0 = xC - deckW / 2;
  final xd1 = xC + deckW / 2;
  const zN = 4.40;
  const zF = -5.40;

  const steelMat = const Mat(0xd0d5dd, tint: 0x6a6590, bands: '3');
  const steelDarkMat = const Mat(0x9aa2ae, tint: 0x605a80, bands: '3');
  const railMat = const Mat(0x8b9cb2, tint: 0x5c5a84, bands: '3');
  const railDarkMat = const Mat(0x6d7c92, tint: 0x54527a, bands: '3');
  const treadMat = const Mat(0xc4c8d0, tint: 0x6a6288, bands: '3');
  const nosingMat = const Mat(0xe6d9a8, tint: 0x8f7050, bands: '2');
  const concreteMat = const Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
  const concreteMidMat = const Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
  const canopyRibMat = const Mat(0x9aa2ad, tint: 0x5a5678, bands: '3');
  const ballastMat = const Mat(0x7d7686, tint: 0x655d84, bands: '3');
  const cabinetMat = const Mat(0xd8d5da, tint: 0x6f6890, bands: '3');
  const cabinetTopMat = const Mat(0xb6b2bc, tint: 0x6a6288, bands: '3');

  final cz = (zN + zF) / 2;
  final len = zN - zF;

  // -- Deck --
  add(boxGeometry(deckW, slabH, len), trs(xC, deckY - slabH / 2, cz), treadMat);
  for (final s in [-1.0, 1.0]) {
    final gx = xC + s * (deckW / 2 - 0.06);
    add(boxGeometry(0.12, girderH, len), trs(gx, deckY - slabH - girderH / 2, cz), steelMat);
    add(boxGeometry(0.3, 0.07, len), trs(gx, deckY - slabH - girderH, cz), steelDarkMat);
  }
  // Cross beams.
  final nb = (len / 1.4).round();
  for (var i = 0; i <= nb; i++) {
    final z = zF + (len / nb) * i;
    add(boxGeometry(deckW - 0.1, 0.14, 0.09), trs(xC, deckY - slabH - girderH + 0.14, z), steelDarkMat);
  }
  // Drainage channel + spout.
  add(boxGeometry(0.14, 0.05, len - 0.2), trs(xd0 + 0.16, deckY - 0.02, cz), steelDarkMat);
  add(cylGeometry(0.045, 0.045, 0.55, 6), trs(xd0 + 0.16, deckY - slabH - 0.3, cz + 1.2), steelDarkMat);

  // Balustrades along deck.
  _addBalustrade(parts, axis: 'z', at: xd0 + 0.05, from: zF, to: zN, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);
  _addBalustrade(parts, axis: 'z', at: xd1 - 0.05, from: zF, to: zN, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);

  // Piers and footings.
  for (final pzVal in [trackHalf + 1.5, -(trackHalf + 1.5)]) {
    final gy = groundY(pzVal);
    for (final s in [-1.0, 1.0]) {
      final px = xC + s * (deckW / 2 - 0.2);
      final hCol = deckY - slabH - girderH - gy;
      add(cylGeometry(0.15, 0.19, hCol, 10), trs(px, gy + hCol / 2, pzVal), steelDarkMat);
    }
    add(boxGeometry(deckW + 0.1, 0.2, 0.5), trs(xC, deckY - slabH - girderH - 0.1, pzVal), steelMat);
    add(boxGeometry(deckW + 0.5, 0.3, 0.9), trs(xC, gy + 0.15, pzVal), concreteMidMat);
  }

  // -- Near head landing --
  add(boxGeometry(headW, slabH, 2.40), trs(xC, deckY - slabH / 2, zN + 1.20), treadMat);
  add(boxGeometry(headW, 0.34, 0.1), trs(xC, deckY - slabH - 0.17, zN + 0.05), steelMat);
  add(boxGeometry(headW, 0.34, 0.1), trs(xC, deckY - slabH - 0.17, zN + 2.35), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(xC - headW / 2 + 0.05, deckY - slabH - 0.17, zN + 1.20), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(xC + headW / 2 - 0.05, deckY - slabH - 0.17, zN + 1.20), steelMat);
  for (final px in [xC - headW / 2 + 0.28, xC + headW / 2 - 0.28]) {
    for (final pz in [zN + 0.28, zN + 2.40 - 0.28]) {
      final gy = groundY(pz);
      final hCol = deckY - slabH - 0.34 - gy;
      add(cylGeometry(0.11, 0.13, hCol, 8), trs(px, gy + hCol / 2, pz), steelDarkMat);
      add(boxGeometry(0.44, 0.16, 0.44), trs(px, gy + 0.08, pz), steelMat);
    }
  }
  _addBalustrade(parts, axis: 'x', at: xC - headW / 2 + 0.05, from: zN, to: zN + 2.40, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);
  _addBalustrade(parts, axis: 'x', at: xC + headW / 2 - 0.05, from: zN, to: zN + 2.40, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);

  // -- Near flight 1 (z-axis, north off head) --
  _addFlight(parts, axis: 'z', at: xC, from: zN + 2.40, y0: deckY, dir: 1,
      n: nFlight, flightW: flightW, going: going, rise: rise,
      treadMat: treadMat, steelDarkMat: steelDarkMat, steelMat: steelMat,
      nosingMat: nosingMat, railMat: railMat, railDarkMat: railDarkMat, railH: railH, rampSide: 1);

  // -- Near corner landing --
  final nMidY = deckY - rise * nFlight;
  final nMidZ = zN + 2.40 + going * nFlight;
  add(boxGeometry(headW + 0.3, slabH, 2.50), trs(xC + 0.15, nMidY - slabH / 2, nMidZ + 1.25), treadMat);
  add(boxGeometry(headW + 0.3, 0.34, 0.1), trs(xC + 0.15, nMidY - slabH - 0.17, nMidZ + 0.05), steelMat);
  add(boxGeometry(headW + 0.3, 0.34, 0.1), trs(xC + 0.15, nMidY - slabH - 0.17, nMidZ + 2.45), steelMat);
  add(boxGeometry(0.1, 0.34, 2.50), trs(xC - headW / 2 + 0.05, nMidY - slabH - 0.17, nMidZ + 1.25), steelMat);
  add(boxGeometry(0.1, 0.34, 2.50), trs(xC + headW / 2 + 0.25, nMidY - slabH - 0.17, nMidZ + 1.25), steelMat);
  for (final px in [xC - headW / 2 + 0.28, xC + headW / 2 + 0.28]) {
    for (final pz in [nMidZ + 0.28, nMidZ + 2.50 - 0.28]) {
      final gy = groundY(pz);
      final hCol = nMidY - slabH - 0.34 - gy;
      add(cylGeometry(0.11, 0.13, hCol, 8), trs(px, gy + hCol / 2, pz), steelDarkMat);
      add(boxGeometry(0.44, 0.16, 0.44), trs(px, gy + 0.08, pz), steelMat);
    }
  }
  _addBalustrade(parts, axis: 'x', at: xC - headW / 2 + 0.05, from: nMidZ, to: nMidZ + 2.50, y: nMidY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);
  _addBalustrade(parts, axis: 'z', at: nMidZ + 2.45, from: xC - headW / 2, to: xC + headW / 2 + 0.3, y: nMidY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);

  // -- Near flight 2 (x-axis, east off corner) --
  _addFlight(parts, axis: 'x', at: nMidZ + 1.25, from: xC + headW / 2 + 0.3, y0: nMidY, dir: 1,
      n: nFlight, flightW: flightW, going: going, rise: rise,
      treadMat: treadMat, steelDarkMat: steelDarkMat, steelMat: steelMat,
      nosingMat: nosingMat, railMat: railMat, railDarkMat: railDarkMat, railH: railH, rampSide: -1);

  // -- Far head landing --
  add(boxGeometry(headW, slabH, 2.40), trs(xC, deckY - slabH / 2, zF - 1.20), treadMat);
  add(boxGeometry(headW, 0.34, 0.1), trs(xC, deckY - slabH - 0.17, zF - 2.35), steelMat);
  add(boxGeometry(headW, 0.34, 0.1), trs(xC, deckY - slabH - 0.17, zF - 0.05), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(xC - headW / 2 + 0.05, deckY - slabH - 0.17, zF - 1.20), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(xC + headW / 2 - 0.05, deckY - slabH - 0.17, zF - 1.20), steelMat);
  for (final px in [xC - headW / 2 + 0.28, xC + headW / 2 - 0.28]) {
    for (final pz in [zF - 2.40 + 0.28, zF - 0.28]) {
      final gy = groundY(pz);
      final hCol = deckY - slabH - 0.34 - gy;
      add(cylGeometry(0.11, 0.13, hCol, 8), trs(px, gy + hCol / 2, pz), steelDarkMat);
      add(boxGeometry(0.44, 0.16, 0.44), trs(px, gy + 0.08, pz), steelMat);
    }
  }
  _addBalustrade(parts, axis: 'x', at: xC - headW / 2 + 0.05, from: zF - 2.40, to: zF, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);
  _addBalustrade(parts, axis: 'x', at: xC + headW / 2 - 0.05, from: zF - 2.40, to: zF, y: deckY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);

  // -- Far flight 1 (x-axis, east off far head) --
  _addFlight(parts, axis: 'x', at: zF - 1.20, from: xC + headW / 2, y0: deckY, dir: 1,
      n: nFlight, flightW: flightW, going: going, rise: rise,
      treadMat: treadMat, steelDarkMat: steelDarkMat, steelMat: steelMat,
      nosingMat: nosingMat, railMat: railMat, railDarkMat: railDarkMat, railH: railH, rampSide: 1);

  // -- Far corner landing --
  final fMidX = xC + headW / 2 + going * nFlight;
  add(boxGeometry(2.50, slabH, 2.40), trs(fMidX + 1.25, nMidY - slabH / 2, zF - 1.30), treadMat);
  add(boxGeometry(2.50, 0.34, 0.1), trs(fMidX + 1.25, nMidY - slabH - 0.17, zF - 2.55), steelMat);
  add(boxGeometry(2.50, 0.34, 0.1), trs(fMidX + 1.25, nMidY - slabH - 0.17, zF - 0.05), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(fMidX + 0.05, nMidY - slabH - 0.17, zF - 1.30), steelMat);
  add(boxGeometry(0.1, 0.34, 2.40), trs(fMidX + 2.45, nMidY - slabH - 0.17, zF - 1.30), steelMat);
  for (final px in [fMidX + 0.28, fMidX + 2.50 - 0.28]) {
    for (final pz in [zF - 2.60 + 0.28, zF - 0.28]) {
      final gy = groundY(pz);
      final hCol = nMidY - slabH - 0.34 - gy;
      add(cylGeometry(0.11, 0.13, hCol, 8), trs(px, gy + hCol / 2, pz), steelDarkMat);
      add(boxGeometry(0.44, 0.16, 0.44), trs(px, gy + 0.08, pz), steelMat);
    }
  }
  _addBalustrade(parts, axis: 'z', at: zF - 2.55, from: fMidX, to: fMidX + 2.50, y: nMidY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);
  _addBalustrade(parts, axis: 'x', at: fMidX + 2.45, from: zF - 2.60, to: zF, y: nMidY, railMat: railMat, railDarkMat: railDarkMat, barGap: barGap, railH: railH);

  // -- Far flight 2 (z-axis, south off corner) --
  _addFlight(parts, axis: 'z', at: fMidX + 1.25, from: zF - 2.60, y0: nMidY, dir: -1,
      n: nFlight, flightW: flightW, going: going, rise: rise,
      treadMat: treadMat, steelDarkMat: steelDarkMat, steelMat: steelMat,
      nosingMat: nosingMat, railMat: railMat, railDarkMat: railDarkMat, railH: railH, rampSide: 1);

  // -- Aprons --
  final nFootX = xC + headW / 2 + 0.3 + going * nFlight;
  final fFootZ = zF - 2.60 - going * nFlight;
  add(boxGeometry(2.6, 0.08, flightW + 0.4), trs(nFootX + 1.1, groundY(nMidZ) + 0.04, nMidZ + 1.25), concreteMat);
  add(boxGeometry(flightW + 0.4, 0.08, 2.6), trs(fMidX + 1.25, groundY(fFootZ) + 0.04, fFootZ - 1.1), concreteMat);

  // -- Canopy ribs --
  {
    final deckSpan = xd1 - xd0;
    final camber = 0.26;
    final sheetLen = math.sqrt(deckSpan * deckSpan / 4 + camber * camber) + 0.04;
    final canopySlope = math.atan2(camber, deckSpan / 2);
    add(boxGeometry(0.12, 0.1, len), trs(xC, deckY + 2.55 + camber + 0.03, cz), canopyRibMat);
    add(boxGeometry(0.1, 0.11, len), trs(xC - deckSpan / 2, deckY + 2.55 - 0.02, cz), canopyRibMat);
    add(boxGeometry(0.1, 0.11, len), trs(xC + deckSpan / 2, deckY + 2.55 - 0.02, cz), canopyRibMat);
    final nr = (len / 2.1).round().clamp(2, 100);
    for (var i = 0; i <= nr; i++) {
      final t = zF + (len / nr) * i;
      for (final s in [-1.0, 1.0]) {
        add(boxGeometry(sheetLen, 0.07, 0.07), trs(xC + s * deckSpan / 4, deckY + 2.55 + camber / 2 - 0.05, t, 0, 0, -s * canopySlope), canopyRibMat);
        add(boxGeometry(0.075, 2.55 - 0.02, 0.075), trs(xC + s * (deckSpan / 2 - 0.08), deckY + 2.55 / 2, t), canopyRibMat);
      }
    }
  }

  // -- Under-bridge --
  for (final pzVal in [trackHalf + 1.5, -(trackHalf + 1.5)]) {
    final gy = groundY(pzVal);
    add(boxGeometry(deckW + 3.4, 0.07, 1.5), trs(xC, gy + 0.035, pzVal), ballastMat);
  }
  // Equipment cabinets (near side).
  add(boxGeometry(0.66, 1.0, 0.42), trs(xd0 - 1.15, groundY(4) + 0.56, trackHalf + 1.5), cabinetMat);
  add(boxGeometry(0.82, 0.12, 0.58), trs(xd0 - 1.15, groundY(4) + 0.06, trackHalf + 1.5), concreteMidMat);
  add(boxGeometry(0.72, 0.05, 0.49), trs(xd0 - 1.15, groundY(4) + 1.1, trackHalf + 1.5), cabinetTopMat);
  // Equipment cabinets (far side).
  add(boxGeometry(0.5, 0.8, 0.36), trs(xd1 + 1.2, groundY(-4) + 0.46, -(trackHalf + 1.5)), cabinetMat);
  add(boxGeometry(0.66, 0.12, 0.52), trs(xd1 + 1.2, groundY(-4) + 0.06, -(trackHalf + 1.5)), concreteMidMat);
  add(boxGeometry(0.56, 0.05, 0.43), trs(xd1 + 1.2, groundY(-4) + 0.9, -(trackHalf + 1.5)), cabinetTopMat);

  return bake(parts);
}

// ── Flight helper ──

void _addFlight(List<Part> parts, {required String axis, required double at, required double from, required double y0, required int dir,
    required int n, required double flightW, required double going, required double rise,
    required Mat treadMat, required Mat steelDarkMat, required Mat steelMat,
    required Mat nosingMat, required Mat railMat, required Mat railDarkMat, required double railH, int rampSide = 1}) {
  final runL = going * n;
  final dropL = rise * n;
  final slope = math.atan2(dropL, runL);
  final slabLen = math.sqrt(runL * runL + dropL * dropL);
  final midT = from + dir * runL / 2;
  final midY = y0 - dropL / 2 - 0.16;
  // The rake: z-axis flight -> +slope; x-axis flight -> -slope
  final rake = axis == 'z' ? slope * dir : -slope * dir;

  for (var i = 0; i < n; i++) {
    final t = from + going * dir * (i + 0.5);
    final y = y0 - rise * (i + 1);
    if (axis == 'z') {
      parts.add(Part(boxGeometry(flightW, 0.055, going), trs(at, y + 0.028, t), treadMat));
      parts.add(Part(boxGeometry(flightW - 0.02, rise - 0.05, 0.04), trs(at, y + rise / 2 + 0.03, t + going * dir * 0.5), steelDarkMat));
      parts.add(Part(boxGeometry(flightW, 0.02, 0.05), trs(at, y + 0.066, t + going * dir * 0.42), nosingMat));
    } else {
      parts.add(Part(boxGeometry(going, 0.055, flightW), trs(t, y + 0.028, at), treadMat));
      parts.add(Part(boxGeometry(0.04, rise - 0.05, flightW - 0.02), trs(t + going * dir * 0.5, y + rise / 2 + 0.03, at), steelDarkMat));
      parts.add(Part(boxGeometry(0.05, 0.02, flightW), trs(t + going * dir * 0.42, y + 0.066, at), nosingMat));
    }
  }

  // Stringers.
  for (final s in [-1.0, 1.0]) {
    final off = s * (flightW / 2 - 0.05);
    if (axis == 'z') {
      parts.add(Part(boxGeometry(0.1, 0.42, slabLen), trs(at + off, midY, midT, rake, 0, 0), steelMat));
    } else {
      parts.add(Part(boxGeometry(slabLen, 0.42, 0.1), trs(midT, midY, at + off, 0, 0, rake), steelMat));
    }
  }
  // Soffit.
  if (axis == 'z') {
    parts.add(Part(boxGeometry(flightW - 0.16, 0.06, slabLen), trs(at, midY + 0.02, midT, rake, 0, 0), steelMat));
  } else {
    parts.add(Part(boxGeometry(slabLen, 0.06, flightW - 0.16), trs(midT, midY + 0.02, at, 0, 0, rake), steelMat));
  }

  // Bicycle ramp channel.
  final rampOff = rampSide * (flightW / 2 - 0.19);
  if (axis == 'z') {
    parts.add(Part(boxGeometry(0.34, 0.07, slabLen), trs(at + rampOff, midY + 0.28, midT, rake, 0, 0), treadMat));
    parts.add(Part(boxGeometry(0.045, 0.075, slabLen), trs(at + rampOff - 0.185, midY + 0.33, midT, rake, 0, 0), steelDarkMat));
    parts.add(Part(boxGeometry(0.045, 0.075, slabLen), trs(at + rampOff + 0.185, midY + 0.33, midT, rake, 0, 0), steelDarkMat));
  } else {
    parts.add(Part(boxGeometry(slabLen, 0.07, 0.34), trs(midT, midY + 0.28, at + rampOff, 0, 0, rake), treadMat));
    parts.add(Part(boxGeometry(slabLen, 0.075, 0.045), trs(midT, midY + 0.33, at + rampOff - 0.185, 0, 0, rake), steelDarkMat));
    parts.add(Part(boxGeometry(slabLen, 0.075, 0.045), trs(midT, midY + 0.33, at + rampOff + 0.185, 0, 0, rake), steelDarkMat));
  }

  // Rake balustrades.
  _addRakeBalustrade(parts, axis: axis, at: at - flightW / 2 + 0.05, from: from, y0: y0, dir: dir, n: n,
      going: going, rise: rise, railMat: railMat, railDarkMat: railDarkMat, railH: railH);
  _addRakeBalustrade(parts, axis: axis, at: at + flightW / 2 - 0.05, from: from, y0: y0, dir: dir, n: n,
      going: going, rise: rise, railMat: railMat, railDarkMat: railDarkMat, railH: railH);
}

// ── Balustrade helpers ──

void _addBalustrade(List<Part> parts, {required String axis, required double at, required double from, required double to, required double y,
  required Mat railMat, required Mat railDarkMat, required double barGap, required double railH}) {
  final a = from < to ? from : to;
  final b = from < to ? to : from;
  final len = b - a;
  final np = (len / 1.8).round().clamp(1, 100);
  for (var i = 0; i <= np; i++) {
    final t = a + (len / np) * i;
    parts.add(Part(boxGeometry(0.07, railH, 0.07), axis == 'z' ? trs(at, y + railH / 2, t) : trs(t, y + railH / 2, at), railMat));
  }
  if (axis == 'z') {
    parts.add(Part(boxGeometry(0.1, 0.06, len + 0.07), trs(at, y + railH, (a + b) / 2), railMat));
    parts.add(Part(boxGeometry(0.06, 0.05, len), trs(at, y + 0.13, (a + b) / 2), railDarkMat));
  } else {
    parts.add(Part(boxGeometry(len + 0.07, 0.06, 0.1), trs((a + b) / 2, y + railH, at), railMat));
    parts.add(Part(boxGeometry(len, 0.05, 0.06), trs((a + b) / 2, y + 0.13, at), railDarkMat));
  }
  final nb = (len / barGap).round().clamp(2, 100);
  for (var i = 0; i <= nb; i++) {
    final t = a + (len / nb) * i;
    parts.add(Part(boxGeometry(0.022, railH - 0.19, 0.022), axis == 'z' ? trs(at, y + 0.13 + (railH - 0.19) / 2, t) : trs(t, y + 0.13 + (railH - 0.19) / 2, at), railDarkMat));
  }
}

void _addRakeBalustrade(List<Part> parts, {required String axis, required double at, required double from, required double y0, required int dir, required int n,
  required double going, required double rise, required Mat railMat, required Mat railDarkMat, required double railH}) {
  final step = going * dir;
  for (var i = 0; i <= n; i++) {
    final t = from + step * i;
    final yy = y0 - rise * i;
    if (i % 6 == 0 || i == n) {
      parts.add(Part(boxGeometry(0.07, railH, 0.07), axis == 'z' ? trs(at, yy + railH / 2, t) : trs(t, yy + railH / 2, at), railMat));
    }
    parts.add(Part(boxGeometry(0.022, railH - 0.16, 0.022), axis == 'z' ? trs(at, yy + 0.1 + (railH - 0.16) / 2, t) : trs(t, yy + 0.1 + (railH - 0.16) / 2, at), railDarkMat));
    if (i == n) continue;
    final mid = t + step / 2;
    final midY = yy - rise / 2;
    final pitch = math.atan2(rise, going) * (axis == 'z' ? dir : -dir);
    final segLen = math.sqrt(going * going + rise * rise) + 0.01;
    // Handrail.
    if (axis == 'z') {
      parts.add(Part(boxGeometry(0.09, 0.06, segLen), trs(at, midY + railH, mid, pitch, 0, 0), railMat));
      parts.add(Part(boxGeometry(0.05, 0.05, segLen), trs(at, midY + 0.1, mid, pitch, 0, 0), railDarkMat));
    } else {
      parts.add(Part(boxGeometry(segLen, 0.06, 0.09), trs(mid, midY + railH, at, 0, 0, pitch), railMat));
      parts.add(Part(boxGeometry(segLen, 0.05, 0.05), trs(mid, midY + 0.1, at, 0, 0, pitch), railDarkMat));
    }
  }
}
