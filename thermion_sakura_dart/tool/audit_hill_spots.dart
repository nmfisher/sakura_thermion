import 'dart:convert';
import 'dart:io';

import 'package:thermion_sakura_dart/src/world_ref/hills.dart';
import 'package:thermion_sakura_dart/src/world_ref/make_sakura.dart';
import 'package:thermion_sakura_dart/src/world_ref/make_trees_other.dart';

void main() {
  final sakura = <SakuraSpot>[];
  final grove = <GroveSpot>[];
  buildHillRangePlanting(auditSakura: sakura, auditGrove: grove);
  Map<String, Object?> cherry(SakuraSpot s) => {
        'x': s.x,
        'z': s.z,
        'y': s.y,
        'scale': s.scale,
        'seed': s.seed,
        'lean': s.lean,
        'leanDir': s.leanDir,
      };
  Map<String, Object?> tree(GroveSpot s) => {
        'x': s.x,
        'z': s.z,
        'y': s.y,
        'scale': s.scale,
        'seed': s.seed,
        'spread': s.spread,
        'lean': s.lean,
        'leanDir': s.leanDir,
        if (s.willow) 'willow': true,
      };
  File('/tmp/sakura-geometry/thermion-hill-planting.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'sakura': sakura.map(cherry).toList(),
    'grove': grove.map(tree).toList(),
  }));
  print('WROTE ${sakura.length} sakura, ${grove.length} grove');
}
