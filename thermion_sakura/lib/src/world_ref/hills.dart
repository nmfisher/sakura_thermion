/// Dart port of the reference `src/world/hills.js` -- the 裏山 height field
/// and its drawn triangulated surface.
///
/// Faithful port of:
///   - 32 elliptical-quartic summits (south massif, west arm, east shoulder,
///     lake rim)
///   - 3 keep-out rectangles + rail corridor
///   - screen-blend height field with pedestal
///   - slope limiter (up to 140 relaxation passes)
///   - 3 roughness octaves (MICRO / FINE / ULTRA) with spatial hash grids
///   - cover field for tone variation
///   - per-facet tone selection (5 grass/bracken/earth materials)
///   - checkerboard-diagonal triangulated mesh with flat face normals
///
/// Deferred (no Dart module yet):
///   - Lake integration (lakeGround, lakeDamp, lakeNear, inLakePoly)
///   - Canal corridor (chanHere, CANAL_X0/X1 from landform.js)
///   - Tunnel notches (inNotch, TUNNELS)
///   - Trail bench cutting (pass 4 of lattice)
///   - Plantation floor tone (standAt / litter)
///   - Instanced props (outcrops, tufts, moss, tree planting)
///   - Road/path geometry (hillPath)
///
/// Returns only the surface triangle soup; the caller is responsible for
/// merging into the scene.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'lakeform.dart';
import 'hill_planting_data.dart';
import 'hill_surface_data.dart';
import 'hill_surface_decode.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart' show groundY, terrainDrop;

// ═══════════════════════════════════════════════════════════════════════════════
// Constants (hills.js).
// ═══════════════════════════════════════════════════════════════════════════════

const _cell = 1.5;
const _skirt = 1.30;
const _ped = 2.60;
const _hmax = 21.0;

/// Mesh window bounds (lattice indices).
const _i0 = -112, _i1 = 200; // x: -168 .. 300
const _j0 = -128, _j1 = 72; // z: -192 .. 108
const _ni = _i1 - _i0 + 1; // 313
const _nj = _j1 - _j0 + 1; // 201

/// Float32 floor threshold (see JS note on FLOOR).
const _floor = -_skirt + 0.005;

// Sun direction for aspect-based tone selection.
final _sunHypot = math.sqrt(52.0 * 52.0 + 56.0 * 56.0);
final _sunAx = -52.0 / _sunHypot;
final _sunAz = 56.0 / _sunHypot;

