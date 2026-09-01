/// Composition-first port of `urayama.js` (ひばり山).
///
/// This tranche is the complete hill-foot-road elevation: the narrow municipal
/// road behind the school, its drainage and safety furniture, the maintained
/// woodland fringe, and the verge planting visible from the fidelity camera.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'hills.dart' show hillFieldAt, hillSurfaceY;
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'urayama_shadow_data.dart';

const _y = 1.05;
const _roadZ = -90.0;
const _roadWidth = 4.4;
const _asphalt = Mat(0xa49db2, unlit: true);
const _patch = Mat(0xa49db1, unlit: true);
const _curb = Mat(0xc7c2d0, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _drain = Mat(0x6d687a, tint: 0x5d5878, bands: '3');
const _line = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2', noOutline: true);
const _schoolRoadShadow = Mat(0x656b8c, unlit: true, noOutline: true);
const _schoolRoadPenumbraOuter = Mat(0x9a94a9, unlit: true, noOutline: true);
const _schoolRoadPenumbra = Mat(0x85849f, unlit: true, noOutline: true);
const _schoolRoadPenumbraInner = Mat(0x81819d, unlit: true, noOutline: true);
const _schoolBranchShadow = Mat(0x8d8ba5, unlit: true, noOutline: true);
const _schoolWalkShadow = Mat(0x818ba0, unlit: true, noOutline: true);
const _timber = Mat(0x9a7f5e, tint: 0x5c5680, bands: '3');
const _timberDark = Mat(0x6f5943, tint: 0x554d72, bands: '3');
const _log = Mat(0x8a7050, tint: 0x5c5680, bands: '3');
const _path = Mat(0xb7a98f, tint: 0x7d74a0, bands: '3');
const _pathEdge = Mat(0x8f887d, tint: 0x6f6790, bands: '3');
const _notice = Mat(0xf1eadc, unlit: true, noOutline: true);

typedef _Point = (double, double);

const _trails = <String, List<_Point>>{
  'main': [
    (18.0, -94.5),
    (15.4, -98.4),
    (10.0, -101.0),
    (1.0, -103.4),
    (-9.0, -105.6),
    (-19.0, -108.4),
    (-26.5, -112.6),
    (-24.0, -117.6),
    (-14.0, -120.0),
    (-3.0, -122.4),
    (8.0, -126.4),
    (17.0, -131.0),
    (24.6, -135.6),
  ],
  'ridge': [
    (24.6, -135.6),
    (17.0, -137.6),
    (8.0, -138.2),
    (-1.0, -137.4),
    (-10.0, -136.2),
    (-18.0, -135.0),
  ],
  'deck': [(24.6, -135.6), (29.6, -135.2), (35.4, -135.4)],
  'hokora': [(-26.5, -112.6), (-32.0, -111.0), (-37.0, -112.0)],
  'glade': [(-14.0, -120.0), (-18.0, -124.5), (-16.0, -129.0)],
  'foot': [
    (13.0, -97.4),
    (26.0, -97.6),
    (40.0, -98.0),
    (54.0, -98.4),
    (68.0, -98.2),
    (80.0, -96.6),
    (86.0, -93.8),
  ],
  'toverW': [
    (-66.0, 22.0),
    (-70.0, 25.5),
    (-75.0, 26.0),
    (-79.5, 23.0),
    (-82.5, 19.0),
    (-84.5, 15.5),
    (-86.0, 12.0),
  ],
  'toverE': [
    (91.0, -18.8),
    (97.5, -18.2),
    (104.0, -17.4),
    (106.0, -16.6),
    (99.0, -15.6),
    (97.8, -14.8),
    (100.6, -13.6),
    (101.4, -12.4),
    (104.0, -12.0),
  ],
};

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _roadShadow(List<Part> parts) {
  // Canopy shadow measured from the reference and inverted through the
  // urayama camera onto the curved road. Its abrupt far notch and wandering
  // near edge are both visible; a rectangular building footprint is not.
  // Above the worn asphalt patches, below the raised centre markings.
  const y = _y + .125;
  const rows = <(double, double, double, double)>[
    // The strong canopy core begins at y≈670 px. Earlier thin marks are
    // disconnected rail/tree shadows and are represented by the measured band
    // layer below; extending this polygon upward creates a false dark patch.
    (54.9500, -88.9500, 54.9300, -87.7860),
    (54.5466, -90.7213, 54.5187, -87.7939),
    (53.9122, -90.7338, 53.8853, -87.8139),
    (53.3719, -90.7343, 53.3467, -87.8227),
    (52.9049, -90.7252, 52.8818, -87.8282),
    (52.4965, -90.7127, 52.4755, -87.8312),
    (52.1368, -90.7180, 52.1167, -87.8369),
    (51.8164, -90.7188, 51.7973, -87.8409),
    (51.5337, -90.7200, 51.5108, -87.8437),
    (51.2688, -90.6984, 51.2523, -87.8456),
    (50.98, -90.71, 50.96, -87.85),
    (50.68, -90.70, 50.66, -87.86),
    (50.38, -90.706, 50.36, -87.87),
    (49.98, -90.71, 49.96, -87.88),
  ];
  final positions = <double>[];
  for (final p in rows) {
    positions.addAll([p.$1, y, p.$2, p.$3, y, p.$4]);
  }
  final indices = <int>[];
  for (var i = 0; i < rows.length - 1; i++) {
    final a = i * 2, b = a + 2;
    indices.addAll([a, b, a + 1, a + 1, b, b + 1]);
  }
  final raw = ThreeGeom(
    Float32List.fromList(positions),
    Float32List(0),
    indices,
  );
  parts.add(Part(
    ThreeGeom(raw.positions, computeNormals(raw), raw.indices),
    Matrix4.identity(),
    _schoolRoadShadow,
  ));
  for (final band in const [
    (-.12, -.08, _schoolRoadPenumbraOuter),
    (-.08, -.04, _schoolRoadPenumbra),
    (-.04, 0.0, _schoolRoadPenumbraInner),
  ]) {
    final featherPositions = <double>[];
    for (final p in rows) {
      featherPositions.addAll([
        p.$1,
        y + .001,
        p.$2 + band.$1,
        p.$1,
        y + .001,
        p.$2 + band.$2,
      ]);
    }
    final featherRaw = ThreeGeom(Float32List.fromList(featherPositions),
        Float32List(0), List<int>.from(indices));
    parts.add(Part(
      ThreeGeom(
          featherRaw.positions, computeNormals(featherRaw), featherRaw.indices),
      Matrix4.identity(),
      band.$3,
    ));
  }

  // Disconnected tree and rail shadows on the sunlit half of the road. These
  // cannot be folded into the canopy edge: the reference preserves sunlit
  // gaps between individual branches. The compact table stores screen-derived
  // quads inverted through this camera onto the curved road surface.
  void addMeasuredBands(List<int> data, Mat material, double lift) {
    final bandPositions = <double>[];
    final bandIndices = <int>[];
    for (var i = 0; i < data.length; i += 8) {
      final first = bandPositions.length ~/ 3;
      for (var j = 0; j < 8; j += 2) {
        bandPositions.addAll([
          50 + data[i + j] / 10000,
          y + lift,
          -91 + data[i + j + 1] / 10000,
        ]);
      }
      bandIndices
          .addAll([first, first + 2, first + 1, first, first + 3, first + 2]);
    }
    final bandRaw = ThreeGeom(
        Float32List.fromList(bandPositions), Float32List(0), bandIndices);
    parts.add(Part(
      ThreeGeom(bandRaw.positions, computeNormals(bandRaw), bandRaw.indices),
      Matrix4.identity(),
      material,
    ));
  }

  addMeasuredBands(urayamaLeftShadowBands, _schoolBranchShadow, .003);

  const walkRows = <(double, double, double, double)>[
    (63.199, -86.797, 63.450, -85.969),
    (61.380, -86.955, 61.567, -86.116),
    (58.996, -87.108, 59.123, -86.286),
    (57.396, -87.194, 57.503, -86.321),
    (56.208, -87.245, 56.296, -86.386),
    (55.716, -87.251, 55.797, -86.406),
    (54.866, -87.467, 54.953, -86.394),
    (53.873, -87.503, 53.947, -86.422),
    (53.593, -87.511, 53.665, -86.425),
    (52.90, -87.53, 52.97, -86.43),
    (52.10, -87.55, 52.17, -86.44),
    (51.20, -87.57, 51.27, -86.45),
    (50.20, -87.59, 50.27, -86.46),
  ];
  final walkPositions = <double>[];
  for (final p in walkRows) {
    walkPositions.addAll([p.$1, y + .002, p.$2, p.$3, y + .002, p.$4]);
  }
  final walkIndices = <int>[];
  for (var i = 0; i < walkRows.length - 1; i++) {
    final a = i * 2, b = a + 2;
    walkIndices.addAll([a, b, a + 1, a + 1, b, b + 1]);
  }
  final walkRaw = ThreeGeom(
      Float32List.fromList(walkPositions), Float32List(0), walkIndices);
  parts.add(Part(
    ThreeGeom(walkRaw.positions, computeNormals(walkRaw), walkRaw.indices),
    Matrix4.identity(),
    _schoolWalkShadow,
  ));
}

void _member(List<Part> parts, Vector3 a, Vector3 b, double r, Mat mat,
    [int segments = 6]) {
  final direction = b - a;
  final length = direction.length;
  if (length < 1e-4) return;
  final rotation =
      quatFromUnitVectors(Vector3(0, 1, 0), direction.normalized());
  parts.add(Part(cylGeometry(r, r, 1, segments),
      composePRS((a + b) * .5, rotation, Vector3(r, length, r)), mat));
}

List<_Point> _sampleTrail(List<_Point> points, [double step = 1]) {
  final line = <_Point>[];
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i], b = points[i + 1];
    final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
    final count = math.max(1, (math.sqrt(dx * dx + dz * dz) / step).round());
    for (var k = 0; k < count; k++) {
      final t = k / count;
      line.add((a.$1 + dx * t, a.$2 + dz * t));
    }
  }
  line.add(points.last);
  return line;
}

