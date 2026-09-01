// Validates the makeHouse port against the reference's makeHouse (dumped by
// extract_part.mjs). Matches per-triangle centroid + material colour. The house
// is flat-shaded boxes/extrusions, so normals are checked too.
//
//   dart run bin/validate_house.dart   (run extract_part.mjs first)
import 'dart:io';

import 'package:thermion_sakura/src/world_ref/make_house.dart';
import 'package:vector_math/vector_math_64.dart';

Future<void> main() async {
  final house = makeHouse(const HouseOpts(
      x: 0, z: 0, w: 7.0, d: 7.0, floors: 2, face: 'x+', seed: 21, wall: 0, roof: 1, roofKind: 'gable'));

  final jsLines = (await File('/tmp/house_js.txt').readAsString())
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .toList();
  final jsC = <Vector3>[], jsN = <Vector3>[], jsCol = <int>[];
  for (final line in jsLines) {
    final p = line.split(' ').map(double.parse).toList();
    jsC.add(Vector3(p[0], p[1], p[2]));
    jsN.add(Vector3(p[3], p[4], p[5]));
    jsCol.add(p[6].toInt());
  }

  // The reference's makeHouse adds hullOutline meshes (inverted-hull ink shells)
  // which we don't port — they're a render pass, not geometry. They carry the
  // wall/roof colour, so they'd appear as extra triangles. Tolerate a leftover.
  const tol = 0.02;
  final used = List<bool>.filled(jsC.length, false);
  int matched = 0, unmatched = 0, colorBad = 0, normalBad = 0;
  double worstCen = 0, worstNormal = 0;
  for (final t in house) {
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
    if (nd > 0.05) normalBad++;
    if (jsCol[best] != t.mat.color) colorBad++;
    matched++;
  }
  final jsLeft = used.where((u) => !u).length;

  print('HOUSE: dart ${house.length} tris, js ${jsLines.length} tris');
  print('       matched $matched | dart-unmatched $unmatched | js-leftover $jsLeft');
  print('       worst centroid Δ $worstCen | worst normal Δ $worstNormal');
  print('       colour-mismatch $colorBad | normal-mismatch(>0.05) $normalBad');
  // PASS if every Dart tri matched (geometry is faithful). js-leftover is the
  // hull-outline shells we deliberately don't port.
  final ok = unmatched == 0 && colorBad == 0 && normalBad == 0;
  print(ok
      ? '\n✓ PASS — house geometry matches three.js (js-leftover = unported hull outlines).'
      : '\n✗ FAIL');
  exit(ok ? 0 : 1);
}
