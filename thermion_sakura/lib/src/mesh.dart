/// A face-accumulating geometry builder that bakes cel shading into per-vertex
/// colours. Faces are authored in world space and every face is flat-shaded
/// (one cel band per face), mirroring the reference's flat-shaded
/// MeshToonMaterial look. The whole static world bakes into a handful of these.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:thermion_dart/thermion_dart.dart';
import 'package:vector_math/vector_math_64.dart';

import 'cel.dart';
import 'palette.dart';

/// A disc-shaped baked cast shadow on the ground (from a tree canopy, etc.).
class ShadowDisc {
  const ShadowDisc(this.x, this.z, this.r);
  final double x, z, r;
}

/// An axis-aligned box that casts a shadow.
class ShadowBox {
  const ShadowBox(this.cx, this.cy, this.cz, this.hx, this.hy, this.hz);
  final double cx, cy, cz, hx, hy, hz;
}

/// A sphere that casts a shadow (a tree canopy, a shrub).
class ShadowSphere {
  const ShadowSphere(this.x, this.y, this.z, this.r);
  final double x, y, z, r;
}

/// Ray-traced sun-visibility test: is a point occluded on its way to the sun?
/// Replaces the old flat [ShadowDisc] map with real per-face cast shadows
/// (buildings, the train, tree canopies), which is what gives the reference
/// its deep violet shadows, contrast and vibrance.
class ShadowScene {
  ShadowScene({this.maxDist = 90.0});
  final List<ShadowBox> boxes = [];
  final List<ShadowSphere> spheres = [];
  final double maxDist;

  /// True if the ray from [p] along [sunDir] (pointing toward the sun) hits a
  /// caster within [maxDist]. [eps] offsets the origin off the surface.
  bool occludes(Vector3 p, Vector3 sunDir, {double eps = 0.05}) {
    final ox = p.x + sunDir.x * eps, oy = p.y + sunDir.y * eps, oz = p.z + sunDir.z * eps;
    final dx = sunDir.x, dy = sunDir.y, dz = sunDir.z;
    for (final b in boxes) {
      if (_hitBox(ox, oy, oz, dx, dy, dz, b)) return true;
    }
    for (final s in spheres) {
      if (_hitSphere(ox, oy, oz, dx, dy, dz, s)) return true;
    }
    return false;
  }

  bool _hitBox(double ox, double oy, double oz, double dx, double dy, double dz, ShadowBox b) {
    // slab method; ray direction is unit-length (sunDir is normalised)
    double tmin = 0.0, tmax = maxDist;
    // X
    double t1, t2;
    final invx = dx.abs() < 1e-9 ? 1e18 : 1.0 / dx;
    t1 = (b.cx - b.hx - ox) * invx;
    t2 = (b.cx + b.hx - ox) * invx;
    if (invx < 0) { final tmp = t1; t1 = t2; t2 = tmp; }
    if (t1 > tmin) tmin = t1;
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return false;
    // Y
    final invy = dy.abs() < 1e-9 ? 1e18 : 1.0 / dy;
    t1 = (b.cy - b.hy - oy) * invy;
    t2 = (b.cy + b.hy - oy) * invy;
    if (invy < 0) { final tmp = t1; t1 = t2; t2 = tmp; }
    if (t1 > tmin) tmin = t1;
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return false;
    // Z
    final invz = dz.abs() < 1e-9 ? 1e18 : 1.0 / dz;
    t1 = (b.cz - b.hz - oz) * invz;
    t2 = (b.cz + b.hz - oz) * invz;
    if (invz < 0) { final tmp = t1; t1 = t2; t2 = tmp; }
    if (t1 > tmin) tmin = t1;
    if (t2 < tmax) tmax = t2;
    return tmin <= tmax && tmax > 0;
  }

  bool _hitSphere(double ox, double oy, double oz, double dx, double dy, double dz, ShadowSphere s) {
    final ex = ox - s.x, ey = oy - s.y, ez = oz - s.z;
    final b = ex * dx + ey * dy + ez * dz; // half-b (dir unit)
    final c = ex * ex + ey * ey + ez * ez - s.r * s.r;
    final disc = b * b - c;
    if (disc < 0) return false;
    final t = -b - math.sqrt(disc);
    return t < maxDist && t > 0;
  }
}

