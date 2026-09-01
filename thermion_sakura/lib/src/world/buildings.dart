/// Houses and the corner shop — ports of the reference `buildings.js`
/// (simplified `makeHouse`) and `shop.js` (the 青空商店 volumes).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import '../palette.dart';
import 'street.dart';

class HouseDef {
  const HouseDef({
    required this.x, required this.z, required this.w, required this.d,
    required this.floors, required this.seed, required this.wall, required this.roof,
    this.roofKind = 'gable', this.face = 'x+',
  });
  final double x, z, w, d;
  final int floors, seed, wall, roof;
  final String roofKind, face;
}

/// The reference `houseDefs` — the street-facing houses around the crossing.
const List<HouseDef> houseDefs = [
  HouseDef(x: -13.6, z: 12.6, w: 7.0, d: 7.0, floors: 2, seed: 21, wall: 0, roof: 1),
  HouseDef(x: -9.4, z: 23.2, w: 7.0, d: 8.0, floors: 2, seed: 22, wall: 2, roof: 0, roofKind: 'hip'),
  HouseDef(x: -10.6, z: 33.5, w: 6.4, d: 7.2, floors: 1, seed: 23, wall: 1, roof: 2),
  HouseDef(x: -13.5, z: 43.0, w: 7.4, d: 7.4, floors: 2, seed: 24, wall: 4, roof: 1, roofKind: 'flat'),
  HouseDef(x: 9.4, z: 20.4, w: 5.6, d: 7.8, floors: 2, seed: 25, wall: 3, roof: 0, face: 'x-'),
  HouseDef(x: 8.9, z: 29.6, w: 6.6, d: 7.4, floors: 2, seed: 26, wall: 5, roof: 3, roofKind: 'hip', face: 'x-'),
  HouseDef(x: 7.4, z: 38.5, w: 6.8, d: 7.0, floors: 1, seed: 27, wall: 0, roof: 2, face: 'x-'),
  HouseDef(x: -8.7, z: -7.6, w: 6.8, d: 6.2, floors: 2, seed: 28, wall: 1, roof: 0),
  HouseDef(x: -8.2, z: -16.4, w: 6.6, d: 7.0, floors: 2, seed: 29, wall: 4, roof: 1, roofKind: 'hip'),
  HouseDef(x: -15.2, z: -34.6, w: 7.4, d: 7.0, floors: 2, seed: 30, wall: 2, roof: 2, face: 'z+'),
  HouseDef(x: -5.4, z: -33.5, w: 8.0, d: 7.4, floors: 2, seed: 44, wall: 0, roof: 1, face: 'z+'),
  HouseDef(x: 8.5, z: -7.4, w: 6.6, d: 6.0, floors: 1, seed: 31, wall: 0, roof: 3, face: 'x-'),
  HouseDef(x: 10.0, z: -16.2, w: 6.8, d: 7.2, floors: 2, seed: 32, wall: 3, roof: 1, roofKind: 'hip', face: 'x-'),
  HouseDef(x: 14.4, z: -35.5, w: 7.0, d: 7.4, floors: 1, seed: 45, wall: 1, roof: 3, roofKind: 'hip', face: 'x-'),
  HouseDef(x: -18.0, z: -13.0, w: 8.0, d: 8.0, floors: 2, seed: 34, wall: 1, roof: 1, face: 'z+'),
  HouseDef(x: -27.5, z: -12.0, w: 7.6, d: 7.6, floors: 1, seed: 35, wall: 4, roof: 0, roofKind: 'hip', face: 'z+'),
  HouseDef(x: -37.0, z: -14.5, w: 8.4, d: 8.0, floors: 2, seed: 36, wall: 0, roof: 2, face: 'z+'),
  HouseDef(x: 21.0, z: -14.0, w: 8.2, d: 8.0, floors: 2, seed: 37, wall: 2, roof: 0, roofKind: 'hip', face: 'z+'),
  HouseDef(x: 31.0, z: -13.0, w: 7.8, d: 7.6, floors: 1, seed: 38, wall: 5, roof: 1, face: 'z+'),
  HouseDef(x: 41.5, z: -15.0, w: 8.6, d: 8.2, floors: 2, seed: 39, wall: 3, roof: 2, roofKind: 'flat', face: 'z+'),
  HouseDef(x: -22.0, z: 9.5, w: 8.0, d: 7.6, floors: 2, seed: 40, wall: 0, roof: 1, face: 'z-'),
  HouseDef(x: -33.6, z: 10.5, w: 7.6, d: 7.4, floors: 1, seed: 41, wall: 4, roof: 3, roofKind: 'hip', face: 'z-'),
  HouseDef(x: 21.2, z: 10.0, w: 5.8, d: 7.8, floors: 2, seed: 42, wall: 1, roof: 0, face: 'z-'),
  HouseDef(x: 30.5, z: 11.0, w: 7.8, d: 7.4, floors: 2, seed: 43, wall: 5, roof: 2, roofKind: 'hip', face: 'z-'),
];