/// Source-equivalent swept hill ribbon: one-metre cross-sections, 45 mm lift,
/// and 30 cm side skirts so diagonal facets never expose a floating path edge.
List<Tri> _hillPath(List<_Point> points, double width, Mat topMat) {
  final line = _sampleTrail(points);
  final rim = <(Vector3, Vector3)>[];
  final half = width / 2;
  for (var i = 0; i < line.length; i++) {
    final prev = line[math.max(0, i - 1)];
    final next = line[math.min(line.length - 1, i + 1)];
    var tx = next.$1 - prev.$1, tz = next.$2 - prev.$2;
    final length = math.sqrt(tx * tx + tz * tz);
    if (length > 1e-6) {
      tx /= length;
      tz /= length;
    }
    final nx = -tz, nz = tx;
    final lx = line[i].$1 + nx * half, lz = line[i].$2 + nz * half;
    final rx = line[i].$1 - nx * half, rz = line[i].$2 - nz * half;
    rim.add((
      Vector3(lx, hillSurfaceY(lx, lz) + .045, lz),
      Vector3(rx, hillSurfaceY(rx, rz) + .045, rz),
    ));
  }

  final topPositions = <double>[];
  final sidePositions = <double>[];
  for (final pair in rim) {
    topPositions
      ..addAll([pair.$1.x, pair.$1.y, pair.$1.z])
      ..addAll([pair.$2.x, pair.$2.y, pair.$2.z]);
    sidePositions
      ..addAll([pair.$1.x, pair.$1.y, pair.$1.z])
      ..addAll([pair.$1.x, pair.$1.y - .30, pair.$1.z])
      ..addAll([pair.$2.x, pair.$2.y, pair.$2.z])
      ..addAll([pair.$2.x, pair.$2.y - .30, pair.$2.z]);
  }
  final topIndices = <int>[], sideIndices = <int>[];
  for (var i = 0; i < rim.length - 1; i++) {
    final a = i * 2, b = (i + 1) * 2;
    topIndices.addAll([a, b, b + 1, a, b + 1, a + 1]);
    final s = i * 4, n = (i + 1) * 4;
    sideIndices.addAll([
      s,
      s + 1,
      n + 1,
      s,
      n + 1,
      n,
      n + 2,
      n + 3,
      s + 3,
      n + 2,
      s + 3,
      s + 2,
    ]);
  }
  ThreeGeom geometry(List<double> positions, List<int> indices) {
    final raw =
        ThreeGeom(Float32List.fromList(positions), Float32List(0), indices);
    return ThreeGeom(raw.positions, computeNormals(raw), raw.indices);
  }

  return bake([
    Part(geometry(topPositions, topIndices), Matrix4.identity(), topMat),
    Part(geometry(sidePositions, sideIndices), Matrix4.identity(), _pathEdge),
  ]);
}

