/// Opening-visible geometry from the reference `school.js`.
///
/// This covers the three-storey teaching block, its west-facade bay rhythm,
/// roof furniture, front boundary and the exact cherry rows visible from the
/// crossing. Interior/courtyard detail farther behind the block remains in the
/// source module's later porting tranche.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'street.dart';

const _xWest = 10.6;
const _xEast = 84.0;
const _zSouth = -41.0;
const _zNorth = -86.0;
const _gateZ = -49.5;
const _bx0 = 24.5;
const _bx1 = 34.0;
const _bz0 = -68.0;
const _bz1 = -46.0;
const _floors = 3;
const _floorHeight = 3.5;
const _height = _floorHeight * _floors;
const _secondX0 = 25.0;
const _secondX1 = 47.0;
const _secondZ0 = -84.0;
const _secondZ1 = -75.5;
const _secondFloorHeight = 3.5;
const _secondHeight = _secondFloorHeight * 2;
const _gymX0 = 56.0;
const _gymX1 = 76.0;
const _gymZ0 = -84.0;
const _gymZ1 = -70.0;

const _wall = Mat(0xf7f3ea, tint: 0x6f6790, bands: '3');
const _wallAlt = Mat(0xe4ebf2, tint: 0x6f6790, bands: '3');
const _wallBlue = Mat(0xd3e0ec, tint: 0x6a6288, bands: '3');
const _trim = Mat(0xcfd6de, tint: 0x6a6288, bands: '3');
const _fanHood = Mat(0xb4bac4, tint: 0x655d84, bands: '3');
const _roof = Mat(0x4d5468, tint: 0x514b70, bands: '3');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _boundaryConcrete = Mat(0xc8c4cf, tint: 0x4e4772, bands: '3');
const _boundaryShadow = Mat(0x8182a2, unlit: true);
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _glass = Mat(0x53627a, unlit: true, noOutline: true);
const _interior = Mat(0xa39cb2, unlit: true, noOutline: true);
const _wood = Mat(0x9c7f5e, tint: 0x5c5680, bands: '3');
const _bronze = Mat(0x9a7a4a, tint: 0x6a5a80, bands: '3');
const _clay = Mat(0xcfb59c, tint: 0x6f6790, bands: '3');
const _asphaltWorn = Mat(0x9a95a6, tint: 0x615a82, bands: '3');
const _gymWall = Mat(0xf3f5f8, tint: 0x817aa0, bands: '3');
const _gymSunlitWestWall = Mat(0xedeff0, tint: 0x817aa0, bands: '3');
const _gymRoof = Mat(0x52586b, tint: 0x4e4970, bands: '3');
const _chainMesh = Mat(0xa8bcae, unlit: true, noOutline: true);
const _gymShadow = Mat(0x99a2c7, unlit: true);

void _add(List<Part> p, ThreeGeom geo, Matrix4 matrix, Mat mat) {
  p.add(Part(geo, matrix, mat));
}

List<Tri> _northFenceMesh(double y) {
  const z = _zNorth;
  const bottom = 1.50;
  const top = 2.30;
  const pitch = .42;
  const halfStroke = .0115;
  final out = <Tri>[];

  void ribbon(double x0, double y0, double x1, double y1) {
    final dx = x1 - x0, dy = y1 - y0;
    final inv = halfStroke / math.sqrt(dx * dx + dy * dy);
    final ox = -dy * inv, oy = dx * inv;
    final a = Vector3(x0 + ox, y + y0 + oy, z);
    final b = Vector3(x0 - ox, y + y0 - oy, z);
    final c = Vector3(x1 - ox, y + y1 - oy, z);
    final d = Vector3(x1 + ox, y + y1 + oy, z);
    final n = Vector3(0, 0, -1);
    out
      ..add(Tri(a, d, b, n, _chainMesh))
      ..add(Tri(b, d, c, n, _chainMesh));
  }

  void run(double left, double right) {
    // x-y=c family.
    for (var c = left - top; c <= right - bottom; c += pitch) {
      final y0 = math.max(bottom, left - c);
      final y1 = math.min(top, right - c);
      if (y1 > y0) ribbon(c + y0, y0, c + y1, y1);
    }
    // x+y=c family.
    for (var c = left + bottom; c <= right + top; c += pitch) {
      final y0 = math.max(bottom, c - right);
      final y1 = math.min(top, c - left);
      if (y1 > y0) ribbon(c - y0, y0, c - y1, y1);
    }
  }

  // At distance the reference texture has collapsed into its mipmapped wash;
  // retain explicit geometry only while an individual 0.42 m cell is readable.
  run(52.1, 60.0);
  return out;
}