void _house(Mesh m, HouseDef d, double y) {
  final wallCol = Pal.walls[d.wall % Pal.walls.length];
  final roofCol = Pal.roofs[d.roof % Pal.roofs.length];
  final h = 2.72 * d.floors;
  final hw = d.w / 2, hd = d.d / 2;

  // body
  m.boxAt(d.w, h, d.d, wallCol, d.x, y + h / 2, d.z, tint: 0x6f6790);
  // ground sill (concrete base) + string course between storeys
  m.boxAt(d.w + 0.14, 0.42, d.d + 0.14, Pal.concrete, d.x, y + 0.21, d.z,
      tint: 0x6a6288, bands: '2');
  if (d.floors > 1) {
    m.boxAt(d.w + 0.08, 0.14, d.d + 0.08, Pal.roofSlate, d.x, y + 2.72, d.z,
        tint: 0x514b70, bands: '2');
  }

  // Roof. For x-facing houses the ridge runs along z; for z-facing houses it
  // runs along x (i.e. along the street, perpendicular to the face).
  final isZFace = d.face == 'z+' || d.face == 'z-';
  final ridgeAlong = isZFace ? d.w : d.d;
  final ridgeAcross = isZFace ? d.d : d.w;
  final over = 0.35;
  final pitch = 0.42;
  if (d.roofKind == 'flat') {
    m.boxAt(d.w + over, 0.22, d.d + over, roofCol, d.x, y + h + 0.11, d.z, tint: 0x514b70);
  } else if (d.roofKind == 'gable') {
    final rh = ridgeAcross * pitch;
    final topY = y + h + rh;
    // the two slopes (across the ridge)
    final sign = isZFace ? -1.0 : 1.0;
    Vector3 corner(double sAcross, double sAlong, double yy) => isZFace
        ? Vector3(d.x + sAcross * (hw + over), yy, d.z + sAlong * (hd + over))
        : Vector3(d.x + sAlong * (hw + over), yy, d.z + sAcross * (hd + over));
    final r0 = -sign * (ridgeAcross / 2 + over);
    final r1 = sign * (ridgeAcross / 2 + over);
    m.quad(
      corner(r0, -1, y + h), corner(r0, 1, y + h),
      corner(0, 1, topY), corner(0, -1, topY),
      color: roofCol, tint: 0x514b70,
    );
    m.quad(
      corner(r1, -1, y + h), corner(0, -1, topY),
      corner(0, 1, topY), corner(r1, 1, y + h),
      color: roofCol, tint: 0x514b70,
    );
    // gable ends
    m.tri(corner(r0, -1, y + h), corner(0, -1, topY), corner(r0, 1, y + h),
        color: roofCol, tint: 0x514b70);
    m.tri(corner(r1, -1, y + h), corner(r1, 1, y + h), corner(0, 1, topY),
        color: roofCol, tint: 0x514b70);
  } else {
    // hip roof: four sloped faces from a short ridge
    final rh = math.min(d.w, d.d) * 0.32;
    final topY = y + h + rh;
    final ridgeHalf = math.max(0.0, ridgeAlong / 2 - ridgeAcross * 0.28);
    Vector3 corner(double sAcross, double sAlong, double yy) => isZFace
        ? Vector3(d.x + sAcross * (hw + over), yy, d.z + sAlong * (hd + over))
        : Vector3(d.x + sAlong * (hw + over), yy, d.z + sAcross * (hd + over));
    Vector3 ridgeEnd(double s) => isZFace
        ? Vector3(d.x, topY, d.z + s * ridgeHalf)
        : Vector3(d.x + s * ridgeHalf, topY, d.z);
    // two long slopes
    m.quad(corner(-1, -1, y + h), ridgeEnd(-1), ridgeEnd(1), corner(-1, 1, y + h),
        color: roofCol, tint: 0x514b70);
    m.quad(corner(1, -1, y + h), corner(1, 1, y + h), ridgeEnd(1), ridgeEnd(-1),
        color: roofCol, tint: 0x514b70);
    // two hip ends
    m.tri(corner(-1, -1, y + h), corner(1, -1, y + h), ridgeEnd(-1),
        color: roofCol, tint: 0x514b70);
    m.tri(corner(-1, 1, y + h), ridgeEnd(1), corner(1, 1, y + h),
        color: roofCol, tint: 0x514b70);
  }

  // street-facing fenestration: windows + door on the front wall.
  // face 'x+' -> front wall at x = d.x + hw, spans z (length d.d).
  // face 'x-' -> front wall at x = d.x - hw, spans z (length d.d).
  // face 'z+' -> front wall at z = d.z + hd, spans x (length d.w).
  // face 'z-' -> front wall at z = d.z - hd, spans x (length d.w).
  final planeX = d.face == 'x+' ? d.x + hw : (d.face == 'x-' ? d.x - hw : d.x);
  final planeZ = d.face == 'z+' ? d.z + hd : (d.face == 'z-' ? d.z - hd : d.z);
  final frontNormal = d.face == 'x+' ? Vector3(1, 0, 0) :
      d.face == 'x-' ? Vector3(-1, 0, 0) :
      d.face == 'z+' ? Vector3(0, 0, 1) : Vector3(0, 0, -1);
  final along = isZFace ? d.w : d.d; // span of the frontage
  final alongCenter = isZFace ? d.x : d.z;

  // windows scaled to the frontage width (reference makeHouse: cols from width).
  final winW = 1.1, winH = 1.2;
  final cols = (along - 1.0) / 2.1;
  final nCols = cols < 1 ? 1 : cols.floor();
  for (int f = 0; f < d.floors; f++) {
    final wy = y + 1.15 + f * 2.72 + (f > 0 ? 0.35 : 0);
    for (int cx = 0; cx < nCols; cx++) {
      final t = nCols == 1 ? 0.0 : (cx / (nCols - 1)) * 2 - 1; // -1..1
      final c = alongCenter + along * t * 0.32;
      if (isZFace) {
        m.quad(
          Vector3(c - winW / 2, wy, planeZ),
          Vector3(c + winW / 2, wy, planeZ),
          Vector3(c + winW / 2, wy + winH, planeZ),
          Vector3(c - winW / 2, wy + winH, planeZ),
          color: Pal.glassDark, bands: '2', tint: 0x4a4468, normal: frontNormal,
        );
      } else {
        m.quad(
          Vector3(planeX, wy, c - winW / 2),
          Vector3(planeX, wy, c + winW / 2),
          Vector3(planeX, wy + winH, c + winW / 2),
          Vector3(planeX, wy + winH, c - winW / 2),
          color: Pal.glassDark, bands: '2', tint: 0x4a4468, normal: frontNormal,
        );
      }
    }
  }
  // door
  final doorW = 0.9, doorH = 2.0;
  if (isZFace) {
    m.quad(
      Vector3(d.x - doorW / 2, y, planeZ),
      Vector3(d.x + doorW / 2, y, planeZ),
      Vector3(d.x + doorW / 2, y + doorH, planeZ),
      Vector3(d.x - doorW / 2, y + doorH, planeZ),
      color: 0x8a6a50, bands: '2', tint: 0x4a4468, normal: frontNormal,
    );
  } else {
    m.quad(
      Vector3(planeX, y, d.z - doorW / 2),
      Vector3(planeX, y, d.z + doorW / 2),
      Vector3(planeX, y + doorH, d.z + doorW / 2),
      Vector3(planeX, y + doorH, d.z - doorW / 2),
      color: 0x8a6a50, bands: '2', tint: 0x4a4468, normal: frontNormal,
    );
  }
}

