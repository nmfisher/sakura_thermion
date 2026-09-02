/// Dart port of the reference `src/world/railway.js::buildRailway` — the rail
/// tracks, ballast bed, sleepers, crossing hardware, fencing, catenary, and the
/// small ひばり台 platform. Built entirely on the native Dart substrate.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'sign_atlas.dart';
import 'street.dart' show centerX, roadHalf, walkW;

// Railway constants (railway.js / street.js).
const _railGauge = 1.44;
const _trackHalf = 2.2;
const _gateZ = 2.95;
const _localMin = -150.0;
const _localMax = 150.0;

// Materials (railway.js mat* + PAL).
const _ballastMat = Mat(0x7d7686, tint: 0x655d84, bands: '3'); // PAL.ballast
const _sleeperMat = Mat(0x6d6576, tint: 0x5d5878, bands: '3'); // PAL.sleeper
const _railMat = Mat(0x6b6472,
    tint: 0x5f5878, bands: '3', flat: false); // PAL.railMetal (smooth)
const _headMat = Mat(0xc2bcc4, tint: 0x6f6890, bands: '2'); // PAL.railHead
const _deckMat = Mat(0xdad5df, tint: 0x6f6790, bands: '3');
const _gateBlack = Mat(0x322e3b, tint: 0x4b4560, bands: '2');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _cabinet = Mat(0xd8d5da, tint: 0x6f6890, bands: '3');
const _cabinetTop = Mat(0xb6b2bc, tint: 0x6f6890, bands: '3');
const _concrete = Mat(0xe0ddd5, tint: 0x6f6790, bands: '3');
const _signalOff = Mat(0x6a3b44, unlit: true);
const _signalRed = Mat(0xf2453c, unlit: true);
const _wireMat = Mat(0x878b96, tint: 0x4a4468, bands: '2');
const _grooveMat = Mat(0x4d4757, tint: 0x413c58, bands: '2');
const _lineYellow = Mat(0xf2c53d, tint: 0x8f7050, bands: '2');

/// One crossing boom authored about its hinge at the origin, extending along
/// local +X. Runtime hosts place and rotate this as a separate Filament entity.
List<Tri> buildCrossingBoom({int gateYellowColor = 0xf4c033}) {
  const seg = .52;
  final length = roadHalf * 2 + .5;
  final count = (length / seg).round();
  final yellow = Mat(gateYellowColor, tint: 0x8f7050, bands: '3');
  final parts = <Part>[];
  for (var i = 0; i < count; i++) {
    final x = seg * (i + .5);
    parts.add(Part(boxGeometry(seg, .17, .09), trs(x, 0, 0),
        i.isEven ? yellow : _gateBlack));
    if (i > 0 && i < count - 1 && i % 3 == 1) {
      parts
        ..add(Part(boxGeometry(.03, .12, .03), trs(x, -.05, .06), _metalDark))
        ..add(Part(boxGeometry(.11, .11, .07), trs(x, -.14, .06), _signalOff));
    }
  }
  return bake(parts);
}

/// Bright face of a crossing warning lamp, centred at the local origin.
List<Tri> buildCrossingLamp() => bake([
      Part(cylGeometry(.13, .13, .026, 14), trs(0, 0, 0, math.pi / 2),
          _signalRed),
    ]);

Matrix4 _mul(Matrix4 a, Matrix4 b) => a.clone()..multiply(b);

void _addCrossing(
    List<Part> parts, ThreeGeom geo, Mat mat, Matrix4 parent, Matrix4 local) {
  parts.add(Part(geo, _mul(parent, local), mat));
}

void _tubeBetween(
    List<Part> parts, ThreeGeom unit, Vector3 a, Vector3 b, double radius) {
  final dir = b - a;
  if (dir.length2 < 1e-8) return;
  final q = quatFromUnitVectors(Vector3(0, 1, 0), dir.normalized());
  parts.add(Part(
      unit,
      composePRS((a + b) * .5, q, Vector3(radius, dir.length, radius)),
      _wireMat));
}