// ═══════════════════════════════════════════════════════════════════════════════
// Utility.
// ═══════════════════════════════════════════════════════════════════════════════

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// Hermite smoothstep (port of util.js sstep).
double _sstep(double a, double b, double v) {
  final t = _clamp((v - a) / (b - a == 0 ? 1e-6 : b - a), 0.0, 1.0);
  return t * t * (3 - 2 * t);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Summit data -- the 32 elliptical quartic bumps that define the range.
// ═══════════════════════════════════════════════════════════════════════════════

class _Summit {
  const _Summit(this.x, this.z, this.rx, this.rz, this.h);
  final double x, z, rx, rz, h;
}

const _summits = <_Summit>[
  // -- south massif --
  _Summit(24, -116, 76, 30, 8.0), // A0a
  _Summit(72, -112, 50, 26, 7.0), // A0b
  _Summit(-30, -114, 54, 26, 7.0), // A0c
  _Summit(30, -140, 66, 56, 16.5), // A1
  _Summit(-26, -136, 60, 52, 14.0), // A2
  _Summit(86, -134, 58, 50, 14.5), // A3
  _Summit(22, -162, 80, 40, 17.0), // A4
  _Summit(-84, -150, 62, 48, 14.0), // A5
  _Summit(104, -164, 56, 44, 14.5), // A6
  _Summit(-124, -122, 44, 46, 12.5), // A7
  _Summit(124, -118, 44, 46, 12.5), // A8
  // -- west arm --
  _Summit(-118, -88, 46, 44, 13.0), // W1
  _Summit(-122, -52, 44, 34, 13.5), // W2
  _Summit(-112, 16, 46, 56, 17.0), // W3
  _Summit(-140, 24, 28, 30, 13.5), // W3b
  _Summit(-90, 26, 26, 28, 12.0), // W3c
  _Summit(-108, 56, 42, 32, 12.5), // W4
  _Summit(-98, 84, 36, 26, 9.5), // W5
  // -- east shoulder --
  _Summit(118, -84, 44, 42, 12.5), // E1
  _Summit(124, -48, 42, 32, 12.5), // E2
  _Summit(122, 20, 42, 34, 12.5), // E3
  _Summit(110, 58, 38, 30, 11.0), // E4
  _Summit(102, 88, 34, 26, 8.5), // E5
  _Summit(123, -13, 60, 15, 13.0), // E2b
  // -- lake rim --
  _Summit(170, -26, 46, 30, 11.5), // LN1
  _Summit(214, -24, 46, 30, 11.0), // LN2
  _Summit(252, -36, 34, 32, 10.0), // LN3
  _Summit(266, -76, 34, 42, 11.0), // LE1
  _Summit(258, -118, 34, 34, 10.5), // LE2
  _Summit(214, -152, 56, 34, 11.5), // LS1
  _Summit(158, -146, 42, 32, 11.0), // LS2
  _Summit(188, -106, 21, 18, 11.0), // LP
];

// ═══════════════════════════════════════════════════════════════════════════════
// Keep-out rectangles (ground the hills may not touch).
// ═══════════════════════════════════════════════════════════════════════════════

class _Keep {
  const _Keep(this.x0, this.x1, this.z0, this.z1, this.r);
  final double x0, x1, z0, z1, r;
}

const _keeps = <_Keep>[
  _Keep(-68, 88, -80, 114, 13), // town proper
  _Keep(-6, 94, -96, -60, 13), // school + hill-foot road
  _Keep(-84, -64, -32, 4, 11), // 一丁目 west tail
];

// ═══════════════════════════════════════════════════════════════════════════════
// Height field computation.
// ═══════════════════════════════════════════════════════════════════════════════

/// Screen blend over all summits: `1 - Pi(1 - b/HMAX)`, scaled back.
double _shapeAt(double x, double z) {
  double keepProd = 1;
  for (final s in _summits) {
    final dx = (x - s.x) / s.rx;
    final dz = (z - s.z) / s.rz;
    final d2 = dx * dx + dz * dz;
    if (d2 >= 1) continue;
    final b = s.h * (1 - d2) * (1 - d2);
    keepProd *= 1 - b / _hmax;
    if (keepProd <= 0) return _hmax;
  }
  return _hmax * (1 - keepProd);
}

/// Keep-out mask: rail corridor + KEEP rectangles.
/// Deferred: canal corridor (chanHere), tunnel nearBore (nearBore).
double _keepAt(double x, double z) {
  // rail corridor (no nearBore -> inner width = 16.0)
  final rail = _sstep(7.5, 16.0, z.abs());
  // no channel (deferred) -> chan = 1.0
  double k = rail;
  if (k <= 0) return 0;
  for (final r in _keeps) {
    final dx = math.max(math.max(r.x0 - x, x - r.x1), 0.0);
    final dz = math.max(math.max(r.z0 - z, z - r.z1), 0.0);
    k *= _sstep(0, r.r, math.sqrt(dx * dx + dz * dz));
    if (k <= 0) return 0;
  }
  return k;
}

/// Fade the far-south fringe.
double _farFade(double z) => _sstep(-196, -170, z);

// ═══════════════════════════════════════════════════════════════════════════════
// Roughness bumps.
// ═══════════════════════════════════════════════════════════════════════════════

class _Bump {
  _Bump(this.x, this.z, this.rx, this.rz, this.h);
  final double x, z, rx, rz, h;
}

// -- MICRO octave (r 7-21, h 0.55-2.05, 170 + 76 = 246 bumps) --

late final List<_Bump> _micro = _buildMicro();

List<_Bump> _buildMicro() {
  final rng = RngKit(778213);
  final out = <_Bump>[];
  for (int k = 0; k < 170; k++) {
    final x = rng.range(-166.0, 166.0);
    final z = rng.range(-190.0, 104.0);
    final r = rng.range(7.0, 21.0);
    out.add(_Bump(x, z, r * rng.range(0.7, 1.4), r * rng.range(0.7, 1.4),
        rng.range(0.55, 2.05) * (rng.chance(0.34) ? -1.0 : 1.0)));
  }
  // eastern extension
  final rngE = RngKit(551907);
  for (int k = 0; k < 76; k++) {
    final x = rngE.range(158.0, 302.0);
    final z = rngE.range(-190.0, 104.0);
    final r = rngE.range(7.0, 21.0);
    out.add(_Bump(x, z, r * rngE.range(0.7, 1.4), r * rngE.range(0.7, 1.4),
        rngE.range(0.55, 2.05) * (rngE.chance(0.34) ? -1.0 : 1.0)));
  }
  return out;
}

double _undulate(double x, double z) {
  double s = 0;
  for (final b in _micro) {
    final dx = (x - b.x) / b.rx;
    final dz = (z - b.z) / b.rz;
    final d2 = dx * dx + dz * dz;
    if (d2 >= 1) continue;
    s += b.h * (1 - d2) * (1 - d2);
  }
  return s;
}

// -- Spatial hash grid for point-queried bump fields --

Map<int, List<_Bump>> _buildSpatialGrid(List<_Bump> bumps, int cellSize) {
  final grid = <int, List<_Bump>>{};
  for (final b in bumps) {
    final i0 = ((b.x - b.rx) / cellSize).floor();
    final i1 = ((b.x + b.rx) / cellSize).floor();
    final j0 = ((b.z - b.rz) / cellSize).floor();
    final j1 = ((b.z + b.rz) / cellSize).floor();
    for (int i = i0; i <= i1; i++) {
      for (int j = j0; j <= j1; j++) {
        final key = i * 4096 + j;
        (grid[key] ??= <_Bump>[]).add(b);
      }
    }
  }
  return grid;
}

double _sampleGrid(
    Map<int, List<_Bump>> grid, int cellSize, double x, double z) {
  final a = grid[(x / cellSize).floor() * 4096 + (z / cellSize).floor()];
  if (a == null) return 0;
  double s = 0;
  for (final b in a) {
    final dx = (x - b.x) / b.rx;
    final dz = (z - b.z) / b.rz;
    final d2 = dx * dx + dz * dz;
    if (d2 >= 1) continue;
    s += b.h * (1 - d2) * (1 - d2);
  }
  return s;
}

// -- FINE octave (r 2.8-6.8, h 0.26-0.78, 2400 + 1040 = 3440 bumps) --

const _fineCellSize = 8;

late final Map<int, List<_Bump>> _fineGrid = _buildFineGrid();

Map<int, List<_Bump>> _buildFineGrid() {
  final rng = RngKit(511903);
  final bumps = <_Bump>[];
  for (int k = 0; k < 2400; k++) {
    final r = rng.range(2.8, 6.8);
    bumps.add(_Bump(
        rng.range(-168.0, 168.0),
        rng.range(-194.0, 108.0),
        r * rng.range(0.75, 1.3),
        r * rng.range(0.75, 1.3),
        rng.range(0.26, 0.78) * (rng.chance(0.42) ? -1.0 : 1.0)));
  }
  final rngE = RngKit(613481);
  for (int k = 0; k < 1040; k++) {
    final r = rngE.range(2.8, 6.8);
    bumps.add(_Bump(
        rngE.range(158.0, 302.0),
        rngE.range(-194.0, 108.0),
        r * rngE.range(0.75, 1.3),
        r * rngE.range(0.75, 1.3),
        rngE.range(0.26, 0.78) * (rngE.chance(0.42) ? -1.0 : 1.0)));
  }
  return _buildSpatialGrid(bumps, _fineCellSize);
}

double _fineAt(double x, double z) =>
    _sampleGrid(_fineGrid, _fineCellSize, x, z);

// -- ULTRA octave (r 1.4-3.4, h 0.10-0.30, 8000 + 3440 = 11440 bumps) --

const _ultraCellSize = 4;

late final Map<int, List<_Bump>> _ultraGrid = _buildUltraGrid();

Map<int, List<_Bump>> _buildUltraGrid() {
  final rng = RngKit(390211);
  final bumps = <_Bump>[];
  for (int k = 0; k < 8000; k++) {
    final r = rng.range(1.4, 3.4);
    bumps.add(_Bump(
        rng.range(-168.0, 168.0),
        rng.range(-194.0, 108.0),
        r * rng.range(0.75, 1.3),
        r * rng.range(0.75, 1.3),
        rng.range(0.10, 0.30) * (rng.chance(0.45) ? -1.0 : 1.0)));
  }
  final rngE = RngKit(728533);
  for (int k = 0; k < 3440; k++) {
    final r = rngE.range(1.4, 3.4);
    bumps.add(_Bump(
        rngE.range(158.0, 302.0),
        rngE.range(-194.0, 108.0),
        r * rngE.range(0.75, 1.3),
        r * rngE.range(0.75, 1.3),
        rngE.range(0.10, 0.30) * (rngE.chance(0.45) ? -1.0 : 1.0)));
  }
  return _buildSpatialGrid(bumps, _ultraCellSize);
}

double _ultraAt(double x, double z) =>
    _sampleGrid(_ultraGrid, _ultraCellSize, x, z);

// -- COVER field (r 6-17, h 0.5-1.15, 1100 + 470 = 1570 bumps) --
// Weighted average, not sum -- see palette note.

const _coverCellSize = 24;

late final Map<int, List<_Bump>> _coverGrid = _buildCoverGrid();

Map<int, List<_Bump>> _buildCoverGrid() {
  final rng = RngKit(20857);
  final bumps = <_Bump>[];
  for (int k = 0; k < 1100; k++) {
    final r = rng.range(6.0, 17.0);
    bumps.add(_Bump(
        rng.range(-172.0, 172.0),
        rng.range(-198.0, 112.0),
        r * rng.range(0.7, 1.45),
        r * rng.range(0.7, 1.45),
        rng.range(0.5, 1.15) * (rng.chance(0.5) ? -1.0 : 1.0)));
  }
  final rngE = RngKit(884117);
  for (int k = 0; k < 470; k++) {
    final r = rngE.range(6.0, 17.0);
    bumps.add(_Bump(
        rngE.range(158.0, 306.0),
        rngE.range(-198.0, 112.0),
        r * rngE.range(0.7, 1.45),
        r * rngE.range(0.7, 1.45),
        rngE.range(0.5, 1.15) * (rngE.chance(0.5) ? -1.0 : 1.0)));
  }
  return _buildSpatialGrid(bumps, _coverCellSize);
}

double _coverAt(double x, double z) {
  final a = _coverGrid[
      (x / _coverCellSize).floor() * 4096 + (z / _coverCellSize).floor()];
  if (a == null) return 0;
  double s = 0, w = 0;
  for (final b in a) {
    final dx = (x - b.x) / b.rx;
    final dz = (z - b.z) / b.rz;
    final d2 = dx * dx + dz * dz;
    if (d2 >= 1) continue;
    final g = (1 - d2) * (1 - d2);
    s += b.h * g;
    w += g;
  }
  return w > 0 ? s / math.max(0.55, w) : 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// The lattice.
// ═══════════════════════════════════════════════════════════════════════════════

/// Slope limit at a world point: 1.9 near rail/channel, 0.52 elsewhere.
double _slopeLimitAt(double x, double z) {
  final nearRail = z.abs() < 24;
  final nearChan = (z + 24).abs() < 22;
  return (nearRail || nearChan) ? 1.9 : 0.52;
}

/// Per-node hash in -0.5..0.5 (port of jitterAt).
double _jitterAt(int i, int j) {
  final h = mulberry32(((i & 1023) << 10 ^ (j & 1023)) + 0x9e37)();
  return h - 0.5;
}

/// Build the height lattice.  4 passes (pass 4 / bench deferred).
/// Accesses _micro, _fineGrid, _ultraGrid (initialised lazily).
late final Float32List _nodes = _buildNodes();

Float32List _buildNodes() {
  final nodes = Float32List(_ni * _nj);

  // ── pass 1: the designed surface ──
  for (int i = _i0; i <= _i1; i++) {
    for (int j = _j0; j <= _j1; j++) {
      final x = i * _cell;
      final z = j * _cell;
      final keep = _keepAt(x, z);
      // Lake bed, graded bank, rim, and embankment are part of the landform and
      // must enter before the slope limiter so the limiter preserves them.
      final natural = _shapeAt(x, z) * keep * _farFade(z) - _ped;
      nodes[(i - _i0) * _nj + (j - _j0)] =
          math.max(-_skirt, lakeGround(natural, x, z, keep));
    }
  }

  // ── pass 2: slope limiter (lowers only) ──
  final drop = Float32List(_ni * _nj);
  for (int i = _i0; i <= _i1; i++) {
    for (int j = _j0; j <= _j1; j++) {
      drop[(i - _i0) * _nj + (j - _j0)] =
          _slopeLimitAt(i * _cell, j * _cell) * _cell;
    }
  }
  for (int pass = 0; pass < 140; pass++) {
    bool worked = false;
    for (int ii = 0; ii < _ni; ii++) {
      for (int jj = 0; jj < _nj; jj++) {
        final k = ii * _nj + jj;
        final h = nodes[k];
        if (h <= _floor) continue;
        double cap = double.infinity;
        for (int e = 0; e < 4; e++) {
          final nI = ii +
              (e == 0
                  ? 1
                  : e == 1
                      ? -1
                      : 0);
          final nJ = jj +
              (e == 2
                  ? 1
                  : e == 3
                      ? -1
                      : 0);
          if (nI < 0 || nI >= _ni || nJ < 0 || nJ >= _nj) continue;
          final nK = nI * _nj + nJ;
          cap = math.min(cap, nodes[nK] + math.max(drop[k], drop[nK]));
        }
        if (cap < h) {
          nodes[k] = math.max(-_skirt, cap);
          worked = true;
        }
      }
    }
    if (!worked) break;
  }

  // ── pass 3: undulation (roughness on top of limited surface) ──
  for (int i = _i0; i <= _i1; i++) {
    for (int j = _j0; j <= _j1; j++) {
      final k = (i - _i0) * _nj + (j - _j0);
      final h = nodes[k];
      if (h <= _floor) continue;
      final x = i * _cell;
      final z = j * _cell;
      // deferred: notched check (false)
      final amp = _clamp(h / 2.4, 0.0, 1.0);
      final ampFine = _clamp(h / 1.6, 0.0, 1.0);
      final ampUltra = _clamp(h / 0.7, 0.0, 1.0);
      // Texture octaves vanish at the waterline; the wide landform octave is
      // retained at 20% in the basin so the bed is not a featureless bowl.
      final lakeWeight = lakeDamp(x, z, h);
      double disp = _undulate(x, z) * amp * (.20 + .80 * lakeWeight) +
          (_jitterAt(i, j) * 0.21 * amp +
                  _fineAt(x, z) * ampFine +
                  _ultraAt(x, z) * ampUltra) *
              lakeWeight;
      if (h > 0 && disp < -0.75 * h) disp = -0.75 * h;
      nodes[k] = math.max(-_skirt, h + disp);
    }
  }

  // ── pass 4: bench the trails (deferred) ──

  return nodes;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Lattice queries.
// ═══════════════════════════════════════════════════════════════════════════════

double _nodeAt(int i, int j) {
  if (i < _i0 || i > _i1 || j < _j0 || j > _j1) return -_skirt;
  return _nodes[(i - _i0) * _nj + (j - _j0)];
}

/// Checkerboard diagonal (prevents grain).
bool _flipped(int i, int j) => ((i & 1) ^ (j & 1)) == 1;

/// Bilinear field at an arbitrary point, over the two triangles of one cell.
/// Kept for deferred lake integration (lakeDepthAt, inLakeWater).
// ignore: unused_element
double _fieldAt(double x, double z) {
  final i = (x / _cell).floor();
  final j = (z / _cell).floor();
  if (i < _i0 || i >= _i1 || j < _j0 || j >= _j1) return -_skirt;
  final u = x / _cell - i;
  final v = z / _cell - j;
  final h00 = _nodeAt(i, j);
  final h10 = _nodeAt(i + 1, j);
  final h01 = _nodeAt(i, j + 1);
  final h11 = _nodeAt(i + 1, j + 1);
  if (_flipped(i, j)) {
    return u + v <= 1
        ? h00 + (h10 - h00) * u + (h01 - h00) * v
        : h11 + (h11 - h01) * (u - 1) + (h11 - h10) * (v - 1);
  }
  return u >= v
      ? h00 + (h10 - h00) * u + (h11 - h10) * v
      : h00 + (h11 - h01) * u + (h01 - h00) * v;
}

/// Drawn height of the hill mesh at an arbitrary world point.
///
/// Tunnel caps and other authored hillside details use this to sit directly on
/// the procedural lattice without duplicating its roughness calculation.
double hillSurfaceY(double x, double z) =>
    groundY(z) - terrainDrop + _fieldAt(x, z);

/// Raw height-field sample used by the tunnel cap where it rejoins the notch.
double hillFieldAt(double x, double z) => _fieldAt(x, z);

// ═══════════════════════════════════════════════════════════════════════════════
// Tone selection.
// ═══════════════════════════════════════════════════════════════════════════════

/// Returns 0 = grassSun, 1 = grass, 2 = grassDeep, 3 = bracken, 4 = earth.
int _faceTone(double hAvg, double slope, double gx, double gz, double hash,
    double tj, double cover) {
  // bare earth on steep faces
  if (slope > 0.88 + tj * 0.22 - cover * 0.10) return 4;
  // aspect-lit term
  final lit = slope > 1e-6
      ? ((-gx * _sunAx) + (-gz * _sunAz)) / slope * math.min(1.0, slope / 0.25)
      : 0.0;
  // bracken (dry cover)
  if (lit > 0.08 && cover + (hAvg - 6.0) * 0.02 > 0.42 + tj * 0.30) return 3;
  // green ladder: sun / mid / deep
  final key = lit + (hAvg - 7.0) * 0.022 + cover * 0.55;
  if (key > 0.46 + tj * 0.30) return 0; // sunlit turf
  if (key < -0.44 + tj * 0.30) return 2; // damp, shaded
  return 1; // mid tone
}

// ═══════════════════════════════════════════════════════════════════════════════
// Materials (inline PAL colours, cel = Mat with flat:true default).
// ═══════════════════════════════════════════════════════════════════════════════

const _mGrassSun = Mat(0xb4c98e, tint: 0x7488a8);
const _mGrass = Mat(0x9fbc90, tint: 0x6b7fa0);
const _mGrassDeep = Mat(0x7a9c78, tint: 0x60749a);
const _mBracken = Mat(0xc6bf86, tint: 0x84759c);
const _mEarth = Mat(0xbdb2a2, tint: 0x7a7396);
// Deferred: plantation floor
// const _mLitter = Mat(0x7e8163, tint: 0x847a94);
const _mLakeBed = Mat(0x9aae9e, tint: 0x6f7d96);
const _mLakeShore = Mat(0xcfc6b4, tint: 0x7a7396);

// ═══════════════════════════════════════════════════════════════════════════════
// Build the surface.
// ═══════════════════════════════════════════════════════════════════════════════

/// Build the hill surface as non-indexed flat-shaded triangles, one tone per
/// facet, grouped into grass, earth, lake-bed, and drawdown-margin materials.
/// Deferred: plantation litter and tunnel caps.
List<Tri> _buildSurface() {
  // Access _nodes to trigger lazy lattice build.
  final _ = _nodes;

  final byTone = List<List<double>>.generate(7, (_) => <double>[]);
  const mats = [
    _mGrassSun,
    _mGrass,
    _mGrassDeep,
    _mBracken,
    _mEarth,
    _mLakeBed,
    _mLakeShore,
  ];

  for (int i = _i0; i < _i1; i++) {
    for (int j = _j0; j < _j1; j++) {
      final h00 = _nodeAt(i, j);
      final h10 = _nodeAt(i + 1, j);
      final h01 = _nodeAt(i, j + 1);
      final h11 = _nodeAt(i + 1, j + 1);
      // buried apron: skip cells entirely on the floor
      if (h00 <= _floor && h10 <= _floor && h01 <= _floor && h11 <= _floor) {
        continue;
      }
      // deferred: tunnel notch check (no notches)
      // deferred: inCap check (no caps)

      final x0 = i * _cell, x1 = x0 + _cell;
      final z0 = j * _cell, z1 = z0 + _cell;
      final g0 = groundY(z0) - terrainDrop;
      final g1 = groundY(z1) - terrainDrop;

      final p00 = [x0, g0 + h00, z0];
      final p10 = [x1, g0 + h10, z0];
      final p01 = [x0, g1 + h01, z1];
      final p11 = [x1, g1 + h11, z1];

      final hash = _jitterAt(i * 3 + 1, j * 5 + 2);
      final tj =
          _jitterAt((i >> 1) * 7 + 3, (j >> 1) * 11 + 5) * 0.8 + hash * 0.2;

      // deferred: litter / standAt -> false
      final cover = _coverAt(x0 + _cell / 2, z0 + _cell / 2);
      final hAvg = (h00 + h10 + h01 + h11) / 4;
      final lake = lakeNear(x0 + _cell / 2, z0 + _cell / 2);
      var lakeTone = -1;
      if (lake != null) {
        if (lake.distance > -.4 && hAvg < lakeLevel - .02) {
          lakeTone = 5;
        } else if (lake.distance > -7 && hAvg < lakeLevel + .85) {
          lakeTone = 6;
        }
      }

      void face(List<double> a, List<double> b, List<double> c, double ha,
          double hb, double hc, double dhx, double dhz, double hs) {
        if (lakeTone >= 0) {
          byTone[lakeTone]
            ..addAll(a)
            ..addAll(b)
            ..addAll(c);
          return;
        }
        final gx = dhx / _cell;
        final gz = dhz / _cell;
        final t = _faceTone((ha + hb + hc) / 3, math.sqrt(gx * gx + gz * gz),
            gx, gz, hs, tj, cover);
        byTone[t]
          ..addAll(a)
          ..addAll(b)
          ..addAll(c);
      }

      if (_flipped(i, j)) {
        // diagonal (1,0)-(0,1):  (00,01,10) and (10,01,11)
        face(p00, p01, p10, h00, h01, h10, h10 - h00, h01 - h00, hash);
        face(p10, p01, p11, h10, h01, h11, h11 - h01, h11 - h10, -hash);
      } else {
        // diagonal (0,0)-(1,1):  (00,11,10) and (00,01,11)
        face(p00, p11, p10, h00, h11, h10, h10 - h00, h11 - h10, hash);
        face(p00, p01, p11, h00, h01, h11, h11 - h01, h01 - h00, -hash);
      }
    }
  }

  // Convert flat position lists to Tri soup with computed face normals.
  final out = <Tri>[];
  for (int t = 0; t < mats.length; t++) {
    final list = byTone[t];
    for (int k = 0; k < list.length; k += 9) {
      final a = Vector3(list[k], list[k + 1], list[k + 2]);
      final b = Vector3(list[k + 3], list[k + 4], list[k + 5]);
      final c = Vector3(list[k + 6], list[k + 7], list[k + 8]);
      final fn = (b - a).cross(c - a);
      final fl = fn.length;
      final nn = fl < 1e-12 ? Vector3(0, 1, 0) : fn / fl;
      out.add(Tri(a, b, c, nn, mats[t]));
    }
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Public entry point.
// ═══════════════════════════════════════════════════════════════════════════════

/// Build the 裏山 hill surface.  Returns flat-shaded triangles across 5
/// cel materials (grassSun / grass / grassDeep / bracken / earth).
///
/// The lattice (32 summits, slope limiter, 3 roughness octaves, cover field)
/// is built lazily on first call.  Subsequent calls return the cached mesh.
List<Tri> buildHills() {
  final exact = _buildSourceSurface();
  return exact.isEmpty ? _buildSurface() : exact;
}

List<Tri> _buildSourceSurface() {
  final packed = decodeHillSurface(base64Decode(sourceHillSurfaceZlibBase64));
  if (packed.isEmpty) return const [];
  final data = ByteData.sublistView(packed);
  const mats = [
    _mGrassSun,
    _mGrass,
    _mGrassDeep,
    _mBracken,
    _mEarth,
    Mat(0x7e8163, tint: 0x847a94),
    _mLakeBed,
    _mLakeShore,
  ];
  final out = <Tri>[];
  var offset = 0;
  for (var tone = 0; tone < mats.length; tone++) {
    final vertices = data.getUint32(offset, Endian.little);
    offset += 4;
    for (var vertex = 0; vertex < vertices; vertex += 3) {
      Vector3 point() {
        final x = data.getUint16(offset, Endian.little) / 100 - 200;
        offset += 2;
        final y = data.getUint16(offset, Endian.little) / 1000 - 10;
        offset += 2;
        final z = data.getUint16(offset, Endian.little) / 100 - 200;
        offset += 2;
        return Vector3(x, y, z);
      }

      final a = point(), b = point(), c = point();
      final cross = (b - a).cross(c - a);
      final normal =
          cross.length2 < 1e-12 ? Vector3(0, 1, 0) : cross.normalized();
      out.add(Tri(a, b, c, normal, mats[tone]));
    }
  }
  return out;
}

typedef _PlantPoint = (double, double);

const _plantPaths = <List<_PlantPoint>>[
  [
    (18, -94.5),
    (15.4, -98.4),
    (10, -101),
    (1, -103.4),
    (-9, -105.6),
    (-19, -108.4),
    (-26.5, -112.6),
    (-24, -117.6),
    (-14, -120),
    (-3, -122.4),
    (8, -126.4),
    (17, -131),
    (24.6, -135.6),
  ],
  [
    (24.6, -135.6),
    (17, -137.6),
    (8, -138.2),
    (-1, -137.4),
    (-10, -136.2),
    (-18, -135)
  ],
  [(24.6, -135.6), (29.6, -135.2), (35.4, -135.4)],
  [(-26.5, -112.6), (-32, -111), (-37, -112)],
  [(-14, -120), (-18, -124.5), (-16, -129)],
  [
    (13, -97.4),
    (26, -97.6),
    (40, -98),
    (54, -98.4),
    (68, -98.2),
    (80, -96.6),
    (86, -93.8)
  ],
  [
    (-66, 22),
    (-70, 25.5),
    (-75, 26),
    (-79.5, 23),
    (-82.5, 19),
    (-84.5, 15.5),
    (-86, 12)
  ],
  [
    (91, -18.8),
    (97.5, -18.2),
    (104, -17.4),
    (106, -16.6),
    (99, -15.6),
    (97.8, -14.8),
    (100.6, -13.6),
    (101.4, -12.4),
    (104, -12)
  ],
];

const _plantSites = <(double, double, double)>[
  (34.5, -128.2, 10),
  (-38.5, -112.5, 6.5),
  (-17, -127, 10),
  (8, -138.4, 7.5),
  (24, -99, 5.5),
  (-3, -122.4, 5),
  (-89, -9, 7),
  (91, 7.2, 7),
  (104, -12, 6.5),
  (-86, 12, 7),
  (124, -108, 9),
  (150, -40.5, 13),
  (146, -30, 9),
  (136, -76, 15),
  (167, -80, 9),
  (145, -101, 10),
  (179, -145.2, 14),
  (206, -150, 15),
  (216, -146, 10),
  (252.8, -91.4, 6.5),
];

const _plantViews = <(double, double, double, double, double, double, double)>[
  (34.5, -128.2, -4.5, 44, 9, .55, 48),
  (-86, 12, -3, -13, 6, .5, 26),
  (91, 7.2, 17, -7.2, 5.5, .45, 24),
  (104, -12, 4, 12, 5.5, .5, 24),
  (30, -139, 4.5, 10.8, 5, .35, 14),
  (124, -108, 30, 14, 7, .42, 74),
  (167, -80, 24, -12, 8, .30, 34),
  (136, -76, 24, -3, 10, .24, 32),
  (179, -145.2, -12, 24, 8, .30, 32),
  (216, -146, -14, 18, 7, .32, 30),
];

double _distanceToPlantPaths(double x, double z) {
  var best = double.infinity;
  for (final path in _plantPaths) {
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
      final t = (((x - a.$1) * dx + (z - a.$2) * dz) / (dx * dx + dz * dz))
          .clamp(0.0, 1.0);
      best = math.min(
          best,
          math.sqrt(math.pow(x - (a.$1 + dx * t), 2) +
              math.pow(z - (a.$2 + dz * t), 2)));
    }
  }
  return best;
}

bool _clearOfPlantSites(double x, double z) {
  for (final site in _plantSites) {
    final dx = x - site.$1, dz = z - site.$2;
    if (dx * dx + dz * dz < site.$3 * site.$3) return false;
  }
  return true;
}

bool _clearOfPlantViews(double x, double z) {
  for (final view in _plantViews) {
    final dx = view.$3, dz = view.$4;
    final length = math.sqrt(dx * dx + dz * dz);
    final ax = dx / length, az = dz / length;
    final px = x - view.$1, pz = z - view.$2;
    final along = px * ax + pz * az;
    if (along < -3 || along > view.$7) continue;
    final lateral = (px * az - pz * ax).abs();
    if (lateral < view.$5 + math.max(0, along) * view.$6) return false;
  }
  return true;
}

double _plantSlope(double x, double z) {
  const d = .75;
  final dx = (_fieldAt(x + d, z) - _fieldAt(x - d, z)) / (d * 2);
  final dz = (_fieldAt(x, z + d) - _fieldAt(x, z - d)) / (d * 2);
  return math.sqrt(dx * dx + dz * dz);
}

typedef _Stand = ({double x, double z, double w, double d, double rot});

const _stands = <_Stand>[
  (x: 24, z: -152, w: 60, d: 28, rot: .10),
  (x: -34, z: -140, w: 36, d: 26, rot: -.25),
  (x: 86, z: -138, w: 38, d: 26, rot: .18),
  (x: -114, z: 30, w: 40, d: 24, rot: 0),
  (x: 120, z: 30, w: 34, d: 22, rot: -.15),
  (x: 198, z: -22, w: 52, d: 20, rot: .05),
  (x: 262, z: -98, w: 26, d: 38, rot: -.12),
];

/// Source plantation boundary authority. Broadleaf candidates inside a cedar
/// compartment must be rejected even while cedar geometry itself is deferred:
/// omitting this rejection changes every subsequent seeded tree placement.
bool _insideStand(double x, double z) {
  final wobble =
      _jitterAt((x / 4.5).round() * 13 + 7, (z / 4.5).round() * 17 + 3) * 2.4;
  for (final stand in _stands) {
    final c = math.cos(stand.rot), s = math.sin(stand.rot);
    final dx = x - stand.x, dz = z - stand.z;
    final lx = dx * c + dz * s;
    final lz = -dx * s + dz * c;
    if (lx.abs() < stand.w / 2 + wobble && lz.abs() < stand.d / 2 + wobble) {
      return true;
    }
  }
  return false;
}

/// Range-wide deterministic broadleaf planting pass. Random draws for deferred
/// understorey are still consumed so every later tree retains its source pose.
List<Tri> buildHillRangePlanting({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
  List<SakuraSpot>? auditSakura,
  List<GroveSpot>? auditGrove,
}) {
  auditSakura?.addAll(sourceHillSakura);
  auditGrove?.addAll(sourceHillGrove);
  return [
    ...buildSakura(sourceHillSakura,
        blossomLightColor: blossomLightColor,
        blossomColor: blossomColor,
        blossomDeepColor: blossomDeepColor),
    ...buildGrove(sourceHillGrove),
    ...buildCedar(sourceHillCedar),
    ...buildBamboo(sourceHillBamboo),
    ...buildShrubs(sourceHillShrubs),
    ...buildHillRocks(sourceHillRocks, hillSurfaceY),
    ...buildHillTufts(sourceHillTufts, hillSurfaceY),
  ];
}

/// Algorithmic parity workbench retained for auditing rejection rules. Runtime
/// uses the source records above so later source changes cannot silently move
/// hundreds of seeded trees.
List<Tri> buildGeneratedHillRangePlanting({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
  List<SakuraSpot>? auditSakura,
  List<GroveSpot>? auditGrove,
}) {
  final rng = RngKit(31337);
  final sakura = <SakuraSpot>[];
  final grove = <GroveSpot>[];
  var tries = 0;
  const target = 560;
  while (sakura.length + grove.length < target && tries < 26000) {
    tries++;
    final x = rng.range(-166, 166);
    final z = rng.range(-190, 106);
    final field = _fieldAt(x, z);
    if (field < .5) continue;
    if (inLakePoly(x, z) && field < lakeLevel + .25) continue;
    final slope = _plantSlope(x, z);
    if (slope > .90) continue;
    final trailDistance = _distanceToPlantPaths(x, z);
    if (trailDistance < 3) continue;
    if (!_clearOfPlantSites(x, z) || !_clearOfPlantViews(x, z)) continue;
    if (_insideStand(x, z)) continue;

    final zone = x < -80
        ? 2
        : (-96 - z < 26 && x > -40 && x < 100)
            ? 0
            : 1;
    final near = math.min(1, trailDistance / 22);
    final probability = zone == 0
        ? .30 + near * .22
        : zone == 2
            ? .42 + near * .26
            : .55 + near * .30 + math.min(.16, field / 90);
    if (!rng.chance(probability)) continue;

    final seed = 40000 + sakura.length * 7 + grove.length * 3;
    final y = hillSurfaceY(x, z);
    final blossomOdds = zone == 0
        ? .42
        : zone == 2
            ? .10
            : .16;
    final isBlossom = rng.chance(blossomOdds);
    if (isBlossom) {
      sakura.add(SakuraSpot(
          x: x,
          z: z,
          y: y,
          scale: rng.range(.94, 1.26),
          seed: seed,
          lean: rng.range(.04, .15),
          leanDir: rng.range(0, math.pi * 2)));
    } else {
      grove.add(GroveSpot(
          x: x,
          z: z,
          y: y,
          scale: zone == 2 ? rng.range(1, 1.42) : rng.range(1.12, 1.68),
          seed: seed,
          spread: zone == 2 ? rng.range(.85, 1.05) : rng.range(.95, 1.25),
          lean: rng.range(.02, zone == 2 ? .14 : .08),
          leanDir: rng.range(0, math.pi * 2)));
    }

    // Preserve the exact source stream even though these lightweight details
    // are ported separately. Their conditional draws affect every subsequent
    // broadleaf placement.
    if (isBlossom && rng.chance(.3)) {
      rng.range(1.4, 2.6);
    }
    if (rng.chance(zone == 2 ? .62 : .4)) {
      rng.range(-3.4, 3.4);
      rng.range(-3.4, 3.4);
      rng.range(.42, .62);
      rng.ints(3, 5);
      rng.range(1.2, 2.2);
    }
    if (rng.chance(.24)) {
      rng.range(-4.5, 4.5);
      rng.range(-4.5, 4.5);
      rng.ints(4, 8);
      rng.range(1.2, 2.4);
    }
    if (rng.chance(zone == 2 ? .2 : .11)) {
      rng.range(-4, 4);
      rng.range(-4, 4);
      rng.ints(2, 4);
      rng.range(.5, 1.05);
      rng.range(1.2, 2.4);
    }
    if (slope > .34 && rng.chance(.14)) {
      rng.range(-3, 3);
      rng.range(-3, 3);
      rng.ints(3, 5);
      rng.range(.8, 1.5);
      rng.range(1.6, 2.8);
    }
  }

  // Independent lake-basin sweep. Its separate RNG deliberately leaves the
  // original 560-tree range stream untouched, while supplying the eastern-rim
  // trees that are visible down the Urayama road.
  final lakeRng = RngKit(46411);
  var lakeTries = 0, lakePlaced = 0;
  while (lakePlaced < 330 && lakeTries < 22000) {
    lakeTries++;
    final x = lakeRng.range(112, 292);
    final z = lakeRng.range(-158, -8);
    final field = _fieldAt(x, z);
    if (field < .5) continue;
    if (inLakePoly(x, z) && field < lakeLevel + .25) continue;
    if (_plantSlope(x, z) > .95) continue;
    final trailDistance = _distanceToPlantPaths(x, z);
    if (trailDistance < 2.6) continue;
    if (!_clearOfPlantSites(x, z) || !_clearOfPlantViews(x, z)) continue;
    if (_insideStand(x, z)) continue;
    final above = field - lakeLevel;
    final shoreish = above < 2.6;
    final probability = shoreish ? .46 : .62 + math.min(.18, field / 70);
    if (!lakeRng.chance(probability)) continue;
    lakePlaced++;
    final seed = 46000 + lakePlaced * 7;
    final y = hillSurfaceY(x, z);
    final blossom = lakeRng.chance(shoreish ? .34 : .12);
    if (blossom) {
      sakura.add(SakuraSpot(
          x: x,
          z: z,
          y: y,
          scale: lakeRng.range(.96, 1.3),
          seed: seed,
          lean: lakeRng.range(.05, .17),
          leanDir: math.atan2(-(x - 190), -(z + 84)) + lakeRng.range(-.5, .5)));
      if (lakeRng.chance(.4)) lakeRng.range(1.6, 3.0);
    } else {
      grove.add(GroveSpot(
          x: x,
          z: z,
          y: y,
          scale: shoreish ? lakeRng.range(1.05, 1.5) : lakeRng.range(1.15, 1.7),
          seed: seed,
          spread: shoreish ? lakeRng.range(1.0, 1.34) : lakeRng.range(.95, 1.2),
          lean: lakeRng.range(.02, shoreish ? .12 : .07),
          leanDir: lakeRng.range(0, 6.28)));
    }
    if (lakeRng.chance(shoreish ? .52 : .36)) {
      lakeRng.range(-3.2, 3.2);
      lakeRng.range(-3.2, 3.2);
      lakeRng.range(.44, .66);
      lakeRng.ints(3, 5);
      lakeRng.range(1.3, 2.4);
    }
    if (lakeRng.chance(.3)) {
      lakeRng.range(-4.5, 4.5);
      lakeRng.range(-4.5, 4.5);
      lakeRng.ints(4, 8);
      lakeRng.range(1.2, 2.6);
    }
    if (lakeRng.chance(.12)) {
      lakeRng.range(-4, 4);
      lakeRng.range(-4, 4);
      lakeRng.ints(2, 4);
      lakeRng.range(.45, 1.0);
      lakeRng.range(1.2, 2.4);
    }
    if (above < 1.4 && lakeRng.chance(.3)) {
      lakeRng.range(-2.5, 2.5);
      lakeRng.range(-2.5, 2.5);
      lakeRng.ints(3, 5);
      lakeRng.range(.8, 1.6);
      lakeRng.range(1.4, 2.6);
    }
  }

  for (final willow in const [
    (144.0, -93.0, 1.08),
    (147.2, -103.6, 1.12),
    (156.0, -122.6, 1.06),
    (170.0, -128.4, 1.10),
    (203.6, -128.4, 1.12),
    (214.4, -131.6, 1.08),
    (228.4, -127.0, 1.04),
    (246.0, -108.0, 1.06),
  ]) {
    final field = _fieldAt(willow.$1, willow.$2);
    if (field <= lakeLevel) continue;
    grove.add(GroveSpot(
        x: willow.$1,
        z: willow.$2,
        y: hillSurfaceY(willow.$1, willow.$2),
        scale: willow.$3,
        seed: 47100 + willow.$1.round(),
        spread: 1.55,
        lean: .16,
        leanDir: math.atan2(-(willow.$1 - 190), -(willow.$2 + 84)),
        willow: true));
  }
  auditSakura?.addAll(sakura);
  auditGrove?.addAll(grove);
  return [
    ...buildSakura(sakura,
        blossomLightColor: blossomLightColor,
        blossomColor: blossomColor,
        blossomDeepColor: blossomDeepColor),
    ...buildGrove(grove),
  ];
}

/// Camera-relevant portion of `hills.js::plantRange` behind the school.
///
/// The complete reference range contains more than a thousand trees, most of
/// which are below the curved-world horizon in the fidelity views. These are
/// the exact deterministic spots whose crowns form the school approach's
/// visible middle-distance tree belt.
List<Tri> buildVisibleHillPlanting({
  int blossomLightColor = 0xfff0f4,
  int blossomColor = 0xfbc6d8,
  int blossomDeepColor = 0xf0a3c0,
}) {
  final out = <Tri>[];
  out.addAll(buildGrove(const [
    GroveSpot(
        x: -42.995870899409056,
        y: 11.242622665547579,
        z: -121.29305558465421,
        scale: 1.1566055730357767,
        seed: 41203,
        spread: 1.1331297074677422,
        lean: 0.021221415526233613,
        leanDir: 5.999736381499097),
    GroveSpot(
        x: -33.8666699193418,
        y: 13.038831128145665,
        z: -126.99728834815323,
        scale: 1.6480992131493986,
        seed: 41502,
        spread: 1.2020625022705644,
        lean: 0.05181932992767542,
        leanDir: 2.070651980228722),
    GroveSpot(
        x: -31.80040808673948,
        y: 13.22303480608858,
        z: -124.77374181523919,
        scale: 1.5129245121218264,
        seed: 41943,
        spread: 1.028434714768082,
        lean: 0.03285798285156488,
        leanDir: 5.63783243524842),
    GroveSpot(
        x: -7.047998,
        y: 7.174998,
        z: -114.103998,
        scale: 1.158998,
        seed: 40212,
        spread: 1.041998,
        lean: 0.064998,
        leanDir: 4.612998),
    GroveSpot(
        x: -1.090998,
        y: 5.333998,
        z: -109.675998,
        scale: 1.136998,
        seed: 40117,
        spread: 0.973998,
        lean: 0.068998,
        leanDir: 0.611998),
    GroveSpot(
        x: 11.020998,
        y: 8.842998,
        z: -118.718998,
        scale: 1.164998,
        seed: 41803,
        spread: 1.040998,
        lean: 0.022998,
        leanDir: 3.858998),
  ]));
  out.addAll(buildSakura(
    const [
      SakuraSpot(
          x: -30.337178562767804,
          y: 5.673759999641958,
          z: -102.72493385337293,
          scale: 1.0694407513737678,
          seed: 41108,
          lean: 0.12749937546206638,
          leanDir: 0.3915402727108449),
      SakuraSpot(
          x: -14.494,
          y: 16.921,
          z: -145.442,
          scale: 1.077,
          seed: 40967,
          lean: 0.068,
          leanDir: 2.863),
      SakuraSpot(
          x: -12.572,
          y: 16.316,
          z: -148.885,
          scale: 0.942,
          seed: 41366,
          lean: 0.074,
          leanDir: 2.177),
      SakuraSpot(
          x: -11.785,
          y: 16.240,
          z: -150.236,
          scale: 1.084,
          seed: 40912,
          lean: 0.046,
          leanDir: 2.588),
      SakuraSpot(
          x: 3.487,
          y: 6.603,
          z: -112.665,
          scale: 1.135,
          seed: 40698,
          lean: 0.080,
          leanDir: 0.409),
      SakuraSpot(
          x: 10.942,
          y: 9.145,
          z: -119.406,
          scale: 1.104,
          seed: 40292,
          lean: 0.134,
          leanDir: 5.647),
      SakuraSpot(
          x: 12.107,
          y: 7.612,
          z: -116.683,
          scale: 0.959,
          seed: 40824,
          lean: 0.083,
          leanDir: 3.467),
    ],
    blossomLightColor: blossomLightColor,
    blossomColor: blossomColor,
    blossomDeepColor: blossomDeepColor,
  ));
  out.addAll(buildCedar(const [
    CedarSpot(
        x: -36.167,
        y: 13.137,
        z: -142.091,
        scale: 0.990,
        seed: 52610,
        lean: 0.033,
        leanDir: 5.187),
    CedarSpot(
        x: -26.268,
        y: 13.854,
        z: -132.329,
        scale: 1.064,
        seed: 52690,
        lean: 0.012,
        leanDir: 5.506),
    CedarSpot(
        x: -20.199,
        y: 15.076,
        z: -141.321,
        scale: 1.200,
        seed: 52740,
        lean: 0.005,
        leanDir: 3.232),
    CedarSpot(
        x: 21.021,
        y: 16.971,
        z: -141.918,
        scale: 0.933,
        seed: 52230,
        lean: 0.015,
        leanDir: 3.189),
    CedarSpot(
        x: 24.927,
        y: 17.633,
        z: -142.705,
        scale: 0.965,
        seed: 52260,
        lean: 0.028,
        leanDir: 2.324),
    CedarSpot(
        x: 28.792,
        y: 19.128,
        z: -145.117,
        scale: 0.966,
        seed: 52285,
        lean: 0.031,
        leanDir: 0.001),
  ]));
  return out;
}