/// A closed triangular prism matching the gym's bevel-free gable extrusion.
ThreeGeom _gableGeometry(double width, double height, double depth) {
  final x = width / 2;
  final z = depth / 2;
  final positions = Float32List.fromList([
    -x,
    0,
    -z,
    x,
    0,
    -z,
    0,
    height,
    -z,
    -x,
    0,
    z,
    0,
    height,
    z,
    x,
    0,
    z,
    -x,
    0,
    -z,
    -x,
    0,
    z,
    x,
    0,
    -z,
    x,
    0,
    z,
    x,
    0,
    -z,
    x,
    0,
    z,
    0,
    height,
    -z,
    0,
    height,
    z,
    0,
    height,
    -z,
    0,
    height,
    z,
    -x,
    0,
    -z,
    -x,
    0,
    z,
  ]);
  final slopeNormal = Vector3(height, width / 2, 0)..normalize();
  final normals = Float32List.fromList([
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    0,
    1,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    0,
    -1,
    0,
    slopeNormal.x,
    slopeNormal.y,
    0,
    slopeNormal.x,
    slopeNormal.y,
    0,
    slopeNormal.x,
    slopeNormal.y,
    0,
    slopeNormal.x,
    slopeNormal.y,
    0,
    -slopeNormal.x,
    slopeNormal.y,
    0,
    -slopeNormal.x,
    slopeNormal.y,
    0,
    -slopeNormal.x,
    slopeNormal.y,
    0,
    -slopeNormal.x,
    slopeNormal.y,
    0,
  ]);
  return ThreeGeom(positions, normals, const [
    0,
    2,
    1,
    3,
    5,
    4,
    6,
    8,
    7,
    7,
    8,
    9,
    10,
    12,
    11,
    11,
    12,
    13,
    14,
    16,
    15,
    15,
    16,
    17,
  ]);
}

/// Build the part of the school that contributes to the opening skyline.
List<Tri> buildSchool({bool includeManualShadow = false}) {
  final p = <Part>[];
  final y = groundY(-50);

  // Site surfaces and the south/front boundary establish the school scale in
  // gaps beneath the train and at the right edge of the opening.
  _add(p, boxGeometry(_bx0 - _xWest, .07, 11),
      trs((_xWest + _bx0) / 2, y + .035, -51), _concrete);
  _add(p, boxGeometry(_xEast - _xWest, .07, 3),
      trs((_xWest + _xEast) / 2, y + .035, -43.1), _concrete);
  _add(p, boxGeometry(7, .07, 4), trs(15, y + .035, -58), _concrete);
  _add(p, boxGeometry(12.5, .07, 5.4), trs(17.75, y + .035, -62.7), _concrete);
  _add(p, boxGeometry(44, .06, 22), trs(58, y + .03, -56.5), _clay);
  _add(p, boxGeometry(13, .07, 6.5), trs(41, y + .035, -71.75), _concrete);
  _add(p, boxGeometry(22, .07, 2.6), trs(66, y + .035, -69), _concrete);
  _add(p, boxGeometry(8, .07, 6), trs(51, y + .035, -71.5), _concrete);
  _add(p, boxGeometry(12.6, .07, 11), trs(17.2, y + .035, -78.2), _asphaltWorn);
  _add(
      p, boxGeometry(12.6, .07, 8.6), trs(17.2, y + .035, -68.6), _asphaltWorn);
  _add(p, boxGeometry(5.2, .07, 5.0),
      trs(50.0, y + .035, _zNorth + 2.2), _asphaltWorn);
  _boundary(p, y,
      wall: includeManualShadow ? _boundaryShadow : _boundaryConcrete);
  _teachingBlock(p, y);
  _secondBlock(p, y);
  _gymnasium(p, y,
      wall: includeManualShadow ? _gymShadow : _gymWall,
      sunlitWestWall: includeManualShadow);

  final out = bake(p);
  out.addAll(_northFenceMesh(y));
  out.addAll(_schoolTrees(y));
  return out;
}

