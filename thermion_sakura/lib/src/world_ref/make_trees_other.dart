/// Dart ports of the reference `src/world/trees.js` non-cherry tree builders:
/// `buildShrubs`, `buildGrove`, `buildBamboo`, `buildCedar`.
///
/// Each function returns baked triangle soup (`List<Tri>`) and mirrors the
/// reference's placement, colour and geometry faithfully, using the same
/// geometry substrate as `make_sakura.dart`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shrubs -- low-poly rounded blobs in three leaf tones
// ─────────────────────────────────────────────────────────────────────────────

const _shrubMats = <Mat>[
  Mat(0x5aa578, tint: 0x5b6f8c, bands: '3'), // PAL.leaf
  Mat(0x3f7f60, tint: 0x5b6f8c, bands: '3'), // PAL.leafDeep
  Mat(0x84bd97, tint: 0x5b6f8c, bands: '3'), // PAL.leafPale
];

class ShrubSpot {
  const ShrubSpot({
    required this.x,
    required this.z,
    this.y = 0,
    this.seed = 11,
    this.count = 3,
    this.r = 0.55,
    this.spread = 1,
  });
  final double x, z, y, r, spread;
  final int seed, count;
}

/// Build rounded low-poly shrubs in three teal-leaning greens.
/// Returns baked triangle soup; pass [spots] to override placement.
List<Tri> buildShrubs([List<ShrubSpot>? spots]) {
  spots ??= const [ShrubSpot(x: 0, z: 0)];
  final blobGeo = icosahedronGeometry(1, 1);
  final parts = <Part>[];
  for (final s in spots) {
    final rng = RngKit(s.seed);
    for (int i = 0; i < s.count; i++) {
      final r = s.r * rng.range(0.75, 1.2);
      parts.add(Part(
        blobGeo,
        trs(
          s.x + rng.range(-0.5, 0.5) * s.spread,
          s.y + r * 0.72,
          s.z + rng.range(-0.5, 0.5) * s.spread,
          rng.range(0, 3),
          rng.range(0, 3),
          rng.range(0, 3),
          r,
          r * 0.8,
          r,
        ),
        _shrubMats[i % 3],
        planetRigid: true,
      ));
    }
  }
  return bake(parts);
}

// ─────────────────────────────────────────────────────────────────────────────
// Grove -- broadleaf shade trees (or willows) with blob canopy
// ─────────────────────────────────────────────────────────────────────────────

/// GREEN_TONES = [0x8cb884, 0x5f9470, PAL.cedar, PAL.willow]
const _groveCanopyMats = <Mat>[
  Mat(0x8ab682, tint: 0x5b6f8c, bands: '3'),
  Mat(0x5d926e, tint: 0x5b6f8c, bands: '3'),
  Mat(0x3f6b52, tint: 0x5b6f8c, bands: '3'),
  Mat(0xa8c489, tint: 0x5b6f8c, bands: '3'),
];

const _groveWoodMat =
    Mat(0x725b5e, tint: 0x6f5a80, bands: '3'); // compensated PAL.trunkDark

class GroveSpot {
  const GroveSpot({
    required this.x,
    required this.z,
    this.y = 0,
    this.scale = 1,
    this.seed = 1,
    this.lean = 0,
    this.leanDir,
    this.spread = 1,
    this.willow = false,
    this.tone,
  });
  final double x, z, y, scale, lean, spread;
  final int seed;
  final double? leanDir;
  final bool willow;
  final int? tone;
}

