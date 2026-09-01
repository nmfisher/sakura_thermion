/// Planet-surface wrap — port of the reference `planet.js` / `bakeToPlanet`.
/// The world is authored on a flat (x, z) plane; this maps every flat-space
/// point onto a sphere of radius [planetRadius] centred below the origin, and
/// rotates normals into the surface tangent frame. The opening frame sits near
/// the sphere's top, so the curvature is slight but present (distant terrain
/// curves down to the horizon).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'three_geom.dart';

const double planetRadius = 160.0;
final Vector3 _planetCenter = Vector3(0, -planetRadius, 0);

Vector3 _surfaceNormal(double x, double z) {
  final la = x / planetRadius, ph = z / planetRadius;
  final cp = math.cos(ph);
  return Vector3(math.sin(la) * cp, math.cos(la) * cp, math.sin(ph));
}

/// Flat (x, y, z) → sphere-surface world position (y is height above surface).
Vector3 planetPosition(double x, double y, double z) => _surfaceNormal(x, z)
  ..scale(planetRadius + y)
  ..add(_planetCenter);

/// Tangent frame (east, up, north) at flat (x, z) — port of planet.js basisAt.
void planetBasis(double x, double z, Vector3 up, Vector3 east, Vector3 north) {
  final la = x / planetRadius, ph = z / planetRadius;
  final sl = math.sin(la),
      cl = math.cos(la),
      sp = math.sin(ph),
      cp = math.cos(ph);
  up.setValues(sl * cp, cl * cp, sp);
  east.setValues(cl, -sl, 0);
  north.setValues(-sl * sp, -cl * sp, cp);
}

/// Split flat-space triangles until every edge is at most [maxEdge] metres.
///
/// This is the triangle-soup equivalent of the reference's
/// `planet.js::subdivideLongEdges`. Without it, a long box face is mapped only
/// at its corners and spans the curved world as a straight chord. The bounded
/// pass count and longest-edge split order intentionally mirror three.js.
List<Tri> subdivideLongEdges(List<Tri> triangles, {double maxEdge = 3.0}) {
  final maxEdge2 = maxEdge * maxEdge;
  var current = triangles;

  for (var pass = 0; pass < 12; pass++) {
    var splits = 0;
    final next = <Tri>[];
    for (final tri in current) {
      final vertices = [tri.a, tri.b, tri.c];
      final uvs = [tri.uvA, tri.uvB, tri.uvC];
      var longest2 = -1.0;
      var longest = 0;
      for (var edge = 0; edge < 3; edge++) {
        final delta = vertices[edge] - vertices[(edge + 1) % 3];
        final length2 = delta.length2;
        if (length2 > longest2) {
          longest2 = length2;
          longest = edge;
        }
      }
      if (longest2 <= maxEdge2) {
        next.add(tri);
        continue;
      }

      splits++;
      final i0 = longest;
      final i1 = (longest + 1) % 3;
      final i2 = (longest + 2) % 3;
      final midpoint = (vertices[i0] + vertices[i1]) * 0.5;
      final midpointUv = tri.mapped ? (uvs[i0]! + uvs[i1]!) * 0.5 : null;
      next
        ..add(Tri(vertices[i0], midpoint, vertices[i2], tri.normal, tri.mat,
            uvA: uvs[i0],
            uvB: midpointUv,
            uvC: uvs[i2],
            rigidPivot: tri.rigidPivot))
        ..add(Tri(midpoint, vertices[i1], vertices[i2], tri.normal, tri.mat,
            uvA: midpointUv,
            uvB: uvs[i1],
            uvC: uvs[i2],
            rigidPivot: tri.rigidPivot));
    }
    current = next;
    if (splits == 0) break;
  }
  return current;
}

/// Wrap a flat-space triangle soup onto the planet sphere (positions mapped to
/// the surface, normals rotated into the tangent frame). Use this on the output
/// of `buildPortedScene()` before rendering through the planet-frame camera.
List<Tri> wrapOnPlanet(List<Tri> flat, {double maxEdge = 3.0}) {
  final subdivided = subdivideLongEdges(flat, maxEdge: maxEdge);
  return [
    for (final t in subdivided) _wrapTri(t),
  ];
}

Tri _wrapTri(Tri t) {
  final pivot = t.rigidPivot;
  if (pivot == null) {
    final a = planetPosition(t.a.x, t.a.y, t.a.z);
    final b = planetPosition(t.b.x, t.b.y, t.b.z);
    final c = planetPosition(t.c.x, t.c.y, t.c.z);
    final normal = (b - a).cross(c - a)..normalize();
    return Tri(
      a,
      b,
      c,
      normal,
      t.mat,
      uvA: t.uvA,
      uvB: t.uvB,
      uvC: t.uvC,
    );
  }
  final up = Vector3.zero(), east = Vector3.zero(), north = Vector3.zero();
  planetBasis(pivot.x, pivot.z, up, east, north);
  final seated = planetPosition(pivot.x, pivot.y, pivot.z);
  Vector3 point(Vector3 v) =>
      seated +
      east * (v.x - pivot.x) +
      up * (v.y - pivot.y) +
      north * (v.z - pivot.z);
  final normal = east * t.normal.x
    ..addScaled(up, t.normal.y)
    ..addScaled(north, t.normal.z);
  return Tri(point(t.a), point(t.b), point(t.c), normal, t.mat,
      uvA: t.uvA, uvB: t.uvB, uvC: t.uvC, rigidPivot: pivot);
}

/// Camera (eye + forward + up) on the sphere at flat pos/yaw/pitch — the
/// reference's spawn framing. Port of the planet-frame camera.
void spawnCamera(Vector3 eye, Vector3 fwd, Vector3 up,
    {double px = 1.85,
    double pz = 13.6,
    double eyeH = 1.62,
    double yaw = 0.20,
    double pitch = -0.008}) {
  eye.setFrom(planetPosition(px, eyeH, pz));
  final u = Vector3.zero(), e = Vector3.zero(), n = Vector3.zero();
  planetBasis(px, pz, u, e, n);
  final cp = math.cos(pitch),
      sp = math.sin(pitch),
      cy = math.cos(yaw),
      sy = math.sin(yaw);
  fwd
    ..setFrom(e * (-sy * cp))
    ..addScaled(u, sp)
    ..addScaled(n, -cy * cp);
  up.setFrom(u);
}
