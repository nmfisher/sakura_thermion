// Validates the geometry substrate + the makePole port against the reference's
// own output (dumped by `tool/extract_part.mjs`):
//   1. mulberry32(42) sequence matches the JS rng dump.
//   2. makePole(...) triangle set matches the JS pole dump (per-triangle centroid,
//      face normal, material colour).
//
//   dart run bin/validate_pole.dart
// (run `node tool/extract_part.mjs` first to produce /tmp/pole_js.txt + /tmp/rng_js.txt)
import 'dart:io';

import 'package:thermion_sakura/src/geom/three_geom.dart';
import 'package:thermion_sakura/src/world_ref/make_pole.dart';
import 'package:vector_math/vector_math_64.dart';

Future<void> main() async {
  // ── 1. RNG determinism ────────────────────────────────────────────────────
  final jsRng = (await File('/tmp/rng_js.txt').readAsString())
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .map(double.parse)
      .toList();
  final r = mulberry32(42);
  int rngBad = 0;
  double maxDrift = 0;
  for (final expected in jsRng) {
    final got = r();
    final d = (got - expected).abs();
    if (d > 1e-9) rngBad++;
    if (d > maxDrift) maxDrift = d;
  }
  print('RNG  : ${jsRng.length - rngBad}/${jsRng.length} match '
      '(${rngBad} differ, max drift $maxDrift)');

  // ── 2. makePole geometry ──────────────────────────────────────────────────
  final pole = makePole(const PoleOpts(
      seed: 11, h: 9.2, x: 5, y: 0, z: -3, lamp: true, transformer: true, armDir: 1));

  final jsLines = (await File('/tmp/pole_js.txt').readAsString())
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .toList();
  // JS triangles as (centroid, normal, colour).
  final jsC = <Vector3>[], jsN = <Vector3>[], jsCol = <int>[];
  for (final line in jsLines) {
    final p = line.split(' ').map(double.parse).toList();
    jsC.add(Vector3(p[0], p[1], p[2]));
    jsN.add(Vector3(p[3], p[4], p[5]));
    jsCol.add(p[6].toInt());
  }

  // Nearest-unused-neighbour match (tolerant of float rounding at key boundaries).
  const tol = 0.01; // 1 cm — the geometry is micron-close, so this only catches round-off
  final used = List<bool>.filled(jsC.length, false);
  int matched = 0, unmatched = 0, colorBad = 0, normalBad = 0;
  double worstCen = 0, worstNormal = 0;
  for (final t in pole) {
    final cen = t.centroid;
    int best = -1;
    double bd = tol;
    for (int i = 0; i < jsC.length; i++) {
      if (used[i]) continue;
      final d = (jsC[i] - cen).length;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best < 0) {
      unmatched++;
      continue;
    }
    used[best] = true;
    if (bd > worstCen) worstCen = bd;
    final nd = (jsN[best] - t.normal).length;
    if (nd > worstNormal) worstNormal = nd;
    if (nd > 0.01) normalBad++;
    if (jsCol[best] != t.mat.color) colorBad++;
    matched++;
  }
  final jsLeft = used.where((u) => !u).length;

  print('POLE : dart ${pole.length} tris, js ${jsLines.length} tris');
  print('       matched $matched | dart-unmatched $unmatched | js-leftover $jsLeft');
  print('       worst centroid Δ $worstCen, worst normal Δ $worstNormal');
  print('       colour-mismatch $colorBad, normal-mismatch(>0.01) $normalBad');

  final ok = rngBad == 0 &&
      unmatched == 0 &&
      jsLeft == 0 &&
      colorBad == 0 &&
      normalBad == 0;
  print(ok ? '\n✓ PASS — substrate + makePole match three.js exactly.' : '\n✗ FAIL');
  exit(ok ? 0 : 1);
}
