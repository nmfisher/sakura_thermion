/// Cel shading — a faithful port of the reference `src/core/toon.js`.
///
/// The reference uses `MeshToonMaterial` with a hand-authored gradient ramp, so
/// direct sunlight is quantised into 2–4 flat bands, and the darker bands are
/// tinted toward a cool violet rather than simply being a darker version of the
/// base colour. Here we reproduce that *exactly* in Dart and bake the result
/// into per-vertex colours, which an unlit vertex-colour material renders
/// verbatim. The band math matches the comment in the reference palette:
/// RAMPS[N] is an N-texel nearest ramp sampled at `dotNL*0.5+0.5`, so for N=3
/// the band boundaries fall at `dotNL = ±1/3`.
library;

import 'dart:math' show pi;

import 'package:vector_math/vector_math_64.dart';

import 'palette.dart';

/// The 1D gradient ramps, as normalised 0..1 stops (mirrors `RAMPS` in toon.js).
const Map<String, List<double>> ramps = {
  '2': [96 / 255, 1.0],
  '3': [92 / 255, 178 / 255, 1.0],
  '4': [80 / 255, 142 / 255, 202 / 255, 1.0],
  '5': [74 / 255, 124 / 255, 172 / 255, 214 / 255, 1.0],
  'soft': [180 / 255, 1.0],
  'soft3': [172 / 255, 214 / 255, 1.0],
};

List<double> rampFor(String bands) => ramps[bands] ?? ramps['3']!;

/// Quantise a dotNL through the nearest-filtered ramp (the heart of the toon
/// look). `dotNL*0.5+0.5` maps [-1,1]→[0,1]; floor(u*N) picks the band.
double rampQuant(List<double> ramp, double dotNL) {
  final n = ramp.length;
  final u = (dotNL * 0.5 + 0.5).clamp(0.0, 1.0);
  final idx = (u * n).floor().clamp(0, n - 1);
  return ramp[idx];
}

/// The two-light anime setup, evaluated in Dart. Directions point *from the
/// surface toward the light* (i.e. the direction the light travels is -dir;
/// dotNL = dot(normal, dir)). Everything is stored in linear space.
class CelShader {
  CelShader({
    required this.sunDir,
    required this.fillDir,
    required this.bounceDir,
    Vector3? sunColor,
    Vector3? fillColor,
    Vector3? bounceColor,
    Vector3? hemiSky,
    Vector3? hemiGround,
    this.sunI = 2.25,
    this.fillI = 1.08,
    this.bounceI = 0.34,
    this.hemiI = 1.12,
    // three.js's MeshToonMaterial is a Lambert BRDF: outgoing = albedo / PI *
    // irradiance, so the whole lit sum is normalised by 1/PI to match the
    // reference's linear rtScene values exactly (then the grade pass applies
    // the linear->sRGB display transform, like the reference's GRADE_SHADER).
    this.globalGain = 1.0 / pi,
  })  : sunColor = sunColor ?? C.lin(Pal.sun),
        fillColor = fillColor ?? C.lin(Pal.fill),
        bounceColor = bounceColor ?? C.lin(0xd8cbe8),
        hemiSky = hemiSky ?? C.lin(Pal.hemiSky),
        hemiGround = hemiGround ?? C.lin(Pal.hemiGround);

  final Vector3 sunDir, fillDir, bounceDir;
  final Vector3 sunColor, fillColor, bounceColor, hemiSky, hemiGround;
  final double sunI, fillI, bounceI, hemiI;

  /// Overall brightness gain = 1/PI, the Lambert BRDF normalisation that
  /// three.js's MeshToonMaterial applies. With it, the baked linear colour
  /// matches the reference's linear rtScene; the grade pass does the sRGB
  /// display transform.
  final double globalGain;

  /// Lit linear colour for `baseHex` under the lighting, given a face normal.
  /// [tint] is the cool shadow-tint hex for this surface (default violet),
  /// [bands] selects the ramp ("2".."5", "soft", "soft3"). With [inShadow]
  /// the sun is dropped from the sum — the baked equivalent of a cast shadow
  /// (the reference's sunlit/shadowed road differ by exactly this).
  Vector3 shade(
    int baseHex,
    Vector3 n, {
    int tint = 0x6c5f8c,
    String bands = '3',
    bool inShadow = false,
  }) =>
      shadeRamp(baseHex, n, rampFor(bands), tint: tint, inShadow: inShadow);

  /// Cel shade with an explicit ramp (e.g. extracted from the reference's
  /// gradientMap). The public [shade] delegates here after resolving `bands`.
  Vector3 shadeRamp(
    int baseHex,
    Vector3 n,
    List<double> ramp, {
    int tint = 0x6c5f8c,
    bool inShadow = false,
  }) {
    final base = C.lin(baseHex);
    final tintLin = C.lin(tint);

    double dir(Vector3 d) => n.dot(d);
    final key = inShadow ? 0.0 : rampQuant(ramp, dir(sunDir));
    final fil = rampQuant(ramp, dir(fillDir));
    final bnc = rampQuant(ramp, dir(bounceDir));

    final out = Vector3.zero();

    // contribution = base * celBand * mix(tint,1,celBand) * lightColor * I,
    // per channel. mix = tint*(1-b) + b — dark bands go violet.
    void addLight(double b, Vector3 color, double intensity) {
      final mx = tintLin.x * (1 - b) + b;
      final my = tintLin.y * (1 - b) + b;
      final mz = tintLin.z * (1 - b) + b;
      out.x += base.x * b * mx * color.x * intensity;
      out.y += base.y * b * my * color.y * intensity;
      out.z += base.z * b * mz * color.z * intensity;
    }

    addLight(key, sunColor, sunI);
    addLight(fil, fillColor, fillI);
    addLight(bnc, bounceColor, bounceI);

    // hemisphere ambient: sky for up-facing, ground colour for down-facing.
    final h = (n.y * 0.5 + 0.5).clamp(0.0, 1.0);
    out.x += base.x * (hemiSky.x * h + hemiGround.x * (1 - h)) * hemiI;
    out.y += base.y * (hemiSky.y * h + hemiGround.y * (1 - h)) * hemiI;
    out.z += base.z * (hemiSky.z * h + hemiGround.z * (1 - h)) * hemiI;

    out.scale(globalGain);
    return out;
  }
}