/// Build grove trees (broadleaf canopy) or willows.
/// Returns baked triangle soup; pass [spots] to override placement.
List<Tri> buildGrove(
    [List<GroveSpot>? spots,
    void Function(Matrix4 matrix, int tone)? auditRigid,
    bool includeCanopy = true]) {
  spots ??= const [GroveSpot(x: 0, z: 0)];
  final trunkGeo = cylGeometry(0.62, 1.0, 1, 7);
  final branchGeo = cylGeometry(0.28, 0.6, 1, 5);
  final blobGeo = icosahedronGeometry(1, 1);
  final parts = <Part>[];

  for (final spot in spots) {
    final rng = RngKit(spot.seed);
    final s = spot.scale;
    final x = spot.x, z = spot.z, y = spot.y;
    final lean = spot.lean;
    final leanDir = spot.leanDir ?? rng.range(0, math.pi * 2);
    final spread = spot.spread;
    final willow = spot.willow;

    final trunkH = (willow ? 4.3 : 3.6) * s * rng.range(0.9, 1.15);
    final trunkR = (willow ? 0.185 : 0.24) * s;

    parts.add(Part(
        trunkGeo,
        trs(x, y + trunkH / 2, z, lean * math.sin(leanDir), 0,
            -lean * math.cos(leanDir), trunkR, trunkH, trunkR),
        _groveWoodMat));
    // root flare
    parts.add(Part(
        trunkGeo,
        trs(x, y + 0.2 * s, z, 0, 0, 0, trunkR * 1.55, 0.42 * s, trunkR * 1.55),
        _groveWoodMat));

    // trunk tip -- exact rotation of (0, trunkH/2, 0) by the lean Euler
    final tip = Vector3(0, trunkH / 2, 0)
      ..applyQuaternion(quatFromEulerXyz(
          lean * math.sin(leanDir), 0, -lean * math.cos(leanDir)));
    final topX = x + tip.x, topZ = z + tip.z, topY = y + trunkH / 2 + tip.y;

    final limbs = (willow ? 5 : 3) + (rng.next() * 3).floor();
    final centers = <Vector3>[];
    for (int i = 0; i < limbs; i++) {
      final a = (i / limbs) * math.pi * 2 + rng.range(-0.4, 0.4);
      final len = (willow ? 1.35 : 1.5) * s * rng.range(0.8, 1.25);
      final tilt = willow ? rng.range(1.02, 1.42) : rng.range(0.35, 0.7);
      final ex = topX + math.cos(a) * math.sin(tilt) * len * spread;
      final ez = topZ + math.sin(a) * math.sin(tilt) * len * spread;
      final ey = topY + math.cos(tilt) * len;
      final dir = Vector3(ex - topX, ey - topY, ez - topZ);
      final l = dir.length;
      final q = quatFromUnitVectors(Vector3(0, 1, 0), dir);
      parts.add(Part(
          branchGeo,
          composePRS(Vector3((topX + ex) / 2, (topY + ey) / 2, (topZ + ez) / 2),
              q, Vector3(0.15 * s, l, 0.15 * s)),
          _groveWoodMat));
      centers.add(Vector3(ex, ey, ez));
    }

    // canopy blobs
    final count = (willow ? 120 : 30) + (rng.next() * 12).floor();
    double yMin = double.infinity, yMax = double.negativeInfinity;
    for (final c in centers) {
      if (c.y < yMin) yMin = c.y;
      if (c.y > yMax) yMax = c.y;
    }
    for (int i = 0; i < count; i++) {
      final c = centers[(rng.next() * centers.length).floor() % centers.length];
      if (willow) {
        // curtain: hung from limb end, falling toward ground
        final r = 0.185 * s * rng.range(0.7, 1.25);
        final fall = rng.range(0.05, 1.0);
        final px = c.x + rng.range(-1.05, 1.05) * s * spread;
        final pz = c.z + rng.range(-1.05, 1.05) * s * spread;
        final py =
            math.max(y + 0.55 * s, c.y + 0.42 * s - fall * (c.y - y) * 0.95);
        final tone = rng.next() < 0.62 ? 3 : 1;
        final matrix = trs(
            px,
            py,
            pz,
            0,
            rng.range(0, 3),
            rng.range(-0.25, 0.25),
            r,
            r * rng.range(1.7, 2.6),
            r * rng.range(0.85, 1.05));
        auditRigid?.call(matrix, tone);
        if (includeCanopy) {
          parts.add(
              Part(blobGeo, matrix, _groveCanopyMats[tone], planetRigid: true));
        }
        continue;
      }
      final r = 0.72 * s * rng.range(0.7, 1.25);
      final px = c.x + rng.range(-1.25, 1.25) * s * spread;
      final py = c.y + rng.range(-0.7, 1.5) * s;
      final pz = c.z + rng.range(-1.25, 1.25) * s * spread;
      int tone;
      if (spot.tone != null) {
        tone = spot.tone!;
      } else {
        final hi = (py - yMin) / math.max(0.5, yMax + 1.6 * s - yMin);
        tone = hi > 0.66
            ? 0
            : hi < 0.3
                ? 2
                : 1;
        if (rng.next() < 0.2) tone = (tone + 1) % 3;
      }
      final matrix = trs(px, py, pz, rng.range(0, 3), rng.range(0, 3),
          rng.range(0, 3), r, r * rng.range(0.7, 0.92), r);
      auditRigid?.call(matrix, tone);
      if (includeCanopy) {
        parts.add(
            Part(blobGeo, matrix, _groveCanopyMats[tone], planetRigid: true));
      }
    }
  }

  return bake(parts);
}

