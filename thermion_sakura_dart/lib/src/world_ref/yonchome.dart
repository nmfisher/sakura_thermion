/// Major visible geometry from `yonchome.js` (ひばり台四丁目).
///
/// This tranche covers the maintained lane, east arm, community hall and its
/// forecourt furniture. It is the complete composition seen from the suite's
/// `yonchome_hall` camera; the park and northern housing row remain separate
/// follow-up tranches.
library;

import 'dart:math' as math;

import '../geom/three_geom.dart';
import 'details.dart';
import 'make_hall.dart';
import 'make_house.dart';
import 'make_pole.dart';
import 'make_props.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'petals.dart';
import 'sign_atlas.dart';

const _y = .45;
const _road = Mat(0x9a95a6, tint: 0x6a608f, bands: '3');
const _roadPatch = Mat(0x8c8799, tint: 0x6a608f, bands: '3');
const _concrete = Mat(0xd9d5dd, tint: 0x6f6790, bands: '3');
const _concreteMid = Mat(0xc2bdc8, tint: 0x6a6288, bands: '3');
const _curb = Mat(0xc7c2d0, tint: 0x6f6790, bands: '3');
const _line = Mat(0xf4f2f6, tint: 0x8e86ad, bands: '2');
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _shellTrim = Mat(0x9aa0a8, tint: 0x5c5680, bands: '3');
const _shelterSheet = Mat(0xb0c4d0, unlit: true, noOutline: true);
const _dark = Mat(0x322e3b, tint: 0x4b4560, bands: '2');
const _wallGray = Mat(0xdedee6, unlit: true);
const _wood = Mat(0x8a6f52, tint: 0x5c5680, bands: '3');
const _cork = Mat(0xb59668, tint: 0x6f6790, bands: '3');
const _paper = Mat(0xfffbec, unlit: true, noOutline: true);
const _print = Mat(0x54736f, unlit: true, noOutline: true);
const _binBlue = Mat(0x4a7fae, tint: 0x6f6790, bands: '3');
const _binGreen = Mat(0x7fae6a, tint: 0x6f6790, bands: '3');
const _binYellow = Mat(0xd8c34a, tint: 0x6f6790, bands: '3');

void _box(List<Part> parts, double w, double h, double d, Mat mat, double x,
    double y, double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  parts.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), mat));
}

void _lineZ(List<Part> parts, double x, double from, double to, double y) {
  _box(parts, .075, .012, to - from, _line, x, y, (from + to) / 2);
}

void _lineX(List<Part> parts, double z, double from, double to, double y) {
  _box(parts, to - from, .012, .075, _line, (from + to) / 2, y, z);
}

