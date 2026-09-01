/// The cherry trees — a faithful port of the reference `src/world/trees.js`
/// `buildSakura` (wood + blossom blob clusters) and `buildShrubs`.
///
/// The RNG is the same mulberry32 sequence per seed, so trunk lean, limb
/// layout and blob placement match the reference tree for tree.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mathutil.dart';
import '../mesh.dart';
import '../palette.dart';

/// Blossom tones (high-key two-band ramps with pink shadow tints).
const List<int> _blobTones = [Pal.blossomLight, Pal.blossom, Pal.blossomDeep];
const List<int> _blobTints = [0xe2c3d2, 0xd8b2c6, 0xc99cba];

class SakuraSpot {
  const SakuraSpot(this.x, this.z, {this.scale = 1.0, required this.seed, this.lean = 0, this.leanDir = 0, this.y});
  final double x, z, scale;
  final int seed;
  final double lean, leanDir;
  final double? y;
}


/// Quaternion rotating +Y onto [dir] (axis-angle form; vector_math has no
/// from-to factory).
Quaternion _alignUpTo(Vector3 dir) {
  final d = dir.normalized();
  final up = Vector3(0, 1, 0);
  final dot = up.dot(d).clamp(-1.0, 1.0);
  if (dot.abs() > 0.9999) {
    return dot > 0 ? Quaternion.identity() : Quaternion.axisAngle(Vector3(1, 0, 0), math.pi);
  }
  final axis = up.cross(d).normalized();
  return Quaternion.axisAngle(axis, math.acos(dot));
}

Matrix4 _rotFromQuat(Quaternion q) {
  final m = Matrix4.zero();
  final x = q.x, y = q.y, z = q.z, w = q.w;
  m.setEntry(0, 0, 1 - 2 * (y * y + z * z));
  m.setEntry(0, 1, 2 * (x * y - z * w));
  m.setEntry(0, 2, 2 * (x * z + y * w));
  m.setEntry(1, 0, 2 * (x * y + z * w));
  m.setEntry(1, 1, 1 - 2 * (x * x + z * z));
  m.setEntry(1, 2, 2 * (y * z - x * w));
  m.setEntry(2, 0, 2 * (x * z - y * w));
  m.setEntry(2, 1, 2 * (y * z + x * w));
  m.setEntry(2, 2, 1 - 2 * (x * x + y * y));
  m.setEntry(3, 3, 1);
  return m;
}

