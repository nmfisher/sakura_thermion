/// Dart port of the reference `src/world/train.js::buildTrain` -- a three-car
/// suburban EMU: cream body, blue waist stripe, dark-strip windows.
///
/// Interiors are painted rather than modelled -- flat silhouette blocks and a
/// soft highlight sit directly on the glass, which is how a background artist
/// would draw a train going past.
///
/// Built on the geometry substrate (`geom/three_geom.dart`): every call is a 1:1
/// translation of the reference's `box`/`cyl`/`plane`/`bake`/`trs` calls.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'sign_atlas.dart';

// ── Train dimensions (from train.js) ──────────────────────────────────────

const _l = 19.4; // car length
const _w = 2.86; // body width
const _pitch = 20.1; // car spacing (centre-to-centre)
const _floor = 1.06;
const _top = 3.74;
const _roof = 3.96;
const _contactWireY = 4.88;
const _railTop = 0.30; // from railway.js

// ── Materials (from train.js initMaterials + PAL) ───────────────────────────

const _roofMat = Mat(0xbdb8bd, tint: 0x60597f, bands: '3'); // PAL.trainRoof
const _skirt = Mat(0x9aa0ad, tint: 0x5b5480, bands: '3'); // PAL.trainSkirt
const _doorMat = Mat(0xeae4d8, tint: 0x6f6796, bands: '3'); // PAL.trainDoor
const _dark = Mat(0x322e3b, tint: 0x4b4560, bands: '2'); // PAL.black
const _metal = Mat(0x878b96, tint: 0x5c5680, bands: '3'); // PAL.metalDark
const _wheelMat = Mat(0x4a4552, tint: 0x4b4560, bands: '2');
const _headlightMat = Mat(0xfff6da, unlit: true);
const _tailMat = Mat(0xff5a4a, unlit: true);

// Interior band colours (flat, from addGlass).
const _seatBack = Mat(0x515a72, unlit: true);
const _seatEdge = Mat(0x9fa8bb, unlit: true);
const _grabRail = Mat(0xb9c0cc, unlit: true);
const _ceilingLit = Mat(0xf0ead8, unlit: true);

// Deferred textures (livery decals, windows-as-texture) -> solid white.
const _white = Mat(0xffffff, unlit: true);

// ── Door / window layout ──────────────────────────────────────────────────

const _doors = [-7.0, -2.4, 2.4, 7.0];
const _doorW = 1.32;

/// Window bays for one car side: [centreX, width].
const _bays = [
  [-8.5, 1.7],
  [-4.7, 3.2],
  [0.0, 3.4],
  [4.7, 3.2],
  [8.5, 1.7],
];

// ── Helpers ───────────────────────────────────────────────────────────────

/// Port of `addGlass` -- window pane + interior bands.
///
/// Glass sits *outside* the window frame, not level with it -- otherwise the
/// frame box wins the depth test and the whole side of the train reads as a
/// blank panel.
///
void _addGlass(List<Part> parts, RngKit rng, double carX, double cx, double bw,
    int sz, Mat windowMat) {
  const y0 = 2.16, y1 = 3.16;
  final zz = sz.toDouble() * (_w / 2 + 0.032);
  final yMid = (y0 + y1) / 2;
  final h = y1 - y0;
  final ry = sz > 0 ? 0.0 : math.pi;

  // Window pane.
  parts.add(
      Part(planeGeometry(bw, h), trs(carX + cx, yMid, zz, 0, ry), windowMat));

  // Consume one rng value to keep the seeded sequence in sync with the
  // reference (the original code called rng.next() here for passenger
  // silhouettes that are now replaced by interior bands).
  rng.next();

  // Interior bands: seat backs, grab rail, ceiling light strip.
  void band(double yFrac, double hh, Mat col, double off) {
    parts.add(Part(planeGeometry(bw - 0.06, hh),
        trs(carX + cx, y0 + h * yFrac, zz + sz * off, 0, ry), col));
  }

  band(0.14, h * 0.28, _seatBack, 0.018); // seat backs
  band(0.30, 0.035, _seatEdge, 0.021); // top edge of seat run
  band(0.72, 0.045, _grabRail, 0.021); // grab rail
  band(0.93, 0.07, _ceilingLit, 0.018); // ceiling light strip
}