/// Exact static opening-frame geometry from railway.js::buildCrossing.
/// The animation starts with the two booms raised, so their pivot rotation is
/// just under 90 degrees. Text printed on the sign board is deferred, but the
/// board, crossbucks, signals, lamps, cabinets, and kerbs are all geometric.
void _buildCrossing(List<Part> parts, List<Tri> mapped, Mat gateYellow,
    {bool includeBooms = true, bool includeActiveLamps = true}) {
  final cx = centerX(0);
  final gy = 0.0;

  void corner(int sx, int sz, bool hasArm) {
    final x = cx + sx * (roadHalf + 0.42);
    final z = sz * _gateZ;
    final root = trs(x, gy, z);

    void add(ThreeGeom geo, Mat mat, Matrix4 local) =>
        _addCrossing(parts, geo, mat, root, local);

    add(boxGeometry(0.66, 0.2, 0.62), _concrete, trs(0, 0.1, 0));

    if (hasArm) {
      const mh = 0.92;
      add(boxGeometry(0.46, mh, 0.38), _cabinet, trs(0, 0.2 + mh / 2, 0));
      add(boxGeometry(0.54, 0.07, 0.46), _cabinetTop,
          trs(0, 0.2 + mh + 0.03, 0));
      for (int i = 0; i < 3; i++) {
        add(boxGeometry(0.48, 0.11, 0.4), i.isEven ? gateYellow : _gateBlack,
            trs(0, 0.34 + i * 0.24, 0));
      }

      // Raised striped boom: local +X arm, yawed toward the opposite kerb.
      const seg = 0.52;
      final length = roadHalf * 2 + 0.5;
      final n = (length / seg).round();
      // The opening capture occurs while the train has the animated booms just
      // off vertical.  A 1.36 rad sweep reproduces their opposing diagonals in
      // that frame (the old rest pose made both conspicuously ruler-vertical).
      final pivot =
          trs(0, 0.2 + mh + 0.12, sz * 0.2, 0, sx > 0 ? math.pi : 0, 1.36);
      if (includeBooms) {
        for (int i = 0; i < n; i++) {
          final segment = _mul(pivot, trs(seg * (i + 0.5), 0, 0));
          add(boxGeometry(seg, 0.17, 0.09), i.isEven ? gateYellow : _gateBlack,
              segment);
          if (i > 0 && i < n - 1 && i % 3 == 1) {
            add(boxGeometry(0.03, 0.12, 0.03), _metalDark,
                _mul(pivot, trs(seg * (i + 0.5), -0.05, 0.06)));
            add(boxGeometry(0.11, 0.11, 0.07), _signalOff,
                _mul(pivot, trs(seg * (i + 0.5), -0.14, 0.06)));
          }
        }
      }
      add(boxGeometry(0.2, 0.2, 0.14), _metalDark,
          trs(0, 0.2 + mh + 0.12, sz * 0.2));
    }

    // Yellow mast with four black bands.
    final mastX = hasArm ? sx * 0.44 : 0.0;
    const mastH = 2.45;
    add(cylGeometry(0.075, 0.09, mastH, 8), gateYellow,
        trs(mastX, 0.2 + mastH / 2, 0));
    for (int i = 0; i < 4; i++) {
      add(cylGeometry(0.082, 0.082, 0.22, 8), _gateBlack,
          trs(mastX, 0.42 + i * 0.56, 0));
    }
    if (hasArm) {
      add(boxGeometry(0.5, 0.09, 0.09), _metalDark, trs(mastX / 2, 0.7, 0));
    }

    // Signal bar, two hoods/lenses, and bell. The thin cylinders are oriented
    // along Z to face the road, matching headGrp.rotation.y in the reference.
    final head =
        trs(mastX, 0.2 + mastH + 0.02, sz * 0.02, 0, sz > 0 ? 0 : math.pi, 0);
    add(boxGeometry(0.86, 0.13, 0.1), _gateBlack, _mul(head, trs(0, 0.06, 0)));
    for (int i = 0; i < 2; i++) {
      final lx = i == 0 ? -0.28 : 0.28;
      add(cylGeometry(0.145, 0.16, 0.13, 12, openEnded: true), _gateBlack,
          _mul(head, trs(lx, -0.12, 0.07, math.pi / 2, 0, 0)));
      add(
          cylGeometry(0.13, 0.13, 0.025, 14),
          includeActiveLamps && i == 0 ? _signalRed : _signalOff,
          _mul(head, trs(lx, -0.12, 0.145, math.pi / 2, 0, 0)));
    }
    add(cylGeometry(0.13, 0.13, 0.18, 10), _metal, _mul(head, trs(0, 0.3, 0)));

    if (!hasArm) {
      // Sign board and the characteristic yellow crossing crossbuck.
      final boardY = 0.2 + mastH + 0.62;
      add(boxGeometry(1.15, 0.58, 0.05), _concrete,
          trs(0, boardY, sz * 0.05, 0, sz > 0 ? 0 : math.pi, 0));
      appendSignAtlasPlane(mapped, crossingSignRegion,
          width: 1.15,
          height: .58,
          matrix: root *
              trs(0, boardY, sz * .05, 0, sz > 0 ? 0 : math.pi, 0) *
              trs(0, 0, .0251));

      for (final rz in const [0.72, -0.72]) {
        add(boxGeometry(1.2, 0.15, 0.045), gateYellow,
            trs(0, 0.2 + mastH + 1.28, sz * 0.05, 0, 0, rz));
      }
      add(cylGeometry(0.06, 0.07, 1.3, 8), gateYellow,
          trs(0, 0.2 + mastH + 0.65, 0));
    }
  }

  corner(-1, 1, true);
  corner(1, -1, true);
  corner(1, 1, false);
  corner(-1, -1, false);

  // Relay cabinets and crossing-call control box at the far-left corner.
  final zc = -_gateZ - 1.15;
  final xc = cx - (roadHalf + 1.5);
  parts.add(
      Part(boxGeometry(0.78, 1.32, 0.5), trs(xc, gy + 0.66, zc), _cabinet));
  parts.add(
      Part(boxGeometry(0.86, 0.08, 0.58), trs(xc, gy + 1.36, zc), _cabinetTop));
  parts.add(Part(boxGeometry(0.52, 0.9, 0.4),
      trs(xc - 0.9, gy + 0.45, zc + 0.1), _cabinet));
  parts.add(Part(boxGeometry(0.6, 0.06, 0.46),
      trs(xc - 0.9, gy + 0.93, zc + 0.1), _cabinetTop));
  parts.add(Part(
      boxGeometry(0.02, 1.0, 0.02), trs(xc, gy + 0.66, zc - 0.26), _metalDark));
  parts.add(Part(boxGeometry(0.07, 0.07, 0.03),
      trs(xc + 0.24, gy + 1.16, zc - 0.26), _signalRed));
  parts.add(Part(
      boxGeometry(0.3, 0.4, 0.12), trs(xc, gy + 1.0, zc - 0.3), gateYellow));

  // Safety kerbs guide pedestrians through the deck.
  for (final sx in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(0.34, 0.16, _trackHalf * 2 + 1.6),
        trs(cx + sx * (roadHalf + 0.15), gy + 0.08, 0), _concrete));
  }
}

