/// Loader for reference scene geometry extracted from the headless reference
/// build (see /tmp/cap/extract_geo.js). Parses the binary (materials + meshes),
/// re-applies the matching cel shading per material, and packs the whole world
/// into one GLB.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'cel.dart';
import 'glb.dart';
import 'palette.dart';

class _RMat {
  _RMat(this.color, this.tint, this.ramp, this.flags);
  final int color, tint, flags;
  final List<double> ramp;
  bool get unlit => (flags & 1) != 0;
  bool get smooth => (flags & 2) != 0;
}

const int _refGeoV2Magic = 0x53414b32;
const int _refGeoV3Magic = 0x53414b33;

/// Metadata embedded in a frozen reference-scene geometry artifact.
class ReferenceGeoInfo {
  const ReferenceGeoInfo(
      {required this.version,
      required this.atlasWidth,
      required this.atlasHeight});

  final int version;
  final int atlasWidth;
  final int atlasHeight;
  bool get hasAtlas => atlasWidth > 0 && atlasHeight > 0;
}

class _RefHeader {
  const _RefHeader(this.info, this.materialCount, this.materialOffset,
      this.vertexStride, this.meshHeaderStride);
  final ReferenceGeoInfo info;
  final int materialCount, materialOffset, vertexStride, meshHeaderStride;
}

_RefHeader _readRefHeader(Uint8List bytes) {
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
  final first = bd.getUint32(0, Endian.little);
  if (first == _refGeoV3Magic) {
    return _RefHeader(
        ReferenceGeoInfo(
            version: 3,
            atlasWidth: bd.getUint32(4, Endian.little),
            atlasHeight: bd.getUint32(8, Endian.little)),
        bd.getUint32(12, Endian.little),
        16,
        48,
        12);
  }
  if (first == _refGeoV2Magic) {
    return _RefHeader(
        ReferenceGeoInfo(
            version: 2,
            atlasWidth: bd.getUint32(4, Endian.little),
            atlasHeight: bd.getUint32(8, Endian.little)),
        bd.getUint32(12, Endian.little),
        16,
        32,
        8);
  }
  return _RefHeader(
      const ReferenceGeoInfo(version: 1, atlasWidth: 0, atlasHeight: 0),
      first,
      4,
      24,
      8);
}

ReferenceGeoInfo refGeoInfo(Uint8List bytes) => _readRefHeader(bytes).info;

/// A 2D sun shadow map: project all geometry onto the plane perpendicular to
/// the sun direction and keep, per cell, the geometry closest to the sun. A
/// point is shadowed if something closer to the sun projects to the same cell.
/// This is the directional-light shadow map, cheap enough for millions of
/// vertices (one pass to build, one lookup per face).
class SunShadowMap {
  SunShadowMap(Float32List positions, Vector3 sunDir,
      {this.cell = 1.0, this.bias = 6.0}) {
    final up = Vector3(0, 1, 0);
    final r = sunDir.cross(up)..normalize();
    if (r.length2 < 1e-6) r.setValues(1, 0, 0);
    _right = r;
    _up = r.cross(sunDir)..normalize();
    _sun = sunDir;
    // bounds in (u,v)
    double u0 = 1e30, u1 = -1e30, v0 = 1e30, v1 = -1e30;
    for (int i = 0; i < positions.length; i += 3) {
      final px = positions[i], py = positions[i + 1], pz = positions[i + 2];
      if (px.isNaN ||
          py.isNaN ||
          pz.isNaN ||
          px.isInfinite ||
          py.isInfinite ||
          pz.isInfinite) {
        continue;
      }
      final u = px * _right.x + py * _right.y + pz * _right.z;
      final v = px * _up.x + py * _up.y + pz * _up.z;
      if (u < u0) u0 = u;
      if (u > u1) u1 = u;
      if (v < v0) v0 = v;
      if (v > v1) v1 = v;
    }
    _u0 = u0 - cell;
    _v0 = v0 - cell;
    _nu = ((u1 - u0 + 2 * cell) / cell).ceil();
    _nv = ((v1 - v0 + 2 * cell) / cell).ceil();
    _depth = List<double>.filled(_nu * _nv, -1e30);
    for (int i = 0; i < positions.length; i += 3) {
      final px = positions[i], py = positions[i + 1], pz = positions[i + 2];
      if (px.isNaN ||
          py.isNaN ||
          pz.isNaN ||
          px.isInfinite ||
          py.isInfinite ||
          pz.isInfinite) {
        continue;
      }
      final u = px * _right.x + py * _right.y + pz * _right.z;
      final v = px * _up.x + py * _up.y + pz * _up.z;
      final d = px * _sun.x + py * _sun.y + pz * _sun.z;
      final iu = ((u - _u0) / cell).floor();
      final iv = ((v - _v0) / cell).floor();
      if (iu < 0 || iv < 0 || iu >= _nu || iv >= _nv) continue;
      final k = iv * _nu + iu;
      if (d > _depth[k]) _depth[k] = d;
    }
  }
  final double cell, bias;
  late final Vector3 _right, _up, _sun;
  late final double _u0, _v0;
  late final int _nu, _nv;
  late final List<double> _depth;

