/// Minimal glTF 2.0 binary (GLB) encoder.
///
/// The Thermion web build renders glTF via gltfio but renders nothing for the
/// custom `createGeometry` path, so the world is packed into a single GLB
/// buffer and loaded with `loadGltfFromBuffer`. One unlit material with vertex
/// colours carries the whole cel-baked world.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'mesh.dart';

class _Accessor {
  _Accessor({
    required this.bufferView,
    required this.componentType,
    required this.count,
    required this.type,
    required this.byteOffset,
    this.min,
    this.max,
  });
  final int bufferView;
  final int componentType; // 5126 float, 5123 ushort, 5125 uint
  final int count;
  final String type; // SCALAR, VEC3, VEC4
  final int byteOffset;
  final List<double>? min;
  final List<double>? max;
}

/// Encode a [Mesh] (and any extra raw-colour quads) into GLB bytes.
///
/// The mesh's per-vertex colours are already display-space sRGB (baked cel);
/// they are written into a FLOAT VEC4 COLOR_0 accessor. Positions/normals are
/// FLOAT VEC3, indices are UINT. The single material is unlit + double-sided
/// with a white base colour factor, so the displayed colour is the vertex
/// colour unchanged.
Uint8List meshToGlb(Mesh m) {
  final positions = m.positions;
  final normals = m.normals;
  final colors = m.colors;
  final indices = m.indices;

  final posBytes = Float32List.fromList(positions).buffer.asUint8List();
  final nrmBytes = Float32List.fromList(normals).buffer.asUint8List();
  final colBytes = Float32List.fromList(colors).buffer.asUint8List();
  final idxBytes = Uint32List.fromList(indices).buffer.asUint8List();

  // Buffer views, 4-byte aligned (all accessors are FLOAT or UINT).
  int offset = 0;
  final views = <Map<String, dynamic>>[];
  final addView = (Uint8List bytes) {
    final o = offset;
    views.add({
      'buffer': 0,
      'byteOffset': o,
      'byteLength': bytes.length,
      'target': o == 0 ? 34962 : null, // ARRAY_BUFFER for the first
    });
    // null target entries are dropped below; index buffer gets ELEMENT_ARRAY
    offset += bytes.length;
    return o;
  };
  addView(posBytes);
  addView(nrmBytes);
  addView(colBytes);
  addView(idxBytes);
  // The index view must be ELEMENT_ARRAY_BUFFER (34963).
  views[3]['target'] = 34963;

  final posMin = <double>[1e30, 1e30, 1e30];
  final posMax = <double>[-1e30, -1e30, -1e30];
  for (var i = 0; i < positions.length; i += 3) {
    for (var c = 0; c < 3; c++) {
      final v = positions[i + c];
      if (v < posMin[c]) posMin[c] = v;
      if (v > posMax[c]) posMax[c] = v;
    }
  }

  final accessors = <_Accessor>[
    _Accessor(
      bufferView: 0, componentType: 5126, count: m.vertexCount,
      type: 'VEC3', byteOffset: 0, min: posMin, max: posMax,
    ),
    _Accessor(
      bufferView: 1, componentType: 5126, count: m.vertexCount,
      type: 'VEC3', byteOffset: 0,
    ),
    _Accessor(
      bufferView: 2, componentType: 5126, count: m.vertexCount,
      type: 'VEC4', byteOffset: 0,
    ),
    _Accessor(
      bufferView: 3, componentType: 5125, count: m.indexCount,
      type: 'SCALAR', byteOffset: 0,
    ),
  ];

  final json = {
    'asset': {'version': '2.0', 'generator': 'thermion_sakura'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]}
    ],
    'nodes': [
      {'mesh': 0}
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'NORMAL': 1,
              'COLOR_0': 2,
            },
            'indices': 3,
            'material': 0,
            'mode': 4, // TRIANGLES
          }
        ]
      }
    ],
    'materials': [
      {
        'name': 'SakuraCel',
        'doubleSided': true,
        'pbrMetallicRoughness': {
          'baseColorFactor': [1, 1, 1, 1],
          'metallicFactor': 0.0,
          'roughnessFactor': 1.0,
        },
        'extensions': {'KHR_materials_unlit': {}},
      }
    ],
    'buffers': [
      {'byteLength': offset}
    ],
    'bufferViews': views.map((v) {
      // drop null targets
      final c = Map<String, dynamic>.from(v);
      if (c['target'] == null) c.remove('target');
      return c;
    }).toList(),
    'accessors': accessors.map((a) {
      final m = <String, dynamic>{
        'bufferView': a.bufferView,
        'componentType': a.componentType,
        'count': a.count,
        'type': a.type,
        'byteOffset': a.byteOffset,
      };
      if (a.min != null) m['min'] = a.min;
      if (a.max != null) m['max'] = a.max;
      return m;
    }).toList(),
  };

  final jsonBytes = utf8.encode(jsonEncode(json));
  // JSON chunk must be padded to 4 bytes with spaces.
  final jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  final bin = BytesBuilder()
    ..add(posBytes)
    ..add(nrmBytes)
    ..add(colBytes)
    ..add(idxBytes);
  final binBytes = bin.takeBytes();
  final binPad = (4 - (binBytes.length % 4)) % 4;

  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + binBytes.length + binPad;
  final out = BytesBuilder();
  // header
  out.add(_u32(0x46546C67)); // glTF
  out.add(_u32(2));
  out.add(_u32(total));
  // JSON chunk
  out.add(_u32(jsonBytes.length + jsonPad));
  out.add(_u32(0x4E4F534A)); // JSON
  out.add(jsonBytes);
  out.add(Uint8List(jsonPad));
  // BIN chunk
  out.add(_u32(binBytes.length + binPad));
  out.add(_u32(0x004E4942)); // BIN
  out.add(binBytes);
  out.add(Uint8List(binPad));

  final result = out.takeBytes();
  assert(result.length == total);
  return result;
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

