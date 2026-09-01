/// Pure landform definition for ひばり湖.
///
/// Ported from `src/world/lakeform.js`; it has no scene or renderer dependency
/// so both the hill lattice and the water/detail builders can survey the same
/// shoreline, bed, bank, and rim.
library;

import 'dart:math' as math;

const lakeLevel = 3.40;
const _floorY = -1.30;
const _reach = 62.0;
const _rimCrestWidth = 5.5;

class LakeShorePoint {
  const LakeShorePoint(this.x, this.z, this.bank, this.depthRamp, this.maxDepth,
      this.crest, this.fall,
      [this.handIn = 7, this.handOut = 17]);
  final double x, z;
  final double bank, depthRamp, maxDepth, crest, fall;
  final double handIn, handOut;
}

const lakeShore = <LakeShorePoint>[
  LakeShorePoint(161, -45.2, .50, 14, 2.5, 2.2, .48),
  LakeShorePoint(154, -48.8, .50, 15, 2.6, 2.2, .48),
  LakeShorePoint(147.2, -52.2, .46, 14, 2.5, 4.2, .46, 10),
  LakeShorePoint(143.6, -60, .26, 16, 2.6, 5.6, .46, 12, 24),
  LakeShorePoint(142.4, -70, .21, 17, 2.6, 6.4, .44, 14, 28),
  LakeShorePoint(142.2, -80, .20, 18, 2.6, 6.8, .44, 15, 30),
  LakeShorePoint(145, -90, .24, 17, 2.6, 7.0, .44, 14, 28),
  LakeShorePoint(147.6, -100, .38, 14, 2.5, 7.2, .44, 11, 24),
  LakeShorePoint(148.6, -110, .26, 16, 2.3, 6.8, .42, 9),
  LakeShorePoint(151.6, -118, .22, 18, 2.1, 6.2, .42),
  LakeShorePoint(159.4, -125.6, .18, 20, 1.9, 5.6, .40),
  LakeShorePoint(170, -131.6, .24, 18, 1.9, 5.4, .40, 11, 24),
  LakeShorePoint(181, -135.6, .26, 16, 1.8, 5.4, .40, 12, 24),
  LakeShorePoint(184, -126, .30, 14, 1.9, 5.0, .40),
  LakeShorePoint(186, -116, .32, 13, 2.1, 4.8, .40),
  LakeShorePoint(189, -107, .34, 12, 2.3, 4.6, .40),
  LakeShorePoint(194, -101, .36, 12, 2.4, 4.2, .40),
  LakeShorePoint(199, -105, .34, 12, 2.3, 4.6, .40),
  LakeShorePoint(201, -114, .30, 13, 2.1, 4.8, .40),
  LakeShorePoint(200, -124, .26, 15, 1.8, 5.0, .40),
  LakeShorePoint(202, -134, .11, 26, 1.1, 5.4, .38),
  LakeShorePoint(214, -136.5, .10, 28, 1.0, 5.6, .38),
  LakeShorePoint(226, -135, .12, 26, 1.1, 5.8, .38),
  LakeShorePoint(236, -130, .16, 22, 1.6, 6.4, .40),
  LakeShorePoint(243, -120, .30, 17, 2.3, 7.2, .42),
  LakeShorePoint(247, -108, .34, 15, 2.5, 7.4, .42),
  LakeShorePoint(249.6, -96, .38, 14, 2.5, 7.6, .42),
  LakeShorePoint(249.8, -84, .40, 14, 2.5, 7.6, .42),
  LakeShorePoint(247, -72, .38, 15, 2.5, 7.4, .42),
  LakeShorePoint(242, -60, .32, 16, 2.4, 7.0, .42),
  LakeShorePoint(234, -50, .26, 18, 2.2, 6.4, .40),
  LakeShorePoint(224, -43, .24, 19, 2.2, 6.2, .42),
  LakeShorePoint(212, -40, .26, 20, 2.4, 6.4, .44),
  LakeShorePoint(199, -39.4, .28, 20, 2.5, 6.8, .46),
  LakeShorePoint(186, -39.6, .28, 20, 2.5, 7.2, .46),
  LakeShorePoint(174, -40.6, .30, 18, 2.5, 7.2, .46),
  LakeShorePoint(166, -42.4, .36, 16, 2.5, 6.0, .46),
];

