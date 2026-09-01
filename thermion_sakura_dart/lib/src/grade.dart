/// The reference's anime colour grade, approximated as a Filament ColorGrading
/// (the live viewer has no offline finale, so the grade — saturation, split-tone
/// toward cool darks / warm lights, warmth — is applied here). Mirrors
/// `tool/finale.py::grade()` / `post.js GRADE_SHADER` as closely as Filament's
/// tonal controls allow.
library;

import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:vector_math/vector_math_64.dart';

/// Build the graded ColorGrading: linear tone mapper (no ACES), SAT 1.12, a
/// warm white balance, and a split-tone (shadows cooled toward violet, lights
/// warmed toward cream) — the reference's GRADE_SHADER signature.
Future<dynamic> buildGradedColorGrading(FFIFilamentApp app) async {
  final b = FFIColorGradingBuilder(
    await withPointerCallback<TColorGradingBuilder>(
        (cb) => ColorGradingBuilder_createRenderThread(cb)),
    app,
  );
  // Linear tone mapper: keep the cel values as-authored (the grade below shapes
  // them; no ACES compression).
  b.toneMapper(await ToneMapper.linear(app));
  // The finale grade multiplies by mix(shadowTint, lightTint, k) ≈ ×0.7–0.85
  // (a ~25% darkening). Approximate that overall multiply with a negative
  // exposure stop (slopeOffsetPower would do it per-channel; exposure is the
  // single global lever).
  b.exposure(-0.35);
  // SAT 1.12 (post.js uSaturation).
  b.saturation(1.12);
  // Warm late-afternoon light (post.js warmth: R up, B down).
  b.whiteBalance(0.35, 0.0);
  // Split-tone: shadows cooled toward the violet shadowTint (0xada8d0),
  // highlights warmed toward the cream lightTint (0xfff7e8).
  b.shadowsMidtonesHighlights(
    Vector4(-0.04, -0.05, 0.02, 0.0), // shadows: cool toward violet
    Vector4(0.0, 0.0, 0.0, 0.0), // midtones: neutral
    Vector4(0.0, -0.03, -0.06, 0.0), // highlights: warm (drop G/B)
    Vector4(0.0, 0.3, 0.55, 1.0),
  );
  return b.build();
}
