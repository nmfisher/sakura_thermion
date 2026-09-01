import 'dart:convert';
import 'dart:io';

import 'package:thermion_sakura_dart/src/geom/three_geom.dart';

void main() {
  final geometry = icosahedronGeometry(1, 1);
  final positions = <double>[];
  for (final index in geometry.indices) {
    positions.addAll([
      geometry.positions[index * 3],
      geometry.positions[index * 3 + 1],
      geometry.positions[index * 3 + 2],
    ]);
  }
  File('/tmp/sakura-object-parity/dart-ico.json').writeAsStringSync(jsonEncode({
    'count': positions.length ~/ 3,
    'positions': positions,
  }));
}
