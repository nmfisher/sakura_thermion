/// Canonical tuning for Sakura's live ink, grade, vignette and FXAA finale.
///
/// Keep interactive hosts and deterministic fidelity renders on these values;
/// command-line renderers may still override them for calibration sweeps.
abstract final class SakuraPostSettings {
  static const saturation = 1.12;
  static const lift = 0.035;
  static const warmth = 0.025;
  static const vignette = 0.15;

  // One-pixel depth taps keep silhouettes crisp at the native output size.
  // A radius of 2 made opposing samples produce visibly broad, fuzzy bands.
  static const inkThickness = 1.0;
  static const inkSensitivity = 0.0042;
  static const inkConcave = 0.024;
  static const inkConcaveAmount = 0.418;
  static const inkFadeStart = 40.0;
  static const inkFadeEnd = 98.0;
  static const inkStrength = 0.968;
  static const inkSkyDepth = 420.0;
  static const cameraNear = 0.25;
}