/// Encode raw geometry with per-vertex base+UV0+UV1 for the toon material.
/// The GLB's vertex-color material is overridden at runtime via
/// asset.setMaterialInstanceForAll(toonMat).
Uint8List rawToGlbToon(Float32List positions, Float32List normals,
    Float32List colors, Float32List uv0, Float32List uv1) {
  final posBytes = positions.buffer.asUint8List(positions.offsetInBytes, positions.length * 4);
  final nrmBytes = normals.buffer.asUint8List(normals.offsetInBytes, normals.length * 4);
  final colBytes = colors.buffer.asUint8List(colors.offsetInBytes, colors.length * 4);
  final uv0Bytes = uv0.buffer.asUint8List(uv0.offsetInBytes, uv0.length * 4);
  final uv1Bytes = uv1.buffer.asUint8List(uv1.offsetInBytes, uv1.length * 4);
  final vc = positions.length ~/ 3;

  int offset = 0;
  final views = <Map<String, dynamic>>[];
  for (final b in [posBytes, nrmBytes, colBytes, uv0Bytes, uv1Bytes]) {
    views.add({'buffer': 0, 'byteOffset': offset, 'byteLength': b.length, 'target': 34962});
    offset += b.length;
  }

  final posMin = <double>[1e30, 1e30, 1e30];
  final posMax = <double>[-1e30, -1e30, -1e30];
  for (var i = 0; i < positions.length; i += 3) {
    for (var c = 0; c < 3; c++) {
      if (positions[i + c] < posMin[c]) posMin[c] = positions[i + c];
      if (positions[i + c] > posMax[c]) posMax[c] = positions[i + c];
    }
  }

  final json = {
    'asset': {'version': '2.0', 'generator': 'thermion_sakura'},
    'scene': 0,
    'scenes': [{'nodes': [0]}],
    'nodes': [{'mesh': 0}],
    'meshes': [{'primitives': [{'attributes': {
      'POSITION': 0, 'NORMAL': 1, 'COLOR_0': 2, 'TEXCOORD_0': 3, 'TEXCOORD_1': 4,
    }, 'material': 0, 'mode': 4}]}],
    'materials': [{
      'name': 'SakuraToon', 'doubleSided': true,
      'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0.0, 'roughnessFactor': 1.0},
      'extensions': {'KHR_materials_unlit': {}},
    }],
    'buffers': [{'byteLength': offset}],
    'bufferViews': views,
    'accessors': [
      {'bufferView': 0, 'componentType': 5126, 'count': vc, 'type': 'VEC3', 'min': posMin, 'max': posMax},
      {'bufferView': 1, 'componentType': 5126, 'count': vc, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5126, 'count': vc, 'type': 'VEC4'},
      {'bufferView': 3, 'componentType': 5126, 'count': vc, 'type': 'VEC2'},
      {'bufferView': 4, 'componentType': 5126, 'count': vc, 'type': 'VEC2'},
    ],
  };

  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  final binBytes = (BytesBuilder()
        ..add(posBytes)..add(nrmBytes)..add(colBytes)..add(uv0Bytes)..add(uv1Bytes))
      .takeBytes();
  final binPad = (4 - (binBytes.length % 4)) % 4;
  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + binBytes.length + binPad;
  final out = BytesBuilder()
    ..add(_u32(0x46546C67))..add(_u32(2))..add(_u32(total))
    ..add(_u32(jsonBytes.length + jsonPad))..add(_u32(0x4E4F534A))..add(jsonBytes)..add(Uint8List(jsonPad))
    ..add(_u32(binBytes.length + binPad))..add(_u32(0x004E4942))..add(binBytes)..add(Uint8List(binPad));
  return out.takeBytes();
}

