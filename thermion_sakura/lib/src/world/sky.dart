/// The painted sky — a faithful port of the reference `src/core/sky.js`.
///
/// A three-stop painted gradient dome (slight banding intentional — it reads
/// as airbrushed background art), flat cel clouds, and pale layered ridge
/// lines on the horizon. Everything is unlit raw colour.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mathutil.dart';
import '../mesh.dart';
import '../palette.dart';

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// Exact linear-space port of `core/sky.js`'s dome fragment shader.
Vector3 skyColor(double h) {
  var t = (h * 1.15 + 0.02).clamp(0.0, 1.0);
  final q = (t * 26.0).floor() / 26.0;
  t = t * 0.65 + q * 0.35;
  final haze = C.lin(Pal.skyHaze);
  final mid = C.lin(Pal.skyMid);
  final top = C.lin(Pal.skyTop);
  var color = haze * (1.0 - _smoothstep(0.0, 0.30, t)) +
      mid * _smoothstep(0.0, 0.30, t);
  final toTop = _smoothstep(0.26, 0.92, t);
  color = color * (1.0 - toTop) + top * toTop;
  final warmth = _smoothstep(0.12, -0.05, h) * 0.6;
  return color * (1.0 - warmth) + haze * warmth;
}

/// The gradient dome centred on [center] (the camera's eye) + puffy clouds +
/// distant hill silhouettes. Painted into [m]. [eye] is the viewer position
/// used to tint each cloud cell with the sky colour behind it (defaults to
/// [center]); the reference draws the sky at radius 500 around the planet.
void buildSky(Mesh m, Vector3 center, {double radius = 380, Vector3? eye}) {
  // The source evaluates the gradient per fragment on a 32x20 sphere. A
  // denser vertex mesh reproduces that continuous result with the available
  // vertex-colour material while keeping the same spherical silhouette.
  final segH = 64;
  final segV = 64;
  // THREE.SphereGeometry is a complete sphere. This matters away from the
  // flat-authoring origin: the planet camera's local up tilts with the curved
  // surface, so its visible sky can lie in either world-Y hemisphere.
  for (int i = 0; i < segV; i++) {
    final v0 = -math.pi / 2 + i / segV * math.pi;
    final v1 = -math.pi / 2 + (i + 1) / segV * math.pi;
    for (int j = 0; j < segH; j++) {
      final a0 = j / segH * math.pi * 2;
      final a1 = (j + 1) / segH * math.pi * 2;
      // corners (direction from center)
      Vector3 dir(double v, double a) => Vector3(
          math.cos(a) * math.cos(v), math.sin(v), math.sin(a) * math.cos(v));
      final p00 = center + dir(v0, a0) * radius;
      final p10 = center + dir(v1, a0) * radius;
      final p11 = center + dir(v1, a1) * radius;
      final p01 = center + dir(v0, a1) * radius;
      Vector3 colorAt(Vector3 p) => skyColor((p / p.length).y);
      m.quadRawLinColors(p00, p10, p11, p01,
          [colorAt(p00), colorAt(p10), colorAt(p11), colorAt(p01)],
          normal: Vector3(0, 0, 1));
    }
  }

  _buildClouds(m, eye ?? center);
  // The reference's horizon cards stay in the flat authoring frame. In the
  // curved-world camera basis the same untransformed cards can rise across the
  // sky as a rectangular wall (most visibly on the school approach), so leave
  // the real terrain to supply the distant ridgeline.
}

/// The reference's cloud texture (textures.js `cloudTex`): white ellipse
/// puffs on a transparent canvas, bottom 22% trimmed flat. Ported as an
/// alpha function over unit UVs — u across the width, v up from the bottom
/// (canvas y is top-down, hence the flip).
const _PUFFS = [
  [0.22, 0.62, 0.15],
  [0.36, 0.46, 0.2],
  [0.52, 0.4, 0.24],
  [0.68, 0.5, 0.19],
  [0.82, 0.63, 0.14],
  [0.45, 0.66, 0.2],
  [0.6, 0.68, 0.17],
];

double _cloudAlpha(double u, double v) {
  if (v < 0.22) return 0.0;
  final cv = 1.0 - v;
  for (final p in _PUFFS) {
    final x = (u - p[0]) / (p[2] * 0.55);
    final y = (cv - p[1]) / (p[2] * 1.1);
    if (x * x + y * y < 1.0) return 1.0;
  }
  return 0.0;
}

