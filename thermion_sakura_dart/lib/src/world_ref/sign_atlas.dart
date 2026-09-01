/// Exact Canvas2D signage extracted from the Three.js reference.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';

const int sakuraSignAtlasWidth = 4096;
const int sakuraSignAtlasHeight = 3528;

class SignAtlasRegion {
  const SignAtlasRegion(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

const hallPlateRegion = SignAtlasRegion(2, 2, 512, 152);
const hallNoticeRegion = SignAtlasRegion(518, 2, 256, 352);
const gomiPlateRegion = SignAtlasRegion(780, 2, 384, 288);
const gomiGateRegion = SignAtlasRegion(1170, 2, 770, 410);
const scooterPlateRegion = SignAtlasRegion(2, 420, 256, 128);
const crossingSignRegion = SignAtlasRegion(262, 420, 512, 256);
const stationSignRegion = SignAtlasRegion(778, 420, 768, 192);
const railwayWarningRegion = SignAtlasRegion(1548, 420, 256, 512);
const trainDestinationRegion = SignAtlasRegion(2, 680, 512, 128);
const trainNumberRegion = SignAtlasRegion(518, 680, 256, 96);
const superFasciaRegion = SignAtlasRegion(2046, 2, 2048, 256);
const superInteriorCheckoutRegion = SignAtlasRegion(2046, 262, 512, 384);
const superInteriorChillerRegion = SignAtlasRegion(2562, 262, 512, 384);
const superBannerSpecialRegion = SignAtlasRegion(3070, 262, 1024, 192);
const superBannerProduceRegion = SignAtlasRegion(3070, 458, 1024, 192);
const superBannerPointsRegion = SignAtlasRegion(3070, 654, 1024, 192);
const onsenFasciaYunoyaRegion = SignAtlasRegion(2, 1026, 1024, 220);
const onsenFasciaHouraiRegion = SignAtlasRegion(1030, 1026, 1024, 220);
const onsenFasciaSakuraanRegion = SignAtlasRegion(2058, 1026, 1024, 220);
const onsenFasciaYunokaRegion = SignAtlasRegion(3070, 1026, 1024, 220);
const onsenFasciaKokeshiRegion = SignAtlasRegion(2, 1250, 1024, 220);
const onsenBladeYunoyaRegion = SignAtlasRegion(1030, 1250, 192, 768);
const onsenBladeHouraiRegion = SignAtlasRegion(1226, 1250, 192, 768);
const onsenBladeSakuraanRegion = SignAtlasRegion(1422, 1250, 192, 768);
const onsenBladeYunokaRegion = SignAtlasRegion(1618, 1250, 192, 768);
const onsenBladeKokeshiRegion = SignAtlasRegion(1814, 1250, 192, 768);
const onsenNorenYunoyaRegion = SignAtlasRegion(2010, 1250, 512, 256);
const onsenNorenKanmiRegion = SignAtlasRegion(2526, 1250, 512, 256);
const onsenNorenKissaRegion = SignAtlasRegion(3042, 1250, 512, 256);
const tatamiRoom0Region = SignAtlasRegion(2010, 1510, 512, 320);
const tatamiRoom1Region = SignAtlasRegion(2526, 1510, 512, 320);
const shopFasciaBentoRegion = SignAtlasRegion(2010, 1834, 1024, 224);
const shopFasciaZakkaRegion = SignAtlasRegion(3070, 1834, 1024, 224);
const shopFasciaBunguRegion = SignAtlasRegion(2, 2022, 1024, 224);
const onsenLantern0Region = SignAtlasRegion(1030, 2022, 256, 256);
const onsenLantern1Region = SignAtlasRegion(1290, 2022, 256, 256);
const onsenLantern2Region = SignAtlasRegion(1550, 2022, 256, 256);
const tatamiRoomGlazed0Region = SignAtlasRegion(1810, 2022, 512, 320);
const tatamiRoomGlazed1Region = SignAtlasRegion(2326, 2022, 512, 320);
const onsenPoster2Region = SignAtlasRegion(2842, 2022, 320, 448);
const houraiFujiRegion = SignAtlasRegion(2, 2498, 1024, 340);
const onsenNorenMaleRegion = SignAtlasRegion(1030, 2498, 512, 256);
const onsenNorenFemaleRegion = SignAtlasRegion(1546, 2498, 512, 256);
const ashiyuPlateRegion = SignAtlasRegion(2062, 2498, 384, 512);
const schoolChainRegion = SignAtlasRegion(2450, 2498, 1600, 40);
const pedestrianArrowRegion = SignAtlasRegion(2, 3014, 512, 512);
const superHoursRegion = SignAtlasRegion(518, 3014, 384, 512);
const superPoster0Region = SignAtlasRegion(906, 3014, 362, 512);
const superPoster1Region = SignAtlasRegion(1272, 3014, 362, 512);
const superPoster2Region = SignAtlasRegion(1638, 3014, 362, 512);
const superPoster3Region = SignAtlasRegion(2004, 3014, 362, 512);
const superDealRegion = SignAtlasRegion(2370, 3014, 384, 512);

const _atlasMaterial = Mat(0xffffff, unlit: true, noOutline: true);

/// Appends one atlas-backed quad in the local XY plane, facing local +Z.
///
/// Atlas V coordinates are inverted because PNG rows start at the top while
/// Filament's texture coordinates start at the bottom. [matrix] places the
/// quad directly in the source scene's flat world before planet wrapping.
void appendSignAtlasPlane(
  List<Tri> out,
  SignAtlasRegion region, {
  required double width,
  required double height,
  required Matrix4 matrix,
  Mat material = _atlasMaterial,
  bool flipU = false,
}) {
  final regionU0 = region.x / sakuraSignAtlasWidth;
  final regionU1 = (region.x + region.width) / sakuraSignAtlasWidth;
  final u0 = flipU ? regionU1 : regionU0;
  final u1 = flipU ? regionU0 : regionU1;
  final vTop = 1.0 - region.y / sakuraSignAtlasHeight;
  final vBottom = 1.0 - (region.y + region.height) / sakuraSignAtlasHeight;
  final hw = width / 2;
  final hh = height / 2;
  final topLeft = matrix.transformed3(Vector3(-hw, hh, 0));
  final bottomLeft = matrix.transformed3(Vector3(-hw, -hh, 0));
  final bottomRight = matrix.transformed3(Vector3(hw, -hh, 0));
  final topRight = matrix.transformed3(Vector3(hw, hh, 0));
  final normalMatrix = matrix.clone()..setTranslationRaw(0, 0, 0);
  final normal = normalMatrix.transformed3(Vector3(0, 0, 1))..normalize();

  out
    ..add(Tri(
      topLeft,
      bottomLeft,
      topRight,
      normal,
      material,
      uvA: Vector2(u0, vTop),
      uvB: Vector2(u0, vBottom),
      uvC: Vector2(u1, vTop),
    ))
    ..add(Tri(
      bottomLeft,
      bottomRight,
      topRight,
      normal,
      material,
      uvA: Vector2(u0, vBottom),
      uvB: Vector2(u1, vBottom),
      uvC: Vector2(u1, vTop),
    ));
}

/// Appends the open mapped torso of a vertical cylinder.
void appendSignAtlasCylinder(
  List<Tri> out,
  SignAtlasRegion region, {
  required double radius,
  required double height,
  required int segments,
  required Matrix4 matrix,
  Mat material = _atlasMaterial,
}) {
  final atlasU0 = region.x / sakuraSignAtlasWidth;
  final atlasU1 = (region.x + region.width) / sakuraSignAtlasWidth;
  final vTop = 1.0 - region.y / sakuraSignAtlasHeight;
  final vBottom = 1.0 - (region.y + region.height) / sakuraSignAtlasHeight;
  final normalMatrix = matrix.clone()..setTranslationRaw(0, 0, 0);
  for (var i = 0; i < segments; i++) {
    final a0 = i * math.pi * 2 / segments;
    final a1 = (i + 1) * math.pi * 2 / segments;
    final u0 = atlasU0 + (atlasU1 - atlasU0) * i / segments;
    final u1 = atlasU0 + (atlasU1 - atlasU0) * (i + 1) / segments;
    final top0 = matrix.transformed3(
        Vector3(radius * math.sin(a0), height / 2, radius * math.cos(a0)));
    final bottom0 = matrix.transformed3(
        Vector3(radius * math.sin(a0), -height / 2, radius * math.cos(a0)));
    final top1 = matrix.transformed3(
        Vector3(radius * math.sin(a1), height / 2, radius * math.cos(a1)));
    final bottom1 = matrix.transformed3(
        Vector3(radius * math.sin(a1), -height / 2, radius * math.cos(a1)));
    final normal0 = normalMatrix
        .transformed3(Vector3(math.sin(a0), 0, math.cos(a0)))
      ..normalize();
    final normal1 = normalMatrix
        .transformed3(Vector3(math.sin(a1), 0, math.cos(a1)))
      ..normalize();
    out
      ..add(Tri(top0, bottom0, top1, normal0, material,
          uvA: Vector2(u0, vTop),
          uvB: Vector2(u0, vBottom),
          uvC: Vector2(u1, vTop)))
      ..add(Tri(bottom0, bottom1, top1, normal1, material,
          uvA: Vector2(u0, vBottom),
          uvB: Vector2(u1, vBottom),
          uvC: Vector2(u1, vTop)));
  }
}