/// Encode raw position/normal/colour buffers (non-indexed triangle list) into a
/// GLB. Used for the ported reference geometry, which arrives as a flat triangle
/// list with cel-baked colours.
Uint8List rawToGlb(Float32List positions, Float32List normals, Float32List colors) {
  final posBytes = positions.buffer.asUint8List(positions.offsetInBytes, positions.length * 4);
  final nrmBytes = normals.buffer.asUint8List(normals.offsetInBytes, normals.length * 4);
  final colBytes = colors.buffer.asUint8List(colors.offsetInBytes, colors.length * 4);
  final vertCount = positions.length ~/ 3;

  int offset = 0;
  final views = <Map<String, dynamic>>[];
  final addView = (Uint8List bytes) {
    final o = offset;
    views.add({'buffer': 0, 'byteOffset': o, 'byteLength': bytes.length});
    offset += bytes.length;
    return o;
  };
  addView(posBytes);
  addView(nrmBytes);
  addView(colBytes);

  final posMin = <double>[1e30, 1e30, 1e30];
  final posMax = <double>[-1e30, -1e30, -1e30];
  for (var i = 0; i < positions.length; i += 3) {
    for (var c = 0; c < 3; c++) {
      final v = positions[i + c];
      if (v < posMin[c]) posMin[c] = v;
      if (v > posMax[c]) posMax[c] = v;
    }
  }

  final json = {
    'asset': {'version': '2.0', 'generator': 'thermion_sakura'},
    'scene': 0,
    'scenes': [{'nodes': [0]}],
    'nodes': [{'mesh': 0}],
    'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'COLOR_0': 2}, 'material': 0, 'mode': 4}]}],
    'materials': [{
      'name': 'SakuraCel', 'doubleSided': true,
      'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0.0, 'roughnessFactor': 1.0},
      'extensions': {'KHR_materials_unlit': {}},
    }],
    'buffers': [{'byteLength': offset}],
    'bufferViews': views,
    'accessors': [
      {'bufferView': 0, 'componentType': 5126, 'count': vertCount, 'type': 'VEC3', 'min': posMin, 'max': posMax},
      {'bufferView': 1, 'componentType': 5126, 'count': vertCount, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5126, 'count': vertCount, 'type': 'VEC4'},
    ],
  };

  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  final binBytes = (BytesBuilder()
        ..add(posBytes)
        ..add(nrmBytes)
        ..add(colBytes))
      .takeBytes();
  final binPad = (4 - (binBytes.length % 4)) % 4;
  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + binBytes.length + binPad;
  final out = BytesBuilder()
    ..add(_u32(0x46546C67))..add(_u32(2))..add(_u32(total))
    ..add(_u32(jsonBytes.length + jsonPad))..add(_u32(0x4E4F534A))..add(jsonBytes)..add(Uint8List(jsonPad))
    ..add(_u32(binBytes.length + binPad))..add(_u32(0x004E4942))..add(binBytes)..add(Uint8List(binPad));
  return out.takeBytes();
}