List<Tri> _gomiHouse({List<Tri>? shadowCasters}) {
  final p = <Part>[];
  const x = 9.5, z = 67.6, fy = _y + .07;
  const w = 1.9, d = 1.1, h = 1.05, t = .12, slab = .09;
  const top = slab + h + .06;
  _box(p, w + .12, slab, d + .12, _concreteMid, x, fy + slab / 2, z);
  _box(p, w, h, t, _concreteMid, x, fy + slab + h / 2, z - (d / 2 - t / 2));
  for (final sx in [-1.0, 1.0]) {
    _box(p, t, h, d, _concreteMid, x + sx * (w / 2 - t / 2), fy + slab + h / 2,
        z);
    _box(p, t + .08, .06, d + .08, _concrete, x + sx * (w / 2 - t / 2),
        fy + top - .03, z);
  }
  _box(p, w + .08, .06, t + .08, _concrete, x, fy + top - .03,
      z - (d / 2 - t / 2));
  _box(p, w + .14, .05, d + .22, _shellTrim, x, fy + top + .05, z + .02, -.10);
  _box(p, w + .14, .05, .06, _shellTrim, x, fy + top + .11, z + d / 2 + .11);
  for (final sx in [-1.0, 1.0]) {
    _box(p, .05, .05, d + .10, _metalDark, x + sx * (w / 2 - t), fy + top + .01,
        z + .02, -.10);
  }
  // Three colour-coded bins visible through the mesh gate.
  const mats = [_binBlue, _binGreen, _binYellow];
  for (var i = 0; i < 3; i++) {
    final bx = x - .52 + i * .52;
    _box(p, .44, .62, .40, mats[i], bx, fy + slab + .31, z - .06);
    _box(p, .47, .05, .43, _dark, bx, fy + slab + .64, z - .06);
  }
  // Front gate, hinged on the west jamb and swung toward the lane by the
  // source's -0.42 rad. Baking it flat shortened this foreground screen by
  // nearly half in projection.
  const gateW = 1.62, gateH = .92;
  final gateMx = trs(x - .83, fy + slab, z + d / 2 - .06, 0, -.42);
  for (final gx in [.025, gateW - .025]) {
    p.add(Part(
        boxGeometry(.05, gateH, .05), gateMx * trs(gx, gateH / 2, 0), _metal));
  }
  for (final gy in [.025, gateH / 2, gateH - .025]) {
    p.add(Part(boxGeometry(gateW, .045, .045), gateMx * trs(gateW / 2, gy, 0),
        _metal));
  }
  for (final hy in [slab + .16, slab + gateH - .16]) {
    p.add(Part(cylGeometry(.028, .028, .09, 6),
        trs(x - (w / 2 - t), fy + hy, z + d / 2 - .06), _metalDark));
  }
  _box(p, .05, .10, .06, _metalDark, x + w / 2 - t + .02, fy + slab + .50,
      z + d / 2 - .05);

  // The sign is a real 30 mm box in the source, with the mapped face only on
  // local -X. Its edge therefore still inks at a grazing angle.
  _box(p, .03, .30, .42, _wallGray, x - (w / 2 + .005), fy + slab + h * .60,
      z + .06);

  final solid = bake(p);
  shadowCasters?.addAll(solid);
  final out = List<Tri>.of(solid);
  appendSignAtlasPlane(out, gomiPlateRegion,
      width: .42,
      height: .30,
      matrix: trs(x - (w / 2 + .005) - .0151, fy + slab + h * .60, z + .06, 0,
          -math.pi / 2));
  appendSignAtlasPlane(out, gomiGateRegion,
      width: gateW - .08,
      height: gateH - .10,
      matrix: gateMx * trs(gateW / 2, gateH / 2, .001),
      material: const Mat(0xc2c8d0, unlit: true, noOutline: true));
  return out;
}

List<Tri> _hallStorageShed() {
  const x = 19.3, z = 59.0, w = 1.6, d = .8, h = 1.72;
  const shell = Mat(0xcdd2cf, tint: 0x6a6288, bands: '3');
  const trim = Mat(0x8f9a96, tint: 0x5c5680, bands: '3');
  final p = <Part>[];
  _box(p, w + .1, .09, d + .1, _concreteMid, x, _y + .045, z);
  _box(p, w, h, d, shell, x, _y + .09 + h / 2, z);
  final ribs = (w / .14).round();
  for (var i = 0; i < ribs; i++) {
    _box(p, .05, h - .24, d + .03, trim,
        x - w / 2 + .07 + i * ((w - .14) / (ribs - 1)), _y + .09 + h / 2, z);
  }
  _box(p, w + .12, .06, d + .14, trim, x, _y + .09 + h + .05, z - .02, .06);
  _box(p, w + .14, .05, .05, trim, x, _y + .09 + h + .015, z + d / 2 + .06);
  for (final side in [-1.0, 1.0]) {
    _box(p, w / 2 - .03, h - .3, .03, shell, x + side * w / 4,
        _y + .09 + h / 2 - .02, z + d / 2 + .02);
    _box(p, .04, .24, .05, _metalDark, x + side * .07, _y + .09 + h * .55,
        z + d / 2 + .045);
  }
  for (final sy in [_y + .24, _y + .09 + h - .13]) {
    _box(p, w, .05, .06, trim, x, sy, z + d / 2 + .03);
  }
  return bake(p);
}