/// Tests ground points against the world's baked cast shadows.
class ShadowMap {
  ShadowMap(this.discs);
  final List<ShadowDisc> discs;
  bool hit(double x, double z) {
    for (final d in discs) {
      final dx = x - d.x, dz = z - d.z;
      if (dx * dx + dz * dz < d.r * d.r) return true;
    }
    return false;
  }
}

class Mesh {
  Mesh(this.cel);
  final CelShader cel;

  final List<double> _pos = [];
  final List<double> _nrm = [];
  final List<double> _col = [];
  /// Raw LINEAR albedo per vertex (the surface's base colour BEFORE cel
  /// baking, fog or shadow). Populated alongside [_col] so a realtime lit
  /// path can fetch plain albedo + flat normals without any baked lighting.
  final List<double> _alb = [];
  final List<int> _idx = [];
  int _v = 0;

  int get vertexCount => _v;
  int get indexCount => _idx.length;

  /// Raw positions (xyz triples), normals, RGBA colours and indices — consumed
  /// by the GLB encoder.
  List<double> get positions => _pos;
  List<double> get normals => _nrm;
  List<double> get colors => _col;
  List<int> get indices => _idx;

  /// The world's baked cast shadows, consulted for ground faces.
  ShadowMap? shadows;

  /// Ray-traced cast-shadow scene (buildings + tree canopies). When set, each
  /// cel face is shadowed by a sun-visibility ray test — real per-face cast
  /// shadows rather than the flat [shadows] disc map.
  ShadowScene? shadowScene;

  /// Baked distance fog (reference: THREE.Fog(PAL.fog, 44, 205)). Applied to
  /// cel-shaded faces by their centre distance from [fogOrigin]; raw-colour
  /// faces (sky, clouds, hills) are exempt, like the reference's fog:false.
  final Vector3 fogOrigin = Vector3(1.85, 1.62, 13.6);
  static const double fogNear = 44;
  static const double fogFar = 205;

  double _fogAt(Vector3 center) {
    final d = (center - fogOrigin).length;
    if (d <= fogNear) return 0;
    if (d >= fogFar) return 1;
    final t = (d - fogNear) / (fogFar - fogNear);
    return t * t * (3 - 2 * t);
  }

  /// Per-face sun shadow: ray-trace the face centre toward the sun.
  bool _shadowed(Vector3 center, Vector3 n, bool hint) {
    if (hint) return true;
    final ss = shadowScene;
    if (ss == null) return false;
    return ss.occludes(center, cel.sunDir);
  }

  /// A quad given as four CCW world-space corners. [normal] overrides the
  /// computed face normal (useful for billboards / forced shading).
  void quad(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d, {
    required int color,
    int tint = 0x6c5f8c,
    String bands = '3',
    Vector3? normal,
    bool inShadow = false,
    double? fog,
  }) {
    final n = normal ?? _faceNormal(a, b, c);
    final center = (a + b + c + d) * 0.25;
    inShadow = _shadowed(center, n, inShadow || _inShadow(a, b, c, d));
    fog ??= _fogAt(center);
    _emit(a, n, color, tint, bands, inShadow: inShadow, fog: fog);
    _emit(b, n, color, tint, bands, inShadow: inShadow, fog: fog);
    _emit(c, n, color, tint, bands, inShadow: inShadow, fog: fog);
    _emit(d, n, color, tint, bands, inShadow: inShadow, fog: fog);
    final o = _v - 4;
    _idx.addAll([o, o + 1, o + 2, o, o + 2, o + 3]);
  }

  /// A single triangle.
  void tri(
    Vector3 a,
    Vector3 b,
    Vector3 c, {
    required int color,
    int tint = 0x6c5f8c,
    String bands = '3',
    Vector3? normal,
  }) {
    final n = normal ?? _faceNormal(a, b, c);
    final center = (a + b + c) * (1 / 3);
    final inShadow = _shadowed(center, n, false);
    final fog = _fogAt(center);
    _emit(a, n, color, tint, bands, inShadow: inShadow, fog: fog);
    _emit(b, n, color, tint, bands, inShadow: inShadow, fog: fog);
    _emit(c, n, color, tint, bands, inShadow: inShadow, fog: fog);
    final o = _v - 3;
    _idx.addAll([o, o + 1, o + 2]);
  }

  bool _inShadow(Vector3 a, Vector3 b, Vector3 c, Vector3 d) {
    final s = shadows;
    if (s == null || s.discs.isEmpty) return false;
    final cx = (a.x + b.x + c.x + d.x) * 0.25;
    final cz = (a.z + b.z + c.z + d.z) * 0.25;
    return s.hit(cx, cz);
  }

