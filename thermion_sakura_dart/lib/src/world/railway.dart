/// The railway — a port of the reference `src/world/railway.js`, focused on
/// the level crossing (the namesake of the scene): ballast bed, sleepers,
/// rails, the crossing deck through the road, and the gates with signals.
/// Single track running along X at z = 0.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import '../palette.dart';
import 'street.dart';

const double railGauge = 1.44;
const double railTop = 0.30;

const double _xMin = -120;
const double _xMax = 80;

/// Build the track + crossing into [m].
void buildRailway(Mesh m) {
  _ballast(m);
  _sleepers(m);
  _rails(m, _xMin, _xMax);
  _crossingDeck(m);
  _gates(m);
  _fence(m);
}

void _ballast(Mesh m) {
  // trapezoid bed: flat top at y 0.26 across the gauge, slopes to the ground
  final zHalf = trackHalf + 0.9;
  final n = 60;
  for (int i = 0; i < n; i++) {
    final x0 = _xMin + (_xMax - _xMin) * (i / n);
    final x1 = _xMin + (_xMax - _xMin) * ((i + 1) / n);
    // top face
    m.quad(
      Vector3(x0, 0.26, -trackHalf),
      Vector3(x0, 0.26, trackHalf),
      Vector3(x1, 0.26, trackHalf),
      Vector3(x1, 0.26, -trackHalf),
      color: Pal.ballast, tint: 0x655d84,
    );
    // slopes
    m.quad(
      Vector3(x0, 0, -zHalf),
      Vector3(x0, 0.26, -trackHalf),
      Vector3(x1, 0.26, -trackHalf),
      Vector3(x1, 0, -zHalf),
      color: Pal.ballast, tint: 0x655d84,
    );
    m.quad(
      Vector3(x0, 0, zHalf),
      Vector3(x1, 0, zHalf),
      Vector3(x1, 0.26, trackHalf),
      Vector3(x0, 0.26, trackHalf),
      color: Pal.ballast, tint: 0x655d84,
    );
  }
}

void _sleepers(Mesh m) {
  for (double x = _xMin; x < _xMax; x += 0.62) {
    if (x.abs() < roadHalf + walkW + 0.6) continue;
    m.boxAt(0.24, 0.16, 2.5, Pal.sleeper, x, 0.32, 0, tint: 0x5d5878);
  }
}

void _rails(Mesh m, double x0, double x1) {
  final L = x1 - x0;
  final mid = (x0 + x1) / 2;
  for (final s in [-1.0, 1.0]) {
    final zr = s * railGauge / 2;
    // web (dark steel) — a few stacked boxes for the rail profile
    m.boxAt(L, 0.055, 0.115, Pal.railMetal, mid, 0.392, zr, tint: 0x5f5878);
    m.boxAt(L, 0.10, 0.05, Pal.railMetal, mid, 0.325, zr, tint: 0x5f5878);
    m.boxAt(L, 0.03, 0.17, Pal.railMetal, mid, 0.27, zr, tint: 0x5f5878);
    // polished running surface
    m.boxAt(L, 0.016, 0.09, Pal.railHead, mid, 0.424, zr, tint: 0x6f6890, bands: '2');
  }
}

void _crossingDeck(Mesh m) {
  final w = roadHalf * 2 + walkW * 2 + 1.0;
  final cx = centerX(0);
  const deck = 0xb0abb5;
  // concrete panels either side of each rail
  m.boxAt(w, 0.28, railGauge - 0.26, deck, cx, 0.18, 0, tint: 0x6f6790);
  for (final s in [-1.0, 1.0]) {
    m.boxAt(w, 0.28, 1.55, deck, cx, 0.18, s * (railGauge / 2 + 0.90), tint: 0x6f6790);
    // rails continue across the deck, proud of the concrete
    m.boxAt(w, 0.12, 0.115, Pal.railMetal, cx, 0.36, s * railGauge / 2, tint: 0x5f5878);
    m.boxAt(w, 0.016, 0.09, Pal.railHead, cx, 0.424, s * railGauge / 2, tint: 0x6f6890, bands: '2');
    // flangeway grooves
    for (final gs in [-1.0, 1.0]) {
      m.boxAt(w, 0.06, 0.055, 0x4d4757, cx, 0.33, s * railGauge / 2 + gs * 0.086, tint: 0x413c58, bands: '2');
    }
  }
  // yellow hazard bands + diagonal ticks on the road either side of the tracks
  for (final s in [-1.0, 1.0]) {
    for (final [off, wide] in [[0.42, 0.3], [0.92, 0.16]]) {
      m.quadRaw(
        Vector3(cx - roadHalf + 0.075, 0.335, s * (trackHalf + off) - wide / 2),
        Vector3(cx - roadHalf + 0.075, 0.335, s * (trackHalf + off) + wide / 2),
        Vector3(cx + roadHalf - 0.075, 0.335, s * (trackHalf + off) + wide / 2),
        Vector3(cx + roadHalf - 0.075, 0.335, s * (trackHalf + off) - wide / 2),
        C.srgb(Pal.lineYellow),
        normal: Vector3(0, 1, 0),
      );
    }
    for (int i = -5; i <= 5; i++) {
      // diagonal ticks
      final x0 = cx + i * 0.56 - 0.25, x1 = cx + i * 0.56 + 0.25;
      final z = s * (trackHalf + 0.67);
      m.quadRaw(
        Vector3(x0, 0.333, z - 0.055),
        Vector3(x0, 0.333, z + 0.055),
        Vector3(x1, 0.333, z + 0.055),
        Vector3(x1, 0.333, z - 0.055),
        C.srgb(Pal.lineYellow),
        normal: Vector3(0, 1, 0),
      );
    }
  }
}

