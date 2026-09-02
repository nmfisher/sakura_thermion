/// Dart port of the reference `src/world/petals.js` — fallen cherry-blossom
/// petals scattered on the street surface (gutters, pavement, crossing deck,
/// open road), plus the initial placement of the 980 falling petals (their
/// per-frame drift is a runtime animation concern and not baked here).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'street.dart' show centerX, groundY;

// ── Palette (palette.js) ──────────────────────────────────────────────────

const _petalMat =
    Mat(0xfcd9e4, unlit: true, noOutline: true); // flat(PAL.petal)
const _blossomLightMat =
    Mat(0xfff0f4, unlit: true, noOutline: true); // flat(PAL.blossomLight)
const _petalDeepMat =
    Mat(0xf6bccf, unlit: true, noOutline: true); // flat(PAL.petalDeep)

const _fallenMats = [_petalMat, _blossomLightMat, _petalDeepMat];

/// An authored patch of fallen blossom, normally placed under a district's
/// cherry trees and biased toward its kerbs and walls.
class PetalPatch {
  const PetalPatch({
    required this.x,
    required this.z,
    required this.w,
    required this.d,
    required this.y,
    this.n = 90,
  });

  final double x, z, w, d, y;
  final int n;
}

/// Low-poly silhouette of the canvas `petalTex` alpha mask. The source mask
/// occupies only about 63% of its quad width and 78% of its height; rendering
/// the whole PlaneGeometry made nearby petals read as large rectangular cards.
ThreeGeom _petalGeometry(double w, double h) {
  // Polygonal alpha-test silhouette fitted to textures.js::petalTex. Its
  // 0.53-quad width accounts for the source canvas Bézier's true extrema.
  const outline = <(double, double)>[
    (0.0, 0.41),
    (0.172, 0.28),
    (0.265, 0.0),
    (0.195, -0.30),
    (0.086, -0.375),
    (0.0, -0.235),
    (-0.086, -0.375),
    (-0.195, -0.30),
    (-0.265, 0.0),
    (-0.172, 0.28),
  ];
  final pos = <double>[0, 0, 0];
  final nor = <double>[0, 0, 1];
  for (final p in outline) {
    pos.addAll([p.$1 * w, p.$2 * h, 0]);
    nor.addAll([0, 0, 1]);
  }
  final idx = <int>[];
  for (var i = 0; i < outline.length; i++) {
    idx.addAll([0, (i + 1) % outline.length + 1, i + 1]);
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Build the source's edge-biased district petal patches.
List<Tri> buildFallenPatches(List<PetalPatch> patches,
    {int seed = 6619, int skip = 0}) {
  final rng = RngKit(seed);
  final geo = _petalGeometry(.17, .125);
  final flatMat = Matrix4.rotationX(-math.pi / 2);
  final parts = <Part>[];

  // All districts share one source generator. A district port can skip the
  // placements emitted by earlier districts and still reproduce its exact
  // authored scatter without building their geometry.
  for (var i = 0; i < skip; i++) {
    final u = rng.next();
    if (u < .45) {
      rng.sign();
      rng.range(.34, .5);
    } else {
      rng.range(-.34, .34);
    }
    rng.range(-.48, .48);
    rng.chance(.5);
    rng.range(0, 6.28);
    rng.range(.8, 1.3);
    rng.ints(0, 2);
  }

  for (final patch in patches) {
    for (var i = 0; i < patch.n; i++) {
      final u = rng.next();
      final edge =
          u < .45 ? rng.sign() * rng.range(.34, .5) : rng.range(-.34, .34);
      final other = rng.range(-.48, .48);
      final alongX = rng.chance(.5);
      final px = patch.x + (alongX ? other : edge) * patch.w;
      final pz = patch.z + (alongX ? edge : other) * patch.d;
      final yRot = rng.range(0, 6.28);
      final scale = rng.range(.8, 1.3);
      final tone = _fallenMats[rng.ints(0, 2)];
      final matrix = trs(px, patch.y + .021, pz, 0, yRot, 0) *
          flatMat *
          trs(0, 0, 0, 0, 0, 0, scale, 1, scale);
      parts.add(Part(geo, matrix, tone));
    }
  }
  return bake(parts);
}

// ── Fallen petals (buildFallenPetals) ──────────────────────────────────────

/// 620 petals lying flat on the ground.  Port of `buildFallenPetals`.
List<Tri> _buildFallenPetals() {
  final rng = RngKit(4471);
  // PlaneGeometry(0.17, 0.125) rotated -PI/2 around X → flat quad, normal up.
  final geo = _petalGeometry(0.17, 0.125);
  // Pre-bake the rotation so every part just needs translation + Y-rotation + scale.
  final flatMat = Matrix4.rotationX(-math.pi / 2);

  final parts = <Part>[];

  for (int i = 0; i < 620; i++) {
    final z = rng.range(-26.0, 32.0);
    final cx = centerX(z);
    final y = groundY(z);
    final r = rng.next();
    double px, pz, py;

    if (r < 0.42) {
      // hugging the gutters
      final s = rng.sign();
      px = cx + s * rng.range(2.35, 3.12);
      pz = z;
      py = y;
    } else if (r < 0.62) {
      // on the pavement, against the tactile line
      final s = rng.sign();
      px = cx + s * rng.range(3.2, 4.6);
      pz = z;
      py = y + 0.135;
    } else if (r < 0.78) {
      // caught along the crossing deck
      pz = rng.range(-2.4, 2.4);
      px = cx + rng.range(-3.1, 3.1);
      py = 0.32;
    } else {
      // thin scatter over the open road
      px = cx + rng.range(-3.0, 3.0);
      pz = z;
      py = y;
    }

    final yRot = rng.range(0, math.pi * 2);
    final s = rng.range(0.8, 1.25);
    // T * Ry * flatRotation * S
    final matrix = trs(px, py + 0.019, pz, 0, yRot, 0) *
        flatMat *
        trs(0, 0, 0, 0, 0, 0, s, 1, s);
    final toneIdx = rng.ints(0, 2);
    parts.add(Part(geo, matrix, _fallenMats[toneIdx]));
  }

  return bake(parts);
}

// ── Falling petals — initial placement only (buildPetals) ──────────────────

/// 980 petals at their initial scattered positions.  The reference runs 40
/// settle steps then animates per-frame; here we emit the first-frame
/// positions after the reference's 40 × 0.1 s zero-gust settle steps.
List<Tri> _buildFallingPetals({int groupCount = 1, int groupIndex = 0}) {
  const count = 980, top = 6.8, z0 = -30.0, z1 = 34.0, half = 9.5;
  final rng = RngKit(8123);
  final geo = _petalGeometry(0.185, 0.135);
  final counts = [
    (count * 0.55).round(),
    (count * 0.28).round(),
    count - (count * 0.55).round() - (count * 0.28).round(),
  ];
  final mats = [_petalMat, _blossomLightMat, _petalDeepMat];
  final petals = <_FallingPetal>[];

  // Generate the complete P array first. Respawn randomness during settling
  // starts only after all 980 initial records have consumed their RNG values.
  for (var group = 0; group < counts.length; group++) {
    for (var i = 0; i < counts[group]; i++) {
      petals.add(_FallingPetal(
        mat: mats[group],
        x: rng.range(-half, half),
        y: rng.range(0.2, top),
        z: rng.range(z0, z1),
        fall: rng.range(0.42, 0.86),
        swayAmp: rng.range(0.25, 0.75),
        swayFreq: rng.range(0.5, 1.35),
        phase: rng.range(0, 10),
        spin: Vector3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1))
          ..normalize(),
        spinRate: rng.range(0.5, 2.4),
        angle: rng.range(0, 6.28),
        scale: rng.range(0.78, 1.25),
        drift: rng.range(-0.16, 0.16),
      ));
    }
  }

  var time = 0.0;
  void update(double dt, double gust, double gustDir) {
    time += dt;
    final wind = gust * 5.4 * gustDir;
    final lift = gust * 1.5;
    for (final p in petals) {
      final s1 = math.sin(time * p.swayFreq + p.phase);
      final s2 = math.sin(time * p.swayFreq * 2.7 + p.phase * 1.7);
      p.y -= (p.fall + gust * .4) * dt;
      p.x += (p.swayAmp * s1 * .55 + p.drift + wind * .24) * dt;
      p.z += (p.swayAmp * s2 * .32 + wind * .05) * dt;
      p.y += lift * math.max(0, 1 - p.z.abs() / 8) * dt;
      p.angle += p.spinRate * dt * (1 + gust);
      final cx = centerX(p.z);
      if (p.x < cx - half) p.x = cx + half;
      if (p.x > cx + half) p.x = cx - half;
      if (p.z < z0) p.z = z1;
      if (p.z > z1) p.z = z0;
      if (p.y < groundY(p.z) + 0.04) {
        p.x = rng.range(-half, half);
        p.z = rng.range(z0, z1);
        p.y = top + rng.range(0, 1.4);
        p.phase = rng.range(0, 10);
      }
    }
  }

  for (var step = 0; step < 40; step++) {
    update(.1, 0, 1);
  }
  // The opening capture is taken after one nominal 60 Hz world update. The
  // train advances first, then its near-crossing gust updates the petals.
  const captureDt = 1 / 60;
  const trainSpeed = 23.5;
  final near = math.max(0, 1 - (trainSpeed * captureDt) / 46).toDouble();
  update(captureDt, near * near, 1);

  return bake([
    for (final indexed in petals.indexed)
      if (indexed.$1 % groupCount == groupIndex)
        Part(
          geo,
          composePRS(
              Vector3(indexed.$2.x, indexed.$2.y, indexed.$2.z),
              Quaternion.axisAngle(indexed.$2.spin, indexed.$2.angle),
              Vector3.all(indexed.$2.scale)),
          indexed.$2.mat,
        ),
  ]);
}