void _boundary(List<Part> p, double y, {Mat wall = _boundaryConcrete}) {
  const wallHeight = 1.3;
  const runs = [
    ('z', _xWest, _zNorth, _gateZ - 2.8),
    ('z', _xWest, _gateZ + 3.4, _zSouth),
    ('x', _zSouth, _xWest, _xEast),
    ('z', _xEast, _zNorth, _zSouth),
    ('x', _zNorth, _xWest, 16.6),
    ('x', _zNorth, 19.4, 47.9),
    ('x', _zNorth, 52.1, _xEast),
  ];
  for (final run in runs) {
    final alongX = run.$1 == 'x';
    final from = run.$3;
    final to = run.$4;
    final at = run.$2;
    final length = (to - from).abs();
    final lo = math.min(from, to);
    final panelCount = math.max(1, (length / 4.2).round());
    final step = length / panelCount;
    for (var i = 0; i < panelCount; i++) {
      final center = lo + step * (i + .5);
      _add(
          p,
          boxGeometry(alongX ? step + .02 : .26, wallHeight,
              alongX ? .26 : step + .02),
          trs(alongX ? center : at, y - .05 + wallHeight / 2,
              alongX ? at : center),
          wall);
      _add(
          p,
          boxGeometry(alongX ? step + .02 : .38, .10,
              alongX ? .38 : step + .02),
          trs(alongX ? center : at, y + wallHeight,
              alongX ? at : center),
          _concrete);
    }
    final center = (from + to) / 2;
    // Sparse posts and two horizontal rails preserve the fence silhouette.
    final count = math.max(1, (length / 2.1).round());
    for (var i = 0; i <= count; i++) {
      final q = from + (to - from) * i / count;
      _add(p, cylGeometry(.045, .045, 1, 6),
          trs(alongX ? q : at, y + wallHeight + .6, alongX ? at : q), _metal);
    }
    for (final dy in [.22, 1.05]) {
      _add(
          p,
          boxGeometry(alongX ? length : .05, .05, alongX ? .05 : length),
          trs(alongX ? center : at, y + wallHeight + dy, alongX ? at : center),
          _metal);
    }
  }

  // Closed 4.2 m service gate facing the hill-foot road.
  for (final x in [47.9, 52.1]) {
    _add(p, boxGeometry(.54, 2.3, .54), trs(x, y + 1.10, _zNorth), _concrete);
    _add(
        p, boxGeometry(.66, .10, .66), trs(x, y + 2.30, _zNorth), _concreteMid);
  }
  const leafWidth = 1.95;
  for (final center in [49.0, 51.0]) {
    _add(p, boxGeometry(leafWidth, .08, .09), trs(center, y + 1.85, _zNorth),
        _metal);
    _add(p, boxGeometry(leafWidth, .08, .09), trs(center, y + .12, _zNorth),
        _metal);
    for (final edge in [-.935, .935]) {
      _add(p, boxGeometry(.08, 1.90, .10), trs(center + edge, y + .95, _zNorth),
          _metal);
    }
    for (var i = 1; i < 10; i++) {
      _add(
          p,
          boxGeometry(.05, 1.70, .05),
          trs(center - leafWidth / 2 + leafWidth * i / 10, y + .95, _zNorth),
          _metal);
    }
    _add(p, boxGeometry(leafWidth * .97, .06, .05),
        trs(center, y + .95, _zNorth, 0, 0, .75), _metal);
  }

  // Main gate pillars and the shut sliding leaf.
  for (final z in [_gateZ - 2.5, _gateZ + 3.1]) {
    _add(p, boxGeometry(.62, 2.55, .62), trs(_xWest, y + 1.275, z), _concrete);
    _add(p, boxGeometry(.76, .12, .76), trs(_xWest, y + 2.61, z), _concreteMid);
  }
  const gateWidth = 3.2, gateHeight = 1.85, gateCenter = _gateZ - .9;
  _add(p, boxGeometry(.07, .09, gateWidth),
      trs(_xWest, y + gateHeight - .05, gateCenter), _metal);
  _add(p, boxGeometry(.07, .09, gateWidth), trs(_xWest, y + .12, gateCenter),
      _metal);
  for (var i = 0; i <= 16; i++) {
    _add(
        p,
        boxGeometry(.05, gateHeight - .2, .05),
        trs(_xWest, y + gateHeight / 2,
            gateCenter - gateWidth / 2 + gateWidth * i / 16),
        _metal);
  }
}

