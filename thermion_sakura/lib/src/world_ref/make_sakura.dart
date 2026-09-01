/// Dart port of the reference `src/world/trees.js::buildSakura` — a cherry
/// tree: a baked trunk/branch/twig mesh plus three tones of faceted blossom
/// blobs (soft-ramp, no shadow receive). Built on the geometry substrate, so
/// the output matches three.js bit-for-bit (validated the same way as makePole).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

// PAL tones + per-tone tints (trees.js BLOB_TONES / BLOB_TINT).
const _trunkMat = Mat(0x9a8082, tint: 0x8a7290, bands: '3'); // PAL.trunk

class SakuraSpot {
  const SakuraSpot({
    required this.x,
    required this.z,
    this.y = 0,
    this.scale = 1,
    this.seed = 1,
    this.lean = 0,
    this.leanDir,
    this.tone,
  });
  final double x, z, y, scale, lean;
  final int seed;
  final double? leanDir;
  final int? tone;
}

/// Build one or more cherry trees, returning the wood + blossom triangle soup
/// in flat space (apply the planet wrap afterwards, as the reference does).
List<Tri> buildSakura(List<SakuraSpot> spots,
    {int blossomLightColor = 0xfff0f4,
    int blossomColor = 0xfbc6d8,
    int blossomDeepColor = 0xf0a3c0,
    bool includeCanopy = true}) {
  final blossomMats = <Mat>[
    Mat(blossomLightColor, tint: 0xe2c3d2, bands: 'soft'),
    Mat(blossomColor, tint: 0xd8b2c6, bands: 'soft'),
    Mat(blossomDeepColor, tint: 0xc99cba, bands: 'soft'),
  ];
  final trunkGeo = cylGeometry(0.7, 1.0, 1, 7);
  final branchGeo = cylGeometry(0.25, 0.55, 1, 5);
  final twigGeo = cylGeometry(0.12, 0.3, 1, 4);
  final blobGeo = icosahedronGeometry(1, 1);

  final parts = <Part>[];

  for (final spot in spots) {
    final rng = RngKit(spot.seed);
    final s = spot.scale;
    final x = spot.x, z = spot.z, y = spot.y;
    final lean = spot.lean;
    final leanDir = spot.leanDir ?? rng.range(0, math.pi * 2);

    final trunkH = 2.5 * s * rng.range(0.9, 1.12);
    final trunkR = 0.2 * s;
    parts.add(Part(
        trunkGeo,
        trs(x, y + trunkH / 2, z, lean * math.sin(leanDir), 0,
            -lean * math.cos(leanDir), trunkR, trunkH, trunkR),
        _trunkMat));
    // root flare
    parts.add(Part(
        trunkGeo,
        trs(x, y + 0.16 * s, z, 0, 0, 0, trunkR * 1.5, 0.34 * s, trunkR * 1.5),
        _trunkMat));

    // Trunk tip (exact rotation of (0, trunkH/2, 0) by the lean Euler).
    final tip = Vector3(0, trunkH / 2, 0)
      ..applyQuaternion(quatFromEulerXyz(
          lean * math.sin(leanDir), 0, -lean * math.cos(leanDir)));
    final topX = x + tip.x, topZ = z + tip.z, topY = y + trunkH / 2 + tip.y;

    final canopyCenters = <Vector3>[];
    final limbs = 3 + (rng.next() * 2).floor();
    for (int i = 0; i < limbs; i++) {
      final a = (i / limbs) * math.pi * 2 + rng.range(-0.4, 0.4);
      final len = 1.9 * s * rng.range(0.82, 1.2);
      final tilt = rng.range(0.5, 0.85);
      final ex = topX + math.cos(a) * math.sin(tilt) * len;
      final ez = topZ + math.sin(a) * math.sin(tilt) * len;
      final ey = topY + math.cos(tilt) * len;
      final mid = Vector3((topX + ex) / 2, (topY + ey) / 2, (topZ + ez) / 2);
      final dir = Vector3(ex - topX, ey - topY, ez - topZ);
      final l = dir.length;
      final q = quatFromUnitVectors(Vector3(0, 1, 0), dir);
      parts.add(Part(branchGeo,
          composePRS(mid, q, Vector3(0.13 * s, l, 0.13 * s)), _trunkMat));
      canopyCenters.add(Vector3(ex, ey, ez));

      if (rng.next() < 0.75) {
        // one fork per limb: normalize dir, add jitter, re-normalise (matches ref)
        final dir2 = dir.clone()
          ..normalize()
          ..add(Vector3(
              rng.range(-0.7, 0.7), rng.range(0.1, 0.6), rng.range(-0.7, 0.7)))
          ..normalize();
        final l2 = len * rng.range(0.5, 0.8);
        final e2 = Vector3(ex, ey, ez)..addScaled(dir2, l2);
        final mid2 = (Vector3(ex, ey, ez) + e2) * 0.5;
        final q2 = quatFromUnitVectors(Vector3(0, 1, 0), dir2);
        parts.add(Part(twigGeo,
            composePRS(mid2, q2, Vector3(0.09 * s, l2, 0.09 * s)), _trunkMat));
        canopyCenters.add(e2);
      }
    }

    // Blossom mass: many small faceted blobs, tone biased by height.
    final count = 26 + (rng.next() * 10).floor();
    double yMin = double.infinity, yMax = double.negativeInfinity;
    for (final c in canopyCenters) {
      if (c.y < yMin) yMin = c.y;
      if (c.y > yMax) yMax = c.y;
    }
    for (int i = 0; i < count; i++) {
      final c = canopyCenters[
          (rng.next() * canopyCenters.length).floor() % canopyCenters.length];
      final r = 0.56 * s * rng.range(0.68, 1.3);
      final px = c.x + rng.range(-1.15, 1.15) * s;
      final py = c.y + rng.range(-0.55, 0.95) * s;
      final pz = c.z + rng.range(-1.15, 1.15) * s;
      int tone;
      if (spot.tone != null) {
        tone = spot.tone!;
      } else {
        final hi = (py - yMin) / math.max(0.5, yMax + 1.2 * s - yMin);
        tone = hi > 0.62 ? 0 : (hi < 0.28 ? 2 : 1);
        if (rng.next() < 0.22) tone = (tone + 1) % 3;
      }
      final matrix = trs(px, py, pz, rng.range(0, 3), rng.range(0, 3),
          rng.range(0, 3), r, r * rng.range(0.68, 0.88), r);
      if (includeCanopy) {
        parts.add(Part(blobGeo, matrix, blossomMats[tone], planetRigid: true));
      }
    }

    // a small cluster crowning the silhouette
    for (int i = 0; i < 4; i++) {
      final r = 0.6 * s * rng.range(0.8, 1.15);
      final matrix = trs(
          topX + rng.range(-0.7, 0.7) * s,
          topY + (1.25 + rng.range(0, 0.5)) * s,
          topZ + rng.range(-0.7, 0.7) * s,
          rng.range(0, 3),
          rng.range(0, 3),
          rng.range(0, 3),
          r,
          r * 0.8,
          r);
      if (includeCanopy) {
        parts.add(Part(blobGeo, matrix, blossomMats[0], planetRigid: true));
      }
    }
  }

  return bake(parts);
}