List<Tri> _northHousing() {
  final out = <Tri>[];

  // ハイツ ひばり: the source uses makeWalkup, which is not otherwise needed
  // by the native port. Keep its measured envelope and rebuild the visible
  // street-facing gallery on top of the shared house geometry.
  out.addAll(makeHouse(const HouseOpts(
      x: 14.6,
      z: 76.5,
      y: _y,
      w: 6.4,
      d: 6.6,
      floors: 3,
      face: 'z-',
      wall: 0,
      roof: 1,
      roofKind: 'flat',
      seed: 8330)));
  final p = <Part>[];
  for (final floorY in [3.12, 5.84]) {
    _box(p, 6.25, .12, .82, _concrete, 14.6, _y + floorY, 72.86);
    for (var i = 0; i <= 8; i++) {
      _box(p, .045, .82, .045, _metalDark, 11.55 + i * .7625, _y + floorY + .45,
          72.48);
    }
    _box(p, 6.25, .055, .055, _metalDark, 14.6, _y + floorY + .84, 72.48);
  }
  // Open stair on the east end of the gallery.
  for (var i = 0; i < 12; i++) {
    _box(p, 1.55, .10, .42, _concrete, 18.45, _y + .18 + i * .46,
        72.65 + i * .15);
  }

  // The measured 二階半 house and the family carport close the right edge.
  out.addAll(makeHouse(const HouseOpts(
      x: 24.0,
      z: 76.7,
      y: _y,
      w: 5.8,
      d: 6.0,
      floors: 2,
      face: 'z-',
      wall: 7,
      roof: 2,
      roofKind: 'gable',
      seed: 8333)));
  _box(p, 3.0, .07, 5.0, _roadPatch, 28.4, _y + .035, 74.4);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      _box(p, .075, 2.3, .075, _metal, 28.4 + sx * 1.25, _y + 1.22,
          74.6 + sz * 2.05);
    }
  }
  _box(p, 2.7, .09, 4.6, _metal, 28.4, _y + 2.42, 74.6, .055);
  out.addAll(bake(p));
  return out;
}