  bool shadowed(Vector3 p) {
    if (p.x.isNaN ||
        p.y.isNaN ||
        p.z.isNaN ||
        p.x.isInfinite ||
        p.y.isInfinite ||
        p.z.isInfinite) {
      return false;
    }
    final u = p.x * _right.x + p.y * _right.y + p.z * _right.z;
    final v = p.x * _up.x + p.y * _up.y + p.z * _up.z;
    final d = p.x * _sun.x + p.y * _sun.y + p.z * _sun.z;
    final iu = ((u - _u0) / cell).floor();
    final iv = ((v - _v0) / cell).floor();
    if (iu < 0 || iv < 0 || iu >= _nu || iv >= _nv) return false;
    return d < _depth[iv * _nu + iu] - bias;
  }
}

int _rampIdOf(List<int> b) {
  if (b.length == 3 && b[0] <= 95) return 0; // 3-band
  if (b.length == 2 && b[0] >= 170) return 1; // soft
  if (b.length == 2) return 2; // 2-band
  if (b.length == 4) return 3; // 4-band
  if (b.length == 5) return 4; // 5-band
  if (b.length == 3) return 5; // soft3
  return 0;
}

/// Packed per-vertex geometry for the custom per-pixel toon material
/// (base+tint+ramp+shadow, NOT cel-baked).
class PackedGeo {
  PackedGeo(this.positions, this.normals, this.colors, this.uvs, this.uvs1,
      this.attribute0, this.indices,
      {Float32List? atlasRegions})
      : atlasRegions = atlasRegions ?? Float32List(0);
  final Float32List positions, normals, colors, uvs, uvs1, attribute0;
  final Float32List atlasRegions;
  final List<int> indices;
}

