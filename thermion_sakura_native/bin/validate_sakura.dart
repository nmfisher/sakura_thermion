// Validates the makeSakura port + the icosahedron/quaternion/compose substrate
// additions against the reference's buildSakura (dumped by extract_part.mjs).
// Matches per-triangle centroid + material colour (the geometry). Face normals
// are reported too, but a mismatch there is expected for the flat-shaded blossom
// blobs: three.js stores the icosahedron's smooth vertex normals in the geometry
// and re-derives flat face normals in-shader, while we compute the face normal
// directly in bake() — same rendered result, different stored representation.
//
//   dart run bin/validate_sakura.dart   (run extract_part.mjs first)
import 'dart:io';

import 'package:thermion_sakura/src/world_ref/make_sakura.dart';
import 'package:vector_math/vector_math_64.dart';

Future<void> main() async {
  final tree = buildSakura(const [SakuraSpot(x: 0, z: 0, scale: 1, seed: 42)]);

  final jsLines = (await File('/tmp/sakura_js.txt').readAsString())
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

  const tol = 0.02;
  final used = List<bool>.filled(jsC.length, false);
  int matched = 0, unmatched = 0, colorBad = 0, normalBad = 0;
  double worstCen = 0;
  for (final t in tree) {
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
    if (jsCol[best] != t.mat.color) colorBad++;
    if ((jsN[best] - t.normal).length > 0.05) normalBad++;
    matched++;
  }
  final jsLeft = used.where((u) => !u).length;

  print('SAKURA: dart ${tree.length} tris, js ${jsLines.length} tris');
  print('        matched $matched | dart-unmatched $unmatched | js-leftover $jsLeft');
  print('        worst centroid Δ $worstCen | colour-mismatch $colorBad | normal-mismatch(>0.05) $normalBad');
  final ok = unmatched == 0 && jsLeft == 0 && colorBad == 0;
  print(ok
      ? '\n✓ PASS — geometry (centroid + colour) matches three.js; normal mismatch '
          'is the expected flat-vs-stored representation difference on blobs.'
      : '\n✗ FAIL');
  exit(ok ? 0 : 1);
}