/// One sakura tree, ported exactly from the reference. Returns the tree's
/// baked cast shadow (canopy projected along the sun onto the ground).
ShadowDisc? _sakura(Mesh m, SakuraSpot spot) {
  final rng = rngKit(spot.seed);
  final s = spot.scale;
  final x = spot.x, z = spot.z, y = spot.y ?? 0;
  final lean = spot.lean;
  final leanDir = spot.leanDir != 0 ? spot.leanDir : rng.range(0.0, math.pi * 2);

  final trunkH = 2.5 * s * rng.range(0.9, 1.12);
  final trunkR = 0.2 * s;

  // trunk (leaning) + root flare
  final leanQ = Quaternion.euler(lean * math.sin(leanDir), 0, -lean * math.cos(leanDir));
  final trunkRot = _rotFromQuat(leanQ);
  final trunkMat = Matrix4.translation(Vector3(x, y + trunkH / 2, z))
    ..multiply(trunkRot)
    ..scale(trunkR, trunkH, trunkR);
  m.cylUnit(trunkMat, Pal.trunk, segments: 7, tint: 0x8a7290);
  final flareMat = Matrix4.translation(Vector3(x, y + 0.16 * s, z))
    ..scale(trunkR * 1.5, 0.34 * s, trunkR * 1.5);
  m.cylUnit(flareMat, Pal.trunk, segments: 7, tint: 0x8a7290);

  // tip of the trunk (rotation applied to (0, trunkH/2, 0))
  final tipLocal = trunkRot.transform3(Vector3(0, trunkH / 2, 0));
  final topX = x + tipLocal.x;
  final topZ = z + tipLocal.z;
  final topY = y + trunkH / 2 + tipLocal.y;

  // main limbs + forks
  final limbs = 3 + (rng.next() * 2).floor();
  final canopyCenters = <Vector3>[];
  for (int i = 0; i < limbs; i++) {
    final a = (i / limbs) * math.pi * 2 + rng.range(-0.4, 0.4);
    final len = 1.9 * s * rng.range(0.82, 1.2);
    final tilt = rng.range(0.5, 0.85);
    final ex = topX + math.cos(a) * math.sin(tilt) * len;
    final ez = topZ + math.sin(a) * math.sin(tilt) * len;
    final ey = topY + math.cos(tilt) * len;
    final dir = Vector3(ex - topX, ey - topY, ez - topZ);
    final l = dir.length;
    final q = _alignUpTo(dir);
    final mid = Vector3((topX + ex) / 2, (topY + ey) / 2, (topZ + ez) / 2);
    final branchMat = Matrix4.translation(mid)
      ..multiply(_rotFromQuat(q))
      ..scale(0.13 * s, l, 0.13 * s);
    m.cylUnit(branchMat, Pal.trunk, segments: 5, tint: 0x8a7290);
    canopyCenters.add(Vector3(ex, ey, ez));

    // one fork per limb
    if (rng.next() < 0.75) {
      final dir2 = dir.normalized() +
          Vector3(rng.range(-0.7, 0.7), rng.range(0.1, 0.6), rng.range(-0.7, 0.7));
      dir2.normalize();
      final l2 = len * rng.range(0.5, 0.8);
      final e2 = Vector3(ex, ey, ez) + dir2 * l2;
      final mid2 = (Vector3(ex, ey, ez) + e2) * 0.5;
      final q2 = _alignUpTo(dir2);
      final forkMat = Matrix4.translation(mid2)
        ..multiply(_rotFromQuat(q2))
        ..scale(0.09 * s, l2, 0.09 * s);
      m.cylUnit(forkMat, Pal.trunk, segments: 4, tint: 0x8a7290);
      canopyCenters.add(e2);
    }
  }

  // blossom mass: dense clusters of small faceted lumps, tone biased by height
  var count = 26 + (rng.next() * 10).floor();
  double yMin = 1e30, yMax = -1e30;
  for (final c in canopyCenters) {
    yMin = math.min(yMin, c.y);
    yMax = math.max(yMax, c.y);
  }
  for (int i = 0; i < count; i++) {
    final c = canopyCenters[(rng.next() * canopyCenters.length).floor()];
    final r = 0.56 * s * rng.range(0.68, 1.3);
    final px = c.x + rng.range(-1.15, 1.15) * s;
    final py = c.y + rng.range(-0.55, 0.95) * s;
    final pz = c.z + rng.range(-1.15, 1.15) * s;
    var tone = 1;
    final hi = (py - yMin) / math.max(0.5, yMax + 1.2 * s - yMin);
    tone = hi > 0.62 ? 0 : (hi < 0.28 ? 2 : 1);
    if (rng.next() < 0.22) tone = (tone + 1) % 3;
    m.ico(Vector3(px, py, pz), r, _blobTones[tone],
        tint: _blobTints[tone], bands: 'soft', squashY: rng.range(0.68, 0.88));
  }

  // a small cluster crowning the silhouette
  for (int i = 0; i < 4; i++) {
    final r = 0.6 * s * rng.range(0.8, 1.15);
    m.ico(
        Vector3(
          topX + rng.range(-0.7, 0.7) * s,
          topY + (1.25 + rng.range(0, 0.5)) * s,
          topZ + rng.range(-0.7, 0.7) * s,
        ),
        r,
        _blobTones[0],
        tint: _blobTints[0],
        bands: 'soft',
        squashY: 0.8);
  }

  // baked cast shadow: the canopy mass projected along the sun onto the ground
  final sd = m.cel.sunDir;
  double cx = 0, cy = 0, cz = 0;
  for (final c in canopyCenters) {
    cx += c.x;
    cy += c.y;
    cz += c.z;
  }
  if (canopyCenters.isNotEmpty && sd.y.abs() > 0.1) {
    cx /= canopyCenters.length;
    cy /= canopyCenters.length;
    cz /= canopyCenters.length;
    final h = cy - y;
    // The light travels along -sunDir, so the shadow of a point at height h
    // lands offset by (-sd.x, -sd.z) / sd.y * h.
    final sx = cx - sd.x / sd.y * h;
    final sz = cz - sd.z / sd.y * h;
    final r = 2.7 * s;
    return ShadowDisc(sx, sz, r);
  }
  return null;
}