class _Segment {
  _Segment(this.a, this.b, this.arc)
      : dx = b.x - a.x,
        dz = b.z - a.z,
        length =
            math.sqrt((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
  final LakeShorePoint a, b;
  final double arc, dx, dz, length;
  double get length2 => length * length;
}

late final List<_Segment> _segments = () {
  final out = <_Segment>[];
  var arc = 0.0;
  for (var i = 0; i < lakeShore.length; i++) {
    final segment =
        _Segment(lakeShore[i], lakeShore[(i + 1) % lakeShore.length], arc);
    out.add(segment);
    arc += segment.length;
  }
  return out;
}();

class LakeNear {
  const LakeNear(this.distance, this.bank, this.depthRamp, this.maxDepth,
      this.crest, this.fall, this.handIn, this.handOut, this.arc);
  final double distance;
  final double bank, depthRamp, maxDepth, crest, fall;
  final double handIn, handOut, arc;
}

bool inLakePoly(double x, double z) {
  if (x < 141 || x > 251 || z < -138 || z > -38) return false;
  var inside = false;
  for (final segment in _segments) {
    final a = segment.a, b = segment.b;
    if ((a.z > z) != (b.z > z)) {
      final t = (z - a.z) / (b.z - a.z);
      if (x < a.x + t * (b.x - a.x)) inside = !inside;
    }
  }
  return inside;
}

LakeNear? lakeNear(double x, double z) {
  if (x < 142.2 - _reach ||
      x > 249.8 + _reach ||
      z < -136.5 - _reach ||
      z > -39.4 + _reach) {
    return null;
  }
  var best = double.infinity;
  late _Segment picked;
  var pickedT = 0.0;
  for (final segment in _segments) {
    final t =
        (((x - segment.a.x) * segment.dx + (z - segment.a.z) * segment.dz) /
                segment.length2)
            .clamp(0.0, 1.0);
    final px = segment.a.x + segment.dx * t;
    final pz = segment.a.z + segment.dz * t;
    final distance2 = (x - px) * (x - px) + (z - pz) * (z - pz);
    if (distance2 < best) {
      best = distance2;
      picked = segment;
      pickedT = t;
    }
  }
  final distance = math.sqrt(best);
  final inside = inLakePoly(x, z);
  if (!inside && distance > _reach) return null;
  double lerp(double a, double b) => a + (b - a) * pickedT;
  return LakeNear(
    inside ? distance : -distance,
    lerp(picked.a.bank, picked.b.bank),
    lerp(picked.a.depthRamp, picked.b.depthRamp),
    lerp(picked.a.maxDepth, picked.b.maxDepth),
    lerp(picked.a.crest, picked.b.crest),
    lerp(picked.a.fall, picked.b.fall),
    lerp(picked.a.handIn, picked.b.handIn),
    lerp(picked.a.handOut, picked.b.handOut),
    picked.arc + picked.length * pickedT,
  );
}

double _smoothstep(double a, double b, double value) {
  final t = ((value - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double lakeDepthProfile(double x, double z) {
  final near = lakeNear(x, z);
  if (near == null || near.distance <= 0) return near?.distance ?? -99;
  final t = (near.distance / near.depthRamp).clamp(0.0, 1.0);
  return near.maxDepth * t * t * (3 - 2 * t);
}

double _rimAt(LakeNear near) {
  if (near.distance >= 0) return double.negativeInfinity;
  final s = -near.distance;
  final wob =
      math.sin(near.arc * .062) * 4 + math.sin(near.arc * .148 + 1.7) * 1.8;
  final crestWidth = math.max(2, _rimCrestWidth + wob);
  final crest = near.crest * (1 + .09 * math.sin(near.arc * .091 + .4));
  final riseRun = crest / math.max(.08, near.bank);
  if (s <= riseRun) return lakeLevel + near.bank * s;
  if (s <= riseRun + crestWidth) return lakeLevel + crest;
  return lakeLevel + crest - (s - riseRun - crestWidth) * near.fall;
}

double _damAt(double x, double z) {
  const ax = 143.0, az = -44.0, bx = 157.0, bz = -37.0;
  const crest = 6.30, half = 3.4, face = .50;
  const dx = bx - ax, dz = bz - az;
  final t =
      (((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)).clamp(0.0, 1.0);
  final distance = math
      .sqrt(math.pow(x - (ax + dx * t), 2) + math.pow(z - (az + dz * t), 2));
  return distance <= half ? crest : crest - (distance - half) * face;
}

double lakeGround(double natural, double x, double z, double keep) {
  final near = lakeNear(x, z);
  if (near == null) return natural;
  double fade(double value) => _floorY + (value - _floorY) * keep;
  var height = math.max(natural, fade(_damAt(x, z)));
  final rim = _rimAt(near);
  if (rim.isFinite) height = math.max(height, fade(rim));
  if (near.distance >= 0) {
    final t = (near.distance / near.depthRamp).clamp(0.0, 1.0);
    height = lakeLevel - near.maxDepth * t * t * (3 - 2 * t);
  } else {
    final distance = -near.distance;
    final bank = lakeLevel + near.bank * distance;
    final cut = math.min(bank, height);
    final weight = _smoothstep(near.handIn, near.handOut, distance);
    height = cut + (height - cut) * weight;
  }
  return height;
}

double lakeDamp(double x, double z, double height) {
  final near = lakeNear(x, z);
  if (near == null) return 1;
  if (near.distance > -2) return 0;
  final byDistance = ((-near.distance - 2) / 10).clamp(0.0, 1.0);
  final byRise = ((height - lakeLevel - .9) / 2.4).clamp(0.0, 1.0);
  return math.min(byDistance, byRise);
}
