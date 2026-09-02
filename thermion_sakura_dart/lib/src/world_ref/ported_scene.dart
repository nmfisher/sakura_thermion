/// The ported world scene assembled from the ported modules — street ground +
/// road, a row of houses, cherry trees, and utility poles — as a flat-space
/// triangle soup. This is the "ported geometry" view: reproducible Dart code
/// (no extracted .bin), grown module-by-module. Apply the planet wrap for the
/// real camera; for inspection a flat view suffices.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'details.dart';
import 'approach_detail.dart';
import 'canal_details.dart';
import 'districts.dart';
import 'districts_tsu.dart';
import 'hills.dart';
import 'kohan.dart';
import 'library.dart';
import 'lakeroad_details.dart';
import 'make_house.dart';
import 'make_props.dart';
import 'make_pole.dart';
import 'make_sakura.dart';
import 'make_trees_other.dart';
import 'matsuri.dart';
import 'nanachome.dart';
import 'onsen.dart';
import 'petals.dart';
import 'railway.dart';
import 'rokuchome.dart';
import 'school.dart';
import 'shop.dart';
import 'showa.dart';
import 'street.dart';
import 'structures.dart';
import 'train.dart';
import 'tunnel.dart';
import 'urayama.dart';
import 'urayama_sites.dart';
import 'water.dart';
import 'yonchome.dart';