// ─────────────────────────────────────────────────────────────────────────────
// Bamboo -- thin culms with nodes and leaf spray
// ─────────────────────────────────────────────────────────────────────────────

const _bambooCulmMats = <Mat>[
  Mat(0x94b06b, tint: 0x5b6f8c, bands: '3'), // PAL.bamboo
  Mat(0x6f8c50, tint: 0x5b6f8c, bands: '3'), // PAL.bambooDeep
];

const _bambooNodeMat = Mat(0xb8c88a, tint: 0x5b6f8c, bands: '2');

const _bambooLeafMats = <Mat>[
  Mat(0xa6c078, tint: 0x5b6f8c, bands: '3'),
  Mat(0x6f8c50, tint: 0x5b6f8c, bands: '3'), // PAL.bambooDeep
];

class BambooClump {
  const BambooClump({
    required this.x,
    required this.z,
    this.y = 0,
    this.seed = 5,
    this.n = 9,
    this.scale = 1,
    this.spread = 1.2,
  });
  final double x, z, y, scale, spread;
  final int seed, n;
}

/// Build bamboo clumps: thin culms with nodes and a light spray of leaf blobs.
/// Returns baked triangle soup; pass [clumps] to override placement.
List<Tri> buildBamboo([List<BambooClump>? clumps]) {
  clumps ??= const [BambooClump(x: 0, z: 0)];
  final culmGeo = cylGeometry(1, 1.16, 1, 5);
  final nodeGeo = cylGeometry(1.25, 1.25, 1, 5);
  final leafGeo = icosahedronGeometry(1, 0);
  final parts = <Part>[];

  for (final c in clumps) {
    final rng = RngKit(c.seed);
    for (int i = 0; i < c.n; i++) {
      final s = c.scale;
      final h = (4.2 + rng.range(-1.0, 1.4)) * s;
      final r = 0.045 * s * rng.range(0.85, 1.2);
      final px = c.x + rng.range(-1, 1) * c.spread;
      final pz = c.z + rng.range(-1, 1) * c.spread;
      final lean = rng.range(-0.07, 0.07);
      final leanD = rng.range(0, 6.3);
      final tone = i % 2;

      parts.add(Part(
          culmGeo,
          trs(px, c.y + h / 2, pz, lean * math.sin(leanD), 0,
              -lean * math.cos(leanD), r, h, r),
          _bambooCulmMats[tone]));

      // nodes along the culm
      for (int k = 1; k < 5; k++) {
        final nk = k / 5;
        parts.add(Part(
            nodeGeo,
            trs(
                px + lean * math.sin(leanD) * (h * nk - h / 2),
                c.y + h * nk,
                pz - lean * math.cos(leanD) * (h * nk - h / 2),
                0,
                0,
                0,
                r,
                0.035 * s,
                r),
            _bambooNodeMat));
      }

      // leaf spray: flattened blobs high on the culm
      for (int k = 0; k < 4; k++) {
        final ly = c.y + h * rng.range(0.66, 1.0);
        final rr = 0.34 * s * rng.range(0.7, 1.2);
        parts.add(Part(
            leafGeo,
            trs(
                px + rng.range(-0.5, 0.5) * s,
                ly,
                pz + rng.range(-0.5, 0.5) * s,
                rng.range(0, 3),
                rng.range(0, 3),
                rng.range(0, 3),
                rr,
                rr * 0.42,
                rr * 1.25),
            _bambooLeafMats[k % 2]));
      }
    }
  }

  return bake(parts);
}