class _FallingPetal {
  _FallingPetal({
    required this.mat,
    required this.x,
    required this.y,
    required this.z,
    required this.fall,
    required this.swayAmp,
    required this.swayFreq,
    required this.phase,
    required this.spin,
    required this.spinRate,
    required this.angle,
    required this.scale,
    required this.drift,
  });
  final Mat mat;
  double x, y, z, phase, angle;
  final double fall, swayAmp, swayFreq, spinRate, scale, drift;
  final Vector3 spin;
}

/// Mutable port of `petals.js::buildPetals` for realtime hosts.
///
/// Geometry remains a single triangle soup; callers can upload [positions]
/// into its writable position buffer after each [update].
class FallingPetalSimulation {
  FallingPetalSimulation() : _rng = RngKit(8123) {
    const count = 980;
    final counts = [
      (count * .55).round(),
      (count * .28).round(),
      count - (count * .55).round() - (count * .28).round(),
    ];
    final mats = [_petalMat, _blossomLightMat, _petalDeepMat];
    for (var group = 0; group < counts.length; group++) {
      for (var i = 0; i < counts[group]; i++) {
        _petals.add(_FallingPetal(
          mat: mats[group],
          x: _rng.range(-_half, _half),
          y: _rng.range(.2, _top),
          z: _rng.range(_z0, _z1),
          fall: _rng.range(.42, .86),
          swayAmp: _rng.range(.25, .75),
          swayFreq: _rng.range(.5, 1.35),
          phase: _rng.range(0, 10),
          spin: Vector3(_rng.range(-1, 1), _rng.range(-1, 1), _rng.range(-1, 1))
            ..normalize(),
          spinRate: _rng.range(.5, 2.4),
          angle: _rng.range(0, 6.28),
          scale: _rng.range(.78, 1.25),
          drift: _rng.range(-.16, .16),
        ));
      }
    }
    for (var i = 0; i < 40; i++) {
      update(.1, 0, 1);
    }
  }