void _trailRail(
    List<Part> parts, List<_Point> points, double side, double offset,
    [double height = .92]) {
  final posts = <Vector3>[];
  for (var s = 0; s < points.length - 1; s++) {
    final a = points[s], b = points[s + 1];
    final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
    final length = math.sqrt(dx * dx + dz * dz);
    final count = math.max(1, (length / 2.1).round());
    final nx = -dz / length * side, nz = dx / length * side;
    for (var k = 0; k < count; k++) {
      final t = k / count;
      final x = a.$1 + dx * t + nx * offset;
      final z = a.$2 + dz * t + nz * offset;
      final y = hillSurfaceY(x, z) + .04;
      final foot = Vector3(x, y, z);
      final top = Vector3(x, y + height, z);
      _member(parts, foot, top, .045, _metalDark);
      posts.add(top);
    }
  }
  final end = points.last;
  final before = points[points.length - 2];
  final dx = end.$1 - before.$1, dz = end.$2 - before.$2;
  final length = math.sqrt(dx * dx + dz * dz);
  final x = end.$1 - dz / length * side * offset;
  final z = end.$2 + dx / length * side * offset;
  final y = hillSurfaceY(x, z) + .04;
  final endTop = Vector3(x, y + height, z);
  _member(parts, Vector3(x, y, z), endTop, .045, _metalDark);
  posts.add(endTop);
  for (var i = 0; i < posts.length - 1; i++) {
    _member(parts, posts[i], posts[i + 1], .042, _metalDark);
  }
}