/// Parse the extracted geometry and pack it for the REALTIME toon material
/// (`sakura_toon_rt.mat`) uploaded via `createGeometry` (NOT gltfio).
///
/// - COLOR0.rgb = raw LINEAR albedo (plain `C.lin(matColor)` — no gltfio
///   sRGB compensation, since `createGeometry` does not re-encode COLOR_0).
/// - COLOR0.a packs face state, ramp id, and mapped state into an exact small
///   integer. UV1 is therefore available for the atlas coordinates.
/// - Normals are flat or smooth according to the source material and become
///   Filament's tangent-frame normal input.
///
/// The extracted sky meshes (dome ShaderMaterial + flat cloud billboards) are
/// skipped, matching `refGeoToGlb` — the painted sky is rebuilt from `sky.dart`.
PackedGeo refGeoToPacked(Uint8List bytes, SunShadowMap shadowMap) {
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
  final header = _readRefHeader(bytes);
  int p = header.materialOffset;
  final nMat = header.materialCount;
  final stride = header.vertexStride;
  final mColor = <int>[];
  final mTint = <int>[];
  final mUnlit = <bool>[];
  final mSmooth = <bool>[];
  final mMapped = <bool>[];
  final mRid = <int>[]; // ramp id per material
  for (int i = 0; i < nMat; i++) {
    mColor.add(bd.getUint32(p, Endian.little));
    p += 4;
    mTint.add(bd.getUint32(p, Endian.little));
    p += 4;
    final rl = bytes[p];
    p += 1;
    final rampBytes = bytes.sublist(p, p + rl).toList();
    p += rl;
    final flags = bytes[p];
    p += 1;
    mUnlit.add((flags & 1) != 0);
    mSmooth.add((flags & 2) != 0);
    mMapped.add((flags & 4) != 0);
    mRid.add((flags & 1) != 0 ? 6 : _rampIdOf(rampBytes));
  }
  final nMesh = bd.getUint32(p, Endian.little);
  p += 4;
  p = (p + 3) & ~3;

  int totalVerts = 0;
  int q = p;
  for (int i = 0; i < nMesh; i++) {
    q += 4; // matIdx
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    q += header.meshHeaderStride - 8;
    totalVerts += c;
    q += c * stride;
  }

  final positions = Float32List(totalVerts * 3);
  final normals = Float32List(totalVerts * 3);
  final colors = Float32List(totalVerts * 4);
  final uvs = Float32List(totalVerts * 2);
  final uvs1 = Float32List(totalVerts * 2);
  final attribute0 = Float32List(totalVerts * 4);
  final atlasRegionValues = <double>[];
  final atlasRegionIds = <String, int>{};

  int atlasRegionId(
      double originU, double originV, double sizePack, int mapFlags) {
    final key = '$originU|$originV|$sizePack|$mapFlags';
    final existing = atlasRegionIds[key];
    if (existing != null) return existing;
    final id = atlasRegionIds.length;
    final wrapS = mapFlags & 3;
    final wrapT = (mapFlags >> 2) & 3;
    final flipY = (mapFlags & 16) != 0;
    final packedSize = sizePack.round();
    atlasRegionValues.addAll([
      originU + wrapS,
      originV + wrapT + (flipY ? 4 : 0),
      (packedSize % 4096) / header.info.atlasWidth,
      (packedSize ~/ 4096) / header.info.atlasHeight,
    ]);
    atlasRegionIds[key] = id;
    return id;
  }

  int vi = 0;
  q = p;
  for (int i = 0; i < nMesh; i++) {
    final mid = bd.getUint32(q, Endian.little);
    q += 4;
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    final meshFlags =
        header.info.version >= 3 ? bd.getUint32(q, Endian.little) : 3;
    q += header.meshHeaderStride - 8;
    final unlit = mUnlit[mid];
    final smooth = mSmooth[mid];
    final mapped = mMapped[mid];
    final color = mColor[mid];
    final baseLin = C.lin(color); // plain linear for the createGeometry path
    final tintLin =
        C.lin(unlit ? 0xffffff : (mTint[mid] == 0 ? 0x6c5f8c : mTint[mid]));

    Vector3 readV(int idx) {
      final o = q + idx * stride;
      return Vector3(
          bd.getFloat32(o, Endian.little),
          bd.getFloat32(o + 4, Endian.little),
          bd.getFloat32(o + 8, Endian.little));
    }

    // per-vertex normal from the binary (used for smooth materials; matches
    // refGeoToGlb, which cel-bakes smooth mats with these and flat mats with
    // the cross product).
    Vector3 readN(int idx) {
      final o = q + idx * stride + 12;
      return Vector3(
          bd.getFloat32(o, Endian.little),
          bd.getFloat32(o + 4, Endian.little),
          bd.getFloat32(o + 8, Endian.little));
    }

    // Skip the extracted sky meshes (see refGeoToGlb): the dome is a
    // ShaderMaterial with no colour (would bake white) and the cloud billboards
    // lose their puff texture + transparency (would read as solid quads). The
    // sky is rebuilt from sky.dart instead.
    if (c >= 3) {
      if (!unlit) {
        final probe = readV(0);
        if ((probe.length - 500).abs() < 4) {
          q += c * stride;
          continue; // sky dome
        }
      } else if (color == 0xfdfaf8 || color == 0xe6e6f2) {
        final probe = readV(0);
        final r = math.sqrt(probe.x * probe.x + probe.z * probe.z);
        if (probe.y >= 40 && probe.y <= 145 && r >= 200 && r <= 360) {
          q += c * stride;
          continue; // cloud billboards
        }
      }
    }

    final triCount = c ~/ 3;
    for (int t = 0; t < triCount; t++) {
      final a = readV(t * 3), b = readV(t * 3 + 1), cc = readV(t * 3 + 2);
      // Per-face cast-shadow decision from the CPU SunShadowMap (the same map
      // refGeoToGlb bakes with, and the reference uses). Packed into COLOR0.a:
      // 1.0 = unlit accent, 0.5 = lit face in cast shadow, 0.0 = lit & sunlit.
      // Soft-ramp materials (blossom canopies) do NOT receive shadows: the
      // reference sets receiveShadow=false on them (trees.js) because a big
      // cherry self-shadows into a dark violet lump otherwise. They still cast.
      final receivesShadow = !unlit && mRid[mid] != 1 && (meshFlags & 2) != 0;
      final inShadow =
          receivesShadow && shadowMap.shadowed((a + b + cc) * (1.0 / 3.0));
      // flat face normal (cross product) for flat materials; the binary's
      // per-vertex normal for smooth ones — same choice refGeoToGlb makes.
      Vector3 fnFlat() {
        final e1 = b - a;
        final e2 = cc - a;
        final fn = e1.cross(e2);
        final l = fn.length;
        return l < 1e-9 ? Vector3(0, 1, 0) : fn / l;
      }

      final List<Vector3> ns = smooth
          ? [readN(t * 3), readN(t * 3 + 1), readN(t * 3 + 2)]
          : [fnFlat(), fnFlat(), fnFlat()];
      for (int k = 0; k < 3; k++) {
        final v = (k == 0)
            ? a
            : (k == 1)
                ? b
                : cc;
        final n = ns[k];
        positions[vi * 3] = v.x;
        positions[vi * 3 + 1] = v.y;
        positions[vi * 3 + 2] = v.z;
        normals[vi * 3] = n.x;
        normals[vi * 3 + 1] = n.y;
        normals[vi * 3 + 2] = n.z;
        // V2 carries authored, atlas-remapped UVs. Lighting metadata lives in
        // COLOR0.a so both components of UV1 remain available to the atlas.
        double atlasU = 0.0, atlasV = 0.0;
        var atlasOriginU = 0.0, atlasOriginV = 0.0;
        var atlasSizePack = 1.0;
        var atlasRegionIndex = 0;
        var sourceMapped = false;
        if (header.info.version >= 3 && mapped) {
          final o = q + (t * 3 + k) * stride;
          atlasU = bd.getFloat32(o + 24, Endian.little);
          atlasV = bd.getFloat32(o + 28, Endian.little);
          atlasOriginU = bd.getFloat32(o + 32, Endian.little);
          atlasOriginV = bd.getFloat32(o + 36, Endian.little);
          atlasSizePack = bd.getFloat32(o + 40, Endian.little);
          final mapFlags = bd.getFloat32(o + 44, Endian.little).round();
          atlasRegionIndex = atlasRegionId(
              atlasOriginU, atlasOriginV, atlasSizePack, mapFlags);
          uvs[vi * 2] = 0.0;
          uvs[vi * 2 + 1] = 0.0;
          sourceMapped = true;
        } else if (header.info.version >= 2 && mapped) {
          final o = q + (t * 3 + k) * stride;
          atlasU = bd.getFloat32(o + 24, Endian.little);
          atlasV = bd.getFloat32(o + 28, Endian.little);
          uvs[vi * 2] = 0.0;
          uvs[vi * 2 + 1] = 0.0;
        } else {
          uvs[vi * 2] = 0.0;
          uvs[vi * 2 + 1] = 0.0;
        }
        uvs1[vi * 2] = atlasU;
        uvs1[vi * 2 + 1] = atlasV;
        colors[vi * 4] = baseLin.x;
        colors[vi * 4 + 1] = baseLin.y;
        colors[vi * 4 + 2] = baseLin.z;
        final stateCode = unlit
            ? 3
            : !receivesShadow
                ? 2
                : (inShadow ? 1 : 0);
        colors[vi * 4 + 3] = 1.0 +
            stateCode +
            4.0 * mRid[mid] +
            (sourceMapped
                ? 56.0 + 28.0 * atlasRegionIndex
                : (mapped ? 28.0 : 0.0));
        attribute0[vi * 4] = tintLin.x;
        attribute0[vi * 4 + 1] = tintLin.y;
        attribute0[vi * 4 + 2] = tintLin.z;
        attribute0[vi * 4 + 3] = 0.0;
        vi++;
      }
    }
    q += c * stride;
  }

  // The sky-skip leaves the pre-allocated tails zeroed; trim to what we wrote.
  return PackedGeo(
    Float32List.sublistView(positions, 0, vi * 3),
    Float32List.sublistView(normals, 0, vi * 3),
    Float32List.sublistView(colors, 0, vi * 4),
    Float32List.sublistView(uvs, 0, vi * 2),
    Float32List.sublistView(uvs1, 0, vi * 2),
    Float32List.sublistView(attribute0, 0, vi * 4),
    List<int>.generate(vi, (i) => i),
    atlasRegions: Float32List.fromList(atlasRegionValues),
  );
}