/// The two-storey special-classroom block along the north boundary. Its long
/// corridor elevation is the dominant building in the back-hill road view.
void _secondBlock(List<Part> p, double y) {
  const width = _secondX1 - _secondX0;
  const depth = _secondZ1 - _secondZ0;
  const cx = (_secondX0 + _secondX1) / 2;
  const cz = (_secondZ0 + _secondZ1) / 2;
  const thickness = .3;

  _add(p, boxGeometry(width + .4, .45, depth + .4), trs(cx, y + .225, cz),
      _concreteMid);
  for (final side in [-1.0, 1.0]) {
    _add(
        p,
        boxGeometry(thickness, _secondHeight, depth),
        trs(cx + side * (width / 2 - thickness / 2), y + _secondHeight / 2, cz),
        _wall);
  }
  // Solid corridor wall beneath two long north-facing ribbon windows.
  _add(p, boxGeometry(width - thickness * 2, _secondHeight, thickness),
      trs(cx, y + _secondHeight / 2, _secondZ0 + thickness / 2), _wallAlt);
  for (var floor = 0; floor <= 2; floor++) {
    _add(p, boxGeometry(width - thickness * 2, .26, depth - thickness),
        trs(cx, y + floor * _secondFloorHeight + .13, cz), _trim);
  }
  _add(p, boxGeometry(width + .16, .16, depth + .16),
      trs(cx, y + _secondFloorHeight, cz), _trim);
  _add(p, boxGeometry(width + .5, .3, depth + .5),
      trs(cx, y + _secondHeight + .15, cz), _roof);
  for (final side in [-1.0, 1.0]) {
    _add(p, boxGeometry(width + .5, .44, .18),
        trs(cx, y + _secondHeight + .52, cz + side * (depth / 2 + .16)), _roof);
    _add(p, boxGeometry(.18, .44, depth + .5),
        trs(cx + side * (width / 2 + .16), y + _secondHeight + .52, cz), _roof);
  }

  for (var floor = 0; floor < 2; floor++) {
    final windowY = y + floor * _secondFloorHeight + 2.1;
    _add(p, boxGeometry(width - 1.6, 1.4, .05),
        trs(cx, windowY, _secondZ0 - .02), _glass);
    final divisions = ((width - 1.6) / 1.55).round();
    for (var i = 0; i <= divisions; i++) {
      _add(
          p,
          boxGeometry(.08, 1.5, .1),
          trs(cx - (width - 1.6) / 2 + (width - 1.6) * i / divisions, windowY,
              _secondZ0 - .02),
          _metal);
    }
    for (final dy in [-.76, .74]) {
      _add(p, boxGeometry(width - 1.5, .1, .18),
          trs(cx, windowY + dy, _secondZ0), _metal);
    }
  }

  // Corridor services and roof furniture carry the otherwise broad silhouette.
  for (final dx in [-7.6, -.4, 7.2]) {
    for (var floor = 0; floor < 2; floor++) {
      _add(
          p,
          cylGeometry(.07, .07, _secondFloorHeight, 6),
          trs(cx + dx, y + floor * _secondFloorHeight + _secondFloorHeight / 2,
              _secondZ0 - .2),
          _metal);
    }
  }
  final roofY = y + _secondHeight + .3;
  for (final dx in [-6.0, 4.4]) {
    _add(p, boxGeometry(1.5, .9, 1.4), trs(cx + dx, roofY + .45, cz + 1),
        _metal);
    _add(p, boxGeometry(1.7, .11, 1.6), trs(cx + dx, roofY + .95, cz + 1),
        _roof);
  }
  for (final dx in [-2.0, 1.2, 8.0]) {
    _add(p, cylGeometry(.15, .15, .85, 8), trs(cx + dx, roofY + .425, cz - 2.2),
        _metal);
    _add(p, cylGeometry(.25, .19, .16, 8), trs(cx + dx, roofY + .9, cz - 2.2),
        _metalDark);
  }
}