List<Tri> _buildTrails() {
  final out = <Tri>[];
  for (final entry in _trails.entries) {
    final width = entry.key == 'main'
        ? 1.5
        : entry.key == 'foot'
            ? 1.7
            : 1.25;
    out.addAll(
        _hillPath(entry.value, width, entry.key == 'foot' ? _pathEdge : _path));
  }

  final dress = <Part>[];
  // The two deliberately steep main-trail pitches use pinned round logs.
  for (final segment in [(4, 6), (6, 7)]) {
    final points = _trails['main']!;
    for (var s = segment.$1; s < segment.$2; s++) {
      final a = points[s], b = points[s + 1];
      final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
      final length = math.sqrt(dx * dx + dz * dz);
      final count = math.max(1, (length / .62).round());
      final nx = -dz / length, nz = dx / length;
      for (var k = 1; k < count; k++) {
        final t = k / count;
        final x = a.$1 + dx * t, z = a.$2 + dz * t;
        final y = hillSurfaceY(x, z) + .10;
        _member(dress, Vector3(x - nx * .76, y, z - nz * .76),
            Vector3(x + nx * .76, y, z + nz * .76), .075, _timber, 7);
      }
    }
  }

  _trailRail(dress, _trails['main']!.sublist(4, 8), 1, .98);
  _trailRail(dress, _trails['ridge']!.sublist(0, 4), -1, .86, .86);
  _trailRail(dress, _trails['deck']!, 1, .86, .86);

  // Short timber boardwalk across the damp upper shelf.
  const a = (-11.0, -121.2), b = (-4.4, -122.6);
  final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
  final length = math.sqrt(dx * dx + dz * dz);
  final count = (length / .34).round();
  final yaw = math.atan2(dx, dz);
  for (var k = 0; k < count; k++) {
    final t = (k + .5) / count;
    final x = a.$1 + dx * t, z = a.$2 + dz * t;
    final y = hillSurfaceY(x, z);
    _box(dress, 1.4, .06, .26, _timber, x, y + .14, z, 0, yaw + math.pi / 2);
    if (k % 6 == 0) {
      for (final side in [-1.0, 1.0]) {
        _box(dress, .12, .24, .12, _timberDark, x + math.cos(yaw) * side * .58,
            y, z - math.sin(yaw) * side * .58);
      }
    }
  }
  out.addAll(bake(dress));
  return out;
}