List<Tri> buildYonchome({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
  Map<String, List<Tri>>? shadowCasterGroups,
  int blossomLightColor = 0xf8e9ed,
  int blossomColor = 0xecb8cc,
  int blossomDeepColor = 0xe598b9,
}) {
  final surfaces = <Part>[];
  final fixedShadowCasters = <Tri>[];

  void addFixedShadowCasters(List<Tri> tris) {
    shadowCasters?.addAll(tris);
    groupedShadowCasters?.addAll(tris);
    fixedShadowCasters.addAll(tris);
  }

  // The unkerbed north lane, the east arm and the continuous junction pad.
  _box(surfaces, 3.4, .08, 16.4, _road, 6, _y + .04, 63.8);
  _box(surfaces, 20.1, .08, 3.0, _road, 17.95, _y + .04, 70.0);
  _box(surfaces, 4.4, .08, 3.6, _road, 6.1, _y + .04, 70.0);
  for (final z in [68.45, 71.55]) {
    _box(surfaces, 20.1, .17, .16, _curb, 17.95, _y + .085, z);
  }
  _lineZ(surfaces, 4.8, 58.4, 68.0, _y + .075);
  _lineZ(surfaces, 7.22, 58.4, 64.85, _y + .075);
  _lineX(surfaces, 68.75, 9.0, 27.4, _y + .105);
  _lineX(surfaces, 71.25, 9.0, 27.4, _y + .105);
  // West slotted drain and repair patches.
  for (var z = 56.75; z < 71.4; z += .9) {
    _box(surfaces, .28, .035, .7, _metalDark, 4.62, _y + .067, z);
  }
  _box(surfaces, 1.6, .018, 2.0, _roadPatch, 5.7, _y + .092, 60.4);
  _box(surfaces, 1.2, .018, 1.4, _roadPatch, 6.9, _y + .092, 65.8);

  // Hall forecourt and its two marked parking bays.
  _box(surfaces, 10.6, .07, 3.45, _concrete, 13.0, _y + .035, 66.575);
  _box(surfaces, 4.6, .07, 4.9, _road, 20.2, _y + .035, 65.85);
  for (var i = 0; i <= 2; i++) {
    _lineZ(surfaces, 18.1 + i * 2.1, 63.8, 68.1, _y + .095);
  }

  final scene = bake(surfaces);
  final hall = makeHall();
  scene.addAll(hall);
  addFixedShadowCasters(hall);
  final housing = _northHousing();
  scene.addAll(housing);
  addFixedShadowCasters(housing);

  // Porch doormat and paired planters.
  _appendBox(scene, .8, .025, .44,
      const Mat(0x6e625f, tint: 0x5c5680, bands: '2'), 12.0, _y + .215, 65.65);
  for (final spec in const [
    (9.9, 65.35, .26, 8303),
    (14.1, 65.30, .24, 8304),
    (15.9, 65.25, .21, 8305),
    (16.6, 65.27, .19, 8306),
  ]) {
    scene.addAll(makePlanter(
        x: spec.$1,
        y: _y + .07,
        z: spec.$2,
        r: spec.$3,
        seed: spec.$4,
        flower: spec.$4 < 8305));
  }

  // Two pairs of source wheel stops at the closed ends of the hall bays,
  // including their small number stakes. One pair is visible through the
  // refuse gate and the parked van in the fidelity view.
  final wheelStops = <Part>[];
  const stopBaseY = _y + .07;
  for (final bayOffset in [-1.05, 1.05]) {
    for (final side in [-1.0, 1.0]) {
      final sx = 20.2 + bayOffset + side * .725;
      _box(wheelStops, .60, .12, .16, _concrete, sx, stopBaseY + .06, 64.5);
      _box(wheelStops, .56, .04, .11, _curb, sx, stopBaseY + .14, 64.5);
      for (final pin in [-.18, .18]) {
        wheelStops.add(Part(cylGeometry(.018, .018, .03, 6),
            trs(sx + pin, stopBaseY + .165, 64.5), _metalDark));
      }
    }
    final stakeX = 20.2 + bayOffset;
    _box(wheelStops, .045, .35, .045, _metalDark, stakeX, stopBaseY + .175,
        64.24);
    _box(wheelStops, .18, .12, .022, _curb, stakeX, stopBaseY + .36, 64.26);
    _box(wheelStops, .18, .026, .026, _metalDark, stakeX, stopBaseY + .425,
        64.26);
  }
  final wheelStopTris = bake(wheelStops);
  scene.addAll(wheelStopTris);
  addFixedShadowCasters(wheelStopTris);

  // Four-metre bicycle shelter and the row underneath it.  The reference
  // lean-to is mostly its narrow frame and seventeen corrugation ribs; using
  // one thick roof slab erased that characteristic striped silhouette.
  final shelterFrame = <Part>[];
  const shelterX = 15.0, shelterZ = 66.9;
  const shelterW = 4.0, shelterD = 1.8, shelterH = 2.05, shelterFall = .18;
  final shelterTilt = math.atan2(shelterFall, shelterD);
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      final postH = shelterH + (sz > 0 ? 0 : shelterFall);
      shelterFrame.add(Part(
          cylGeometry(.045, .05, postH, 7),
          trs(shelterX + sx * (shelterW / 2 - .12), _y + .07 + postH / 2,
              shelterZ + sz * (shelterD / 2 - .1)),
          _metalDark));
      shelterFrame.add(Part(
          cylGeometry(.10, .12, .12, 8),
          trs(shelterX + sx * (shelterW / 2 - .12), _y + .07 + .06,
              shelterZ + sz * (shelterD / 2 - .1)),
          _metalDark));
    }
    _box(
        shelterFrame,
        .06,
        .06,
        shelterD / math.cos(shelterTilt),
        _metalDark,
        shelterX + sx * (shelterW / 2 - .12),
        _y + .07 + shelterH + shelterFall / 2 + .02,
        shelterZ,
        shelterTilt);
  }
  _box(shelterFrame, shelterW, .07, .09, _metalDark, shelterX,
      _y + .07 + shelterH + .02, shelterZ + shelterD / 2 - .08);
  _box(shelterFrame, shelterW, .09, .11, _metalDark, shelterX,
      _y + .07 + shelterH + shelterFall - .02, shelterZ - shelterD / 2 + .06);
  final ribCount = (shelterW / .24).round();
  for (var i = 0; i < ribCount; i++) {
    final rx =
        shelterX - shelterW / 2 + .1 + i * ((shelterW - .2) / (ribCount - 1));
    _box(shelterFrame, .05, .05, shelterD / math.cos(shelterTilt) + .16, _metal,
        rx, _y + .07 + shelterH + shelterFall / 2 + .09, shelterZ, shelterTilt);
  }
  final shelterFrameTris = bake(shelterFrame);
  scene.addAll(shelterFrameTris);
  addFixedShadowCasters(shelterFrameTris);

  // The translucent source sheet does not cast; keep it visually light and
  // separate from the native shadow-caster collection.
  final shelterSheet = bake([
    Part(
        boxGeometry(shelterW + .16, .03, shelterD / math.cos(shelterTilt) + .2),
        trs(shelterX, _y + .07 + shelterH + shelterFall / 2 + .07, shelterZ,
            shelterTilt),
        _shelterSheet),
  ]);
  scene.addAll(shelterSheet);
  for (var i = 0; i < 6; i++) {
    final bike = makeBicycle(
        x: 13.4 + i * .64,
        y: _y + .07,
        z: 66.7,
        ry: math.pi / 2,
        lean: i.isEven ? .035 : -.025,
        color: i % 3 == 0 ? 0x4f8f6a : (i % 3 == 1 ? 0x596fa0 : 0x8f6fb5));
    scene.addAll(bike);
    addFixedShadowCasters(bike);
  }
  // The rack is full, so one association member leaves a bicycle just beyond
  // its east end. This seventh silhouette is exposed in the hall view.
  final looseBike = makeBicycle(
      x: 17.4,
      y: _y + .07,
      z: 66.9,
      ry: math.pi / 2 + .05,
      lean: .07,
      color: 0x4f8f6a);
  scene.addAll(looseBike);
  addFixedShadowCasters(looseBike);

  // Service pocket behind the hall: the ribbed shed and its crate stack fill
  // the gap seen through the bicycle shelter in the reference.
  final storageShed = _hallStorageShed();
  scene.addAll(storageShed);
  addFixedShadowCasters(storageShed);
  final storageCrates =
      makeCrates(x: 20.6, y: _y, z: 58.6, n: 3, seed: 8308, ry: .3);
  scene.addAll(storageCrates);
  addFixedShadowCasters(storageCrates);

  // Small service-door clutter on the west flank. The coloured crate stack is
  // clipped by the left edge of the fidelity camera, but is conspicuous in the
  // reference and was entirely absent from the port.
  final flankCrates =
      makeCrates(x: 8.9, y: _y, z: 58.9, n: 2, seed: 8307, ry: -.2);
  scene.addAll(flankCrates);
  addFixedShadowCasters(flankCrates);

  // Notice board on the hall's west flank, facing the lane.
  final board = <Part>[];
  _box(board, .14, 1.05, 2.0, _wood, 8.5, _y + 1.425, 61.6);
  _box(board, .035, .91, 1.82, _cork, 8.42, _y + 1.425, 61.6);
  for (var page = 0; page < 3; page++) {
    final pz = 60.98 + page * .62;
    _box(board, .018, .58, .42, _paper, 8.398, _y + 1.425, pz);
    for (var row = 0; row < 4; row++) {
      _box(board, .018, .025, .38 - row * .04, _print, 8.398,
          _y + 1.56 - row * .12, pz);
    }
    _box(
        board,
        .018,
        .035,
        .035,
        page.isOdd ? const Mat(0xd8564e, unlit: true) : _binYellow,
        8.385,
        _y + 1.68,
        pz);
  }
  for (final pz in [60.7, 62.5]) {
    _box(board, .11, 2.05, .11, _wood, 8.5, _y + 1.025, pz);
  }
  _box(board, .14, .09, 2.10, _wood, 8.5, _y + 1.99, 61.6);
  _box(board, .34, .06, 2.24, const Mat(0x525a70, tint: 0x514b70, bands: '3'),
      8.4, _y + 2.11, 61.6, 0, 0, -.20);
  final boardTris = bake(board);
  scene.addAll(boardTris);
  addFixedShadowCasters(boardTris);

  // Corner refuse enclosure and the hall's two traffic placements. These sit
  // close to the fidelity camera and are essential to the reference layering.
  final refuseCasters = <Tri>[];
  final refuse = _gomiHouse(shadowCasters: refuseCasters);
  scene.addAll(refuse);
  addFixedShadowCasters(refuseCasters);
  final hallVan = makeVehicle(
      kind: 'keivan',
      color: CAR.silver,
      x: 21.55,
      y: _y + .07,
      z: 66.3,
      ry: math.pi / 2 + .025);
  scene.addAll(hallVan);
  addFixedShadowCasters(hallVan);
  final scooter =
      makeEbike(x: 12.2, y: _y + .07, z: 68.2, ry: 0, color: 0xb0bec6);
  scene.addAll(scooter);
  addFixedShadowCasters(scooter);

  // Convex safety mirror on the blind junction.  This sits less than two
  // metres from the fidelity camera, so its amber back is the large hanging
  // foreground shape that frames the hall roof in the reference.
  final mirror =
      makeMirror(x: 7.4, y: _y + .08, z: 68.5, ry: -2.5, h: 2.5, r: .42);
  scene.addAll(mirror);
  addFixedShadowCasters(mirror);

  // Exact visible poles and street cherries for this block.
  for (final opts in const [
    PoleOpts(x: 2.45, y: _y, z: 58.6, h: 8.4, seed: 8361, lamp: true),
    PoleOpts(x: 2.40, y: _y, z: 66.4, h: 8.2, seed: 8362, lamp: true),
    PoleOpts(
        x: 10.4,
        y: _y + .07,
        z: 68.0,
        h: 8.4,
        seed: 8363,
        lamp: true,
        poleColor: 0xd4c9cc,
        poleUnlit: true),
  ]) {
    final pole = makePole(opts);
    scene.addAll(pole);
    addFixedShadowCasters(pole);
  }
  const treeSpots = [
    SakuraSpot(
        x: 3.5,
        z: 59.8,
        y: _y,
        scale: 1.18,
        seed: 8317,
        lean: .1,
        leanDir: 4.4),
    SakuraSpot(
        x: 3.2,
        z: 69.0,
        y: _y,
        scale: 1.24,
        seed: 8318,
        lean: .1,
        leanDir: 4.4),
    SakuraSpot(
        x: 9.4,
        z: 66.55,
        y: _y + .07,
        scale: 1.16,
        seed: 8322,
        lean: .11,
        leanDir: 2.4),
    SakuraSpot(
        x: -8.0,
        z: 57.2,
        y: _y,
        scale: 1.22,
        seed: 8335,
        lean: .11,
        leanDir: 1.4),
    SakuraSpot(
        x: 2.0,
        z: 77.4,
        y: _y + .06,
        scale: 1.22,
        seed: 8354,
        lean: .12,
        leanDir: 1.4),
    SakuraSpot(
        x: 6.2,
        z: 79.0,
        y: _y + .06,
        scale: 1.14,
        seed: 8355,
        lean: .10,
        leanDir: 3.2),
    SakuraSpot(
        x: 7.6,
        z: 75.0,
        y: _y + .06,
        scale: 1.10,
        seed: 8356,
        lean: .09,
        leanDir: 5.0),
    // Adjacent library/shotengai planting is part of the hall's upper frame.
    SakuraSpot(
        x: 25.3,
        z: 53.2,
        y: _y,
        scale: 1.20,
        seed: 5512,
        lean: .10,
        leanDir: 2.2),
    SakuraSpot(
        x: 20.8,
        z: 41.0,
        y: _y,
        scale: 1.24,
        seed: 901,
        lean: .12,
        leanDir: 3.4),
    SakuraSpot(
        x: 20.4,
        z: 48.4,
        y: _y,
        scale: 1.18,
        seed: 902,
        lean: .10,
        leanDir: 1.6),
    SakuraSpot(
        x: 31.4,
        z: 47.8,
        y: _y,
        scale: 1.28,
        seed: 903,
        lean: .09,
        leanDir: 4.9),
    SakuraSpot(
        x: 12.6,
        z: 48.0,
        y: _y,
        scale: 1.14,
        seed: 904,
        lean: .11,
        leanDir: 2.7),
    SakuraSpot(
        x: 35.0,
        z: 48.8,
        y: _y,
        scale: 1.16,
        seed: 7716,
        lean: .10,
        leanDir: 3.6),
    SakuraSpot(
        x: 30.5,
        z: 51.6,
        y: _y,
        scale: 1.20,
        seed: 7770,
        lean: .12,
        leanDir: 4.6),
    SakuraSpot(
        x: 45.0,
        z: 42.6,
        y: _y,
        scale: 1.14,
        seed: 7771,
        lean: .10,
        leanDir: 2.0),
  ];
  final trees = buildSakura(treeSpots,
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor);
  scene.addAll(trees);
  shadowCasters?.addAll(trees);
  groupedShadowCasters?.addAll(trees);
  for (var i = 0; i < treeSpots.length; i++) {
    shadowCasterGroups?['yonchome_sakura_$i'] = buildSakura([treeSpots[i]],
        blossomLightColor: blossomLightColor,
        blossomColor: blossomColor,
        blossomDeepColor: blossomDeepColor);
  }

  const groveSpots = [
    GroveSpot(x: -5.8, z: 62.0, y: _y, scale: 1.55, seed: 8331, spread: 1.15),
    GroveSpot(x: .3, z: 62.4, y: _y, scale: 1.35, seed: 8332, spread: 1.05),
    GroveSpot(x: 7.8, z: 51.4, y: _y, scale: 1.80, seed: 906, spread: 1.20),
    GroveSpot(x: 28.2, z: 53.1, y: _y, scale: 1.65, seed: 907, spread: 1.15),
    GroveSpot(x: 22.9, z: 53.4, y: _y, scale: 1.75, seed: 5510, spread: 1.15),
    GroveSpot(x: 8.6, z: 53.8, y: _y, scale: 1.60, seed: 5511, spread: 1.10),
    // North Block's south-lane tree overhangs the hall bicycle shelter and is
    // the dominant upper-right canopy in the representative view.
    GroveSpot(x: 21.6, z: 62.2, y: _y, scale: 1.70, seed: 7772, spread: 1.15),
    GroveSpot(x: 28.8, z: 69.6, y: _y, scale: 1.5, seed: 8371, spread: 1.15),
    GroveSpot(x: 29.5, z: 71.4, y: _y, scale: 1.35, seed: 8372, spread: 1.1),
    GroveSpot(
        x: 2.7, z: 79.0, y: _y + .06, scale: 1.45, seed: 8357, spread: 1.1),
  ];
  final grove = buildGrove(groveSpots);
  scene.addAll(grove);
  final groveShadowCasters = <Tri>[];
  for (var i = 0; i < groveSpots.length; i++) {
    final group = buildGrove([groveSpots[i]]);
    groveShadowCasters.addAll(group);
    shadowCasterGroups?['yonchome_grove_$i'] = group;
  }
  shadowCasters?.addAll(groveShadowCasters);
  groupedShadowCasters?.addAll(groveShadowCasters);
  shadowCasterGroups?['yonchome_fixed'] = fixedShadowCasters;

  scene.addAll(buildFallenPatches(const [
    PetalPatch(x: -6.0, z: 56.8, w: 6.0, d: 3.0, y: _y + .02, n: 80),
    PetalPatch(x: 6.0, z: 62.0, w: 2.9, d: 8.0, y: _y + .07, n: 90),
    PetalPatch(x: 3.4, z: 60.6, w: 2.4, d: 3.0, y: _y + .02, n: 40),
    PetalPatch(x: 13.4, z: 66.9, w: 8.4, d: 2.6, y: _y + .09, n: 90),
    PetalPatch(x: 4.6, z: 74.6, w: 5.0, d: 3.4, y: _y + .08, n: 80),
    PetalPatch(x: 22.0, z: 72.6, w: 7.0, d: 1.5, y: _y + .02, n: 60),
    PetalPatch(x: 13.6, z: 72.4, w: 6.0, d: 1.4, y: _y + .02, n: 50),
  ], skip: 8896));

  return scene;
}

void _appendBox(List<Tri> output, double w, double h, double d, Mat mat,
    double x, double y, double z) {
  output.addAll(bake([Part(boxGeometry(w, h, d), trs(x, y, z), mat)]));
}