void _buildStation(List<Part> parts, List<Tri> mapped) {
  const x0 = 15.5, x1 = 38.0;
  const frontZ = -1.92, backZ = -5.62;
  const platformH = .98;
  const concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
  const concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
  const roofTeal = Mat(0x4f6b70, tint: 0x4a4468, bands: '3');
  const wallCream = Mat(0xf2e7d3, tint: 0x6f6790, bands: '3');
  const signFace = Mat(0xfbfaf6, unlit: true, noOutline: true);
  final cx = (x0 + x1) / 2;
  final cz = (frontZ + backZ) / 2;

  parts.add(Part(boxGeometry(x1 - x0, platformH, frontZ - backZ),
      trs(cx, platformH / 2, cz), concrete));
  parts.add(Part(boxGeometry(x1 - x0, .06, .34),
      trs(cx, platformH - .02, frontZ - .17), concreteMid));
  // Tactile line: a yellow carrier with repeated raised bars. This retains the
  // source texture's cadence without a texture atlas.
  parts.add(Part(boxGeometry(x1 - x0 - 1, .018, .46),
      trs(cx, platformH + .014, frontZ - .62), _lineYellow));
  for (double x = x0 + .55; x < x1 - .45; x += .46) {
    parts.add(Part(boxGeometry(.08, .025, .34),
        trs(x, platformH + .031, frontZ - .62), _lineYellow));
  }

  // Canopy and four posts over the middle of the platform.
  final canopyX = cx + 1.5;
  const roofW = 9.5, roofD = 3.2;
  for (final x in [canopyX - roofW / 2 + .6, canopyX + roofW / 2 - .6]) {
    for (final z in [frontZ - .9, backZ + .7]) {
      parts.add(Part(cylGeometry(.075, .075, 2.6, 8),
          trs(x, platformH + 1.3, z), _metalDark));
    }
  }
  parts.add(Part(boxGeometry(roofW, .16, roofD),
      trs(canopyX, platformH + 2.66, cz - .1), roofTeal));
  parts.add(Part(boxGeometry(roofW + .3, .1, .14),
      trs(canopyX, platformH + 2.56, cz - 1.75), _metal));

  // Paired cream benches under the canopy.
  for (final x in [canopyX - 2.2, canopyX + 1.4]) {
    parts.add(Part(boxGeometry(1.7, .08, .42),
        trs(x, platformH + .42, backZ + .95), wallCream));
    parts.add(Part(boxGeometry(1.7, .5, .07),
        trs(x, platformH + .66, backZ + .75), wallCream));
    for (final dx in [-.7, .7]) {
      parts.add(Part(boxGeometry(.1, .42, .36),
          trs(x + dx, platformH + .21, backZ + .95), _metalDark));
    }
  }

  // Two geometric station-name boards facing the track.
  for (final x in [x0 + 4.0, x1 - 4.5]) {
    parts.add(Part(cylGeometry(.06, .06, 2.2, 8),
        trs(x, platformH + 1.1, frontZ - .55), _metalDark));
    parts.add(Part(boxGeometry(1.9, .5, .06),
        trs(x, platformH + 2.25, frontZ - .55), signFace));
    appendSignAtlasPlane(mapped, stationSignRegion,
        width: 1.9,
        height: .5,
        matrix: trs(x, platformH + 2.25, frontZ - .5199));
  }

  // Back fence.
  for (double x = x0; x <= x1; x += 2.2) {
    parts.add(Part(boxGeometry(.08, 1.2, .08),
        trs(x, platformH + .6, backZ + .06), _metal));
  }
  for (final y in [platformH + .5, platformH + 1.1]) {
    parts.add(
        Part(boxGeometry(x1 - x0, .06, .06), trs(cx, y, backZ + .06), _metal));
  }

  // The vertical 立入禁止 plate is mapped on the board's local +Z face after
  // the source's PI yaw, so its visible normal points toward the back fence.
  parts.add(Part(boxGeometry(.36, .72, .04),
      trs(x0 + 8.5, platformH + 1, backZ + .02, 0, math.pi), _concrete));
  appendSignAtlasPlane(mapped, railwayWarningRegion,
      width: .36,
      height: .72,
      matrix: trs(x0 + 8.5, platformH + 1, backZ + .02, 0, math.pi) *
          trs(0, 0, .0201));

  // Six overlapping steps down from the west end and their raked rails.
  for (var i = 0; i < 6; i++) {
    final h = platformH * ((6 - i) / 6);
    final x = x0 - .18 - i * .36;
    parts.add(
        Part(boxGeometry(.36, h, 2.4), trs(x, h / 2, backZ + 1.3), concrete));
  }
  for (final z in [backZ + .1, backZ + 2.5]) {
    parts.add(Part(
        boxGeometry(2.4, .07, .07), trs(x0 - 1.2, .95, z, 0, 0, .36), _metal));
  }

  // Platform lamps.
  for (final x in [x0 + 2.5, cx - 3.5, x1 - 2.0]) {
    parts.add(Part(cylGeometry(.055, .055, 3.1, 8),
        trs(x, platformH + 1.55, backZ + .5), _metalDark));
    parts.add(Part(cylGeometry(0, .26, .22, 10, openEnded: true),
        trs(x, platformH + 3.05, backZ + .5), _cabinetTop));
    parts.add(Part(boxGeometry(.18, .05, .18),
        trs(x, platformH + 2.92, backZ + .5), _warmLight));
  }
}