List<Tri> buildUrayama({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
  bool includeSchoolRoadShadow = false,
  int blossomLightColor = 0xf8e9ed,
  int blossomColor = 0xecb8cc,
  int blossomDeepColor = 0xe598b9,
}) {
  final scene = <Tri>[];
  void add(List<Tri> tris, {bool casts = true}) {
    scene.addAll(tris);
    if (casts) {
      shadowCasters?.addAll(tris);
      groupedShadowCasters?.addAll(tris);
    }
  }

  final ground = <Part>[];
  // 裾道: the source lane is a 6 cm slab centred at Y0 + its 5 cm rise.
  _box(ground, 89.4, .06, _roadWidth, _asphalt, 45.5, _y + .05, _roadZ);
  _box(ground, 1.8, .02, 1.3, _patch, 14.0, _y + .065, -89.4);
  _box(ground, 1.5, .02, 1.1, _patch, 61.0, _y + .065, -90.5);
  // Principal projected footprint of the north classroom block.
  if (includeSchoolRoadShadow) {
    _roadShadow(ground);
  }
  // North-side kerb, split at the back and service gates.
  const gaps = [(15.2, 21.0), (21.6, 27.0), (46.6, 53.4)];
  var cursor = .8;
  for (final gap in gaps) {
    if (gap.$1 > cursor) {
      _box(ground, gap.$1 - cursor, .16, .26, _curb, (cursor + gap.$1) / 2,
          _y + .13, -87.67);
    }
    _box(ground, gap.$2 - gap.$1, .06, .26, _curb, (gap.$1 + gap.$2) / 2,
        _y + .08, -87.67);
    cursor = gap.$2;
  }
  _box(ground, 90.2 - cursor, .16, .26, _curb, (cursor + 90.2) / 2, _y + .13,
      -87.67);

  // South-side slotted drain.
  const gullyCount = 93;
  for (var i = 0; i < gullyCount; i++) {
    final x = 2.0 + (i + .5) * 84.0 / gullyCount;
    _box(ground, .70, .04, .30, _drain, x, _y + .055, -92.50);
  }
  for (final x in [22.0, 58.0]) {
    ground.add(Part(
        cylGeometry(.30, .30, .04, 12), trs(x, _y + .07, -91.95), _metalDark));
  }

  add(bake(ground), casts: false);

  final markings = <Part>[];
  const dashCount = 23;
  for (var i = 0; i < dashCount; i++) {
    final x = 8.0 + 74.0 * (i + .25) / dashCount;
    _box(markings, 1.6, .02, .10, _line, x, _y + .12, _roadZ);
  }
  add(bake(markings), casts: false);

  // Concrete block retaining run sampled from the actual hill toe. Each cap
  // follows the field independently; a straight substitute buries one end.
  final toeKerb = <Part>[];
  for (var x = 0.0; x < 84.0; x += 2.0) {
    double? toeZ;
    for (var z = -93.0; z > -106.0; z -= .5) {
      if (hillFieldAt(x, z) > .35) {
        toeZ = z;
        break;
      }
    }
    if (toeZ == null) continue;
    final y = hillSurfaceY(x, toeZ);
    _box(toeKerb, 2.05, .46, .30, _concreteMid, x + 1.0, y - .02, toeZ + .20);
    _box(toeKerb, 2.05, .08, .42, _concreteMid, x + 1.0, y + .25, toeZ + .20);
  }
  add(bake(toeKerb));

  // All eight authored hill routes, including the two tunnel-overlook climbs.
  // Their surfaces receive light but do not cast broad ribbon shadows.
  add(_buildTrails(), casts: false);

  // Guardrails where the road crosses the two drainage falls.
  add(makeGuardrail(x: 36, y: _y, z: -92.95, len: 12));
  add(makeGuardrail(x: 69, y: _y, z: -92.95, len: 14));
  add(makeGuardrail(x: 6.6, y: _y, z: -92.6, len: 3));
  add(makeGuardrail(x: 84.6, y: _y, z: -92.6, len: 3));

  // Two authored caution boards at the unmanaged edge of the verge.
  final notices = <Part>[];
  for (final x in [36.0, 66.0]) {
    notices.add(
        Part(cylGeometry(.045, .05, 2.0, 8), trs(x, _y + 1.0, -93.4), _timber));
    notices.add(Part(
        cylGeometry(.10, .12, .14, 8), trs(x, _y + .07, -93.4), _concreteMid));
    _box(notices, .90, .68, .05, _notice, x, _y + 1.50, -93.342);
  }
  add(bake(notices));

  // Maintenance clutter at the camera-visible verge: coloured crates and the
  // two-row stack of cut logs from the reference module.
  add(makeCrates(x: 52, y: _y, z: -93.2, ry: .2, n: 3, seed: 8431));
  final logs = <Part>[];
  for (var i = 0; i < 6; i++) {
    logs.add(Part(
        cylGeometry(.14, .15, 1.7, 7),
        trs(58 + (i % 3) * .31, _y + .15 + (i ~/ 3) * .28, -93.6, 0, 0,
            math.pi / 2),
        _log));
  }
  add(bake(logs));

  final cherries = buildSakura(const [
    SakuraSpot(
        x: 8, z: -93.6, y: _y, scale: 1.18, seed: 8421, lean: .1, leanDir: 3.4),
    SakuraSpot(
        x: 43,
        z: -93.8,
        y: _y,
        scale: 1.24,
        seed: 8422,
        lean: .1,
        leanDir: 3.4),
    SakuraSpot(
        x: 72,
        z: -93.4,
        y: _y,
        scale: 1.12,
        seed: 8423,
        lean: .1,
        leanDir: 3.4),
  ],
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  add(cherries);

  final shrubs = <ShrubSpot>[];
  final rng = RngKit(83117);
  for (var i = 0; i < 26; i++) {
    final x = rng.range(-4, 88);
    double? toeZ;
    for (var z = -92.5; z > -104.0; z -= .5) {
      if (hillFieldAt(x, z) > .2) {
        toeZ = z;
        break;
      }
    }
    if (toeZ == null || (x - 24).abs() < 7 || (x - 18).abs() < 5) continue;
    final ySampleZ = toeZ - rng.range(.5, 3.0);
    final z = toeZ - rng.range(.5, 3.0);
    shrubs.add(ShrubSpot(
        x: x,
        z: z,
        y: hillSurfaceY(x, ySampleZ),
        r: rng.range(.42, .62),
        count: rng.ints(3, 5),
        spread: rng.range(1.2, 2.2),
        seed: 8400 + i));
  }
  add(buildShrubs(shrubs));

  return scene;
}