/// Unlit cloud billboard with both reference layers composited into its vertex
/// colours. The source uses a 512x256 alpha texture twice: a cream foreground
/// and a lower, slightly offset lavender backing. Baking the two layers into a
/// single dense grid preserves that transparency ordering in the otherwise
/// opaque triangle-soup renderer.
void _cloudBillboard(Mesh m, Vector3 eye, Vector3 center, double w, double h,
    Vector3 right, Vector3 up) {
  const cols = 128, rows = 64;
  Vector3 corner(double u, double v) =>
      center + right * (w * (u - 0.5)) + up * (h * (v - 0.5));

  Vector3 shade(double u, double v) {
    final dir = corner(u, v) - eye;
    var c = skyColor(dir.y / dir.length);
    // The backing plane is translated +2 in local X and -10% of its height.
    // Inverse-map the foreground sample point into that translated plane.
    final backA = _cloudAlpha(u - 2.0 / w, v + 0.1) * 0.34;
    c = c * (1 - backA) + C.lin(Pal.cloudShade) * backA;
    final frontA = _cloudAlpha(u, v) * 0.62;
    return c * (1 - frontA) + C.lin(Pal.cloud) * frontA;
  }

  double coverage(double u, double v) => math.max(
      _cloudAlpha(u - 2.0 / w, v + 0.1) * 0.34, _cloudAlpha(u, v) * 0.62);

  for (int j = 0; j < rows; j++) {
    final v0 = j / rows, v1 = (j + 1) / rows;
    for (int i = 0; i < cols; i++) {
      final u0 = i / cols, u1 = (i + 1) / cols;
      // Transparent texels must remain holes. Emitting an opaque sky-coloured
      // cell there writes depth and hides other cloud billboards behind it,
      // unlike the reference's depthWrite=false transparent planes.
      if (coverage(u0, v0) == 0 &&
          coverage(u1, v0) == 0 &&
          coverage(u1, v1) == 0 &&
          coverage(u0, v1) == 0 &&
          coverage((u0 + u1) * .5, (v0 + v1) * .5) == 0) {
        continue;
      }
      m.quadRawLinColors(
        corner(u0, v0),
        corner(u1, v0),
        corner(u1, v1),
        corner(u0, v1),
        [shade(u0, v0), shade(u1, v0), shade(u1, v1), shade(u0, v1)],
        normal: Vector3(0, 0, 1),
      );
    }
  }
}

void _buildClouds(Mesh m, Vector3 eye) {
  final rng = rngKit(7781);
  for (int i = 0; i < 22; i++) {
    final r = rng.range(220.0, 350.0);
    final a = rng.range(0.0, math.pi * 2);
    final w = rng.range(90.0, 210.0);
    final h = w * rng.range(0.24, 0.34);
    final y = rng.range(46.0, 140.0);
    final local = Vector3(math.cos(a) * r, y, math.sin(a) * r);
    // Match THREE.Group.lookAt(0, y * .55, 0): local +Z points toward that
    // target, X stays level, and Y inherits the small vertical pitch.
    final forward = Vector3(0, y * 0.55, 0) - local
      ..normalize();
    final right = Vector3(0, 1, 0).cross(forward)..normalize();
    final up = forward.cross(right)..normalize();
    // main.js translates the complete cloud group to the active camera every
    // frame, while retaining the orientations authored above.
    final cloudCenter = eye + local;
    _cloudBillboard(m, eye, cloudCenter, w, h, right, up);
  }
}

/// Pale layered ridge lines on the horizon — pure silhouette, unlit.
void _buildDistantHills(Mesh m) {
  final rng = rngKit(4242);
  final layers = [
    (z: -330.0, h: 46.0, color: Pal.hillFar, width: 900.0, bumps: 9, y: -6.0),
    (z: -250.0, h: 34.0, color: Pal.hill, width: 760.0, bumps: 7, y: -4.0),
  ];
  for (final L in layers) {
    final n = 90;
    final pts = <Vector2>[];
    for (int i = 0; i <= n; i++) {
      final t = i / n;
      final x = (t - 0.5) * L.width;
      double y = 0;
      for (int b = 1; b <= L.bumps; b++) {
        y += math.sin(t * math.pi * b * 1.7 + b * 2.1) * (L.h / (b * 1.25));
      }
      pts.add(Vector2(x, math.max(2.0, y * 0.55 + L.h * 0.55)));
    }
    final xOff = rng.range(-30.0, 30.0);
    final c = C.lin(L.color);
    for (int i = 0; i < n; i++) {
      final x0 = pts[i].x + xOff, y0 = pts[i].y + L.y;
      final x1 = pts[i + 1].x + xOff, y1 = pts[i + 1].y + L.y;
      m.quadRawLin(
        Vector3(x0, -60, L.z),
        Vector3(x1, -60, L.z),
        Vector3(x1, y1, L.z),
        Vector3(x0, y0, L.z),
        c,
        normal: Vector3(0, 0, -1),
      );
    }
    // mirrored copy behind the camera so turning around reads as a valley
    final backXOff = rng.range(-40.0, 40.0);
    final zBack = -L.z * 1.15;
    for (int i = 0; i < n; i++) {
      final x0 = pts[i].x + backXOff, y0 = pts[i].y + L.y;
      final x1 = pts[i + 1].x + backXOff, y1 = pts[i + 1].y + L.y;
      m.quadRawLin(
        Vector3(x0, y0, zBack),
        Vector3(x1, y1, zBack),
        Vector3(x1, -60, zBack),
        Vector3(x0, -60, zBack),
        c,
        normal: Vector3(0, 0, 1),
      );
    }
  }
}
