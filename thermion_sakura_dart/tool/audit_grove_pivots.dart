import 'dart:convert';
import 'dart:io';

import 'package:thermion_sakura_dart/src/world_ref/make_trees_other.dart';
import 'package:thermion_sakura_dart/src/world_ref/street.dart' show groundY;
import 'package:vector_math/vector_math_64.dart';

void main() {
  final rows = <Map<String, num>>[];
  buildGrove([
    GroveSpot(
        x: -20.8,
        z: 43.2,
        y: groundY(43.2),
        scale: 2.5,
        seed: 801,
        spread: 1.35,
        lean: .05,
        leanDir: 2.0),
    GroveSpot(
        x: -26.6,
        z: 45.8,
        y: groundY(45.8),
        scale: 1.9,
        seed: 802,
        spread: 1.2),
    GroveSpot(
        x: -31.4,
        z: 42.6,
        y: groundY(42.6),
        scale: 1.6,
        seed: 803,
        spread: 1.15),
    GroveSpot(
        x: -36.6,
        z: 42.0,
        y: groundY(42.0),
        scale: 1.45,
        seed: 804,
        spread: 1.1),
    GroveSpot(
        x: -39.6,
        z: 46.6,
        y: groundY(46.6),
        scale: 1.8,
        seed: 806,
        spread: 1.2),
    for (var i = 0; i < 5; i++)
      GroveSpot(
          x: -49.4 - (i % 2) * 2.2,
          z: 43.0 + i * 3.6,
          y: .4,
          scale: 1.45 + (i % 3) * .15,
          seed: 9810 + i,
          spread: 1.15,
          lean: .06,
          leanDir: i * 1.3),
    for (var i = 0; i < 4; i++)
      GroveSpot(
          x: -15.2 + (i % 2) * 2.4,
          z: 52.0 + i * 3.4,
          y: .45,
          scale: 1.35 + (i % 2) * .2,
          seed: 9830 + i,
          spread: 1.1),
  ], (matrix, tone) {
    final p = Vector3.zero(), q = Quaternion.identity(), s = Vector3.zero();
    matrix.decompose(p, q, s);
    rows.add({
      'tone': tone,
      'x': p.x,
      'y': p.y,
      'z': p.z,
      'sx': s.x,
      'sy': s.y,
      'sz': s.z,
      'qx': q.x,
      'qy': q.y,
      'qz': q.z,
      'qw': q.w,
    });
  });
  File('/tmp/sakura-object-parity/thermion-onsen-grove.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  print(
      'WROTE /tmp/sakura-object-parity/thermion-onsen-grove.json (${rows.length} instances)');
}
