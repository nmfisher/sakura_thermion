/// Faithful Dart port of the reference's geometry **substrate** — the small set
/// of `three.js` primitives + helpers every world module is built from
/// (`core/util.js` + `BoxGeometry`/`CylinderGeometry`).
///
/// This exists so reference world modules can be translated ~mechanically into
/// Dart (vector math, control flow, material literals and primitive calls all
/// map 1:1) and produce **bit-faithful** geometry — validated against the
/// reference's own output (see `tool/extract_part.js` + the diff in
/// `world_ref/make_pole.dart`). Once a module is ported and verified, the
/// extracted `ref_geo*.bin` no longer needs to carry its geometry.
///
/// Conventions match three.js r180 exactly: vertex layout, face normals and
/// index winding are reproduced, so cel banding, silhouettes and back-face
/// culling all match the reference.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic PRNG — exact port of util.js mulberry32 / rngKit. The world's
// placements are seeded; matching the sequence bit-for-bit is what makes a
// ported module land its objects in the same spots as the reference.
// ─────────────────────────────────────────────────────────────────────────────

/// JS `Math.imul` (low 32 bits of a × b, as unsigned). Dart ints are 64-bit so
/// we mask explicitly.
int _imul(int a, int b) {
  final al = a & 0xFFFF;
  final ah = (a >> 16) & 0xFFFF;
  final bl = b & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF;
  return ((al * bl) + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF;
}

/// Exact port of `mulberry32(seed)`. Returns a 0..1 generator.
double Function() mulberry32(int seed) {
  int a = seed & 0xFFFFFFFF;
  return () {
    a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = a;
    t = _imul((t ^ (t >>> 15)) & 0xFFFFFFFF, t | 1);
    t = (t ^ ((t + _imul((t ^ (t >>> 7)) & 0xFFFFFFFF, t | 61)) & 0xFFFFFFFF)) &
        0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  };
}

/// Port of `rngKit(seed)` — the helper bundle every module draws from.
class RngKit {
  RngKit(int seed) : _r = mulberry32(seed);
  final double Function() _r;
  double next() => _r();
  double range(double a, double b) => a + (b - a) * _r();
  int ints(int a, int b) => (a + (b - a + 1) * _r()).floor();
  T pick<T>(List<T> arr) => arr[(_r() * arr.length).floor() % arr.length];
  bool chance(double p) => _r() < p;
  int sign() => _r() < 0.5 ? -1 : 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// trs — compose a Matrix4 from translation / Euler-XYZ rotation / scale.
// Port of util.js `trs` (which uses THREE.Matrix4.compose + Euler 'XYZ').
// ─────────────────────────────────────────────────────────────────────────────

Matrix4 trs(
    [double px = 0,
    double py = 0,
    double pz = 0,
    double rx = 0,
    double ry = 0,
    double rz = 0,
    double sx = 1,
    double sy = double.nan,
    double sz = double.nan]) {
  sy = sy.isNaN ? sx : sy;
  sz = sz.isNaN ? sx : sz;
  final q = quatFromEulerXyz(rx, ry, rz);
  // M = T · R · S
  return Matrix4.translation(Vector3(px, py, pz)) *
      _rotationMatrix(q.x, q.y, q.z, q.w) *
      Matrix4.diagonal3(Vector3(sx, sy, sz));
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry — minimal attribute container (positions, normals, indices), matching
// three.js BufferGeometry's non-indexed-after-merge shape.
// ─────────────────────────────────────────────────────────────────────────────

class ThreeGeom {
  ThreeGeom(this.positions, this.normals, this.indices);
  final Float32List positions;
  final Float32List normals;
  final List<int> indices;
  int get vertexCount => positions.length ~/ 3;
}

/// Exact port of `THREE.BoxGeometry(w, h, d)` (1×1×1 segments). 6 faces, 24
/// verts, face normals, indices (a,b,d / b,c,d) per face — CCW outward.
ThreeGeom boxGeometry(double w, double h, double d) {
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  // buildPlane(u, v, w, udir, vdir, depth) — depth>0 → normal +w axis.
  void plane(String u, String v, String ww, double udir, double vdir,
      double width, double height, double depth) {
    final start = pos.length ~/ 3;
    final wh = width / 2, hh = height / 2, dh = depth / 2;
    for (int iy = 0; iy <= 1; iy++) {
      final y = iy * height - hh;
      for (int ix = 0; ix <= 1; ix++) {
        final x = ix * width - wh;
        final p = Vector3.zero();
        _setAxis(p, u, x * udir);
        _setAxis(p, v, y * vdir);
        _setAxis(p, ww, dh);
        pos.add(p.x);
        pos.add(p.y);
        pos.add(p.z);
        final n = Vector3.zero();
        _setAxis(n, ww, depth > 0 ? 1.0 : -1.0);
        nor.add(n.x);
        nor.add(n.y);
        nor.add(n.z);
      }
    }
    // grid 1×1 → one segment: a=start+0, b=start+2, c=start+3, d=start+1
    final a = start;
    final b = start + 2;
    final c = start + 3;
    final dd = start + 1;
    idx.add(a);
    idx.add(b);
    idx.add(dd);
    idx.add(b);
    idx.add(c);
    idx.add(dd);
  }

  // Order + args copied from three.js BoxGeometry (the materialIndex is unused).
  plane('z', 'y', 'x', -1, -1, d, h, w); // px
  plane('z', 'y', 'x', 1, -1, d, h, -w); // nx
  plane('x', 'z', 'y', 1, 1, w, d, h); // py
  plane('x', 'z', 'y', 1, -1, w, d, -h); // ny
  plane('x', 'y', 'z', 1, -1, w, h, d); // pz
  plane('x', 'y', 'z', -1, -1, w, h, -d); // nz
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

void _setAxis(Vector3 v, String axis, double value) {
  switch (axis) {
    case 'x':
      v.x = value;
      break;
    case 'y':
      v.y = value;
      break;
    case 'z':
      v.z = value;
      break;
  }
}

/// Port of `THREE.PlaneGeometry(w, h, segX, segY)` — a grid in the XY plane
/// (z=0), normal +Z, indexed. Rotate/translate via the part matrix.
ThreeGeom planeGeometry(double w, double h, [int segX = 1, int segY = 1]) {
  final hw = w / 2, hh = h / 2;
  final sw = w / segX, sh = h / segY;
  final pos = <double>[], nor = <double>[], idx = <int>[];
  for (int iy = 0; iy <= segY; iy++) {
    for (int ix = 0; ix <= segX; ix++) {
      pos.add(ix * sw - hw);
      // three.js builds PlaneGeometry rows from top to bottom.  Keeping this
      // sign is important: with the index order below it makes the front face
      // point along +Z (and also matches the reference UV row orientation).
      pos.add(hh - iy * sh);
      pos.add(0.0);
      nor.addAll([0, 0, 1]);
    }
  }
  final row = segX + 1;
  for (int iy = 0; iy < segY; iy++) {
    for (int ix = 0; ix < segX; ix++) {
      final a = ix + row * iy;
      final b = ix + row * (iy + 1);
      final c = (ix + 1) + row * (iy + 1);
      final d = (ix + 1) + row * iy;
      idx.addAll([a, b, d, b, c, d]);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Triangular prism used for traditional gable-end boarding. The triangular
/// cross-section lies in XY and [depth] is centred on Z, matching the simple
/// non-bevelled `ExtrudeGeometry` used by the Three.js reference.
ThreeGeom triangularPrismGeometry(double width, double height, double depth) {
  final a0 = Vector3(-width / 2, 0, -depth / 2);
  final b0 = Vector3(width / 2, 0, -depth / 2);
  final c0 = Vector3(0, height, -depth / 2);
  final a1 = Vector3(-width / 2, 0, depth / 2);
  final b1 = Vector3(width / 2, 0, depth / 2);
  final c1 = Vector3(0, height, depth / 2);
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  void face(Vector3 a, Vector3 b, Vector3 c) {
    final n = (b - a).cross(c - a)..normalize();
    final start = pos.length ~/ 3;
    for (final v in [a, b, c]) {
      pos.addAll([v.x, v.y, v.z]);
      nor.addAll([n.x, n.y, n.z]);
    }
    idx.addAll([start, start + 1, start + 2]);
  }

  face(a0, c0, b0);
  face(a1, b1, c1);
  face(a0, b0, b1);
  face(a0, b1, a1);
  face(b0, c0, c1);
  face(b0, c1, b1);
  face(c0, a0, a1);
  face(c0, a1, c1);
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// A quad strip swept along z from [z0] to [z1]: at each step row, edge points
/// are [a(z)] and [b(z)] (each (x, y)). Port of street.js `makeStrip` (without
/// uvs — the cel material doesn't use them). Normals computed (smooth); for a
/// flat road strip they collapse to the up vector. [flip] reverses winding.
ThreeGeom stripGeometry(double z0, double z1, double step,
    Vector2 Function(double z) a, Vector2 Function(double z) b,
    {bool flip = false}) {
  final rows =
      (z1 - z0).abs() / step + 1 < 2 ? 2 : ((z1 - z0).abs() / step + 1).round();
  final pos = <double>[], nor = <double>[], idx = <int>[];
  for (int i = 0; i < rows; i++) {
    final t = i / (rows - 1);
    final z = z0 + (z1 - z0) * t;
    final pa = a(z), pb = b(z);
    pos.addAll([pa.x, pa.y, z, pb.x, pb.y, z]);
    nor.addAll([0, 0, 1, 0, 0, 1]);
  }
  for (int i = 0; i < rows - 1; i++) {
    final o = i * 2;
    if (flip) {
      idx.addAll([o, o + 1, o + 2, o + 1, o + 3, o + 2]);
    } else {
      idx.addAll([o, o + 2, o + 1, o + 1, o + 2, o + 3]);
    }
  }
  // Recompute smooth normals (matches three.js computeVertexNormals on the strip).
  final g = ThreeGeom(Float32List.fromList(pos), Float32List(0), idx);
  final n = computeNormals(g);
  return ThreeGeom(g.positions, n, g.indices);
}

/// Minimal port of `THREE.ExtrudeGeometry(shape, {depth})` (no bevel, no holes):
/// extrude a convex 2D polygon [shape] (CCW points) along +Z by [depth]. Front
/// and back faces are fan-triangulated (convex assumption — fine for gable
/// ends, arches, signs); side walls are one quad per edge with outward normals.
/// Rotate/translate via the part matrix (the gable end is rotated to face the
/// roof's long axis).
ThreeGeom extrudeGeometry(List<Vector2> shape, double depth) {
  final n = shape.length;
  final pos = <double>[], nor = <double>[], idx = <int>[];
  void vert(Vector2 p, double z, Vector3 nn) {
    pos.add(p.x);
    pos.add(p.y);
    pos.add(z);
    nor.add(nn.x);
    nor.add(nn.y);
    nor.add(nn.z);
  }

  // Front face (z = 0, normal +Z) and back face (z = depth, normal -Z), fan from
  // vertex 0.
  final frontStart = pos.length ~/ 3;
  for (final p in shape) {
    vert(p, 0, Vector3(0, 0, 1));
  }
  for (int i = 1; i < n - 1; i++) {
    idx.addAll([frontStart, frontStart + i, frontStart + i + 1]);
  }
  final backStart = pos.length ~/ 3;
  for (final p in shape) {
    vert(p, depth, Vector3(0, 0, -1));
  }
  for (int i = 1; i < n - 1; i++) {
    idx.addAll(
        [backStart, backStart + i + 1, backStart + i]); // reversed winding
  }

  // Side walls: one quad per polygon edge.
  for (int i = 0; i < n; i++) {
    final a = shape[i];
    final b = shape[(i + 1) % n];
    final edge = (b - a).normalized();
    final nn = Vector3(edge.y, -edge.x, 0); // outward (CCW polygon)
    final o = pos.length ~/ 3;
    vert(a, 0, nn);
    vert(b, 0, nn);
    vert(b, depth, nn);
    vert(a, depth, nn);
    idx.addAll([o, o + 1, o + 2, o, o + 2, o + 3]);
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

Float32List computeNormals(ThreeGeom g) {
  final n = Float32List(g.positions.length);
  final acc = List<double>.filled(g.vertexCount * 3, 0.0);
  Vector3 pv(int i) => Vector3(
      g.positions[i * 3], g.positions[i * 3 + 1], g.positions[i * 3 + 2]);
  for (int i = 0; i < g.indices.length; i += 3) {
    final ai = g.indices[i], bi = g.indices[i + 1], ci = g.indices[i + 2];
    final fn = (pv(bi) - pv(ai)).cross(pv(ci) - pv(ai));
    for (final k in [ai, bi, ci]) {
      acc[k * 3] += fn.x;
      acc[k * 3 + 1] += fn.y;
      acc[k * 3 + 2] += fn.z;
    }
  }
  for (int i = 0; i < acc.length; i += 3) {
    final v = Vector3(acc[i], acc[i + 1], acc[i + 2]);
    final l = v.length;
    final nn = l < 1e-12 ? Vector3(0, 1, 0) : v / l;
    n[i] = nn.x;
    n[i + 1] = nn.y;
    n[i + 2] = nn.z;
  }
  return n;
}

/// Exact port of `THREE.CylinderGeometry(rt, rb, h, radialSegments)` with
/// heightSegments=1, optional [thetaStart]/[thetaLength] (partial cylinders)
/// and caps (unless [openEnded]). `THREE.ConeGeometry(r, h, seg, _, open)` is
/// `cylGeometry(0, r, h, seg, openEnded: open)`. Caps are only emitted for full
/// (2π) cylinders; partial cylinders are rare and use openEnded.
ThreeGeom cylGeometry(double rt, double rb, double h, int radialSegments,
    {bool openEnded = false,
    double thetaStart = 0.0,
    double thetaLength = -1.0}) {
  if (thetaLength < 0) thetaLength = math.pi * 2;
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  final half = h / 2;
  final slope = (rb - rt) / h;

  // Torso: 2 rows × (radialSegments+1) verts.
  final rows = <List<int>>[];
  for (int y = 0; y <= 1; y++) {
    final v = y.toDouble();
    final radius = v * (rb - rt) + rt;
    final row = <int>[];
    for (int x = 0; x <= radialSegments; x++) {
      final u = x / radialSegments;
      final theta = u * thetaLength + thetaStart;
      final st = math.sin(theta), ct = math.cos(theta);
      pos.add(radius * st);
      pos.add(-v * h + half);
      pos.add(radius * ct);
      final n = Vector3(st, slope, ct)..normalize();
      nor.add(n.x);
      nor.add(n.y);
      nor.add(n.z);
      row.add(pos.length ~/ 3 - 1);
    }
    rows.add(row);
  }
  for (int x = 0; x < radialSegments; x++) {
    final a = rows[0][x],
        b = rows[1][x],
        c = rows[1][x + 1],
        dd = rows[0][x + 1];
    if (rt > 0) {
      idx.add(a);
      idx.add(b);
      idx.add(dd);
    }
    if (rb > 0) {
      idx.add(b);
      idx.add(c);
      idx.add(dd);
    }
  }

  void cap(bool top) {
    final radius = top ? rt : rb;
    final sign = top ? 1.0 : -1.0;
    final centerStart = pos.length ~/ 3;
    for (int x = 1; x <= radialSegments; x++) {
      pos.add(0);
      pos.add(half * sign);
      pos.add(0);
      nor.add(0);
      nor.add(sign);
      nor.add(0);
    }
    final centerEnd = pos.length ~/ 3;
    for (int x = 0; x <= radialSegments; x++) {
      final u = x / radialSegments;
      final theta = u * thetaLength + thetaStart;
      final st = math.sin(theta), ct = math.cos(theta);
      pos.add(radius * st);
      pos.add(half * sign);
      pos.add(radius * ct);
      nor.add(0);
      nor.add(sign);
      nor.add(0);
    }
    for (int x = 0; x < radialSegments; x++) {
      final center = centerStart + x;
      final ring = centerEnd + x;
      if (top) {
        idx.add(ring);
        idx.add(ring + 1);
        idx.add(center);
      } else {
        idx.add(ring + 1);
        idx.add(ring);
        idx.add(center);
      }
    }
  }

  // Caps only for full cylinders (partial-cylinder caps would be pie slices;
  // rare and always openEnded in the world modules).
  final full = thetaLength >= math.pi * 2 * 0.999;
  if (full && !openEnded && rt > 0) cap(true);
  if (full && !openEnded && rb > 0) cap(false);
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Transform a geometry by [m]: positions by the full matrix, normals by the
/// rotation (scale-tolerant — cel normalises). Returns a new ThreeGeom.
ThreeGeom applyMatrix(ThreeGeom g, Matrix4 m) {
  final p = Float32List(g.positions.length);
  final n = Float32List(g.normals.length);
  final rot = m.clone()..setTranslationRaw(0, 0, 0);
  // Drop any scale from the normal transform (normalize later anyway): scale a
  // basis vector, measure length, divide. Uniform scale cancels; non-uniform is
  // approximated (rare in the world modules — mostly pure translation/rotation).
  for (int i = 0; i < g.positions.length; i += 3) {
    final v = m.transformed3(
        Vector3(g.positions[i], g.positions[i + 1], g.positions[i + 2]));
    p[i] = v.x;
    p[i + 1] = v.y;
    p[i + 2] = v.z;
    final nv = rot
        .transformed3(Vector3(g.normals[i], g.normals[i + 1], g.normals[i + 2]))
      ..normalize();
    n[i] = nv.x;
    n[i + 1] = nv.y;
    n[i + 2] = nv.z;
  }
  return ThreeGeom(p, n, List<int>.from(g.indices));
}

// ─────────────────────────────────────────────────────────────────────────────
// Parts + bake — mirrors util.js `bake(parts)`: each part is a {geometry, matrix,
// material}; bake applies the matrix and merges into one triangle soup (per-part
// material carried through).
// ─────────────────────────────────────────────────────────────────────────────

/// Material description for a part (mirrors the `cel({color, bands, tint})` /
/// `flat({color})` literals from toon.js). [flat] matches the reference's
/// `flatShading` (cel default true): when true the face normal is used (faceted
/// blobs, boxes); when false the geometry's per-vertex (smooth) normal is used.
class Mat {
  const Mat(this.color,
      {this.tint = 0x6c5f8c,
      this.bands = '3',
      this.unlit = false,
      this.flat = true,
      this.noOutline = false,
      this.receiveShadow = true});
  final int color;
  final int tint;
  final String bands;
  final bool unlit;
  final bool flat;
  final bool noOutline;
  final bool receiveShadow;
}

/// One transformed, material-tagged piece of geometry (a `bake` input).
class Part {
  Part(this.geo, this.matrix, this.mat, {this.planetRigid = false});
  final ThreeGeom geo;
  final Matrix4 matrix;
  final Mat mat;
  final bool planetRigid;
}

/// A world-space triangle with its face normal and material — the bake output,
/// directly diffable against the reference extraction.
class Tri {
  Tri(this.a, this.b, this.c, this.normal, this.mat,
      {this.uvA, this.uvB, this.uvC, this.rigidPivot});
  final Vector3 a, b, c, normal;
  final Mat mat;
  final Vector2? uvA, uvB, uvC;
  final Vector3? rigidPivot;
  bool get mapped => uvA != null && uvB != null && uvC != null;
  Vector3 get centroid => (a + b + c) * (1 / 3);
}

/// A unit-sphere icosahedron of the given [detail] (0 = 20 faces, 1 = 80, …),
/// scaled to [radius]. Matches the shape of `THREE.IcosahedronGeometry` (12 base
/// verts + midpoint subdivision normalised to the sphere). Per-vertex normals
/// are the sphere normal (= the unit vertex); flat-shaded mats recompute face
/// normals in `bake`, so for canopies the per-vertex normal is unused.
ThreeGeom icosahedronGeometry(double radius, int detail) {
  final t = (1 + math.sqrt(5)) / 2;
  final verts = <Vector3>[
    Vector3(-1, t, 0),
    Vector3(1, t, 0),
    Vector3(-1, -t, 0),
    Vector3(1, -t, 0),
    Vector3(0, -1, t),
    Vector3(0, 1, t),
    Vector3(0, -1, -t),
    Vector3(0, 1, -t),
    Vector3(t, 0, -1),
    Vector3(t, 0, 1),
    Vector3(-t, 0, -1),
    Vector3(-t, 0, 1),
  ].map((v) => v.normalized()).toList();
  var faces = <List<int>>[
    [0, 11, 5],
    [0, 5, 1],
    [0, 1, 7],
    [0, 7, 10],
    [0, 10, 11],
    [1, 5, 9],
    [5, 11, 4],
    [11, 10, 2],
    [10, 7, 6],
    [7, 1, 8],
    [3, 9, 4],
    [3, 4, 2],
    [3, 2, 6],
    [3, 6, 8],
    [3, 8, 9],
    [4, 9, 5],
    [2, 4, 11],
    [6, 2, 10],
    [8, 6, 7],
    [9, 8, 1],
  ];
  for (int d = 0; d < detail; d++) {
    final mid = <int, int>{};
    int midpoint(int a, int b) {
      final key = a < b ? a * 1000003 + b : b * 1000003 + a;
      final cached = mid[key];
      if (cached != null) return cached;
      verts.add(((verts[a] + verts[b]) * 0.5).normalized());
      final idx = verts.length - 1;
      mid[key] = idx;
      return idx;
    }

    final next = <List<int>>[];
    for (final f in faces) {
      final a = f[0], b = f[1], c = f[2];
      final ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a);
      next.add([a, ab, ca]);
      next.add([b, bc, ab]);
      next.add([c, ca, bc]);
      next.add([ab, bc, ca]);
    }
    faces = next;
  }
  // Non-indexed with flat per-vertex normals (each face's 3 verts share the
  // face normal) — matches what three.js's flatShading renders for the canopy
  // blobs, so bake's per-vertex normal is the faceted cel normal.
  final pos = <double>[], nor = <double>[];
  for (final f in faces) {
    final a = verts[f[0]], b = verts[f[1]], c = verts[f[2]];
    var n = (b - a).cross(c - a);
    final l = n.length;
    n = l < 1e-9 ? Vector3(0, 1, 0) : n / l;
    if (n.dot(a) < 0) n = -n; // ensure outward
    for (final v in [a, b, c]) {
      pos.add(v.x * radius);
      pos.add(v.y * radius);
      pos.add(v.z * radius);
      nor.add(n.x);
      nor.add(n.y);
      nor.add(n.z);
    }
  }
  final idx = List<int>.generate(faces.length * 3, (i) => i);
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Exact detail-0 topology of `THREE.DodecahedronGeometry`.
ThreeGeom dodecahedronGeometry(double radius) {
  final t = (1 + math.sqrt(5)) / 2;
  final r = 1 / t;
  final vertices = <Vector3>[
    Vector3(-1, -1, -1),
    Vector3(-1, -1, 1),
    Vector3(-1, 1, -1),
    Vector3(-1, 1, 1),
    Vector3(1, -1, -1),
    Vector3(1, -1, 1),
    Vector3(1, 1, -1),
    Vector3(1, 1, 1),
    Vector3(0, -r, -t),
    Vector3(0, -r, t),
    Vector3(0, r, -t),
    Vector3(0, r, t),
    Vector3(-r, -t, 0),
    Vector3(-r, t, 0),
    Vector3(r, -t, 0),
    Vector3(r, t, 0),
    Vector3(-t, 0, -r),
    Vector3(t, 0, -r),
    Vector3(-t, 0, r),
    Vector3(t, 0, r),
  ].map((v) => v.normalized() * radius).toList();
  const indices = <int>[
    3,
    11,
    7,
    3,
    7,
    15,
    3,
    15,
    13,
    7,
    19,
    17,
    7,
    17,
    6,
    7,
    6,
    15,
    17,
    4,
    8,
    17,
    8,
    10,
    17,
    10,
    6,
    8,
    0,
    16,
    8,
    16,
    2,
    8,
    2,
    10,
    0,
    12,
    1,
    0,
    1,
    18,
    0,
    18,
    16,
    6,
    10,
    2,
    6,
    2,
    13,
    6,
    13,
    15,
    2,
    16,
    18,
    2,
    18,
    3,
    2,
    3,
    13,
    18,
    1,
    9,
    18,
    9,
    11,
    18,
    11,
    3,
    4,
    14,
    12,
    4,
    12,
    0,
    4,
    0,
    8,
    11,
    9,
    5,
    11,
    5,
    19,
    11,
    19,
    7,
    19,
    5,
    14,
    19,
    14,
    4,
    19,
    4,
    17,
    1,
    12,
    14,
    1,
    14,
    5,
    1,
    5,
    9,
  ];
  final pos = <double>[];
  final nor = <double>[];
  for (var i = 0; i < indices.length; i += 3) {
    final a = vertices[indices[i]];
    final b = vertices[indices[i + 1]];
    final c = vertices[indices[i + 2]];
    final n = (b - a).cross(c - a)..normalize();
    for (final v in [a, b, c]) {
      pos.addAll([v.x, v.y, v.z]);
      nor.addAll([n.x, n.y, n.z]);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor),
      List<int>.generate(indices.length, (i) => i));
}

/// Exact topology and vertex convention of `THREE.SphereGeometry` for the
/// full-sphere case used by small authored props such as kokeshi heads.
ThreeGeom sphereGeometry(double radius, int widthSegments, int heightSegments) {
  widthSegments = math.max(3, widthSegments);
  heightSegments = math.max(2, heightSegments);
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  final grid = <List<int>>[];
  var index = 0;
  for (var iy = 0; iy <= heightSegments; iy++) {
    final row = <int>[];
    final v = iy / heightSegments;
    for (var ix = 0; ix <= widthSegments; ix++) {
      final u = ix / widthSegments;
      final phi = u * math.pi * 2;
      final theta = v * math.pi;
      final x = -radius * math.cos(phi) * math.sin(theta);
      final y = radius * math.cos(theta);
      final z = radius * math.sin(phi) * math.sin(theta);
      pos.addAll([x, y, z]);
      final n = Vector3(x, y, z)..normalize();
      nor.addAll([n.x, n.y, n.z]);
      row.add(index++);
    }
    grid.add(row);
  }
  for (var iy = 0; iy < heightSegments; iy++) {
    for (var ix = 0; ix < widthSegments; ix++) {
      final a = grid[iy][ix + 1];
      final b = grid[iy][ix];
      final c = grid[iy + 1][ix];
      final d = grid[iy + 1][ix + 1];
      if (iy != 0) idx.addAll([a, b, d]);
      if (iy != heightSegments - 1) idx.addAll([b, c, d]);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

/// Port of `THREE.TorusGeometry`, including its indexed grid topology.
ThreeGeom torusGeometry(double radius, double tube, int radialSegments,
    int tubularSegments, double arc) {
  radialSegments = math.max(3, radialSegments);
  tubularSegments = math.max(3, tubularSegments);
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  for (var j = 0; j <= radialSegments; j++) {
    for (var i = 0; i <= tubularSegments; i++) {
      final u = i / tubularSegments * arc;
      final v = j / radialSegments * math.pi * 2;
      final cv = math.cos(v), sv = math.sin(v);
      final cu = math.cos(u), su = math.sin(u);
      final x = (radius + tube * cv) * cu;
      final y = (radius + tube * cv) * su;
      final z = tube * sv;
      pos.addAll([x, y, z]);
      final n = Vector3(cv * cu, cv * su, sv)..normalize();
      nor.addAll([n.x, n.y, n.z]);
    }
  }
  final row = tubularSegments + 1;
  for (var j = 1; j <= radialSegments; j++) {
    for (var i = 1; i <= tubularSegments; i++) {
      final a = row * j + i - 1;
      final b = row * (j - 1) + i - 1;
      final c = row * (j - 1) + i;
      final d = row * j + i;
      idx.addAll([a, b, d, b, c, d]);
    }
  }
  return ThreeGeom(Float32List.fromList(pos), Float32List.fromList(nor), idx);
}

// ─────────────────────────────────────────────────────────────────────────────
// Quaternion + compose helpers — used by modules that orient parts (tree limbs,
// signs, etc.) via `Quaternion.setFromUnitVectors` + `Matrix4.compose`.
// ─────────────────────────────────────────────────────────────────────────────

/// Quaternion from an XYZ Euler (three.js Euler default order), for rotating a
/// vector the same way `trs`'s rotation does.
Quaternion quatFromEulerXyz(double rx, double ry, double rz) {
  final c1 = math.cos(rx / 2), s1 = math.sin(rx / 2);
  final c2 = math.cos(ry / 2), s2 = math.sin(ry / 2);
  final c3 = math.cos(rz / 2), s3 = math.sin(rz / 2);
  return Quaternion(
    s1 * c2 * c3 + c1 * s2 * s3,
    c1 * s2 * c3 - s1 * c2 * s3,
    c1 * c2 * s3 + s1 * s2 * c3,
    c1 * c2 * c3 - s1 * s2 * s3,
  );
}

Matrix4 _rotationMatrix(double qx, double qy, double qz, double qw) {
  final xx = 2 * qx * qx, yy = 2 * qy * qy, zz = 2 * qz * qz;
  final tx = 2 * qx * qy, ty = 2 * qy * qz, tz = 2 * qz * qx;
  final r = Matrix4.zero();
  r.setValues(
    1 - yy - zz,
    tx + 2 * qw * qz,
    tz - 2 * qw * qy,
    0,
    tx - 2 * qw * qz,
    1 - xx - zz,
    ty + 2 * qw * qx,
    0,
    tz + 2 * qw * qy,
    ty - 2 * qw * qx,
    1 - xx - yy,
    0,
    0,
    0,
    0,
    1,
  );
  return r;
}

/// Compose a Matrix4 from translation, quaternion rotation, and scale — the
/// `THREE.Matrix4().compose(pos, quat, scale)` equivalent.
Matrix4 composePRS(Vector3 p, Quaternion q, Vector3 s) =>
    Matrix4.translation(p) *
    _rotationMatrix(q.x, q.y, q.z, q.w) *
    Matrix4.diagonal3(s);

/// Port of `THREE.Quaternion.setFromUnitVectors(from, to)` — the rotation that
/// takes [from] to [to] (both treated as unit vectors; they're normalised).
Quaternion quatFromUnitVectors(Vector3 from, Vector3 to) {
  final a = from.normalized();
  final b = to.normalized();
  double r = a.dot(b) + 1;
  double x, y, z;
  if (r < 1e-6) {
    // Opposite directions: rotate 180° about an axis perpendicular to `from`.
    r = 0;
    if (a.x.abs() > a.z.abs()) {
      x = -a.y;
      y = a.x;
      z = 0;
    } else {
      x = 0;
      y = -a.z;
      z = a.y;
    }
  } else {
    final ax = a.cross(b);
    x = ax.x;
    y = ax.y;
    z = ax.z;
  }
  return Quaternion(x, y, z, r)..normalize();
}

/// Apply each part's matrix and concatenate into one triangle list. Uses the
/// geometry's per-vertex normal at vertex 0 — every generator emits flat
/// per-vertex normals (boxes/cylinders natively; the icosahedron is built
/// non-indexed with face normals), so this is the flat face normal three.js's
/// flat shading renders.
List<Tri> bake(Iterable<Part> parts) {
  final tris = <Tri>[];
  for (final p in parts) {
    final g = applyMatrix(p.geo, p.matrix);
    final rigidPivot = p.planetRigid ? p.matrix.getTranslation() : null;
    for (int i = 0; i < g.indices.length; i += 3) {
      final ai = g.indices[i], bi = g.indices[i + 1], ci = g.indices[i + 2];
      final a = Vector3(g.positions[ai * 3], g.positions[ai * 3 + 1],
          g.positions[ai * 3 + 2]);
      final b = Vector3(g.positions[bi * 3], g.positions[bi * 3 + 1],
          g.positions[bi * 3 + 2]);
      final c = Vector3(g.positions[ci * 3], g.positions[ci * 3 + 1],
          g.positions[ci * 3 + 2]);
      final n = Vector3(
          g.normals[ai * 3], g.normals[ai * 3 + 1], g.normals[ai * 3 + 2]);
      tris.add(Tri(a, b, c, n, p.mat, rigidPivot: rigidPivot));
    }
  }
  return tris;
}
