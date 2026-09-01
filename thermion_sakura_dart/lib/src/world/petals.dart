/// Falling and fallen blossom — a port of the reference `src/world/petals.js`.
///
/// Petals are small flat hexagons (opaque, unlit). The falling field is
/// settled with 40 update steps so the very first frame already has petals
/// mid-air, exactly like the reference; the fallen ones hug gutters, kerbs,
/// the crossing deck and a thin scatter over the open road.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mathutil.dart';
import '../mesh.dart';
import '../palette.dart';
import 'street.dart';

const int _count = 980;
const double _top = 6.8;
const double _z0 = -30;
const double _z1 = 34;
const double _half = 9.5;

class _Petal {
  _Petal(this.x, this.y, this.z, this.fall, this.swayAmp, this.swayFreq, this.phase, this.scale, this.drift);
  double x, y, z, phase;
  final double fall, swayAmp, swayFreq, scale, drift;
}

void _petalShape(Mesh m, Vector3 center, double scale, int color, double yaw) {
  const r = 0.092; // ~0.185 wide
  final pts = <Vector3>[];
  for (int i = 0; i < 6; i++) {
    final a = yaw + i / 6 * math.pi * 2;
    pts.add(Vector3(center.x + math.cos(a) * r * scale, center.y, center.z + math.sin(a) * r * scale * 0.73));
  }
  for (int i = 0; i < 6; i++) {
    final j = (i + 1) % 6;
    m.triRaw(center, pts[i], pts[j], C.srgb(color), normal: Vector3(0, 1, 0));
  }
}

/// The falling field + the fallen scatter, baked for the opening frame.
void buildPetals(Mesh m, double Function(double z) groundY) {
  final rng = rngKit(8123);
  final petals = <_Petal>[];
  for (int i = 0; i < _count; i++) {
    petals.add(_Petal(
      rng.range(-_half, _half),
      rng.range(0.2, _top),
      rng.range(_z0, _z1),
      rng.range(0.42, 0.86),
      rng.range(0.25, 0.75),
      rng.range(0.5, 1.35),
      rng.range(0.0, 10.0),
      rng.range(0.78, 1.25),
      rng.range(-0.16, 0.16),
    ));
  }

  // settle the field so the first frame already has petals mid-air
  for (int k = 0; k < 40; k++) {
    for (final p in petals) {
      final s = math.sin(k * 0.1 * p.swayFreq + p.phase);
      p.y -= p.fall * 0.1;
      p.x += (p.swayAmp * s * 0.55 + p.drift) * 0.1;
      p.z += p.swayAmp * math.sin(k * 0.1 * p.swayFreq * 2.7 + p.phase * 1.7) * 0.32 * 0.1;
      final cx = centerX(p.z);
      if (p.x < cx - _half) p.x = cx + _half;
      if (p.x > cx + _half) p.x = cx - _half;
      if (p.z < _z0) p.z = _z1;
      if (p.z > _z1) p.z = _z0;
      if (p.y < groundY(p.z) + 0.04) {
        p.y = _top + rng.range(0, 1.4);
        p.z = rng.range(_z0, _z1);
        p.x = rng.range(-_half, _half);
        p.phase = rng.range(0, 10);
      }
    }
  }

  final tones = [Pal.petal, Pal.blossomLight, Pal.petalDeep];
  for (int i = 0; i < _count; i++) {
    final p = petals[i];
    final tone = tones[i % 3];
    final yaw = rng.range(0.0, 6.28);
    _petalShape(m, Vector3(p.x, p.y, p.z), p.scale, tone, yaw);
  }

  // fallen petals
  _buildFallenPetals(m, rng, groundY);
}

void _buildFallenPetals(Mesh m, Rng rng, double Function(double z) groundY) {
  final tones = [Pal.petal, Pal.blossomLight, Pal.petalDeep];
  for (int i = 0; i < 620; i++) {
    final z = rng.range(-26.0, 32.0);
    final cx = centerX(z);
    final y = groundY(z);
    final r = rng.next();
    double x, py;
    if (r < 0.42) {
      final s = rng.sign().toDouble();
      x = cx + s * rng.range(2.35, 3.12);
      py = y;
    } else if (r < 0.62) {
      final s = rng.sign().toDouble();
      x = cx + s * rng.range(3.2, 4.6);
      py = y + 0.135;
    } else if (r < 0.78) {
      final dz = rng.range(-2.4, 2.4);
      x = cx + rng.range(-3.1, 3.1);
      py = 0.32;
      assert(dz.abs() < 3); // dz only used for placement spread in the reference
    } else {
      x = cx + rng.range(-3.0, 3.0);
      py = y;
    }
    final tone = tones[i % 3];
    final scale = rng.range(0.8, 1.25);
    final yaw = rng.range(0.0, 6.28);
    _petalShape(m, Vector3(x, py + 0.019, z), scale, tone, yaw);
  }
}