  /// Unlit quad with an exact display-space colour (no cel baking) — for
  /// accent panels, road markings, petals. The colour is sRGB-intent and is
  /// converted to linear here so it rides the linear pipeline.
  void quadRaw(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d,
    Vector3 srgb, {
    Vector3? normal,
  }) {
    final n = normal ?? _faceNormal(a, b, c);
    _emitRaw(a, n, srgb);
    _emitRaw(b, n, srgb);
    _emitRaw(c, n, srgb);
    _emitRaw(d, n, srgb);
    final o = _v - 4;
    _idx.addAll([o, o + 1, o + 2, o, o + 2, o + 3]);
  }

  /// Unlit quad whose colour is already LINEAR (the painted sky, clouds and
  /// hills mix their palette in linear space, like the reference shader).
  void quadRawLin(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d,
    Vector3 lin, {
    Vector3? normal,
  }) =>
      quadRawLinColors(a, b, c, d, [lin, lin, lin, lin], normal: normal);

  /// Unlit quad with a LINEAR colour PER VERTEX — the GPU interpolates
  /// between the corners (used for the cloud puff pattern, whose soft edges
  /// need smooth alpha falloff the way the reference's bilinear-filtered
  /// cloud texture has).
  void quadRawLinColors(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Vector3 d,
    List<Vector3> colors, {
    Vector3? normal,
  }) {
    final n = normal ?? _faceNormal(a, b, c);
    _emitRawLin(a, n, colors[0]);
    _emitRawLin(b, n, colors[1]);
    _emitRawLin(c, n, colors[2]);
    _emitRawLin(d, n, colors[3]);
    final o = _v - 4;
    _idx.addAll([o, o + 1, o + 2, o, o + 2, o + 3]);
  }

  /// Unlit triangle with an exact display-space colour.
  void triRaw(Vector3 a, Vector3 b, Vector3 c, Vector3 srgb, {Vector3? normal}) {
    final n = normal ?? _faceNormal(a, b, c);
    _emitRaw(a, n, srgb);
    _emitRaw(b, n, srgb);
    _emitRaw(c, n, srgb);
    final o = _v - 3;
    _idx.addAll([o, o + 1, o + 2]);
  }

  void _emitRaw(Vector3 p, Vector3 n, Vector3 c) {
    _pos.addAll([p.x, p.y, p.z]);
    _nrm.addAll([n.x, n.y, n.z]);
    // raw colours arrive as sRGB-intent (the intended display hex); bake LINEAR
    // so they ride the same linear pipeline as the cel-baked faces.
    final lin = C.fromSrgb(c);
    _col.addAll([lin.x, lin.y, lin.z, 1.0]);
    // alpha=1 marks this as an UNLIT accent face (road markings, petals): the
    // realtime toon material passes raw colour through with no cel/shadow.
    _alb.addAll([lin.x, lin.y, lin.z, 1.0]);
    _v++;
  }

  void _emitRawLin(Vector3 p, Vector3 n, Vector3 c) {
    _pos.addAll([p.x, p.y, p.z]);
    _nrm.addAll([n.x, n.y, n.z]);
    _col.addAll([c.x, c.y, c.z, 1.0]);
    _alb.addAll([c.x, c.y, c.z, 1.0]); // alpha=1 = unlit accent
    _v++;
  }

  void _emit(Vector3 p, Vector3 n, int color, int tint, String bands,
      {bool inShadow = false, double fog = 0}) {
    _pos.addAll([p.x, p.y, p.z]);
    _nrm.addAll([n.x, n.y, n.z]);
    // raw LINEAR albedo (base colour, no cel/fog/shadow) for the realtime path.
    // alpha=0 marks this as a LIT cel face (the toon material cel-shades it).
    final alb = C.lin(color);
    _alb.addAll([alb.x, alb.y, alb.z, 0.0]);
    // cel lit colour in LINEAR space — matches the reference's linear rtScene,
    // so the depth-ink + grade passes see exactly what the reference's do.
    final lit = cel.shade(color, n, tint: tint, bands: bands, inShadow: inShadow);
    if (fog > 0.001) {
      // Fog blends in LINEAR, like three.js (THREE.Fog mixes before encoding).
      final f = C.lin(Pal.fog);
      lit.x = lit.x * (1 - fog) + f.x * fog;
      lit.y = lit.y * (1 - fog) + f.y * fog;
      lit.z = lit.z * (1 - fog) + f.z * fog;
    }
    _col.addAll([lit.x, lit.y, lit.z, 1.0]);
    _v++;
  }