/// Build the assembled ported scene. Positions are a small sample of the
/// reference's opening-frame placement (index.js houseDefs / tree spots),
/// expanded as more modules land.
List<Tri> buildPortedScene({
  List<Tri>? shadowCasters,
  Map<String, List<Tri>>? shadowCasterGroups,
  bool includeManualTrainShadows = false,
  bool includeManualTrainSkirtShade = false,
  bool includeManualTrainPolePanelShade = false,
  bool includeManualCrossingTrainShadows = false,
  bool includeManualPoleTrainShadows = false,
  bool includeManualNearPoleReceiverShadow = false,
  bool segmentManualTrainShadowReceivers = true,
  bool includeManualRoadShadow = false,
  bool includeForegroundBranchShadow = false,
  bool includeForegroundBranchTip = false,
  bool includeForegroundBranchCore = false,
  bool includeForegroundBranchLobe = false,
  bool includeForegroundBranchFork = false,
  bool includePetals = true,
  bool includeFallenPetals = true,
  bool includeFallingPetals = false,
  bool includeTrain = true,
  bool includeCrossingBooms = true,
  bool includeActiveCrossingLamps = true,
  // These are accumulated after district construction in three.js. Until the
  // district-returned vegetation is assembled as one batch, enabling only the
  // global subset exposes shrubs that are occluded in the reference opening.
  bool includeReferenceShrubs = false,
  bool includeShopShutterGrooves = true,
  int foregroundBranchShadow = 0x54567c,
  int foregroundBranchTipShadow = 0x787a92,
  int manualRoadShadowColor = 0x545279,
  Set<int>? manualTrainShadowTrees,
  int manualBodyShadow = 0x96919b,
  int manualStripeShadow = 0x354976,
  bool includeTree0StripeRepair = false,
  int manualTree0StripeRepair = 0x8a8894,
  double manualTree0StripeRepairMinX = -7.4,
  double manualTree0StripeRepairMaxX = -6.0,
  double manualTree0StripeRepairMinX2 = -2.65,
  double manualTree0StripeRepairMaxX2 = -2.0,
  int manualGlassShadow = 0x625772,
  bool includeTree0GlassRepair = false,
  int manualTree0GlassRepair = 0x8a8894,
  double manualTree0GlassRepairMinX = -7.2,
  double manualTree0GlassRepairMaxX = -5.4,
  double manualTree0GlassRepairMinX2 = -2.1,
  double manualTree0GlassRepairMaxX2 = -1.55,
  int manualFrameShadow = 0x4f4f68,
  int manualRoofShadow = 0x5e5c70,
  int manualPolePanelShadow = 0x918ca6,
  int manualNearPoleShadow = 0x85809a,
  double manualNearPoleShadowY0 = .15,
  double manualNearPoleShadowY1 = 2.70,
  int manualSkirtShadow = 0x463e5a,
  // Renderer compensation: Filament's unlit cel accumulation and split-tone
  // grade otherwise resolve the sun-facing cream and blue too hot.
  int trainBodyColor = 0xebe3d5,
  int trainStripeColor = 0x0771c1,
  int trainWindowColor = 0x3b4257,
  int roadColor = 0x8c899c,
  int roadPatchColor = 0x9b96a7,
  int terrainColor = 0xc6c9ba,
  int curbColor = 0xbbb6c4,
  int tactileColor = 0xffdc00,
  int gateYellowColor = 0xf2b727,
  // The same compensation keeps Filament's soft-ramp blossom bands from
  // clipping to hotter pinks than the three.js capture.
  int blossomLightColor = 0xfeedf0,
  int blossomColor = 0xfac3d5,
  int blossomDeepColor = 0xeda1bd,
  int vendingSideShadowColor = 0x005260,
  int vendingTealColor = 0x198284,
  int shopRedColor = 0xd83f3a,
  int shopRedSoftColor = 0xd95050,
  int shopWallColor = 0xe8dac5,
  double manualTree0ShadowX = -0.36,
  double manualTree0ShadowY = 0.39,
  double manualTree0ShadowScale = 1,
  double manualTree1ShadowX = 0,
  double manualTree1ShadowY = 0.08,
  double manualTree1ShadowScale = 1,
  double manualTree4ShadowX = -0.29,
  double manualTree4ShadowY = 0.14,
  double manualTree4ShadowScale = .95,
  // Sit just beyond the outer door/window faces. At the old 1.455 plane those
  // details depth-occluded half of the projected cherry shadow.
  double manualTrainShadowPlaneZ = 1.468,
  double manualTrainShadowSkirtMin = .28,
  // The reference captures after one nominal 60 Hz update. At 23.5 m/s the
  // train has already travelled this far when the opening frame is presented.
  // A 0.33 mm raster compensation keeps Filament's first-frame train edges
  // on the same pixel centres as the three.js capture.
  double trainX = 0.392,
}) {
  final tris = <Tri>[];
  void add(List<Tri> part, {bool casts = false, String group = 'props'}) {
    tris.addAll(part);
    if (casts) {
      shadowCasters?.addAll(part);
      shadowCasterGroups?.putIfAbsent(group, () => <Tri>[]).addAll(part);
    }
  }

  bool outsideEastReplacement(Tri tri) {
    final x = (tri.a.x + tri.b.x + tri.c.x) / 3;
    final z = (tri.a.z + tri.b.z + tri.c.z) / 3;
    return x < 60 || x > 160 || z < -50 || z > 50;
  }

  tris.addAll(buildStreet(
          roadColor: roadColor,
          roadPatchColor: roadPatchColor,
          terrainColor: terrainColor,
          curbColor: curbColor,
          tactileColor: tactileColor)
      .where(outsideEastReplacement));
  // Distant layered hills (heightfield terrain backdrop).
  tris.addAll(buildHills().where(outsideEastReplacement));
  // Range-wide planting is visible geometry but stays out of the approximate
  // projected shadow caster; site modules own the camera-critical local shade.
  tris.addAll(buildHillRangePlanting(
          blossomLightColor: blossomLightColor,
          blossomColor: blossomColor,
          blossomDeepColor: blossomDeepColor)
      .where(outsideEastReplacement));
  tris.addAll(buildTunnel(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('tunnel', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // Water features (canal + lake + lake road).
  tris.addAll(buildCanal());
  // The long canal corridor owns dense bank vegetation and several remote
  // structures; keep them out of the approximate scene-wide shadow caster.
  tris.addAll(buildCanalDetails(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildLake());
  tris.addAll(buildLakeDetails());
  add(buildLakePier(), casts: true, group: 'lake');
  add(buildLakeReeds(), casts: true, group: 'lake');
  // These sites surround the lake camera by tens of metres. Filament's shared
  // projected shadow map turns their off-camera trees into a false blanket over
  // the pier, so retain their lit geometry without adding them to that caster.
  tris.addAll(buildKohan(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  add(
      buildLakeRimPlanting(
          blossomLightColor: blossomLightColor,
          blossomColor: blossomColor,
          blossomDeepColor: blossomDeepColor),
      casts: true,
      group: 'lake');
  tris.addAll(buildLakeRoad());
  tris.addAll(buildLakeRoadDetails(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // Mid-distant set pieces.
  tris.addAll(buildApproach());
  tris.addAll(buildApproachDetail(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('approach', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildShrine());
  add(buildMatsuri(), casts: true, group: 'matsuri');
  tris.addAll(buildShotengai());
  tris.addAll(buildShowa());
  tris.addAll(buildLibrary());
  final school = buildSchool(includeManualShadow: includeManualRoadShadow);
  tris.addAll(school);
  // Keep the gym/site-edge geometry directly. The merged north-block shell
  // cannot enter the projected map without self-occluding the full view.
  final schoolCasters =
      school.where((t) => t.centroid.x > 40 && t.centroid.z < -68).toList();
  shadowCasters?.addAll(schoolCasters);
  shadowCasterGroups
      ?.putIfAbsent('school', () => <Tri>[])
      .addAll(schoolCasters);
  tris.addAll(buildUrayama(
      shadowCasters: shadowCasters,
      includeSchoolRoadShadow: includeManualRoadShadow,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('urayama', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // Authored trail rooms remain visible without joining the approximate
  // scene-wide caster, which would project remote forest shade across them.
  tris.addAll(buildUrayamaSites(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildKoenmae());
  tris.addAll(buildOverbridge());
  // Residential districts (mid-ground density).
  tris.addAll(buildNorthBlock());
  tris.addAll(buildAlleys());
  tris.addAll(buildRestCorner(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildIchome(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildNichome(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildTsugakuro(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildUramachi(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildGakkomae(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildKawabata(
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildOnsen(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('onsen', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildRokuchome(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('rokuchome', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  tris.addAll(buildNanachome(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('nanachome', () => <Tri>[]),
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // 四丁目: maintained north lane and its community-hall composition.
  tris.addAll(buildYonchome(
      shadowCasters: shadowCasters,
      groupedShadowCasters:
          shadowCasterGroups?.putIfAbsent('yonchome', () => <Tri>[]),
      shadowCasterGroups: shadowCasterGroups,
      blossomLightColor: blossomLightColor,
      blossomColor: blossomColor,
      blossomDeepColor: blossomDeepColor));
  // Street details + traffic.
  tris.addAll(buildDetails());
  tris.addAll(buildTraffic());

  // Houses flanking the street — the reference's opening-frame houseDefs
  // (index.js), placed with the same params. Fills the vista.
  const houses = <HouseOpts>[
    HouseOpts(
        x: -13.6,
        z: 12.6,
        w: 7.0,
        d: 7.0,
        face: 'x+',
        floors: 2,
        seed: 21,
        wall: 0,
        roof: 1,
        roofKind: 'gable'),
    HouseOpts(
        x: -9.4,
        z: 23.2,
        w: 7.0,
        d: 8.0,
        face: 'x+',
        floors: 2,
        seed: 22,
        wall: 2,
        roof: 0,
        roofKind: 'hip'),
    HouseOpts(
        x: -10.6,
        z: 33.5,
        w: 6.4,
        d: 7.2,
        face: 'x+',
        floors: 1,
        seed: 23,
        wall: 1,
        roof: 2,
        roofKind: 'gable'),
    HouseOpts(
        x: -13.5,
        z: 43.0,
        w: 7.4,
        d: 7.4,
        face: 'x+',
        floors: 2,
        seed: 24,
        wall: 4,
        roof: 1,
        roofKind: 'flat'),
    HouseOpts(
        x: 9.4,
        z: 20.4,
        w: 5.6,
        d: 7.8,
        face: 'x-',
        floors: 2,
        seed: 25,
        wall: 3,
        roof: 0,
        roofKind: 'gable'),
    HouseOpts(
        x: 8.9,
        z: 29.6,
        w: 6.6,
        d: 7.4,
        face: 'x-',
        floors: 2,
        seed: 26,
        wall: 5,
        roof: 3,
        roofKind: 'hip'),
    HouseOpts(
        x: 7.4,
        z: 38.5,
        w: 6.8,
        d: 7.0,
        face: 'x-',
        floors: 1,
        seed: 27,
        wall: 0,
        roof: 2,
        roofKind: 'gable'),
    HouseOpts(
        x: -8.7,
        z: -7.6,
        w: 6.8,
        d: 6.2,
        face: 'x+',
        floors: 2,
        seed: 28,
        wall: 1,
        roof: 0,
        roofKind: 'gable'),
    HouseOpts(
        x: -8.2,
        z: -16.4,
        w: 6.6,
        d: 7.0,
        face: 'x+',
        floors: 2,
        seed: 29,
        wall: 4,
        roof: 1,
        roofKind: 'hip'),
    HouseOpts(
        x: -15.2,
        z: -34.6,
        w: 7.4,
        d: 7.0,
        face: 'z+',
        floors: 2,
        seed: 30,
        wall: 2,
        roof: 2,
        roofKind: 'gable'),
    HouseOpts(
        x: -5.4,
        z: -33.5,
        w: 8.0,
        d: 7.4,
        face: 'z+',
        floors: 2,
        seed: 44,
        wall: 0,
        roof: 1,
        roofKind: 'gable'),
    HouseOpts(
        x: 8.5,
        z: -7.4,
        w: 6.6,
        d: 6.0,
        face: 'x-',
        floors: 1,
        seed: 31,
        wall: 0,
        roof: 3,
        roofKind: 'gable'),
    HouseOpts(
        x: 10.0,
        z: -16.2,
        w: 6.8,
        d: 7.2,
        face: 'x-',
        floors: 2,
        seed: 32,
        wall: 3,
        roof: 1,
        roofKind: 'hip'),
    HouseOpts(
        x: 14.4,
        z: -35.5,
        w: 7.0,
        d: 7.4,
        face: 'x-',
        floors: 1,
        seed: 45,
        wall: 1,
        roof: 3,
        roofKind: 'hip'),
    // background rows across the tracks
    HouseOpts(
        x: -18.0,
        z: -13.0,
        w: 8.0,
        d: 8.0,
        face: 'z+',
        floors: 2,
        seed: 34,
        wall: 1,
        roof: 1,
        roofKind: 'gable'),
    HouseOpts(
        x: -27.5,
        z: -12.0,
        w: 7.6,
        d: 7.6,
        face: 'z+',
        floors: 1,
        seed: 35,
        wall: 4,
        roof: 0,
        roofKind: 'hip'),
    HouseOpts(
        x: -37.0,
        z: -14.5,
        w: 8.4,
        d: 8.0,
        face: 'z+',
        floors: 2,
        seed: 36,
        wall: 0,
        roof: 2,
        roofKind: 'gable'),
    HouseOpts(
        x: 21.0,
        z: -14.0,
        w: 8.2,
        d: 8.0,
        face: 'z+',
        floors: 2,
        seed: 37,
        wall: 2,
        roof: 0,
        roofKind: 'hip'),
    HouseOpts(
        x: 31.0,
        z: -13.0,
        w: 7.8,
        d: 7.6,
        face: 'z+',
        floors: 1,
        seed: 38,
        wall: 5,
        roof: 1,
        roofKind: 'gable'),
    HouseOpts(
        x: 41.5,
        z: -15.0,
        w: 8.6,
        d: 8.2,
        face: 'z+',
        floors: 2,
        seed: 39,
        wall: 3,
        roof: 2,
        roofKind: 'flat'),
    // Railway-facing near-side row (the four final reference houseDefs).
    HouseOpts(
        x: -22.0,
        z: 9.5,
        w: 8.0,
        d: 7.6,
        face: 'z-',
        floors: 2,
        seed: 40,
        wall: 0,
        roof: 1,
        roofKind: 'gable'),
    HouseOpts(
        x: -33.6,
        z: 10.5,
        w: 7.6,
        d: 7.4,
        face: 'z-',
        floors: 1,
        seed: 41,
        wall: 4,
        roof: 3,
        roofKind: 'hip'),
    HouseOpts(
        x: 21.2,
        z: 10.0,
        w: 5.8,
        d: 7.8,
        face: 'z-',
        floors: 2,
        seed: 42,
        wall: 1,
        roof: 0,
        roofKind: 'gable'),
    HouseOpts(
        x: 30.5,
        z: 11.0,
        w: 7.8,
        d: 7.4,
        face: 'z-',
        floors: 2,
        seed: 43,
        wall: 5,
        roof: 2,
        roofKind: 'hip'),
  ];
  for (final indexed in houses.indexed) {
    add(makeHouse(indexed.$2), casts: true, group: 'house_${indexed.$1}');
  }

  // Near-side lineside strip from index.js. This low foreground cluster is
  // visible through the crossing opening and anchors the left rail boundary.
  const pathMat = Mat(0xd0cbd2, tint: 0x6f6790, bands: '3');
  const pathJointMat = Mat(0xaeb2bd, tint: 0x6a6288, bands: '3');
  add(bake([
    Part(boxGeometry(26, .07, 1.15), trs(-17.5, .035, 4.35), pathMat),
    for (var i = 0; i < 9; i++)
      Part(boxGeometry(.06, .09, 1.15), trs(-5.0 - i * 3.0, .04, 4.35),
          pathJointMat),
  ]));

  final shedWorld = trs(-11.9, 0, 7.0, 0, -.06);
  add(
      bake([
        Part(boxGeometry(2.6, 2.05, 2), shedWorld * trs(0, 1.02, 0),
            const Mat(0xd9d3c4, tint: 0x6f6790, bands: '3')),
        Part(boxGeometry(2.9, .12, 2.3), shedWorld * trs(0, 2.12, 0),
            const Mat(0x4f6b70, tint: 0x514b70, bands: '3')),
        Part(boxGeometry(.06, 1.55, .9), shedWorld * trs(1.31, .8, .3),
            const Mat(0x8a6f5c, tint: 0x5c5680, bands: '3')),
        Part(boxGeometry(2.62, .09, .09), shedWorld * trs(0, 2.02, 1.02),
            const Mat(0xb8bcc6, bands: '3')),
      ]),
      casts: true,
      group: 'shed');
  add(makeCrates(x: -9.6, z: 5, n: 3, seed: 71, ry: .2),
      casts: true, group: 'shed');
  add(makePlanter(x: -7.4, z: 4.9, r: .24, flower: true, seed: 72, n: 5),
      casts: true, group: 'shed');
  add(makePlanter(x: -8.3, z: 5.5, r: .2, seed: 73, n: 4),
      casts: true, group: 'shed');

  // Exact opening-world sakuraSpots from world/index.js. Their placement is
  // composition-critical: two frame the camera, the lineside rows reveal the
  // train between canopies, and the behind-camera tree casts the road shadow.
  SakuraSpot tree(double x, double z, double scale, int seed,
          [double lean = 0, double? leanDir]) =>
      SakuraSpot(
          x: x,
          y: groundY(z),
          z: z,
          scale: scale,
          seed: seed,
          lean: lean,
          leanDir: leanDir);
  final sakuraSpots = [
    tree(-7.1, 5.8, 1.22, 101, 0.13, 1.9),
    tree(6.3, 2.5, 1.06, 102, 0.10, 4.4),
    tree(-5.9, 17.9, 1.16, 128, 0.14, 1.6),
    tree(-5.6, 25.4, 1.04, 129, 0.10, 2.1),
    tree(-12.5, 3.9, 1.00, 103, 0.08),
    tree(-19.0, 3.9, 1.12, 104, 0.10),
    tree(-26.5, 4.0, 0.95, 105, 0.06),
    tree(-34.0, 3.9, 1.08, 106, 0.09),
    tree(13.5, 3.9, 1.05, 107, 0.07),
    tree(20.5, 4.0, 0.98, 108, 0.10),
    tree(28.0, 3.9, 1.14, 109, 0.05),
    tree(32.5, 4.0, 1.00, 110, 0.09),
    tree(-11.0, -4.6, 1.04, 111, 0.08),
    tree(-18.5, -4.6, 0.96, 112, 0.10),
    tree(11.5, -4.7, 1.10, 113, 0.07),
    tree(18.5, -7.4, 1.02, 114, 0.06),
    tree(26.5, -7.8, 1.16, 115, 0.09),
    tree(30.0, -6.9, 0.98, 116, 0.05),
    tree(-13.5, 15.5, 1.10, 117, 0.11),
    tree(5.9, 25.0, 1.05, 118, 0.08),
    tree(-14.0, 30.0, 1.00, 119, 0.07),
    tree(-12.0, -14.5, 1.08, 120, 0.10),
    tree(15.0, -20.0, 1.03, 121, 0.06),
    tree(-44.0, 4.5, 1.20, 122, 0.08),
    tree(46.0, 4.2, 1.15, 123, 0.06),
    tree(-42.0, -4.9, 1.10, 124, 0.09),
    tree(51.0, -9.0, 1.18, 125, 0.07),
    tree(-52.0, 6.0, 1.25, 126, 0.05),
    tree(54.0, 5.5, 1.22, 127, 0.08),

    // Vegetation returned by already-ported districts. In three.js these are
    // accumulated after all district builders and passed through buildSakura
    // together; omitting them changed both the horizon and the shadow map.
    // 一丁目 fills the conspicuous gap in the far-side lineside row.
    tree(-25.6, -4.68, 1.06, 8140, 0.09, 2.4),
    // The rest-corner tree frames the east end of the crossing.
    tree(14.6, 12.2, 1.06, 8831, 0.13, 1.1),
    // Canal banks: two rows leaning over the water at z = -24.
    for (var i = 0; i < 6; i++)
      tree(-49.0 + i * 7.6, -28.8, 1.16 + (i % 3) * 0.1, 1010 + i, 0.24,
          math.pi),
    for (var i = 0; i < 4; i++)
      tree(-45.0 + i * 9.4, -19.4, 1.1 + (i % 2) * 0.12, 1020 + i, 0.22, 0),
    tree(14.6, -28.8, 1.18, 1060, 0.22, math.pi),
    tree(24.0, -28.8, 1.24, 1061, 0.22, math.pi),
    tree(37.0, -28.8, 1.12, 1062, 0.22, math.pi),
    tree(19.4, -19.4, 1.14, 1063, 0.22, 0),
    tree(32.2, -19.4, 1.22, 1064, 0.22, 0),
  ];
  final sakura = <Tri>[];
  final sakuraTrees = <List<Tri>>[];
  for (final spot in sakuraSpots) {
    final treeTris = buildSakura([spot],
        blossomLightColor: blossomLightColor,
        blossomColor: blossomColor,
        blossomDeepColor: blossomDeepColor);
    sakuraTrees.add(treeTris);
    sakura.addAll(treeTris);
  }
  add(sakura, casts: true, group: 'sakura');
  if (shadowCasterGroups != null) {
    for (final (index, treeTris) in sakuraTrees.indexed) {
      shadowCasterGroups['sakura_$index'] = treeTris;
    }
  }
  if (includeManualTrainShadows) {
    for (final (index, treeTris) in sakuraTrees.indexed) {
      if (manualTrainShadowTrees != null &&
          !manualTrainShadowTrees.contains(index)) {
        continue;
      }
      final offsetX = index == 0
          ? manualTree0ShadowX
          : index == 1
              ? manualTree1ShadowX
              : index == 4
                  ? manualTree4ShadowX
                  : 0.0;
      final offsetY = index == 0
          ? manualTree0ShadowY
          : index == 1
              ? manualTree1ShadowY
              : index == 4
                  ? manualTree4ShadowY
                  : 0.0;
      final scale = index == 0
          ? manualTree0ShadowScale
          : index == 1
              ? manualTree1ShadowScale
              : index == 4
                  ? manualTree4ShadowScale
                  : 1.0;
      final trainShadowCasters = treeTris
          .where((tri) => tri.mat.color == 0x9a8082 || tri.mat.bands == 'soft')
          .toList(growable: false);
      tris.addAll(_projectTrainCasterShadows(trainShadowCasters,
          trainX: trainX,
          planeZ: manualTrainShadowPlaneZ,
          skirtMin: manualTrainShadowSkirtMin,
          segmentedGlass: segmentManualTrainShadowReceivers,
          offsetX: offsetX,
          offsetY: offsetY,
          scale: scale,
          bodyColor: manualBodyShadow,
          stripeColor: manualStripeShadow,
          stripeRepairColor: index == 0 && includeTree0StripeRepair
              ? manualTree0StripeRepair
              : null,
          stripeRepairMinX: manualTree0StripeRepairMinX,
          stripeRepairMaxX: manualTree0StripeRepairMaxX,
          stripeRepairMinX2: manualTree0StripeRepairMinX2,
          stripeRepairMaxX2: manualTree0StripeRepairMaxX2,
          glassColor: manualGlassShadow,
          glassRepairColor: index == 0 && includeTree0GlassRepair
              ? manualTree0GlassRepair
              : null,
          glassRepairMinX: manualTree0GlassRepairMinX,
          glassRepairMaxX: manualTree0GlassRepairMaxX,
          glassRepairMinX2: manualTree0GlassRepairMinX2,
          glassRepairMaxX2: manualTree0GlassRepairMaxX2,
          frameColor: manualFrameShadow,
          skirtColor: manualSkirtShadow));
    }
  }
  if (includeManualRoadShadow) {
    // llvmpipe drops the faceted cherry casters from the auxiliary shadow
    // view. Preserve their exact directional projection on the opening road
    // as explicit receiver geometry; clipping below keeps it off the curbs.
    tris.addAll(_projectRoadTreeShadow(sakura, manualRoadShadowColor));
  }
  if (includeForegroundBranchShadow) {
    tris.addAll(_foregroundBranchShadow(foregroundBranchShadow));
  }
  if (includeForegroundBranchTip) {
    tris.addAll(_foregroundBranchTip(foregroundBranchTipShadow));
  }
  if (includeForegroundBranchCore) {
    tris.addAll(_foregroundBranchCore(foregroundBranchShadow));
  }
  if (includeForegroundBranchLobe) {
    tris.addAll(_foregroundBranchLobe(foregroundBranchShadow));
  }
  if (includeForegroundBranchFork) {
    tris.addAll(_foregroundBranchFork(foregroundBranchShadow));
  }
  // Other foliage. Cedars, bamboo, and grove trees are supplied by district
  // return tables in the reference; do not invent near-spawn placeholders for
  // them here (the former cedar at -20,-10 was conspicuously visible through
  // the opening cherry canopy).
  if (includeReferenceShrubs)
    tris.addAll(buildShrubs([
      ShrubSpot(
          x: -6.4,
          z: 6.6,
          y: groundY(6.6),
          r: .5,
          count: 4,
          spread: 1.2,
          seed: 201),
      ShrubSpot(
          x: -5.7,
          z: 12.4,
          y: groundY(12.4),
          r: .45,
          count: 3,
          spread: 1,
          seed: 202),
      const ShrubSpot(
          x: -15.5, z: 4.6, r: .5, count: 4, spread: 1.6, seed: 211),
      const ShrubSpot(
          x: -21.5, z: 4.5, r: .5, count: 4, spread: 1.6, seed: 212),
      ShrubSpot(
          x: 5.6,
          z: 15.6,
          y: groundY(15.6),
          r: .5,
          count: 4,
          spread: 1.4,
          seed: 203),
      ShrubSpot(
          x: 5.4,
          z: 31.5,
          y: groundY(31.5),
          r: .48,
          count: 3,
          spread: 1.2,
          seed: 204),
      ShrubSpot(
          x: -5.4,
          z: -13.4,
          y: groundY(-13.4),
          r: .55,
          count: 5,
          spread: 1.6,
          seed: 205),
      ShrubSpot(
          x: 6.6,
          z: -6,
          y: groundY(-6),
          r: .5,
          count: 4,
          spread: 1.4,
          seed: 206),
      const ShrubSpot(x: 16.5, z: -9.5, r: .6, count: 5, spread: 2, seed: 207),
      const ShrubSpot(x: 30, z: -9, r: .6, count: 5, spread: 2.2, seed: 208),
      const ShrubSpot(x: -16, z: 6, r: .55, count: 4, spread: 1.8, seed: 209),
      const ShrubSpot(x: 24, z: 6.5, r: .55, count: 4, spread: 1.8, seed: 210),
    ]));

  // Exact utility-pole placement table from world/index.js.
  double poleY(double x, double z, [double sink = 0]) =>
      groundY(z) +
      ((x - centerX(z)).abs() < roadHalf + walkW ? 0.135 : 0.0) -
      sink;
  final poles = <PoleOpts>[
    PoleOpts(
        x: -3.86,
        y: poleY(-3.86, 4.55),
        z: 4.55,
        h: 9.4,
        seed: 301,
        lamp: true,
        armDir: 1),
    PoleOpts(
        x: -4.35,
        y: poleY(-4.35, 14.2, 0.02),
        z: 14.2,
        h: 9.0,
        seed: 302,
        armDir: 1),
    PoleOpts(
        x: -4.85,
        y: poleY(-4.85, 24.6),
        z: 24.6,
        h: 9.2,
        seed: 303,
        lamp: true,
        armDir: 1),
    PoleOpts(
        x: -6.6,
        y: poleY(-6.6, 35.0, 0.04),
        z: 35.0,
        h: 8.8,
        seed: 304,
        armDir: 1),
    PoleOpts(
        x: 3.98,
        y: poleY(3.98, -6.6),
        z: -6.6,
        h: 9.2,
        seed: 305,
        lamp: true,
        armDir: -1),
    PoleOpts(
        x: 6.35,
        y: poleY(6.35, -16.5),
        z: -16.5,
        h: 9.0,
        seed: 306,
        armDir: -1),
    PoleOpts(
        x: 8.4,
        y: poleY(8.4, -31.6),
        z: -31.6,
        h: 8.8,
        seed: 307,
        lamp: true,
        armDir: -1),
    PoleOpts(
        x: 4.35, y: poleY(4.35, 20.8), z: 20.8, h: 9.0, seed: 308, armDir: -1),
    PoleOpts(
        x: 4.5,
        y: poleY(4.5, 34.0),
        z: 34.0,
        h: 8.6,
        seed: 309,
        lamp: true,
        armDir: -1),
    PoleOpts(
        x: 12.5,
        y: poleY(12.5, 3.7),
        z: 3.7,
        h: 8.4,
        seed: 310,
        armDir: -1,
        transformer: false),
    PoleOpts(
        x: -16.5,
        y: poleY(-16.5, -4.4),
        z: -4.4,
        h: 8.6,
        seed: 311,
        armDir: 1,
        transformer: false),
  ];
  final poleTris = <Tri>[];
  for (final pole in poles) {
    final builtPole = makePole(pole);
    poleTris.addAll(builtPole);
    add(builtPole, casts: true, group: 'poles');
    // Keep makePole's validated geometry exact and approximate its seeded
    // warning texture here as non-casting decoration until upload is wired.
    tris.addAll(_poleWarningPlate(pole));
  }
  if (includeManualNearPoleReceiverShadow) {
    final pole = poles.first;
    final y0 = manualNearPoleShadowY0, y1 = manualNearPoleShadowY1;
    double radius(double y) => .19 + (.11 - .19) * (y / pole.h) + .003;
    tris.addAll(bake([
      Part(
          cylGeometry(radius(y1), radius(y0), y1 - y0, 8),
          trs(pole.x, pole.y + (y0 + y1) * .5, pole.z),
          Mat(manualNearPoleShadow, unlit: true)),
    ]));
  }

  // Exact opening-world overhead cable graph. Thin four-sided tubes follow
  // the same sampled sine sag as util.js::sagCurve; retaining these cables is
  // compositionally important because they divide the otherwise empty sky.
  const wireMat = Mat(0x4c4658, tint: 0x413c58, bands: '2');
  final wireParts = <Part>[];
  final unitWire = cylGeometry(1, 1, 1, 4);
  void wireSpan(Vector3 a, Vector3 b, double sag, double radius) {
    final dist = (b - a).length;
    final actualSag = sag * math.min(1.6, dist / 14);
    Vector3 point(int i) {
      final t = i / 14;
      final p = a * (1 - t) + b * t;
      p.y -= math.sin(math.pi * t) * actualSag;
      return p;
    }

    var a0 = point(0);
    for (int i = 1; i <= 14; i++) {
      final b0 = point(i);
      final dir = b0 - a0;
      final q = quatFromUnitVectors(Vector3(0, 1, 0), dir.normalized());
      wireParts.add(Part(
          unitWire,
          composePRS((a0 + b0) * .5, q, Vector3(radius, dir.length, radius)),
          wireMat));
      a0 = b0;
    }
  }

  Vector3 at(int i, [double dy = 0, double dz = 0]) =>
      Vector3(poles[i].x, poles[i].y + poles[i].h - 0.6 + dy, poles[i].z + dz);
  void chain(List<int> indices, List<(double, double)> offsets) {
    for (final off in offsets) {
      for (int j = 0; j < indices.length - 1; j++) {
        wireSpan(at(indices[j], off.$1, off.$2),
            at(indices[j + 1], off.$1, off.$2), .55, .026);
      }
    }
  }

  chain([0, 1, 2, 3], const [(0, -.7), (-.42, 0), (-.86, .7)]);
  chain([4, 5, 6], const [(0, -.7), (-.42, 0), (-.86, .7)]);
  chain([7, 8], const [(0, -.6), (-.45, .6)]);
  chain([0, 4], const [(-.15, .2), (-.62, -.3)]);
  chain([1, 7], const [(-.2, .3), (-.7, -.4)]);
  chain([2, 7], const [(-1.3, .9)]);
  chain([9, 4], const [(-1.0, .2)]);
  chain([10, 1], const [(-1.1, .4)]);
  for (final drop in [
    (0, Vector3(-11, 2.35, 5.3)),
    (1, Vector3(-6, groundY(23.2) + 5.4, 21)),
    (7, Vector3(5.9, groundY(18.4) + 5, 17)),
    (4, Vector3(5.6, groundY(-10.5) + 5.2, -9)),
    (2, Vector3(-6.6, groundY(33.5) + 3.4, 32)),
  ]) {
    wireSpan(at(drop.$1, -1.9), drop.$2, .25, .022);
  }
  tris.addAll(bake(wireParts));

  // The train at the crossing.
  if (includeTrain) {
    add(
        buildTrain(
            x: trainX,
            bodyColor: trainBodyColor,
            stripeColor: trainStripeColor,
            windowColor: trainWindowColor),
        casts: true,
        group: 'train');
  }
  if (includeManualTrainSkirtShade) {
    tris.addAll(_trainReceiverBand(
        manualTrainShadowPlaneZ, .42, .60, manualSkirtShadow));
  }
  if (includeManualTrainPolePanelShade) {
    tris
      ..addAll(_trainReceiverBand(
          manualTrainShadowPlaneZ, 1.13, 1.66, manualPolePanelShadow,
          minX: -1.92, maxX: -1.36))
      ..addAll(_trainReceiverBand(
          manualTrainShadowPlaneZ, 2.09, 2.27, manualPolePanelShadow,
          minX: -1.92, maxX: -1.36));
  }
  if (includeManualPoleTrainShadows) {
    final poleCasters = poleTris
        .where((tri) =>
            !tri.mat.unlit &&
            (tri.mat.color == 0xb8bcc6 || tri.mat.color == 0xd6d2d8) &&
            math.max(tri.a.y, math.max(tri.b.y, tri.c.y)) > .55)
        .toList(growable: false);
    tris.addAll(_projectTrainCasterShadows(poleCasters,
        trainX: trainX,
        planeZ: manualTrainShadowPlaneZ,
        skirtMin: manualTrainShadowSkirtMin,
        segmentedGlass: segmentManualTrainShadowReceivers,
        bodyColor: manualBodyShadow,
        stripeColor: manualStripeShadow,
        glassColor: manualGlassShadow,
        frameColor: manualFrameShadow,
        roofColor: manualRoofShadow,
        skirtColor: manualSkirtShadow));
  }
  // The railway tracks + ballast + sleepers + crossing deck.
  final railway = buildRailway(
          gateYellowColor: gateYellowColor,
          includeCrossingBooms: includeCrossingBooms,
          includeActiveCrossingLamps: includeActiveCrossingLamps)
      .where(outsideEastReplacement)
      .toList(growable: false);
  add(railway, casts: true, group: 'railway');
  if (includeManualCrossingTrainShadows) {
    final crossingCasters = railway
        .where((tri) =>
            !tri.mat.unlit &&
            math.max(tri.a.y, math.max(tri.b.y, tri.c.y)) > .55)
        .toList(growable: false);
    tris.addAll(_projectTrainCasterShadows(crossingCasters,
        trainX: trainX,
        planeZ: manualTrainShadowPlaneZ,
        skirtMin: manualTrainShadowSkirtMin,
        segmentedGlass: segmentManualTrainShadowReceivers,
        bodyColor: manualBodyShadow,
        stripeColor: manualStripeShadow,
        glassColor: manualGlassShadow,
        frameColor: manualFrameShadow,
        skirtColor: manualSkirtShadow));
  }

  // The shop against the crossing.
  add(
      buildShop(
          shutterGrooves: includeShopShutterGrooves,
          redColor: shopRedColor,
          redSoftColor: shopRedSoftColor,
          wallColor: shopWallColor),
      casts: true,
      group: 'shop');

  // Falling + fallen cherry petals (atmosphere).
  if (includePetals) {
    tris.addAll(buildPetals(
        includeFallen: includeFallenPetals,
        includeFalling: includeFallingPetals));
  }

  // Exact opening crossing-corner furniture from world/index.js.
  double walkY(double z) => groundY(z) + 0.135;
  add(makeMirror(x: -3.62, y: walkY(3.72), z: 3.72, ry: 2.5), casts: true);
  add(makePostBox(x: 3.62, y: walkY(4.55), z: 4.55, ry: -1.4), casts: true);
  add(makeKeiTruck(x: -2.02, y: groundY(-7.4), z: -7.4, ry: math.pi / 2),
      casts: true);
  add(
      makeBicycle(
          x: -13.9, y: 0, z: 4.9, ry: -0.1, lean: 0.06, color: 0x8f6fb5),
      casts: true);
  tris.addAll(makeBicycle(
      x: -4.3,
      y: walkY(8.4),
      z: 8.4,
      ry: math.pi / 2 + 0.08,
      lean: -0.10,
      color: 0x3f6f9c));
  tris.addAll(makeBicycle(
      x: -4.3,
      y: walkY(12.2),
      z: 12.2,
      ry: -math.pi / 2 + 0.06,
      lean: 0.08,
      color: 0xd8a03c));
  tris.addAll(makeBicycle(
      x: 4.3,
      y: walkY(13.4),
      z: 13.4,
      ry: math.pi / 2 + 0.06,
      lean: 0.08,
      color: 0x9c5a4a));
  tris.addAll(makeBicycle(
      x: 5.7,
      y: walkY(15.7),
      z: 15.7,
      ry: -math.pi / 2 - 0.14,
      lean: 0.07,
      color: 0x4f8f6a));
  add(makeCone(x: 2.62, y: groundY(4.15), z: 4.15, ry: 0.4), casts: true);
  tris.addAll(
      makeCone(x: 2.42, y: groundY(5.05), z: 5.05, ry: -0.7, tilt: 0.06));
  add(makeBarrier(x: 2.62, y: groundY(6.2), z: 6.2, ry: 0.06, len: 1.7),
      casts: true);
  tris.addAll(makeCone(x: -2.3, y: groundY(-4.3), z: -4.3, ry: 0.2));
  tris.addAll(makeGuardrail(
      x: 4.5, y: walkY(15.4), z: 15.4, ry: math.pi / 2, len: 4.2));
  for (final p in const [
    (-4.6, 7.9, 0.22, true),
    (-4.5, 8.6, 0.18, false),
    (-4.7, 12.6, 0.20, true),
    (4.45, 14.5, 0.19, false),
    (-4.5, 22.0, 0.21, true),
    (4.4, 24.5, 0.20, true),
    (-4.6, -8.5, 0.22, false),
    (5.2, -7.4, 0.20, true),
    (4.5, 30.0, 0.19, true),
  ].indexed) {
    final (seedOffset, spot) = p;
    tris.addAll(makePlanter(
        x: spot.$1,
        y: walkY(spot.$2),
        z: spot.$2,
        r: spot.$3,
        flower: spot.$4,
        seed: 300 + seedOffset));
  }

  // Shop vending machines (shop.js): two machines beside the near frontage.
  const shopFront = roadHalf + walkW + 0.12;
  add(
      makeVendingMachine(
          variant: 0,
          seed: 1,
          x: shopFront - 0.42,
          y: walkY(5.55),
          z: 5.55,
          ry: -math.pi / 2),
      casts: true);
  add(
      makeVendingMachine(
          variant: 2,
          seed: 2,
          openingSideShadow: true,
          openingSideShadowColor: vendingSideShadowColor,
          tealBodyColor: vendingTealColor,
          x: shopFront - 0.42,
          y: walkY(6.8),
          z: 6.8,
          ry: -math.pi / 2),
      casts: true);

  return tris;
}

/// The near side of the passing train is another dominant shadow receiver in
/// the opening shot. Project selected caster silhouettes onto that vertical
/// plane; clipping to the body bounds keeps the decals off the sky and track.
List<Tri> _projectTrainCasterShadows(List<Tri> casterTris,
    {required double trainX,
    required double planeZ,
    required double skirtMin,
    required bool segmentedGlass,
    double offsetX = 0,
    double offsetY = 0,
    double scale = 1,
    required int bodyColor,
    required int stripeColor,
    int? stripeRepairColor,
    double stripeRepairMinX = 0,
    double stripeRepairMaxX = 0,
    double stripeRepairMinX2 = 0,
    double stripeRepairMaxX2 = 0,
    required int glassColor,
    int? glassRepairColor,
    double glassRepairMinX = 0,
    double glassRepairMaxX = 0,
    double glassRepairMinX2 = 0,
    double glassRepairMaxX2 = 0,
    required int frameColor,
    int? roofColor,
    required int skirtColor}) {
  final bodyShadow = Mat(bodyColor, unlit: true);
  final stripeShadow = Mat(stripeColor, unlit: true);
  final glassShadow = Mat(glassColor, unlit: true);
  final frameShadow = Mat(frameColor, unlit: true);
  final roofShadow = roofColor == null ? null : Mat(roofColor, unlit: true);
  final skirtShadow = Mat(skirtColor, unlit: true);
  const sunX = -52.0, sunY = 62.0, sunZ = 56.0;
  final out = <Tri>[];

  Vector3 projectRaw(Vector3 p) {
    final t = (p.z - planeZ) / sunZ;
    return Vector3(p.x - sunX * t, p.y - sunY * t, planeZ);
  }

  final projectedCenter = Vector3.zero();
  for (final tri in casterTris) {
    projectedCenter
      ..add(projectRaw(tri.a))
      ..add(projectRaw(tri.b))
      ..add(projectRaw(tri.c));
  }
  if (casterTris.isNotEmpty) {
    projectedCenter.scale(1 / (casterTris.length * 3));
  }

  Vector3 project(Vector3 p) {
    final projected =
        projectedCenter + (projectRaw(p) - projectedCenter) * scale;
    projected.x += offsetX;
    projected.y += offsetY;
    return projected;
  }

  List<Vector3> clipEdge(List<Vector3> polygon, double Function(Vector3) axis,
      double boundary, bool keepAbove) {
    if (polygon.isEmpty) return const [];
    final clipped = <Vector3>[];
    var previous = polygon.last;
    var previousValue = axis(previous);
    var previousInside =
        keepAbove ? previousValue >= boundary : previousValue <= boundary;
    for (final current in polygon) {
      final currentValue = axis(current);
      final currentInside =
          keepAbove ? currentValue >= boundary : currentValue <= boundary;
      if (currentInside != previousInside) {
        final t = (boundary - previousValue) / (currentValue - previousValue);
        clipped.add(previous + (current - previous) * t);
      }
      if (currentInside) clipped.add(current);
      previous = current;
      previousValue = currentValue;
      previousInside = currentInside;
    }
    return clipped;
  }

  List<Vector3> clipRect(List<Vector3> polygon, double minX, double maxX,
      double minY, double maxY) {
    var clipped = clipEdge(polygon, (p) => p.x, minX, true);
    clipped = clipEdge(clipped, (p) => p.x, maxX, false);
    clipped = clipEdge(clipped, (p) => p.y, minY, true);
    return clipEdge(clipped, (p) => p.y, maxY, false);
  }

  void addClipped(List<Vector3> polygon, Mat mat) {
    if (polygon.length < 3) return;
    for (var i = 1; i + 1 < polygon.length; i++) {
      var b = polygon[i];
      var c = polygon[i + 1];
      if ((b - polygon.first).cross(c - polygon.first).z < 0) {
        final swap = b;
        b = c;
        c = swap;
      }
      out.add(Tri(polygon.first, b, c, Vector3(0, 0, 1), mat));
    }
  }

  void addClippedRanges(
      List<Vector3> polygon,
      double minX,
      double maxX,
      double minY,
      double maxY,
      Mat normal,
      int? repairColor,
      List<(double, double)> repairRanges) {
    if (repairColor == null) {
      addClipped(clipRect(polygon, minX, maxX, minY, maxY), normal);
      return;
    }
    final cuts = <double>[minX, maxX];
    for (final range in repairRanges) {
      if (range.$2 <= range.$1 || maxX <= range.$1 || minX >= range.$2) {
        continue;
      }
      cuts
        ..add(math.max(minX, range.$1))
        ..add(math.min(maxX, range.$2));
    }
    cuts.sort();
    for (var i = 0; i + 1 < cuts.length; i++) {
      if (cuts[i + 1] <= cuts[i]) continue;
      final midpoint = (cuts[i] + cuts[i + 1]) * .5;
      final repair = repairRanges
          .any((range) => midpoint >= range.$1 && midpoint <= range.$2);
      addClipped(clipRect(polygon, cuts[i], cuts[i + 1], minY, maxY),
          repair ? Mat(repairColor, unlit: true) : normal);
    }
  }

  // The near faces of the three cars. Keeping the short inter-car gaps open
  // is important in the opening composition, where pale scenery is visible
  // between the coupled cars.
  final cars = [
    for (final center in [-20.1, 0.0, 20.1])
      (trainX + center, trainX + center - 9.7, trainX + center + 9.7),
  ];
  final receiverBands = <(double, double, Mat)>[
    // The second underframe and wheels extend below .40; the old .56 lower
    // bound left their visible faces unable to receive projected shadows.
    (skirtMin, 1.06, skirtShadow),
    (1.06, 1.66, bodyShadow),
    // The main 34 cm waist stripe plus its narrow lower pinstripe.
    (1.66, 2.09, stripeShadow),
    // The metal window frame extends 7 cm below and above the glass pane.
    (2.09, 2.16, frameShadow),
    (3.16, 3.23, frameShadow),
    (3.23, 3.78, bodyShadow),
    // The inset roof has a narrow near-side fascia above the main body. Only
    // poles need this software-renderer repair; the other casters are already
    // retained on the roof by the auxiliary shadow pass.
    if (roofShadow != null) (3.78, 3.97, roofShadow),
  ];

  for (final tri in casterTris) {
    // Only casters on the sunward (+Z) side of this receiver plane can
    // occlude it. Projecting far-side trees backwards along +sun produced
    // large false blobs across the train.
    if (tri.centroid.z <= planeZ) continue;
    final projected = [project(tri.a), project(tri.b), project(tri.c)];
    for (final car in cars) {
      for (final band in receiverBands) {
        if (band.$3 == stripeShadow) {
          addClippedRanges(projected, car.$2, car.$3, band.$1, band.$2,
              stripeShadow, stripeRepairColor, [
            (stripeRepairMinX, stripeRepairMaxX),
            (stripeRepairMinX2, stripeRepairMaxX2),
          ]);
        } else {
          addClipped(
              clipRect(projected, car.$2, car.$3, band.$1, band.$2), band.$3);
        }
      }
      if (!segmentedGlass) {
        addClipped(
            clipRect(projected, car.$2, car.$3, 2.16, 3.16), glassShadow);
        continue;
      }

      // Windows occupy alternating bays and door panes. The gaps are cream
      // pillars/door frames, so they must retain the body shadow tone rather
      // than being painted as one continuous dark glass strip.
      final glassIntervals = <(double, double)>[
        for (final bay in const [
          (-8.5, 1.7),
          (-7.0, .94),
          (-4.7, 3.2),
          (-2.4, .94),
          (0.0, 3.4),
          (2.4, .94),
          (4.7, 3.2),
          (7.0, .94),
          (8.5, 1.7),
        ])
          (car.$1 + bay.$1 - bay.$2 / 2, car.$1 + bay.$1 + bay.$2 / 2),
      ];
      var x = car.$2;
      void addGlass(double minX, double maxX) {
        if (glassRepairColor == null) {
          addClipped(clipRect(projected, minX, maxX, 2.16, 3.16), glassShadow);
          return;
        }
        final repairRanges = [
          (glassRepairMinX, glassRepairMaxX),
          (glassRepairMinX2, glassRepairMaxX2),
        ];
        final cuts = <double>[minX, maxX];
        for (final range in repairRanges) {
          if (range.$2 <= range.$1 || maxX <= range.$1 || minX >= range.$2) {
            continue;
          }
          cuts
            ..add(math.max(minX, range.$1))
            ..add(math.min(maxX, range.$2));
        }
        cuts.sort();
        for (var i = 0; i + 1 < cuts.length; i++) {
          if (cuts[i + 1] <= cuts[i]) continue;
          final midpoint = (cuts[i] + cuts[i + 1]) * .5;
          final repair = repairRanges
              .any((range) => midpoint >= range.$1 && midpoint <= range.$2);
          addClipped(clipRect(projected, cuts[i], cuts[i + 1], 2.16, 3.16),
              repair ? Mat(glassRepairColor, unlit: true) : glassShadow);
        }
      }

      for (final interval in glassIntervals) {
        if (interval.$1 > x) {
          addClipped(
              clipRect(projected, x, interval.$1, 2.16, 3.16), bodyShadow);
        }
        addGlass(interval.$1, interval.$2);
        x = interval.$2;
      }
      if (x < car.$3) {
        addClipped(clipRect(projected, x, car.$3, 2.16, 3.16), bodyShadow);
      }
    }
  }
  return out;
}

List<Tri> _poleWarningPlate(PoleOpts pole) {
  final variant = RngKit(pole.seed).ints(0, 2);
  final field = Mat(const [0xf4c033, 0xe0453f, 0xfdf8f0][variant], unlit: true);
  const glyph = Mat(0xfbd6e0, unlit: true);
  final face = pole.plateFace ?? (pole.armDir > 0 ? math.pi / 2 : -math.pi / 2);
  final parts = <Part>[
    Part(
        cylGeometry(0.2055, 0.2105, 0.62, 12,
            openEnded: true, thetaStart: -1.0, thetaLength: 2.0),
        trs(0, 2.45, 0, 0, face, 0),
        field),
  ];
  if (variant == 1) {
    parts.addAll([
      Part(
          cylGeometry(0.209, 0.212, 0.14, 4,
              openEnded: true, thetaStart: -0.55, thetaLength: 0.35),
          trs(0, 2.38, 0, 0, face, 0),
          glyph),
      Part(
          cylGeometry(0.209, 0.213, 0.24, 2,
              openEnded: true, thetaStart: -0.20, thetaLength: 0.12),
          trs(0, 2.39, 0, 0, face, 0),
          glyph),
      Part(
          cylGeometry(0.211, 0.213, 0.08, 2,
              openEnded: true, thetaStart: -0.75, thetaLength: 0.17),
          trs(0, 2.34, 0, 0, face, 0),
          glyph),
      Part(
          cylGeometry(0.208, 0.210, 0.14, 2,
              openEnded: true, thetaStart: -0.17, thetaLength: 0.07),
          trs(0, 2.58, 0, 0, face, 0),
          glyph),
    ]);
  }
  final baked = bake(parts);
  final offset = Vector3(pole.x, pole.y, pole.z);
  return [
    for (final tri in baked)
      Tri(tri.a + offset, tri.b + offset, tri.c + offset, tri.normal, tri.mat),
  ];
}

/// Project cherry trees along the reference directional light onto the
/// authored road surface. The software renderer does not retain these casters
/// in the auxiliary shadow view.
List<Tri> _projectRoadTreeShadow(List<Tri> trees, int color) {
  const sunX = -52.0, sunY = 62.0, sunZ = 56.0;
  final shadow = Mat(color, unlit: true);
  final out = <Tri>[];

  Vector3 project(Vector3 point) {
    // One refinement accounts for the road's slowly varying height.
    var receiverY = groundY(point.z);
    var t = (point.y - receiverY) / sunY;
    final z = point.z - sunZ * t;
    receiverY = groundY(z);
    t = (point.y - receiverY) / sunY;
    return Vector3(point.x - sunX * t, receiverY + .034, point.z - sunZ * t);
  }

  for (final tri in trees) {
    final projected = [project(tri.a), project(tri.b), project(tri.c)];
    final center = (projected[0] + projected[1] + projected[2]) / 3.0;
    // Small boundary overdraw is hidden by the curb.
    if (center.z > 13.55 || center.z < -20) continue;
    final roadCenter = centerX(center.z);
    if (center.x < roadCenter - roadHalf - .45 ||
        center.x > roadCenter + roadHalf + .45) {
      continue;
    }
    var a = projected[0], b = projected[1], c = projected[2];
    if ((b - a).cross(c - a).y < 0) {
      final swap = b;
      b = c;
      c = swap;
    }
    out.add(Tri(a, b, c, Vector3(0, 1, 0), shadow));
  }
  return out;
}

/// A long branch-scale component of the opening tree shadow. Its two long
/// edges follow the projected sun vector and its endpoints are expressed on
/// the authored road, so it remains seated correctly after the planet wrap.
List<Tri> _foregroundBranchShadow(int color) {
  final mat = Mat(color, unlit: true);
  Vector3 point(double x, double z) => Vector3(x, groundY(z) + .036, z);
  final a = point(-.78, 10.12);
  final b = point(-.10, 9.88);
  final c = point(2.10, 7.25);
  final d = point(1.50, 7.30);
  return [
    Tri(a, b, c, Vector3(0, 1, 0), mat),
    Tri(a, c, d, Vector3(0, 1, 0), mat),
  ];
}

List<Tri> _trainReceiverBand(double z, double minY, double maxY, int color,
    {double minX = -1.8, double maxX = 1.7}) {
  final mat = Mat(color, unlit: true);
  final out = <Tri>[];
  for (final range in [(minX, maxX)]) {
    final minX = range.$1;
    final maxX = range.$2;
    final a = Vector3(minX, minY, z);
    final b = Vector3(maxX, minY, z);
    final c = Vector3(maxX, maxY, z);
    final d = Vector3(minX, maxY, z);
    out
      ..add(Tri(a, b, c, Vector3(0, 0, 1), mat))
      ..add(Tri(a, c, d, Vector3(0, 0, 1), mat));
  }
  return out;
}

/// Tapered continuation of the long foreground branch toward its sunward tip.
List<Tri> _foregroundBranchTip(int color) {
  final mat = Mat(color, unlit: true);
  Vector3 point(double x, double z) => Vector3(x, groundY(z) + .036, z);
  final a = point(1.50, 7.30);
  final b = point(2.10, 7.25);
  final c = point(2.95, 5.36);
  final d = point(2.48, 5.32);
  return [
    Tri(a, b, c, Vector3(0, 1, 0), mat),
    Tri(a, c, d, Vector3(0, 1, 0), mat),
  ];
}

List<Tri> _foregroundBranchCore(int color) {
  final mat = Mat(color, unlit: true);
  Vector3 point(double x, double z) => Vector3(x, groundY(z) + .038, z);
  List<Tri> quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d) => [
        Tri(a, d, c, Vector3(0, 1, 0), mat),
        Tri(a, c, b, Vector3(0, 1, 0), mat),
      ];
  return [
    ...quad(point(1.747, 6.736), point(2.704, 6.490), point(2.501, 7.161),
        point(2.128, 7.254)),
    ...quad(point(1.109, 7.681), point(1.936, 7.495), point(1.826, 7.680),
        point(.956, 7.872)),
  ];
}

/// The broad fork immediately to the right of the long foreground branch.
List<Tri> _foregroundBranchLobe(int color) {
  final mat = Mat(color, unlit: true);
  Vector3 point(double x, double z) => Vector3(x, groundY(z) + .036, z);
  final a = point(.58, 9.53);
  final b = point(.98, 9.641);
  final c = point(2.08, 7.72);
  final d = point(1.52, 7.70);
  return [
    Tri(a, b, c, Vector3(0, 1, 0), mat),
    Tri(a, c, d, Vector3(0, 1, 0), mat),
  ];
}

List<Tri> _foregroundBranchFork(int color) {
  final mat = Mat(color, unlit: true);
  Vector3 point(double x, double z) => Vector3(x, groundY(z) + .037, z);
  final a = point(1.592, 8.426);
  final b = point(1.806, 8.379);
  final c = point(1.769, 8.986);
  final d = point(1.369, 9.071);
  return [
    Tri(a, d, c, Vector3(0, 1, 0), mat),
    Tri(a, c, b, Vector3(0, 1, 0), mat),
  ];
}