/// The expanded gym at the site's north-east corner. The back-hill camera is
/// only ten metres from its west gable, so the gable and north window band are
/// intentionally represented as real layered geometry rather than a backdrop.
void _gymnasium(List<Part> p, double y,
    {Mat wall = _gymWall, bool sunlitWestWall = false}) {
  const width = _gymX1 - _gymX0;
  const depth = _gymZ1 - _gymZ0;
  const cx = (_gymX0 + _gymX1) / 2;
  const cz = (_gymZ0 + _gymZ1) / 2;
  const eaves = 6.8;
  const ridge = 3.1;

  _add(p, boxGeometry(width + .4, .55, depth + .4), trs(cx, y + .275, cz),
      _trim);
  _add(p, boxGeometry(width, eaves, depth), trs(cx, y + eaves / 2, cz), wall);
  if (sunlitWestWall) {
    // The near west face points toward the reference sun and remains fully lit;
    // only the receding long face is under the measured gym shadow. The former
    // whole-box material replacement incorrectly shaded this close gable wall.
    _add(p, planeGeometry(depth, eaves),
        trs(_gymX0 - .002, y + eaves / 2, cz, 0, -math.pi / 2),
        _gymSunlitWestWall);
  }
  _add(p, boxGeometry(width + .12, .2, depth + .12), trs(cx, y + eaves, cz),
      _trim);

  final roofWidth = width + 1;
  final roofDepth = depth + 1;
  final slope = math.atan2(ridge, roofWidth / 2);
  final slab = math.sqrt(math.pow(roofWidth / 2, 2) + ridge * ridge) + .1;
  for (final side in [-1.0, 1.0]) {
    _add(
        p,
        boxGeometry(slab, .18, roofDepth),
        trs(cx + side * roofWidth / 4, y + eaves + ridge / 2, cz, 0, 0,
            -side * slope),
        _gymRoof);
  }
  _add(p, boxGeometry(.3, .22, roofDepth), trs(cx, y + eaves + ridge + .05, cz),
      _gymRoof);

  final gableHeight = ridge * (1 - 1 / roofWidth);
  for (final z in [_gymZ0 + .11, _gymZ1 - .11]) {
    _add(p, _gableGeometry(width, gableHeight, .22), trs(cx, y + eaves, z),
        wall);
  }

  // High ribbon glazing on both long walls.
  const bandY = 4.0;
  const bandHeight = 1.9;
  for (final x in [_gymX0 - .02, _gymX1 + .02]) {
    final from = _gymZ0 + (x < cx ? 1.0 : 1.6);
    final to = _gymZ1 - (x < cx ? 1.0 : 1.6);
    final len = to - from;
    _add(p, boxGeometry(.05, bandHeight, len),
        trs(x, y + bandY + bandHeight / 2, (from + to) / 2), _glass);
    final divisions = math.max(2, (len / 1.9).round());
    for (var i = 0; i <= divisions; i++) {
      _add(
          p,
          boxGeometry(.12, bandHeight + .1, .1),
          trs(x, y + bandY + bandHeight / 2, from + len * i / divisions),
          _metal);
    }
    for (final yy in [bandY - .06, bandY + bandHeight + .06]) {
      _add(p, boxGeometry(.2, .16, len + .2), trs(x, y + yy, (from + to) / 2),
          _trim);
    }
  }

  // Authored north service doors, extract fans and switch cabinet.
  final backZ = _gymZ0 - .02;
  final doorX = cx + 4.0;
  _add(p, boxGeometry(2.2, 2.3, .12), trs(doorX, y + 1.15, backZ), _trim);
  for (final side in [-1.0, 1.0]) {
    _add(p, boxGeometry(.12, 2.3, .14),
        trs(doorX + side * 1.1, y + 1.15, backZ), _metal);
    _add(p, boxGeometry(.07, .9, .06),
        trs(doorX + side * .16, y + 1.1, backZ - .09), _metal);
  }
  _add(p, boxGeometry(2.5, .13, .15), trs(doorX, y + 2.36, backZ), _metal);
  _add(p, boxGeometry(2.9, .13, 1.05), trs(doorX, y + 2.78, backZ - .5, .14),
      _roof);
  for (final x in [cx - 5.2, cx - 2.8]) {
    _add(
        p, boxGeometry(1.05, 1.05, .4), trs(x, y + 5.3, backZ - .18), _fanHood);
    _add(
        p, boxGeometry(1.2, .12, .5), trs(x, y + 5.9, backZ - .22), _metalDark);
    for (var i = 0; i < 4; i++) {
      _add(p, boxGeometry(.95, .05, .06),
          trs(x, y + 4.95 + i * .24, backZ - .4), _metal);
    }
  }
  _add(p, boxGeometry(.8, 1.3, .44), trs(cx - 8.2, y + .65, backZ - .24),
      _metal);
  _add(p, boxGeometry(.88, .08, .52), trs(cx - 8.2, y + 1.34, backZ - .24),
      _trim);

  // Four authored downpipes at the long-wall corners.
  for (final x in [_gymX0 + .16, _gymX1 - .16]) {
    for (final z in [_gymZ0 + 1.2, _gymZ1 - 1.2]) {
      _add(
          p, cylGeometry(.08, .08, eaves, 6), trs(x, y + eaves / 2, z), _metal);
    }
  }

  // Ridge ventilators break up the close roof silhouette.
  for (final dz in [-2.6, .4, 3.4]) {
    _add(p, boxGeometry(.7, .44, 1.5),
        trs(cx, y + eaves + ridge + .34, cz + dz), _metal);
    _add(p, boxGeometry(.95, .1, 1.75),
        trs(cx, y + eaves + ridge + .58, cz + dz), _gymRoof);
  }
}