  /// The reference's split-tone grade (cool violet darks, warm paper lights,
  /// afternoon warmth, shadow lift, gentle saturation). Applied in linear
  /// space by [gradeCel]/[gradeRaw]; kept here as the faithful port.
  static final Vector3 _shadowTint = C.lin(0xada8d0);
  static final Vector3 _lightTint = C.lin(0xfff7e8);
  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  Vector3 _grade(Vector3 c) {
    final l = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;
    final k = _smoothstep(0.02, 0.55, l);
    c = Vector3(
      c.x * (_shadowTint.x * (1 - k) + _lightTint.x * k),
      c.y * (_shadowTint.y * (1 - k) + _lightTint.y * k),
      c.z * (_shadowTint.z * (1 - k) + _lightTint.z * k),
    );
    c.x += 0.05 * l * 0.35;
    c.y += 0.05 * 0.45 * l * 0.35;
    final lift = 0.032 * (1 - k);
    c.x += lift; c.y += lift; c.z += lift;
    return Vector3(
      l + (c.x - l) * 1.12,
      l + (c.y - l) * 1.12,
      l + (c.z - l) * 1.12,
    );
  }

  static Vector3 _faceNormal(Vector3 a, Vector3 b, Vector3 c) {
    final e1 = b - a;
    final e2 = c - a;
    final n = e1.cross(e2);
    final len = n.length;
    if (len < 1e-9) return Vector3(0, 1, 0);
    return n / len;
  }

