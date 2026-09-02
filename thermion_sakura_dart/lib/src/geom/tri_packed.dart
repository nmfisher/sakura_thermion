/// Convert a ported module's triangle soup (`List<Tri>` from the geometry
/// substrate) into the packed per-vertex format the realtime toon material
/// (`sakura_toon_rt.mat`) consumes — the same shape `refGeoToPacked` produces
/// from the extracted `.bin`. This is the bridge that lets ported world modules
/// render through the same realtime cel + CPU sun-shadow path.
library;

import 'dart:typed_data';

import '../palette.dart';
import '../ref_geo.dart' show PackedGeo, SunShadowMap;
import 'three_geom.dart';

int _rampIdFor(String bands) {
  switch (bands) {
    case 'soft':
      return 1;
    case '2':
      return 2;
    case '4':
      return 3;
    case '5':
      return 4;
    case 'soft3':
      return 5;
    case '3':
    default:
      return 0;
  }
}

/// Pack [tris] for the realtime toon material. [shadow] decides per-face cast
/// shadows via face centroid; soft-ramp mats (blossoms) and unlit mats don't
/// receive shadows, matching the reference (`receiveShadow=false` on canopies).
/// COLOR0.a packs face state and ramp id into an exact small integer. A
/// negative sign carries the source `noOutline` marker. UV1 remains available
/// for atlas coordinates; hand-authored geometry leaves it at zero.
PackedGeo trisToPacked(List<Tri> tris, {SunShadowMap? shadow}) {
  final n = tris.length * 3;
  final positions = Float32List(n * 3);
  final normals = Float32List(n * 3);
  final colors = Float32List(n * 4);
  final uvs = Float32List(n * 2);
  final uvs1 = Float32List(n * 2);
  final attribute0 = Float32List(n * 4);
  int vi = 0;
  for (final t in tris) {
    final mat = t.mat;
    final mapped = t.mapped;
    final receivesShadow =
        !mat.unlit && mat.bands != 'soft' && mat.receiveShadow;
    final inShadow =
        shadow != null && receivesShadow && shadow.shadowed(t.centroid);
    // 0.75 marks foliage that casts but deliberately does not receive the
    // directional shadow (matching trees.js).  Keeping this separate from the
    // unlit flag lets the fragment shader retain normal cel lighting.
    final stateCode = mat.unlit
        ? 3
        : !receivesShadow
            ? 2
            : (inShadow ? 1 : 0);
    final lin = C.lin(mat.color);
    final tint = C.lin(mat.tint);
    final rid = _rampIdFor(mat.bands).toDouble();
    final vertices = [t.a, t.b, t.c];
    final atlasUvs = [t.uvA, t.uvB, t.uvC];
    for (var vertex = 0; vertex < 3; vertex++) {
      final v = vertices[vertex];
      positions[vi * 3] = v.x;
      positions[vi * 3 + 1] = v.y;
      positions[vi * 3 + 2] = v.z;
      normals[vi * 3] = t.normal.x;
      normals[vi * 3 + 1] = t.normal.y;
      normals[vi * 3 + 2] = t.normal.z;
      uvs[vi * 2] = 0.0;
      uvs[vi * 2 + 1] = 0.0;
      uvs1[vi * 2] = mapped ? atlasUvs[vertex]!.x : 0.0;
      uvs1[vi * 2 + 1] = mapped ? atlasUvs[vertex]!.y : 0.0;
      colors[vi * 4] = lin.x;
      colors[vi * 4 + 1] = lin.y;
      colors[vi * 4 + 2] = lin.z;
      final metadata = 1.0 + stateCode + 4.0 * rid + (mapped ? 28.0 : 0.0);
      colors[vi * 4 + 3] = mat.noOutline ? -metadata : metadata;
      attribute0[vi * 4] = tint.x;
      attribute0[vi * 4 + 1] = tint.y;
      attribute0[vi * 4 + 2] = tint.z;
      attribute0[vi * 4 + 3] = mat.glaze;
      vi++;
    }
  }
  return PackedGeo(positions, normals, colors, uvs, uvs1, attribute0,
      List<int>.generate(n, (i) => i));
}