/// Build one car's geometry [parts] in train-local space, offset by [carX].
void _buildCar(List<Part> parts, List<Tri> mapped,
    {required bool cab,
    required bool tail,
    required RngKit rng,
    required double carX,
    required Mat bodyMat,
    required Mat stripeMat,
    required Mat windowMat}) {
  // Short-hand: add a part offset by carX.
  void push(Mat mat, ThreeGeom geo, double x, double y, double z,
      [double rx = 0,
      double ry = 0,
      double rz = 0,
      double sx = 1,
      double sy = double.nan,
      double sz = double.nan]) {
    parts.add(Part(geo, trs(carX + x, y, z, rx, ry, rz, sx, sy, sz), mat));
  }

  final bodyH = _top - _floor;

  // ── body ──
  push(bodyMat, boxGeometry(_l, bodyH, _w), 0, (_floor + _top) / 2, 0);

  // ── roof (slightly inset, flatter tone) ──
  push(_roofMat, boxGeometry(_l - 0.1, _roof - _top, _w - 0.24), 0,
      (_top + _roof) / 2, 0);
  // rain gutter line
  for (final s in [-1.0, 1.0]) {
    push(_roofMat, boxGeometry(_l - 0.05, 0.07, 0.1), 0, _top + 0.02,
        s * (_w / 2 - 0.06));
  }

  // ── waist stripe, wrapped round the whole body ──
  const stripeY = 1.92;
  const stripeH = 0.34;
  push(stripeMat, boxGeometry(_l + 0.02, stripeH, _w + 0.03), 0, stripeY, 0);
  push(stripeMat, boxGeometry(_l + 0.02, 0.07, _w + 0.04), 0,
      stripeY - stripeH / 2 - 0.055, 0);

  // ── underframe + skirt ──
  push(_skirt, boxGeometry(_l - 0.3, 0.5, _w - 0.34), 0, _floor - 0.25, 0);
  push(_skirt, boxGeometry(_l - 1.6, 0.28, _w - 0.8), 0, _floor - 0.52, 0);

  // ── doors and glass ──
  for (final sz in [1, -1]) {
    for (final dx in _doors) {
      push(_doorMat, boxGeometry(_doorW, _top - _floor - 0.12, 0.05), dx,
          (_floor + _top) / 2 - 0.02, sz * (_w / 2 + 0.012));
      push(_dark, boxGeometry(0.05, _top - _floor - 0.12, 0.06), dx,
          (_floor + _top) / 2 - 0.02, sz * (_w / 2 + 0.02));
      _addGlass(parts, rng, carX, dx, 0.94, sz, windowMat);
    }
    for (final bay in _bays) {
      final bx = bay[0], bw = bay[1];
      // window frame (sits flush with the body; glass goes on top)
      push(_metal, boxGeometry(bw + 0.12, 1.14, 0.035), bx, 2.66,
          sz * (_w / 2 + 0.008));
      _addGlass(parts, rng, carX, bx, bw, sz, windowMat);
    }
  }

  // ── bogies ──
  for (final bx in [-6.3, 6.3]) {
    push(_metal, boxGeometry(2.9, 0.42, _w - 0.9), bx, 0.78, 0);
    push(_dark, boxGeometry(3.3, 0.2, 0.28), bx, 0.62, 0);
  }

  // ── roof equipment ──
  for (final rx in [-5.6, -1.4, 3.2, 7.4]) {
    push(_roofMat, boxGeometry(2.1, 0.3, 1.5), rx, _roof + 0.13,
        rx % 2 == 0 ? 0.18 : -0.18);
  }
  for (final rx in [-8.2, 0.6, 8.6]) {
    push(_metal, boxGeometry(0.7, 0.16, 0.7), rx, _roof + 0.07, -0.7);
  }

  // ── cab / tail end ──
  if (cab || tail) {
    final s = cab ? 1.0 : -1.0;
    final fx = s * (_l / 2);
    final faceRy = s > 0 ? math.pi / 2 : -math.pi / 2;

    // black mask around the windscreen
    push(_dark, boxGeometry(0.1, 1.34, _w - 0.22), fx + s * 0.03, 2.86, 0);

    // windscreen: two panes with a centre pillar
    for (final wz in [-0.72, 0.72]) {
      push(windowMat, planeGeometry(1.16, 1.02), fx + s * 0.085, 2.88, wz, 0,
          faceRy);
    }
    // centre pillar
    push(bodyMat, boxGeometry(0.12, 1.4, 0.16), fx + s * 0.05, 2.86, 0);

    // destination board (texture deferred -> solid white)
    push(_white, planeGeometry(1.5, 0.38), fx + s * 0.09, 3.52, 0, 0, faceRy);
    appendSignAtlasPlane(mapped, trainDestinationRegion,
        width: 1.5,
        height: .38,
        matrix: trs(carX + fx + s * .091, 3.52, 0, 0, faceRy));
    push(_dark, boxGeometry(0.08, 0.5, 1.66), fx + s * 0.04, 3.52, 0);

    // head / tail lights
    for (final lz in [-1.06, 1.06]) {
      push(_dark, boxGeometry(0.14, 0.42, 0.5), fx + s * 0.05, 1.55, lz);
      push(cab ? _headlightMat : _tailMat, planeGeometry(0.34, 0.16),
          fx + s * 0.13, 1.63, lz, 0, faceRy);
      push(cab ? _tailMat : _headlightMat, planeGeometry(0.34, 0.14),
          fx + s * 0.13, 1.44, lz, 0, faceRy);
    }

    // front skirt + coupler
    push(_skirt, boxGeometry(0.34, 0.78, _w - 0.5), fx + s * 0.1, 0.82, 0);
    push(_dark, boxGeometry(0.5, 0.22, 0.34), fx + s * 0.25, 0.62, 0);

    // car number plate (texture deferred -> solid white)
    push(_white, planeGeometry(0.8, 0.24), fx - s * 1.4, 1.42, _w / 2 + 0.02);
    appendSignAtlasPlane(mapped, trainNumberRegion,
        width: .8,
        height: .24,
        matrix: trs(carX + fx - s * 1.4, 1.42, _w / 2 + .021));
  }

  // ── wheels ──
  //
  // CylinderGeometry laid on its side (rotateX PI/2) so the wheel rolls
  // along X.  The geometry is shared across all 8 wheels per car.
  final wheelGeo = applyMatrix(
      cylGeometry(0.43, 0.43, 0.14, 12), Matrix4.rotationX(math.pi / 2));
  for (final bx in [-6.3, 6.3]) {
    for (final wx in [-1.05, 1.05]) {
      for (final wz in [-0.72, 0.72]) {
        push(_wheelMat, wheelGeo, bx + wx, _railTop + 0.43, wz);
      }
    }
  }

  // ── pantograph (only on the cab / tail car) ──
  if (cab || tail) {
    final px = cab ? -4.0 : 4.0;
    final py = _roof + 0.05;
    final sy = (_contactWireY - py) / 1.64;

    // base plate (no rotation, just Y-scaled)
    push(_metal, boxGeometry(1.5, 0.08 * sy, 1.5), px, py + 0.04 * sy, 0);

    // lower + upper arms (rotated).
    // The reference applies group scale *before* mesh rotation, so the
    // geometry transform is S(1,sY,1) * Rz -- we use applyMatrix to bake
    // this into the geometry and a pure-translation part matrix.
    for (final sign in [-1.0, 1.0]) {
      final lowerM =
          Matrix4.diagonal3(Vector3(1, sy, 1)) * Matrix4.rotationZ(sign * 0.55);
      final lowerGeo = applyMatrix(boxGeometry(0.06, 0.9, 0.06), lowerM);
      parts.add(Part(
          lowerGeo, trs(carX + px + sign * 0.35, py + 0.5 * sy, 0), _metal));

      final upperM = Matrix4.diagonal3(Vector3(1, sy, 1)) *
          Matrix4.rotationZ(sign * 0.148);
      final upperGeo = applyMatrix(boxGeometry(0.05, 0.78, 0.05), upperM);
      parts.add(Part(upperGeo,
          trs(carX + px + sign * 0.0575, py + 1.247 * sy, 0), _metal));
    }

    // crossbars
    push(_dark, boxGeometry(0.1, 0.06 * sy, 1.3), px, py + 1.6 * sy, 0);
    push(_metal, boxGeometry(0.24, 0.05 * sy, 1.34), px, py + 1.64 * sy, 0);
  }
}

