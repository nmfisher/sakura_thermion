// Validates the batch-ported modules (railway/train/shop) against the reference
// dumps (extract_part.mjs). Per-triangle centroid + colour match; tolerates
// unported hull-outline shells (a render pass, not geometry).
//
//   dart run bin/validate_modules.dart   (run extract_part.mjs first)
import 'dart:io';

import 'package:thermion_sakura/src/world_ref/railway.dart';
import 'package:thermion_sakura/src/world_ref/train.dart';
import 'package:thermion_sakura/src/world_ref/shop.dart';
import 'package:vector_math/vector_math_64.dart';

Future<void> _validate(String name, dynamic dartTris, String jsPath) async {
  final jsLines = (await File(jsPath).readAsString())
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .toList();
  final jsC = <Vector3>[], jsCol = <int>[];
  for (final line in jsLines) {
    final p = line.split(' ').map(double.parse).toList();
    jsC.add(Vector3(p[0], p[1], p[2]));
    jsCol.add(p[6].toInt());
  }
  final dart = dartTris as List;
  const tol = 0.02;
  final used = List<bool>.filled(jsC.length, false);
  int matched = 0, unmatched = 0, colorBad = 0;
  for (final t in dart) {
    final cen =
        ((t.a as Vector3) + (t.b as Vector3) + (t.c as Vector3)) * (1 / 3);
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
    if (jsCol[best] != (t.mat.color as int)) colorBad++;
    matched++;
  }
  final jsLeft = used.where((u) => !u).length;
  final ok = unmatched == 0 && colorBad == 0;
  print(
      '$name: dart ${dart.length} | js ${jsLines.length} | matched $matched | '
      'dart-unmatched $unmatched | js-leftover $jsLeft | colour-mismatch $colorBad -> ${ok ? "✓" : "✗"}');
}

Future<void> main(List<String> args) async {
  final selected = args.map((arg) => arg.toLowerCase()).toSet();
  final all = selected.isEmpty;
  if (all || selected.contains('railway')) {
    await _validate('RAILWAY', buildRailway(), '/tmp/railway_js.txt');
  }
  if (all || selected.contains('train')) {
    await _validate('TRAIN', buildTrain(), '/tmp/train_js.txt');
  }
  if (all || selected.contains('shop')) {
    await _validate('SHOP', buildShop(), '/tmp/shop_js.txt');
  }
  exit(0);
}