/// Gates at z = ±GATE_Z, matching the reference's crossing hardware: a yellow
/// signal mast with a red signal head, a yellow-black boom raised at an angle,
/// and a red-white barrier arm lowered across the road (the train is coming).
void _gates(Mesh m) {
  for (final sz in [-1.0, 1.0]) {
    final z = sz * gateZ;
    final yBase = groundY(z);
    final armLen = (roadHalf - 0.35) * 2;

    // corner machinery housings at the road edges
    for (final sx in [-1.0, 1.0]) {
      final x = sx * (roadHalf + 0.42);
      // concrete base
      m.boxAt(0.66, 0.2, 0.62, Pal.concrete, x, yBase + 0.1, z, tint: 0x6f6790);
      // barrier machine cabinet
      m.boxAt(0.46, 0.92, 0.38, Pal.cabinet, x, yBase + 0.66, z, tint: 0x6f6890);
      m.boxAt(0.54, 0.07, 0.46, Pal.cabinetTop, x, yBase + 1.14, z, tint: 0x6f6890);
    }

    // yellow signal mast with black bands + red signal head, at the road edge
    final mastX = roadHalf + 0.42 - 0.44;
    for (final sx in [-1.0, 1.0]) {
      final x = sx * mastX;
      m.cylUnit(Matrix4.translation(Vector3(x, yBase + 1.42, z))..scale(0.08, 2.45, 0.08),
          Pal.gateYellow, segments: 8, tint: 0x8f7050);
      for (int i = 0; i < 4; i++) {
        m.cylUnit(Matrix4.translation(Vector3(x, yBase + 0.62 + i * 0.56, z))..scale(0.085, 0.22, 0.085),
            Pal.gateBlack, segments: 8, tint: 0x4b4560, bands: '2');
      }
      // signal head: two red lamps on a black bar, facing along the road
      final hy = yBase + 2.67;
      m.boxAt(0.86, 0.13, 0.1, Pal.gateBlack, x, hy, z, tint: 0x4b4560, bands: '2');
      for (final lx in [-0.28, 0.28]) {
        m.cylUnit(Matrix4.translation(Vector3(x + lx, hy - 0.12, z + 0.07))..scale(0.15, 0.13, 0.15),
            Pal.gateBlack, segments: 10, tint: 0x4b4560, bands: '2');
        m.quadRaw(
          Vector3(x + lx - 0.11, hy - 0.17, z + 0.071),
          Vector3(x + lx + 0.11, hy - 0.17, z + 0.071),
          Vector3(x + lx + 0.11, hy - 0.02, z + 0.071),
          Vector3(x + lx - 0.11, hy - 0.02, z + 0.071),
          C.srgb(Pal.signalRed) * 0.95,
          normal: Vector3(0, 0, 1),
        );
      }
    }

    // yellow-black boom, raised at an angle from the near-side machine
    final boomY = yBase + 1.15;
    final tilt = 0.62; // radians up
    final hingeX = -(roadHalf - 0.4);
    for (int i = 0; i < 7; i++) {
      final t0 = i / 7.0, t1 = (i + 1) / 7.0;
      final x0 = hingeX + t0 * armLen, x1 = hingeX + t1 * armLen;
      final y0 = boomY + t0 * math.sin(tilt) * 0.8, y1 = boomY + t1 * math.sin(tilt) * 0.8;
      final col = i.isEven ? Pal.gateYellow : Pal.gateBlack;
      m.boxAt((x1 - x0) * 1.05, 0.09, 0.09, col, (x0 + x1) / 2, (y0 + y1) / 2, z,
          tint: 0x8f7050, bands: '2');
    }
    // red-white barrier arm, lowered across the road
    for (int i = 0; i < 7; i++) {
      final t0 = i / 7.0, t1 = (i + 1) / 7.0;
      final x0 = -armLen / 2 + t0 * armLen, x1 = -armLen / 2 + t1 * armLen;
      final col = i.isEven ? Pal.red : Pal.lineWhite;
      m.boxAt((x1 - x0) * 1.05, 0.08, 0.06, col, (x0 + x1) / 2, yBase + 1.02, z,
          tint: 0x6a4060, bands: '2');
    }
    // barrier pivot housings
    for (final sx in [-1.0, 1.0]) {
      m.boxAt(0.3, 0.5, 0.3, Pal.gateBlack, sx * (roadHalf - 0.35), yBase + 0.9, z,
          tint: 0x4b4560, bands: '2');
    }
  }
}

