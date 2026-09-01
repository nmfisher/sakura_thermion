/// Math helpers — a faithful port of the reference `src/core/util.js`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const double tau = math.pi * 2;
const double deg = math.pi / 180;

double clampN(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double lerp(double a, double b, double t) => a + (b - a) * t;
double invLerp(double a, double b, double v) => (v - a) / (b - a);

/// Hermite smoothstep that tolerates a > b (descending ranges).
double sstep(double a, double b, double v) {
  final t = clampN((v - a) / ((b - a).abs() < 1e-12 ? 1e-6 : (b - a)), 0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Deterministic mulberry32 PRNG, ported verbatim so the street looks identical
/// on every load. All values are kept as unsigned 32-bit (Dart ints are 64-bit,
/// so every JS `>>> 0` truncation is a `& 0xFFFFFFFF` here; `Math.imul` is the
/// low 32 bits of the product).
int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;

/// The mulberry32 scramble, applied to an already-incremented state.
int _scramble(int a) {
  var t = a;
  t = _imul(t ^ (t >>> 15), t | 1);
  t = (t ^ ((t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  return (t ^ (t >>> 14)) & 0xFFFFFFFF;
}

class Rng {
  int _a;
  Rng(int seed) : _a = seed >>> 0;
  double next() {
    _a = (_a + 0x6d2b79f5) & 0xFFFFFFFF;
    return _scramble(_a) / 4294967296.0;
  }

  double range(double a, double b) => a + (b - a) * next();
  int intRange(int a, int b) => (a + (b - a + 1) * next()).floor();
  T pick<T>(List<T> arr) => arr[(next() * arr.length).floor() % arr.length];
  bool chance(double p) => next() < p;
  int sign() => next() < 0.5 ? -1 : 1;
}

/// rngKit(seed) helper bundle, matching the reference.
Rng rngKit(int seed) => Rng(seed);

/// Build a Float32List from a growable list of doubles.
Float32List f32(List<double> xs) => Float32List.fromList(xs);