/// Port of `train.js::buildTrain` -- a three-car suburban EMU.
///
/// Returns the baked world-space triangles for all three cars centred at the
/// origin (car 0 at x = -PITCH, car 1 at x = 0, car 2 at x = +PITCH).
List<Tri> buildTrain(
    {double x = 0,
    int bodyColor = 0xf7f2e6,
    int stripeColor = 0x2f7fd0,
    int windowColor = 0x3a4258,
    Set<int>? includeCars}) {
  final rng = RngKit(5150);
  final parts = <Part>[];
  final mapped = <Tri>[];
  final bodyMat = Mat(bodyColor, tint: 0x6f6796, bands: '3');
  final stripeMat = Mat(stripeColor, tint: 0x4a4a92, bands: '3');
  final windowMat = Mat(windowColor, unlit: true);

  for (int i = 0; i < 3; i++) {
    final carParts = <Part>[];
    final carMapped = <Tri>[];
    _buildCar(carParts, carMapped,
        cab: i == 0,
        tail: i == 2,
        rng: rng,
        carX: (i - 1) * _pitch,
        bodyMat: bodyMat,
        stripeMat: stripeMat,
        windowMat: windowMat);
    if (includeCars == null || includeCars.contains(i)) {
      parts.addAll(carParts);
      mapped.addAll(carMapped);
    }
  }

  final baked = [...bake(parts), ...mapped];
  if (x == 0) return baked;
  final offset = Vector3(x, 0, 0);
  return [
    for (final tri in baked)
      Tri(tri.a + offset, tri.b + offset, tri.c + offset, tri.normal, tri.mat,
          uvA: tri.uvA, uvB: tri.uvB, uvC: tri.uvC),
  ];
}