/// matching cel shading. [cel] is the shared CelShader (lighting setup).
Uint8List refGeoToGlb(Uint8List bytes, CelShader cel) {
  final shadowMap = SunShadowMap(
      refGeoPositions(bytes, onlyLit: true, onlyCast: true), cel.sunDir);
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
  final header = _readRefHeader(bytes);
  int p = header.materialOffset;
  final nMat = header.materialCount;
  final stride = header.vertexStride;
  final mats = <_RMat>[];
  for (int i = 0; i < nMat; i++) {
    final color = bd.getUint32(p, Endian.little);
    p += 4;
    final tint = bd.getUint32(p, Endian.little);
    p += 4;
    final rl = bytes[p];
    p += 1;
    final ramp = List<double>.generate(rl, (j) => bytes[p + j] / 255.0);
    p += rl;
    final flags = bytes[p];
    p += 1;
    mats.add(_RMat(color, tint, ramp, flags));
  }
  final nMesh = bd.getUint32(p, Endian.little);
  p += 4;
  p = (p + 3) & ~3; // align to mesh section

  // total vertex count
  int totalVerts = 0;
  int q = p;
  for (int i = 0; i < nMesh; i++) {
    bd.getUint32(q, Endian.little);
    q += 4; // matIdx
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    q += header.meshHeaderStride - 8;
    totalVerts += c;
    q += c * stride;
  }

  final positions = Float32List(totalVerts * 3);
  final normals = Float32List(totalVerts * 3);
  final colors = Float32List(totalVerts * 4);
  final fogOrigin = Vector3(1.85, 1.62, 13.6);

  int vi = 0; // vertex write index
  q = p;
  for (int i = 0; i < nMesh; i++) {
    final mid = bd.getUint32(q, Endian.little);
    q += 4;
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    q += header.meshHeaderStride - 8;
    final mat = mats[mid];
    // The reference's cel() always applies a shadow tint (default 0x6c5f8c).
    // Extraction captures explicit tints; cel materials missing one get the
    // default violet, flat/unlit materials get none.
    final tint = mat.unlit ? 0xffffff : (mat.tint == 0 ? 0x6c5f8c : mat.tint);
    final baseLin = C.lin(mat.color); // for unlit
    final triCount = c ~/ 3;

    Vector3 readV(int idx) {
      final o = q + idx * stride;
      return Vector3(
          bd.getFloat32(o, Endian.little),
          bd.getFloat32(o + 4, Endian.little),
          bd.getFloat32(o + 8, Endian.little));
    }

    Vector3 readN(int idx) {
      final o = q + idx * stride + 12;
      return Vector3(
          bd.getFloat32(o, Endian.little),
          bd.getFloat32(o + 4, Endian.little),
          bd.getFloat32(o + 8, Endian.little));
    }

    // Skip the painted-sky meshes — render_ref rebuilds them from the palette
    // (sky.dart): the extracted dome is a ShaderMaterial with no colour (it
    // would bake as white lit geometry) and the cloud billboards lose their
    // puff texture + transparency (they would read as solid white quads).
    // Dome: a sphere of radius 500 around the origin, the only such mesh.
    // Clouds: unlit quads in the cloud palette colours up in the sky band.
    if (!mat.unlit && c >= 3) {
      final probe = readV(0);
      final dist = probe.length;
      if ((dist - 500).abs() < 4) {
        q += c * stride; // keep the mesh-section pointer aligned
        continue;
      }
    } else if (mat.unlit &&
        (mat.color == 0xfdfaf8 || mat.color == 0xe6e6f2) &&
        c >= 3) {
      final probe = readV(0);
      final r = math.sqrt(probe.x * probe.x + probe.z * probe.z);
      if (probe.y >= 40 && probe.y <= 145 && r >= 200 && r <= 360) {
        q += c * stride;
        continue;
      }
    }

    for (int t = 0; t < triCount; t++) {
      final a = readV(t * 3), b = readV(t * 3 + 1), cc = readV(t * 3 + 2);
      // face normal for flat materials; per-vertex normals for smooth ones
      Vector3 fn;
      if (mat.smooth) {
        fn = readN(t * 3); // placeholder; handled per-vertex below
      } else {
        final e1 = b - a;
        final e2 = cc - a;
        fn = e1.cross(e2);
        final l = fn.length;
        fn = l < 1e-9 ? Vector3(0, 1, 0) : fn / l;
      }
      // fog by triangle centroid distance from the camera
      final cen = (a + b + cc) * (1 / 3);
      final inShadow = mat.unlit ? false : shadowMap.shadowed(cen);
      final dist = (cen - fogOrigin).length;
      double fog = 0;
      if (dist > 44) {
        final t2 = ((dist - 44) / (205 - 44)).clamp(0.0, 1.0);
        fog = t2 * t2 * (3 - 2 * t2);
      }
      final fogLin = C.lin(Pal.fog);

      for (int k = 0; k < 3; k++) {
        final v = (k == 0)
            ? a
            : (k == 1)
                ? b
                : cc;
        final n = mat.smooth ? readN(t * 3 + k) : fn;
        positions[vi * 3] = v.x;
        positions[vi * 3 + 1] = v.y;
        positions[vi * 3 + 2] = v.z;
        normals[vi * 3] = n.x;
        normals[vi * 3 + 1] = n.y;
        normals[vi * 3 + 2] = n.z;
        Vector3 col;
        if (mat.unlit) {
          col = baseLin.clone();
        } else {
          col = cel.shadeRamp(mat.color, n, mat.ramp,
              tint: tint, inShadow: inShadow);
        }
        if (fog > 0.001) {
          col = col * (1 - fog) + fogLin * fog;
        }
        // gltfio's generated unlit material sRGB-ENCODES COLOR_0 (linear→sRGB
        // on upload: written 0.5 comes out ~0.686 in the RT). The bake
        // produces linear values, so write them pre-DECODED; the material's
        // encode returns the RT to linear. Same compensation refGeoPacked
        // applies for the toon GLB.
        final dec = C.fromSrgb(col);
        colors[vi * 4] = dec.x;
        colors[vi * 4 + 1] = dec.y;
        colors[vi * 4 + 2] = dec.z;
        colors[vi * 4 + 3] = 1.0;
        vi++;
      }
    }
    q += c * stride;
  }

  return rawToGlb(positions, normals, colors);
}