void _teachingBlock(List<Part> p, double y) {
  const depth = _bx1 - _bx0;
  const length = _bz1 - _bz0;
  const cx = (_bx0 + _bx1) / 2;
  const cz = (_bz0 + _bz1) / 2;
  const thickness = .3;

  _add(p, boxGeometry(depth + .4, .5, length + .4), trs(cx, y + .25, cz),
      _concreteMid);
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(depth, _height, thickness),
        trs(cx, y + _height / 2, cz + s * (length / 2 - thickness / 2)), _wall);
  }
  _add(p, boxGeometry(thickness, _height, length - thickness * 2),
      trs(_bx1 - thickness / 2, y + _height / 2, cz), _wallAlt);
  for (var floor = 0; floor <= _floors; floor++) {
    _add(p, boxGeometry(depth - thickness, .26, length - thickness * 2),
        trs(cx, y + floor * _floorHeight + .13, cz), _trim);
  }
  for (var floor = 1; floor < _floors; floor++) {
    _add(p, boxGeometry(depth + .16, .16, length + .16),
        trs(cx, y + floor * _floorHeight, cz), _trim);
  }
  _add(p, boxGeometry(depth + .5, .3, length + .5),
      trs(cx, y + _height + .15, cz), _roof);
  for (final s in [-1.0, 1.0]) {
    _add(p, boxGeometry(depth + .5, .46, .18),
        trs(cx, y + _height + .53, cz + s * (length / 2 + .16)), _roof);
    _add(p, boxGeometry(.18, .46, length + .5),
        trs(cx + s * (depth / 2 + .16), y + _height + .53, cz), _roof);
  }

  // West facade: exact nine-bay, three-floor opening rhythm.
  const bays = 9;
  const pitch = (length - .5) / bays;
  const pier = .44;
  const openWidth = pitch - pier;
  const windowY0 = 1.0;
  const windowHeight = 1.62;
  for (var floor = 0; floor < _floors; floor++) {
    final floorY = y + floor * _floorHeight;
    _add(
        p,
        boxGeometry(thickness, windowY0 - .13, length),
        trs(_bx0 + thickness / 2, floorY + .13 + (windowY0 - .13) / 2, cz),
        _wallBlue);
    _add(
        p,
        boxGeometry(thickness, _floorHeight - windowY0 - windowHeight, length),
        trs(
            _bx0 + thickness / 2,
            floorY +
                windowY0 +
                windowHeight +
                (_floorHeight - windowY0 - windowHeight) / 2,
            cz),
        _wall);
    for (var i = 0; i <= bays; i++) {
      _add(
          p,
          boxGeometry(thickness, windowHeight, pier),
          trs(_bx0 + thickness / 2, floorY + windowY0 + windowHeight / 2,
              _bz0 + .25 + i * pitch),
          _wall);
    }
    for (var i = 0; i < bays; i++) {
      final z = _bz0 + .25 + pitch * (i + .5);
      final windowY = floorY + windowY0 + windowHeight / 2;
      _add(p, planeGeometry(openWidth + .4, windowHeight + .5),
          trs(_bx0 + 1.15, windowY, z, 0, -math.pi / 2), _interior);
      _add(p, boxGeometry(.05, windowHeight, openWidth),
          trs(_bx0 - .01, windowY, z), _glass);
      _add(p, boxGeometry(.12, .09, openWidth + .1),
          trs(_bx0 - .01, windowY + windowHeight / 2, z), _metal);
      _add(p, boxGeometry(.16, .1, openWidth + .16),
          trs(_bx0 + .01, windowY - windowHeight / 2 - .04, z), _metal);
      _add(p, boxGeometry(.09, windowHeight, .08), trs(_bx0 - .03, windowY, z),
          _metal);
    }
  }

  _roofFurniture(p, y, cx, cz);
}