/// The train — the reference's white DMU with a blue stripe, crossing the
/// road at the moment the opening frame is taken (the gates are down for it).
/// Two carriages along the track at z = 0, rail top ≈ 0.42.
void buildTrain(Mesh m) {
  const carriageLen = 16.0;
  const x0 = -24.0;
  final railTop = 0.42;
  for (int c = 0; c < 2; c++) {
    final cx = x0 + c * carriageLen + carriageLen / 2;
    // body
    m.boxAt(carriageLen, 2.2, 2.75, Pal.trainBody, cx, railTop + 0.3 + 1.1, 0, tint: 0x6f6890);
    // roof
    m.boxAt(carriageLen - 0.2, 0.18, 2.5, Pal.trainRoof, cx, railTop + 0.3 + 2.2 + 0.09, 0,
        tint: 0x666090, bands: '2');
    // skirt
    m.boxAt(carriageLen, 0.3, 2.6, Pal.trainSkirt, cx, railTop + 0.15, 0, tint: 0x5c5680, bands: '2');
    // blue stripe along both sides
    for (final s in [-1.0, 1.0]) {
      m.boxAt(carriageLen, 0.22, 0.06, Pal.trainStripe, cx, railTop + 1.25, s * 1.38,
          tint: 0x4a5278, bands: '2');
      m.boxAt(carriageLen, 0.22, 0.06, Pal.trainStripe2, cx, railTop + 0.85, s * 1.38,
          tint: 0x4a6a68, bands: '2');
    }
    // windows (dark row on both sides)
    for (final s in [-1.0, 1.0]) {
      for (int w = 0; w < 6; w++) {
        final wx = cx - carriageLen / 2 + 1.5 + w * 2.5;
        m.boxAt(1.7, 0.85, 0.08, Pal.trainWindow, wx, railTop + 1.85, s * 1.38,
            tint: 0x4a4468, bands: '2');
      }
      // doors
      for (final dx in [-carriageLen * 0.22, carriageLen * 0.22]) {
        m.boxAt(1.2, 1.7, 0.06, Pal.trainDoor, cx + dx, railTop + 1.0, s * 1.38,
            tint: 0x6f6890, bands: '2');
      }
    }
    // carriage end faces
    for (final ex in [-carriageLen / 2, carriageLen / 2]) {
      m.boxAt(0.05, 2.6, 2.8, Pal.trainBodyShade, cx + ex, railTop + 0.3 + 1.3, 0,
          tint: 0x6f6890, bands: '2');
      // dark window band on the front
      m.boxAt(0.06, 0.7, 1.9, Pal.trainWindow, cx + ex, railTop + 1.9, 0, tint: 0x4a4468, bands: '2');
    }
  }
}

/// Lineside fence: posts + two rails either side, broken at the crossing.
void _fence(Mesh m) {
  const fz = trackHalf + 1.05;
  final gap = roadHalf + walkW + 0.5;
  void run(double z, double x0, double x1) {
    if (x1 - x0 < 0.7) return;
    for (double x = x0; x <= x1; x += 3.0) {
      m.boxAt(0.07, 1.12, 0.07, Pal.metalDark, x, 0.56, z, tint: 0x5c5680);
    }
    for (final yy in [0.55, 1.02]) {
      final n = math.max(2, ((x1 - x0) / 3.0).round());
      for (int i = 0; i < n; i++) {
        final a = x0 + (x1 - x0) * (i / n);
        final b = x0 + (x1 - x0) * ((i + 1) / n);
        m.boxAt(b - a, 0.06, 0.06, Pal.metal, (a + b) / 2, yy, z, tint: 0x666090);
      }
    }
  }

  run(fz, _xMin, -gap);
  run(fz, gap, _xMax);
  run(-fz, _xMin, -gap);
  run(-fz, gap, 13.5);
}