/// Parse the extracted geometry and return just the positions (as a flat
/// Float32List, non-indexed triangle list). When [onlyLit] is set, meshes
/// whose material is unlit (sky/clouds/hills — not shadow casters) are skipped.
Float32List refGeoPositions(Uint8List bytes,
    {bool onlyLit = false, bool onlyCast = false}) {
  final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
  final header = _readRefHeader(bytes);
  int p = header.materialOffset;
  final nMat = header.materialCount;
  final stride = header.vertexStride;
  final unlit = List<bool>.filled(nMat, false);
  for (int i = 0; i < nMat; i++) {
    p += 8;
    final rl = bytes[p];
    p += 1;
    p += rl;
    unlit[i] = (bytes[p] & 1) != 0;
    p += 1;
  }
  final nMesh = bd.getUint32(p, Endian.little);
  p += 4;
  p = (p + 3) & ~3;
  int totalVerts = 0;
  int q = p;
  for (int i = 0; i < nMesh; i++) {
    final mid = bd.getUint32(q, Endian.little);
    q += 4;
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    final meshFlags =
        header.info.version >= 3 ? bd.getUint32(q, Endian.little) : 3;
    q += header.meshHeaderStride - 8;
    if ((!onlyLit || !unlit[mid]) && (!onlyCast || (meshFlags & 1) != 0)) {
      totalVerts += c;
    }
    q += c * stride;
  }
  final positions = Float32List(totalVerts * 3);
  int vi = 0;
  q = p;
  for (int i = 0; i < nMesh; i++) {
    final mid = bd.getUint32(q, Endian.little);
    q += 4;
    final c = bd.getUint32(q, Endian.little);
    q += 4;
    final meshFlags =
        header.info.version >= 3 ? bd.getUint32(q, Endian.little) : 3;
    q += header.meshHeaderStride - 8;
    if ((onlyLit && unlit[mid]) || (onlyCast && (meshFlags & 1) == 0)) {
      q += c * stride;
      continue;
    }
    for (int j = 0; j < c; j++) {
      positions[vi++] = bd.getFloat32(q, Endian.little);
      positions[vi++] = bd.getFloat32(q + 4, Endian.little);
      positions[vi++] = bd.getFloat32(q + 8, Endian.little);
      q += stride;
    }
  }
  return positions;
}