  /// Axis-aligned box centred at [center], size (w,h,d). The whole box falls
  /// into a baked cast shadow if its centre does (buildings, the crossing deck
  /// and other standing geometry pick up tree shadows this way).
  void box(
    double w,
    double h,
    double d,
    int color, {
    Vector3? center,
    int tint = 0x6c5f8c,
    String bands = '3',
  }) {
    final c = center ?? Vector3.zero();
    final inShadow = _inShadow(c - Vector3(w * 0.5, 0, d * 0.5),
        c + Vector3(w * 0.5, 0, d * 0.5),
        c + Vector3(w * 0.5, 0, -d * 0.5),
        c - Vector3(w * 0.5, 0, -d * 0.5));
    final fog = _fogAt(c);
    final hx = w * 0.5, hy = h * 0.5, hz = d * 0.5;
    // 8 corners
    final p000 = Vector3(c.x - hx, c.y - hy, c.z - hz);
    final p100 = Vector3(c.x + hx, c.y - hy, c.z - hz);
    final p110 = Vector3(c.x + hx, c.y + hy, c.z - hz);
    final p010 = Vector3(c.x - hx, c.y + hy, c.z - hz);
    final p001 = Vector3(c.x - hx, c.y - hy, c.z + hz);
    final p101 = Vector3(c.x + hx, c.y - hy, c.z + hz);
    final p111 = Vector3(c.x + hx, c.y + hy, c.z + hz);
    final p011 = Vector3(c.x - hx, c.y + hy, c.z + hz);
    // Faces wound CCW viewed from outside, so _faceNormal points outward.
    // (Earlier winding was reversed, which shaded every wall as if it faced
    // away from the camera — dim, wrongly-tinted buildings and a dim train.)
    // +x face
    quad(p110, p111, p101, p100, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
    // -x face
    quad(p011, p010, p000, p001, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
    // +y face (top)
    quad(p011, p111, p110, p010, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
    // -y face (bottom)
    quad(p100, p101, p001, p000, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
    // +z face
    quad(p001, p101, p111, p011, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
    // -z face
    quad(p010, p110, p100, p000, color: color, tint: tint, bands: bands, inShadow: inShadow, fog: fog);
  }

  /// Box centred at (x,y,z).
  void boxAt(
    double w,
    double h,
    double d,
    int color,
    double x,
    double y,
    double z, {
    int tint = 0x6c5f8c,
    String bands = '3',
  }) =>
      box(w, h, d, color, center: Vector3(x, y, z), tint: tint, bands: bands);

  /// Convenience: an axis-aligned box whose origin sits at the centre of its
  /// base (matches the reference `boxOnGround`).
  void boxOnGround(
    double w,
    double h,
    double d,
    int color,
    double x,
    double y,
    double z, {
    int tint = 0x6c5f8c,
    String bands = '3',
  }) =>
      box(w, h, d, color, center: Vector3(x, y + h * 0.5, z), tint: tint, bands: bands);

  /// A vertical billboard quad (faces +Y up, oriented around Y by [yaw]) of the
  /// given width/height, centred at [center], used for clouds and tree canopies.
  void billboardY(
    Vector3 center,
    double w,
    double h,
    double yaw, {
    required int color,
    int tint = 0x6c5f8c,
    String bands = 'soft',
    Vector3? normal,
  }) {
    final cs = math.cos(yaw);
    final sn = math.sin(yaw);
    final hw = w * 0.5;
    // quad in the XY plane rotated about Y, then offset; face normal ~= -Z rot
    final n = normal ?? Vector3(sn, 0, cs);
    final cx = center.x, cy = center.y, cz = center.z;
    quad(
      Vector3(cx - cs * hw, cy - h * 0.5, cz + sn * hw),
      Vector3(cx + cs * hw, cy - h * 0.5, cz - sn * hw),
      Vector3(cx + cs * hw, cy + h * 0.5, cz - sn * hw),
      Vector3(cx - cs * hw, cy + h * 0.5, cz + sn * hw),
      color: color,
      tint: tint,
      bands: bands,
      normal: n,
    );
  }

  /// Build a Filament Geometry from the accumulated faces. Vertex colours carry
  /// the cel-baked linear colour; rendered with an unlit vertex-colour material.
  Geometry build() {
    return Geometry(
      Float32List.fromList(_pos),
      _idx,
      normals: Float32List.fromList(_nrm),
      colors: Float32List.fromList(_col),
    );
  }

  /// Build a Filament Geometry carrying raw LINEAR albedo per vertex (no cel,
  /// fog or shadow baked in) plus flat per-face normals. Rendered with the
  /// realtime toon material under a realtime sun shadow map — the albedo is the
  /// only per-vertex colour; all lighting/shadow is computed per pixel.
  ///
  /// The flat per-face normal is also packed into UV0=(nx,ny)/UV1=(nz,0): the
  /// toon material reads its normal from UVs (screen-space derivatives are
  /// unreliable on dense geometry). _nrm is unit-length and constant per face.
  Geometry buildRealtime() {
    final uv = Float32List(_nrm.length ~/ 3 * 2);
    final uv1 = Float32List(_nrm.length ~/ 3 * 2);
    for (int i = 0, j = 0; i < _nrm.length; i += 3, j += 2) {
      uv[j] = _nrm[i];
      uv[j + 1] = _nrm[i + 1];
      uv1[j] = _nrm[i + 2];
    }
    return Geometry(
      Float32List.fromList(_pos),
      _idx,
      normals: Float32List.fromList(_nrm),
      colors: Float32List.fromList(_alb),
      uvs: uv,
      uvs1: uv1,
    );
  }

  /// A duplicate of this mesh's faces, each vertex pushed outward along its
  /// (flat, per-face) normal by [eps]. Rendered with a front-face-culled ink
  /// material, the back faces show as a constant silhouette + crease outline —
  /// the inverted-hull ink technique the reference uses on its hero props,
  /// applied here to every face for whole-scene line work.
  Mesh buildHull(double eps) {
    final h = Mesh(cel);
    for (int i = 0; i < _v; i++) {
      h._pos.addAll([
        _pos[i * 3] + _nrm[i * 3] * eps,
        _pos[i * 3 + 1] + _nrm[i * 3 + 1] * eps,
        _pos[i * 3 + 2] + _nrm[i * 3 + 2] * eps,
      ]);
      h._nrm.addAll([_nrm[i * 3], _nrm[i * 3 + 1], _nrm[i * 3 + 2]]);
      h._col.addAll([1, 1, 1, 1]);
      h._v++;
    }
    h._idx.addAll(_idx);
    return h;
  }

  // ---- primitives ---------------------------------------------------------

  /// Emit a face (3 or 4 corners) given in local space, transformed by [m].
  /// The face normal is recomputed from the transformed corners, so non-uniform
  /// scale in [m] still produces a correct flat normal for cel shading.
  void face(List<Vector3> local, Matrix4 m,
      {required int color, int tint = 0x6c5f8c, String bands = '3'}) {
    final w = <Vector3>[];
    for (final p in local) {
      final q = m.transformedVector3(p)..add(_tmpTrans(m));
      w.add(q);
    }
    if (w.length == 3) {
      tri(w[0], w[1], w[2], color: color, tint: tint, bands: bands);
    } else {
      quad(w[0], w[1], w[2], w[3], color: color, tint: tint, bands: bands);
    }
  }

  static final Vector3 _t0 = Vector3.zero();
  static Vector3 _tmpTrans(Matrix4 m) {
    // translation component of m
    _t0.setValues(m.getTranslation().x, m.getTranslation().y, m.getTranslation().z);
    return _t0;
  }

  /// A unit cylinder (radius 1, height 1, axis +Y, centred at origin) transformed
  /// by [m]. Used for trunks, branches, poles. The matrix carries scale (r,h,r),
  /// rotation and translation.
  void cylUnit(Matrix4 m, int color,
      {int segments = 7, int tint = 0x6c5f8c, String bands = '3'}) {
    final ring = <List<double>>[];
    for (int i = 0; i < segments; i++) {
      final a = i / segments * math.pi * 2;
      ring.add([math.cos(a), math.sin(a)]);
    }
    // sides (quads between top and bottom rings)
    for (int i = 0; i < segments; i++) {
      final j = (i + 1) % segments;
      face([
        Vector3(ring[i][0], 0.5, ring[i][1]),
        Vector3(ring[j][0], 0.5, ring[j][1]),
        Vector3(ring[j][0], -0.5, ring[j][1]),
        Vector3(ring[i][0], -0.5, ring[i][1]),
      ], m, color: color, tint: tint, bands: bands);
    }
    // caps (triangle fans)
    final top = Vector3(0, 0.5, 0);
    final bot = Vector3(0, -0.5, 0);
    for (int i = 0; i < segments; i++) {
      final j = (i + 1) % segments;
      face([top, Vector3(ring[j][0], 0.5, ring[j][1]), Vector3(ring[i][0], 0.5, ring[i][1])], m,
          color: color, tint: tint, bands: bands);
      face([bot, Vector3(ring[i][0], -0.5, ring[i][1]), Vector3(ring[j][0], -0.5, ring[j][1])], m,
          color: color, tint: tint, bands: bands);
    }
  }

  /// An icosahedron of the given radius at [center], subdivided to [detail]
  /// (0 -> 20 faces, 1 -> 80 faces, matching the reference's
  /// IcosahedronGeometry(1,1)). Optionally squashed vertically by [squashY].
  /// Faceted blossom lumps; the flat faces catch the cel bands as painted facets.
  void ico(Vector3 center, double r, int color,
      {int tint = 0x6c5f8c, String bands = 'soft', double squashY = 1.0, int detail = 1}) {
    const t = 1.61803398875; // golden ratio
    final base = <Vector3>[
      Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
      Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
      Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
    ];
    for (final v in base) {
      v.normalize();
    }
    var verts = base;
    var faces = <List<int>>[
      [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
      [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
      [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
      [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ];
    // subdivide: each triangle -> 4, with edge midpoints projected onto the
    // unit sphere (cached so shared edges stay shared).
    for (int d = 0; d < detail; d++) {
      final mid = <String, int>{};
      int midI(int i, int j) {
        final key = i < j ? '$i,$j' : '$j,$i';
        final cached = mid[key];
        if (cached != null) return cached;
        final a = verts[i], b = verts[j];
        final m = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
          ..normalize();
        verts.add(m);
        mid[key] = verts.length - 1;
        return verts.length - 1;
      }

      final nf = <List<int>>[];
      for (final f in faces) {
        final a = f[0], b = f[1], c = f[2];
        final ab = midI(a, b), bc = midI(b, c), ca = midI(c, a);
        nf.add([a, ab, ca]);
        nf.add([ab, b, bc]);
        nf.add([ca, bc, c]);
        nf.add([ab, bc, ca]);
      }
      faces = nf;
    }
    Vector3 w(Vector3 v) =>
        Vector3(center.x + v.x * r, center.y + v.y * r * squashY, center.z + v.z * r);

    for (final f in faces) {
      tri(w(verts[f[0]]), w(verts[f[1]]), w(verts[f[2]]),
          color: color, tint: tint, bands: bands);
    }
  }
}

extension on Matrix4 {
  Vector3 transformedVector3(Vector3 v) {
    final out = Vector3.zero();
    // apply rotation+scale (upper 3x3) only; translation handled separately
    out.x = storage[0] * v.x + storage[4] * v.y + storage[8] * v.z;
    out.y = storage[1] * v.x + storage[5] * v.y + storage[9] * v.z;
    out.z = storage[2] * v.x + storage[6] * v.y + storage[10] * v.z;
    return out;
  }
}
