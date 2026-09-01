import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

/// Decodes the compact, source-extracted triangle format emitted by
/// `tool/extract_flat_object_geometry.mjs`.
List<Tri> decodeSourceGeometry(String encoded) {
  final bytes = Uint8List.fromList(zlib.decode(base64Decode(encoded)));
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  final materialCount = data.getUint32(offset, Endian.little);
  offset += 4;
  final materials = <Mat>[];
  for (var i = 0; i < materialCount; i++) {
    final color = data.getUint32(offset, Endian.little);
    final tint = data.getUint32(offset + 4, Endian.little);
    final bandCount = data.getUint8(offset + 8);
    final flags = data.getUint8(offset + 9);
    final unlit = (flags & 1) != 0;
    materials.add(Mat(color,
        tint: tint == 0 ? 0x6c5f8c : tint,
        bands: bandCount == 2 ? 'soft' : '$bandCount',
        unlit: unlit,
        noOutline: (flags & 2) != 0));
    offset += 12;
  }
  final triangleCount = data.getUint32(offset, Endian.little);
  offset += 4;
  final triangles = <Tri>[];
  Vector3 vertex(int at) => Vector3(
      data.getFloat32(at, Endian.little),
      data.getFloat32(at + 4, Endian.little),
      data.getFloat32(at + 8, Endian.little));
  for (var i = 0; i < triangleCount; i++) {
    final a = vertex(offset);
    final b = vertex(offset + 12);
    final c = vertex(offset + 24);
    final material = materials[data.getUint16(offset + 36, Endian.little)];
    var normal = (b - a).cross(c - a);
    normal = normal.length2 < 1e-12 ? Vector3(0, 1, 0) : normal.normalized();
    triangles.add(Tri(a, b, c, normal, material));
    offset += 40;
  }
  return triangles;
}