const _warmLight = Mat(0xfff3d4, unlit: true, noOutline: true);

void _buildLinesideWalls(List<Part> parts) {
  const wall = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
  const cap = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
  const runs = <(double, double, double)>[
    (_trackHalf + 2.6, -80, -30),
    (_trackHalf + 2.6, 46, 80),
    (-(_trackHalf + 2.6), -80, -30),
    (-(_trackHalf + 2.6), 44, 80),
  ];
  for (final run in runs) {
    final z = run.$1, x0 = run.$2, x1 = run.$3;
    parts.add(
        Part(boxGeometry(x1 - x0, 2.2, .35), trs((x0 + x1) / 2, 1.1, z), wall));
    for (final end in [x0, x1]) {
      final inward = end == x0 ? 1.0 : -1.0;
      final x = end - inward * .22;
      parts.add(Part(boxGeometry(.52, 2.52, .62), trs(x, 1.26, z), wall));
      parts.add(Part(boxGeometry(.62, .1, .72), trs(x, 2.57, z), cap));
    }
  }
}

/// Build the railway (tracks + ballast + sleepers + crossing deck) as a soup.
List<Tri> buildRailway({
  int gateYellowColor = 0xf4c033,
  bool includeCrossingBooms = true,
  bool includeActiveCrossingLamps = true,
}) {
  final parts = <Part>[];
  final mapped = <Tri>[];
  final gateYellow = Mat(gateYellowColor, tint: 0x8f7050, bands: '3');
  final cx0 = centerX(0);
  final length = _localMax - _localMin;

  // Ballast bed — a low trapezoidal prism along the track (approximated as a
  // box; the sloped shoulders are a minor detail).
  parts.add(Part(boxGeometry(length, 0.26, _trackHalf * 2 + 1.8),
      trs(0, 0.13, 0), _ballastMat));

  // Sleepers — instanced every 0.62 m, skipping the road crossing gap.
  final sleeperGeo = boxGeometry(0.24, 0.16, 2.5);
  for (double x = _localMin; x < _localMax; x += 0.62) {
    if (x.abs() < roadHalf + walkW + 0.6) continue;
    parts.add(Part(sleeperGeo, trs(x, 0.32, 0), _sleeperMat));
  }

  // Rails — dark steel web (3 boxes) + a polished head, per rail.
  for (final s in [-1.0, 1.0]) {
    final z = s * _railGauge / 2;
    parts.add(
        Part(boxGeometry(length, 0.055, 0.115), trs(0, 0.392, z), _railMat));
    parts
        .add(Part(boxGeometry(length, 0.10, 0.05), trs(0, 0.325, z), _railMat));
    parts.add(Part(boxGeometry(length, 0.03, 0.17), trs(0, 0.27, z), _railMat));
    parts.add(
        Part(boxGeometry(length, 0.016, 0.09), trs(0, 0.424, z), _headMat));
  }

  // Crossing deck through the road — concrete panels flanking/inside the rails.
  final w = roadHalf * 2 + walkW * 2 + 1.0;
  parts.add(Part(
      boxGeometry(w, 0.28, _railGauge - 0.26), trs(cx0, 0.18, 0), _deckMat));
  for (final s in [-1.0, 1.0]) {
    parts.add(Part(boxGeometry(w, 0.28, 1.55),
        trs(cx0, 0.18, s * (_railGauge / 2 + 0.12 + 0.78)), _deckMat));

    // Flangeway grooves and yellow warning bands/ticks on each approach.
    final railZ = s * _railGauge / 2;
    for (final gs in [-1.0, 1.0]) {
      parts.add(Part(boxGeometry(w, 0.06, 0.055),
          trs(cx0, 0.33, railZ + gs * 0.086), _grooveMat));
    }
    for (final band in const [(0.42, 0.30), (0.92, 0.16)]) {
      parts.add(Part(
          planeGeometry(roadHalf * 2 - 0.15, band.$2),
          trs(cx0, 0.335, s * (_trackHalf + band.$1), -math.pi / 2),
          _lineYellow));
    }
    for (int i = -5; i <= 5; i++) {
      parts.add(Part(
          planeGeometry(.5, .11),
          trs(cx0 + i * .56, 0.333, s * (_trackHalf + .67), -math.pi / 2,
              math.pi / 4),
          _lineYellow));
    }
  }

  // Lineside fencing. The opening frame sees the near-left run prominently;
  // the far-side station gap matches railway.js.
  const fenceZ = _trackHalf + 1.05;
  const gap = roadHalf + walkW + .5;
  final fenceRuns = <(double, double, double)>[
    (fenceZ, -128, -gap),
    (fenceZ, gap, 128),
    (-fenceZ, -128, -gap),
    (-fenceZ, gap, 13.5),
    (-fenceZ, 39.5, 128),
  ];
  for (final run in fenceRuns) {
    final len = run.$3 - run.$2;
    final mid = (run.$2 + run.$3) * .5;
    for (final y in [.55, 1.02]) {
      parts.add(Part(boxGeometry(1, .06, .06),
          trs(mid, y, run.$1, 0, 0, 0, len, 1, 1), _metal));
    }
    for (double x = run.$2; x <= run.$3; x += 2.4) {
      parts.add(Part(boxGeometry(.07, 1.12, .07), trs(x, .56, run.$1), _metal));
    }
    for (double x = run.$2 + .3; x <= run.$3; x += .32) {
      parts.add(Part(boxGeometry(.035, .5, .035), trs(x, .78, run.$1), _metal));
    }
  }

  // Catenary masts plus contact and messenger wires. The phase is inherited
  // from the planet-circumference loop, so the two masts nearest the crossing
  // land at x=±9.48 exactly as in the source.
  final circumference = math.pi * 2 * 160;
  final mastStep = circumference / (circumference / 19).round();
  final xMin = -circumference / 2;
  for (double x = xMin + mastStep;
      x <= circumference / 2 - mastStep * .5;
      x += mastStep) {
    if (x < _localMin || x > _localMax || x.abs() < 8) continue;
    const zf = -(_trackHalf + 1.45);
    parts.add(Part(cylGeometry(.09, .13, 6.6, 6), trs(x, 3.3, zf), _metalDark));
    parts.add(Part(boxGeometry(.1, .1, .02 - zf), trs(x, 6.1, (zf + .02) * .5),
        _metalDark));
    parts.add(Part(boxGeometry(.09, 1, .09), trs(x, 5.6, .02), _metalDark));
    parts.add(
        Part(cylGeometry(.05, .05, .28, 6), trs(x, 5.02, .02), _metalDark));
  }
  final unitWire = cylGeometry(1, 1, 1, 4);
  for (final wire in const [(4.88, .022), (5.95, .026)]) {
    final points = <Vector3>[];
    for (double x = _localMin; x <= _localMax; x += mastStep) {
      points.add(Vector3(x, wire.$1 - (wire.$1 > 5 ? .12 : 0), .02));
      points.add(Vector3(x + mastStep * .5, wire.$1, .02));
    }
    for (int i = 0; i < points.length - 1; i++) {
      _tubeBetween(parts, unitWire, points[i], points[i + 1], wire.$2);
    }
  }

  _buildCrossing(parts, mapped, gateYellow,
      includeBooms: includeCrossingBooms,
      includeActiveLamps: includeActiveCrossingLamps);
  _buildStation(parts, mapped);
  _buildLinesideWalls(parts);

  return [...bake(parts), ...mapped];
}