void _roofFurniture(List<Part> p, double y, double cx, double cz) {
  final roofY = y + _height + .3;
  // Parapet safety rails.
  for (final x in [_bx0 + .1, _bx1 - .1]) {
    for (var i = 0; i <= 11; i++) {
      _add(p, boxGeometry(.055, 1.25, .055),
          trs(x, roofY + 1.085, _bz0 + (_bz1 - _bz0) * i / 11), _metal);
    }
    for (final dy in [.5, 1.65]) {
      _add(p, boxGeometry(.05, .05, _bz1 - _bz0), trs(x, roofY + dy, cz),
          _metal);
    }
  }
  // Water tank on legs.
  final tx = cx + 1.6, tz = _bz0 + 4.4;
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _add(p, boxGeometry(.14, 1.2, .14),
          trs(tx + sx * 1.1, roofY + .6, tz + sz * .9), _metalDark);
    }
  }
  _add(p, boxGeometry(2.8, 1.5, 2.4), trs(tx, roofY + 1.95, tz),
      const Mat(0xdcdce4, tint: 0x6a6288, bands: '3'));
  _add(p, boxGeometry(2.9, .1, 2.5), trs(tx, roofY + 2.75, tz), _metal);
  for (final dz in [-2.0, 5.6, 8.6]) {
    _add(p, cylGeometry(.16, .16, .8, 8), trs(cx - 2.4, roofY + .4, cz + dz),
        _metal);
    _add(p, cylGeometry(.26, .2, .16, 8), trs(cx - 2.4, roofY + .86, cz + dz),
        _metalDark);
  }

  // School bell housing at the south end, the highest visible marker.
  final bellZ = _bz1 - 2.6;
  const bellHeight = 2.5;
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _add(p, boxGeometry(.16, bellHeight, .16),
          trs(cx + sx * .82, roofY + bellHeight / 2, bellZ + sz * .7), _wood);
    }
  }
  _add(p, boxGeometry(2.4, .12, 2.2), trs(cx, roofY + bellHeight + .06, bellZ),
      _roof);
  _add(p, cylGeometry(.2, .34, .56, 12, openEnded: true),
      trs(cx, roofY + bellHeight - .62, bellZ), _bronze);
  _add(p, cylGeometry(.035, .035, .4, 5),
      trs(cx, roofY + bellHeight - .14, bellZ), _metalDark);
}

List<Tri> _schoolTrees(double y) {
  final spots = <SakuraSpot>[
    for (final indexed in [-44.4, -54.0, -58.0, -62.0].indexed)
      SakuraSpot(
          x: 12.4,
          y: y,
          z: indexed.$2,
          scale: 1.14 + (indexed.$1 % 2) * .1,
          seed: 620 + indexed.$1,
          lean: .12,
          leanDir: 1.2),
    const SakuraSpot(
        x: 21.6, z: -41.7, scale: 1.1, seed: 631, lean: .13, leanDir: 4.3),
    const SakuraSpot(
        x: 21.9, z: -55.6, scale: 1.06, seed: 632, lean: .11, leanDir: 4.6),
    const SakuraSpot(
        x: 16.6, z: -60.8, scale: 1.18, seed: 633, lean: .08, leanDir: 2.4),
    for (var i = 0; i < 9; i++)
      SakuraSpot(
          x: 15.5 + i * 7.4,
          y: y,
          z: _zSouth - .8,
          scale: 1.06 + (i % 3) * .09,
          seed: 640 + i,
          lean: .08,
          leanDir: 3),
    const SakuraSpot(
        x: 37.4, z: -41.6, scale: 1.2, seed: 651, lean: .1, leanDir: 2.2),
  ];
  final out = buildSakura(spots);
  out.addAll(buildShrubs([
    for (var i = 0; i < 6; i++)
      ShrubSpot(
          x: 12.2 + (i % 2) * 10.9,
          y: y,
          z: -45.4 - i * 3.1,
          r: .5,
          count: 3,
          spread: 1.1,
          seed: 660 + i),
  ]));
  return out;
}