  static const _top = 6.8, _z0 = -30.0, _z1 = 34.0, _half = 9.5;
  final RngKit _rng;
  final List<_FallingPetal> _petals = [];
  final ThreeGeom _geometry = _petalGeometry(.185, .135);
  double _time = 0;

  void update(double dt, double gust, double gustDir) {
    _time += dt;
    final wind = gust * 5.4 * gustDir;
    final lift = gust * 1.5;
    for (final p in _petals) {
      final sway = math.sin(_time * p.swayFreq + p.phase);
      final flutter = math.sin(_time * p.swayFreq * 2.7 + p.phase * 1.7);
      p.y -= (p.fall + gust * .4) * dt;
      p.x += (p.swayAmp * sway * .55 + p.drift + wind * .24) * dt;
      p.z += (p.swayAmp * flutter * .32 + wind * .05) * dt;
      p.y += lift * math.max(0, 1 - p.z.abs() / 8) * dt;
      p.angle += p.spinRate * dt * (1 + gust);

      final cx = centerX(p.z);
      if (p.x < cx - _half) p.x = cx + _half;
      if (p.x > cx + _half) p.x = cx - _half;
      if (p.z < _z0) p.z = _z1;
      if (p.z > _z1) p.z = _z0;
      if (p.y < groundY(p.z) + .04) {
        p
          ..x = _rng.range(-_half, _half)
          ..z = _rng.range(_z0, _z1)
          ..y = _top + _rng.range(0, 1.4)
          ..phase = _rng.range(0, 10);
      }
    }
  }

  List<Tri> triangles() => bake([
        for (final p in _petals)
          Part(
            _geometry,
            composePRS(Vector3(p.x, p.y, p.z),
                Quaternion.axisAngle(p.spin, p.angle), Vector3.all(p.scale)),
            p.mat,
          ),
      ]);
}

// ── Public entry point ────────────────────────────────────────────────────

/// Build all blossom petals (fallen + falling initial placement).
///
/// **Fallen petals**: 620 quads lying flat on the street (gutters, pavement,
/// crossing deck, open road), port of `buildFallenPetals`.
///
/// **Falling petals**: 980 quads at the reference's settled first-frame pose.
///
/// **Deferred**: `buildFallenPatches` (takes dynamic patch data at runtime).
///
/// Tri count: 620 * 2 (fallen) + 980 * 2 (falling) = 3200 tris.
List<Tri> buildPetals({
  bool includeFallen = true,
  bool includeFalling = true,
}) {
  return [
    if (includeFallen) ..._buildFallenPetals(),
    if (includeFalling) ..._buildFallingPetals(),
  ];
}

/// A deterministic subset of the falling-petal cloud for runtime animation.
List<Tri> buildFallingPetalGroup(int groupIndex, {int groupCount = 8}) =>
    _buildFallingPetals(groupCount: groupCount, groupIndex: groupIndex);