/// All the trees that frame the crossing scene (reference `sakuraSpots`).
const List<SakuraSpot> sakuraSpots = [
  SakuraSpot(-7.1, 5.8, scale: 1.22, seed: 101, lean: 0.13, leanDir: 1.9),
  SakuraSpot(6.3, 2.5, scale: 1.06, seed: 102, lean: 0.1, leanDir: 4.4),
  SakuraSpot(-5.9, 17.9, scale: 1.16, seed: 128, lean: 0.14, leanDir: 1.6),
  SakuraSpot(-5.6, 25.4, scale: 1.04, seed: 129, lean: 0.1, leanDir: 2.1),
  SakuraSpot(-12.5, 3.9, seed: 103, lean: 0.08),
  SakuraSpot(-19.0, 3.9, scale: 1.12, seed: 104, lean: 0.1),
  SakuraSpot(-26.5, 4.0, scale: 0.95, seed: 105, lean: 0.06),
  SakuraSpot(-34.0, 3.9, scale: 1.08, seed: 106, lean: 0.09),
  SakuraSpot(13.5, 3.9, scale: 1.05, seed: 107, lean: 0.07),
  SakuraSpot(20.5, 4.0, scale: 0.98, seed: 108, lean: 0.1),
  SakuraSpot(28.0, 3.9, scale: 1.14, seed: 109, lean: 0.05),
  SakuraSpot(32.5, 4.0, seed: 110, lean: 0.09),
  SakuraSpot(-11.0, -4.6, scale: 1.04, seed: 111, lean: 0.08),
  SakuraSpot(-18.5, -4.6, scale: 0.96, seed: 112, lean: 0.1),
  SakuraSpot(11.5, -4.7, scale: 1.1, seed: 113, lean: 0.07),
  SakuraSpot(18.5, -7.4, scale: 1.02, seed: 114, lean: 0.06),
  SakuraSpot(26.5, -7.8, scale: 1.16, seed: 115, lean: 0.09),
  SakuraSpot(30.0, -6.9, scale: 0.98, seed: 116, lean: 0.05),
  SakuraSpot(-13.5, 15.5, scale: 1.1, seed: 117, lean: 0.11),
  SakuraSpot(5.9, 25.0, scale: 1.05, seed: 118, lean: 0.08),
  SakuraSpot(-14.0, 30.0, seed: 119, lean: 0.07),
  SakuraSpot(-12.0, -14.5, scale: 1.08, seed: 120, lean: 0.1),
  SakuraSpot(15.0, -20.0, scale: 1.03, seed: 121, lean: 0.06),
  SakuraSpot(-44.0, 4.5, scale: 1.2, seed: 122, lean: 0.08),
  SakuraSpot(46.0, 4.2, scale: 1.15, seed: 123, lean: 0.06),
  SakuraSpot(-42.0, -4.9, scale: 1.1, seed: 124, lean: 0.09),
  SakuraSpot(51.0, -9.0, scale: 1.18, seed: 125, lean: 0.07),
  SakuraSpot(-52.0, 6.0, scale: 1.25, seed: 126, lean: 0.05),
  SakuraSpot(54.0, 5.5, scale: 1.22, seed: 127, lean: 0.08),
];

/// Build every sakura tree into [m], seated on [groundY]. Returns the trees'
/// baked cast shadows, for the ground to consume.
List<ShadowDisc> buildSakura(Mesh m, double Function(double z) groundY) {
  final discs = <ShadowDisc>[];
  for (final spot in sakuraSpots) {
    final d = _sakura(m, SakuraSpot(spot.x, spot.z,
        scale: spot.scale, seed: spot.seed, lean: spot.lean, leanDir: spot.leanDir,
        y: groundY(spot.z)));
    if (d != null) discs.add(d);
  }
  return discs;
}

class ShrubSpot {
  const ShrubSpot(this.x, this.z, {this.r = 0.5, this.count = 4, this.spread = 1.4, required this.seed});
  final double x, z, r, spread;
  final int count;
  final int seed;
}

const List<ShrubSpot> shrubSpots = [
  ShrubSpot(-6.4, 6.6, r: 0.5, count: 4, spread: 1.2, seed: 201),
  ShrubSpot(-5.7, 12.4, r: 0.45, count: 3, spread: 1.0, seed: 202),
  ShrubSpot(-15.5, 4.6, r: 0.5, count: 4, spread: 1.6, seed: 211),
  ShrubSpot(-21.5, 4.5, r: 0.5, count: 4, spread: 1.6, seed: 212),
  ShrubSpot(5.6, 15.6, r: 0.5, count: 4, spread: 1.4, seed: 203),
  ShrubSpot(5.4, 31.5, r: 0.48, count: 3, spread: 1.2, seed: 204),
  ShrubSpot(-5.4, -13.4, r: 0.55, count: 5, spread: 1.6, seed: 205),
  ShrubSpot(6.6, -6.0, r: 0.5, count: 4, spread: 1.4, seed: 206),
  ShrubSpot(16.5, -9.5, r: 0.6, count: 5, spread: 2.0, seed: 207),
  ShrubSpot(30.0, -9.0, r: 0.6, count: 5, spread: 2.2, seed: 208),
  ShrubSpot(-16.0, 6.0, r: 0.55, count: 4, spread: 1.8, seed: 209),
  ShrubSpot(24.0, 6.5, r: 0.55, count: 4, spread: 1.8, seed: 210),
];

/// Low rounded shrubs along the frontages.
void buildShrubs(Mesh m, double Function(double z) groundY) {
  for (final spot in shrubSpots) {
    final rng = rngKit(spot.seed);
    final y = groundY(spot.z);
    for (int i = 0; i < spot.count; i++) {
      final r = spot.r * rng.range(0.75, 1.2);
      final dx = rng.range(-spot.spread, spot.spread) * 0.5;
      final dz = rng.range(-spot.spread, spot.spread) * 0.5;
      m.ico(Vector3(spot.x + dx, y + r * 0.55, spot.z + dz), r,
          i % 2 == 0 ? Pal.leaf : Pal.leafDeep,
          tint: 0x6a728c, bands: 'soft', squashY: 0.7);
    }
  }
}