// ─────────────────────────────────────────────────────────────────────────────
// Cedar (杉) -- tall narrow plantation trees with conical tiered crowns
// ─────────────────────────────────────────────────────────────────────────────

const _cedarTierMats = <Mat>[
  Mat(0x64906b, tint: 0x59657f, bands: '3'), // PAL.cedarLit
  Mat(0x3f6b52, tint: 0x59657f, bands: '3'), // PAL.cedar
  Mat(0x2f5540, tint: 0x59657f, bands: '3'), // PAL.cedarDeep
];

const _cedarWoodMat =
    Mat(0x7e6150, tint: 0x6f5a80, bands: '3'); // PAL.cedarBark

class CedarSpot {
  const CedarSpot({
    required this.x,
    required this.z,
    this.y = 0,
    this.scale = 1,
    this.seed = 3,
    this.lean = 0,
    this.leanDir,
  });
  final double x, z, y, scale, lean;
  final int seed;
  final double? leanDir;
}

/// Build cedar plantation trees: tall narrow trunks with conical tiered crowns.
/// Returns baked triangle soup; pass [spots] to override placement.
List<Tri> buildCedar([List<CedarSpot>? spots]) {
  spots ??= const [CedarSpot(x: 0, z: 0)];
  final trunkGeo = cylGeometry(0.34, 1.0, 1, 6);
  // ConeGeometry(1, 1, 7) with base at y=0 -- matches reference's
  // coneGeo.translate(0, 0.5, 0) so the base sits at the placement height.
  final coneGeo = applyMatrix(cylGeometry(0, 1, 1, 7), trs(0, 0.5, 0));
  final parts = <Part>[];

  for (final spot in spots) {
    final rng = RngKit(spot.seed);
    final s = spot.scale;
    final x = spot.x, z = spot.z, y = spot.y;
    final lean = spot.lean;
    final leanDir = spot.leanDir ?? rng.range(0, math.pi * 2);

    final H = 10.6 * s * rng.range(0.82, 1.18);
    final trunkR = 0.125 * s * rng.range(0.86, 1.22);

    // trunk axis direction (lean is nearly zero for planted sugi)
    final eulX = lean * math.sin(leanDir);
    final eulZ = -lean * math.cos(leanDir);
    final axisQ = quatFromEulerXyz(eulX, 0, eulZ);
    final axis = Vector3(0, 1, 0)..applyQuaternion(axisQ);

    // place along trunk axis from foot
    Vector3 at(double h) => Vector3(x, y, z) + axis * h;

    final c = at(H / 2);
    parts.add(Part(trunkGeo,
        trs(c.x, c.y, c.z, eulX, 0, eulZ, trunkR, H, trunkR), _cedarWoodMat));

    // foot flare at ~30 % of height
    final f = at(0.3 * s);
    parts.add(Part(
        trunkGeo,
        trs(f.x, f.y, f.z, 0, 0, 0, trunkR * 1.9, 0.6 * s, trunkR * 1.9),
        _cedarWoodMat));

    // crown: stack of overlapping cones tapering to a point
    final base = H * rng.range(0.30, 0.42);
    final crown = H - base;
    final n = 6 + rng.ints(0, 2);
    final rMax = H * 0.150 * rng.range(0.86, 1.14);

    for (int k = 0; k < n; k++) {
      final u = k / n;
      final hk = base + crown * (u + rng.range(-0.03, 0.03));
      final ck = (crown / n) * 2.15 * rng.range(0.86, 1.14);
      final rk = rMax * math.pow(1 - u, 0.82).toDouble() * rng.range(0.88, 1.1);
      final p = at(hk);
      final off = rng.range(0, 6.28);
      final wob = rk * 0.09;
      final ell = rng.range(0.84, 1.18);
      final tx = eulX + rng.range(-0.07, 0.07);
      final tz = eulZ + rng.range(-0.07, 0.07);

      // lighter at top, deepest underneath
      int tone;
      if (u > 0.62) {
        tone = 0;
      } else if (u < 0.26) {
        tone = 2;
      } else {
        tone = 1;
      }
      if (rng.chance(0.18)) tone = (tone + 1) % 3;

      parts.add(Part(
          coneGeo,
          trs(p.x + math.cos(off) * wob, p.y, p.z + math.sin(off) * wob, tx,
              rng.range(0, 6.28), tz, rk, ck, rk * ell),
          _cedarTierMats[tone]));
    }

    // leader: slim cone finishing the point
    {
      final p = at(base + crown * 0.86);
      parts.add(Part(
          coneGeo,
          trs(p.x, p.y, p.z, eulX, rng.range(0, 6.28), eulZ, rMax * 0.30,
              crown * 0.30 * rng.range(0.9, 1.25), rMax * 0.30),
          _cedarTierMats[0]));
    }

    // two sprigs so no two crowns have the same outline
    for (int k = 0; k < 2; k++) {
      final u = rng.range(0.15, 0.8);
      final p = at(base + crown * u);
      final rk = rMax * (1 - u) * rng.range(0.45, 0.8);
      final a = rng.range(0, 6.28);
      final t = rng.chance(0.5) ? 1 : 2;
      parts.add(Part(
          coneGeo,
          trs(p.x + math.cos(a) * rk * 0.55, p.y, p.z + math.sin(a) * rk * 0.55,
              eulX, rng.range(0, 6.28), eulZ, rk, rk * rng.range(1.3, 2.0), rk),
          _cedarTierMats[t]));
    }
  }

  return bake(parts);
}