/// Build every house into [m], seated on [groundY].
void buildHouses(Mesh m, double Function(double z) groundY) {
  for (final d in houseDefs) {
    _house(m, d, groundY(d.z));
  }
}

// ---------------------------------------------------------------------------
// The corner shop (青空商店)
// ---------------------------------------------------------------------------

/// Simplified 青空商店: two volumes, roof cap, string course, tiled base,
/// striped awning, shopfront glazing and upper windows. Seated on [groundY].
void buildShop(Mesh m, double Function(double z) groundY) {
  const zNear = 4.55;
  const zFar = 12.6;
  final zMid = (zNear + zFar) / 2;
  final xFront = centerX(zMid) + roadHalf + walkW + 0.12;
  const depth = 7.2;
  final y0 = groundY(zMid);
  const h1 = 3.15;
  const h2 = 2.75;

  // main volume
  m.boxAt(depth, h1, zFar - zNear, Pal.wallCream, xFront + depth / 2, y0 + h1 / 2, zMid,
      tint: 0x6f6790);
  // upper storey, set back a little
  m.boxAt(depth - 0.5, h2, zFar - zNear - 0.3, Pal.wallWhite,
      xFront + 0.35 + (depth - 0.5) / 2, y0 + h1 + h2 / 2, zMid, tint: 0x6f6790);
  // parapet + roof cap
  m.boxAt(depth - 0.4, 0.22, zFar - zNear - 0.2, Pal.roofSlate,
      xFront + 0.4 + (depth - 0.5) / 2, y0 + h1 + h2 + 0.11, zMid, tint: 0x514b70);
  // string course between floors
  m.boxAt(depth + 0.06, 0.18, zFar - zNear + 0.06, Pal.roofSlate,
      xFront + depth / 2, y0 + h1 + 0.05, zMid, tint: 0x514b70);
  // tiled base along the front
  m.boxAt(0.1, 0.55, zFar - zNear, 0xe9edf0, xFront - 0.04, y0 + 0.27, zMid, tint: 0x6f6790);
  // roof parapet cap
  m.boxAt(depth + 0.1, 0.14, zFar - zNear + 0.1, 0x6b6472,
      xFront + depth / 2, y0 + h1 + h2 + 0.24, zMid, tint: 0x514b70);

  // shopfront: a red-and-white striped awning spanning the whole frontage,
  // a half-closed shutter, glazing and the door
  final awningZ0 = zNear + 0.35;
  final awningZ1 = zFar - 0.35;
  final awningX = xFront - 0.15;
  final awningY = y0 + 2.42;
  const n = 12;
  for (int i = 0; i < n; i++) {
    final z0 = awningZ0 + (awningZ1 - awningZ0) * (i / n);
    final z1 = awningZ0 + (awningZ1 - awningZ0) * ((i + 1) / n);
    final col = i.isEven ? Pal.red : Pal.lineWhite;
    // slanted awning panel (droops to the street)
    m.quad(
      Vector3(awningX, awningY + 0.14, z0),
      Vector3(awningX, awningY + 0.14, z1),
      Vector3(awningX + 0.95, awningY - 0.2, z1),
      Vector3(awningX + 0.95, awningY - 0.2, z0),
      color: col, bands: '2', tint: 0x7a4060,
    );
  }
  // awning valance (the scalloped front face)
  for (int i = 0; i < n; i++) {
    final z0 = awningZ0 + (awningZ1 - awningZ0) * (i / n);
    final z1 = awningZ0 + (awningZ1 - awningZ0) * ((i + 1) / n);
    final col = i.isEven ? Pal.red : Pal.lineWhite;
    m.quad(
      Vector3(awningX + 0.95, awningY - 0.2, z0),
      Vector3(awningX + 0.95, awningY - 0.2, z1),
      Vector3(awningX + 0.95, awningY - 0.42, z1),
      Vector3(awningX + 0.95, awningY - 0.42, z0),
      color: col, bands: '2', tint: 0x7a4060,
    );
  }

  // half-closed shutter across the middle of the shopfront
  final shutterZc = zNear + 4.35;
  final shutterW = 3.0;
  for (final s in [-1.0, 1.0]) {
    m.boxAt(0.2, 2.75, 0.14, Pal.metalDark,
        xFront - 0.03, y0 + 1.4, shutterZc + s * (shutterW / 2 + 0.07), tint: 0x5c5680, bands: '2');
  }
  m.boxAt(0.07, 2.6, shutterW, Pal.shutter,
      xFront - 0.055, y0 + 1.5, shutterZc, tint: 0x4b4560, bands: '2');
  m.boxAt(0.11, 0.11, shutterW + 0.02, Pal.metalDark,
      xFront - 0.055, y0 + 0.05, shutterZc, tint: 0x5c5680, bands: '2');

  // shopfront glazing beside the shutter
  m.quadRaw(
    Vector3(xFront - 0.02, y0 + 0.9, zNear + 1.2),
    Vector3(xFront - 0.02, y0 + 0.9, shutterZc - shutterW / 2 - 0.35),
    Vector3(xFront - 0.02, y0 + 2.1, shutterZc - shutterW / 2 - 0.35),
    Vector3(xFront - 0.02, y0 + 2.1, zNear + 1.2),
    C.srgb(0x9dc0d4) * 0.85,
    normal: Vector3(-1, 0, 0),
  );
  m.quadRaw(
    Vector3(xFront - 0.02, y0 + 0.9, shutterZc + shutterW / 2 + 0.35),
    Vector3(xFront - 0.02, y0 + 0.9, zFar - 1.2),
    Vector3(xFront - 0.02, y0 + 2.1, zFar - 1.2),
    Vector3(xFront - 0.02, y0 + 2.1, shutterZc + shutterW / 2 + 0.35),
    C.srgb(0x9dc0d4) * 0.85,
    normal: Vector3(-1, 0, 0),
  );

  // upper windows
  final wy = y0 + h1 + 0.7;
  for (final off in [-0.4, 0.4]) {
    m.quadRaw(
      Vector3(xFront + 0.28, wy, zMid + (zFar - zNear) / 2 * off - 0.5),
      Vector3(xFront + 0.28, wy, zMid + (zFar - zNear) / 2 * off + 0.5),
      Vector3(xFront + 0.28, wy + 1.1, zMid + (zFar - zNear) / 2 * off + 0.5),
      Vector3(xFront + 0.28, wy + 1.1, zMid + (zFar - zNear) / 2 * off - 0.5),
      C.srgb(Pal.glassDark),
      normal: Vector3(-1, 0, 0),
    );
  }
}