class HillRockSpot {
  const HillRockSpot(
      {required this.x,
      required this.z,
      this.n = 3,
      this.r = .7,
      this.spread = 1.8,
      this.seed = 41});
  final double x, z, r, spread;
  final int n, seed;
}

List<Tri> buildHillRocks(
    List<HillRockSpot> spots, double Function(double, double) yAt) {
  final geometry = dodecahedronGeometry(1);
  const mats = [
    Mat(0xb4aeb6, tint: 0x655d84, bands: '3'),
    Mat(0xb4aeb6, tint: 0x6f6790, bands: '3'),
  ];
  final parts = <Part>[];
  for (final spot in spots) {
    final rng = RngKit(spot.seed);
    for (var k = 0; k < spot.n; k++) {
      final x = spot.x + rng.range(-1, 1) * spot.spread;
      final z = spot.z + rng.range(-1, 1) * spot.spread;
      final r = spot.r * rng.range(.55, 1.35);
      parts.add(Part(
          geometry,
          trs(
              x,
              yAt(x, z) + r * .42,
              z,
              rng.range(-.3, .3),
              rng.range(0, 3),
              rng.range(-.3, .3),
              r,
              r * rng.range(.55, .8),
              r * rng.range(.8, 1.25)),
          mats[k % 2]));
    }
  }
  return bake(parts);
}

class HillTuftSpot {
  const HillTuftSpot(
      {required this.x,
      required this.z,
      this.n = 5,
      this.spread = 1.4,
      this.scale = 1,
      this.seed = 77});
  final double x, z, spread, scale;
  final int n, seed;
}

List<Tri> buildHillTufts(
    List<HillTuftSpot> spots, double Function(double, double) yAt) {
  final blade = applyMatrix(cylGeometry(0, .055, 1, 4), trs(0, .5, 0));
  const mats = [
    Mat(0x7a9c78, tint: 0x5b6f8c, bands: '3'),
    Mat(0xb2c894, tint: 0x5b6f8c, bands: '3'),
  ];
  final parts = <Part>[];
  for (final spot in spots) {
    final rng = RngKit(spot.seed);
    for (var k = 0; k < spot.n; k++) {
      final x = spot.x + rng.range(-1, 1) * spot.spread;
      final z = spot.z + rng.range(-1, 1) * spot.spread;
      final y = yAt(x, z);
      final h = rng.range(.42, .72) * spot.scale;
      for (var b = 0; b < 3; b++) {
        final a = rng.range(0, 6.3);
        final lean = rng.range(.12, .42);
        parts.add(Part(
            blade,
            trs(
                x + math.cos(a) * .05,
                y,
                z + math.sin(a) * .05,
                lean * math.sin(a),
                0,
                -lean * math.cos(a),
                rng.range(.8, 1.2),
                h,
                rng.range(.8, 1.2)),
            mats[(k + b) % 2]));
      }
    }
  }
  return bake(parts);
}
