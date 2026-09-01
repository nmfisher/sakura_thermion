/// One place for every colour in the scene — a faithful port of the reference
/// `src/core/palette.js`.
///
/// The palette is deliberately narrow: warm off-whites, a gray-purple road,
/// teal-leaning greens, pale pinks, and four saturated accents (red / yellow /
/// blue / teal) reserved for focal objects.  Values are 0xRRGGBB ints.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

class Pal {
  // --- sky & atmosphere ---
  static const int skyTop = 0x8fbdea;
  static const int skyMid = 0xd4e8fa;
  static const int skyHaze = 0xfbe7e9;
  static const int cloud = 0xfdfaf8;
  static const int cloudShade = 0xe6e6f2;
  static const int fog = 0xe6ecf7;
  static const int hill = 0xc6cfe6;
  static const int hillFar = 0xd8dded;

  // --- light ---
  static const int sun = 0xfff1d8;
  static const int fill = 0xa9bdf5;
  static const int hemiSky = 0xdcecff;
  static const int hemiGround = 0xb6a6c6;

  // --- ink ---
  static const int ink = 0x39324f;
  static const int inkSoft = 0x4a4468;

  // --- ground ---
  static const int road = 0x8e8a9c;
  static const int roadWorn = 0x9a95a6;
  static const int roadDark = 0x7b7689;
  static const int lineWhite = 0xf4f2f6;
  static const int lineYellow = 0xf0c341;
  static const int tactile = 0xf2c53d;
  static const int sidewalk = 0xdcd8e2;
  static const int sidewalkAlt = 0xe7e2e6;
  static const int curb = 0xc7c2d0;
  static const int concrete = 0xd9d5dd;
  static const int concreteMid = 0xc2bdc8;
  static const int concreteDark = 0xa7a2b0;
  static const int gutter = 0xbdb8c4;
  static const int drain = 0x6d687a;
  static const int dirt = 0xc9bfae;
  static const int gravel = 0xa9a3ab;
  static const int ballast = 0x7d7686;

  // --- buildings ---
  static const int wallWhite = 0xfaf6ef;
  static const int wallCream = 0xf2e7d3;
  static const int wallBlue = 0xd6e3ee;
  static const int wallBeige = 0xe7dbc4;
  static const int wallGray = 0xdedee6;
  static const int wallPink = 0xf0dcda;
  static const int wallTea = 0xdccdb6;
  static const int wallSage = 0xdde2d6;
  static const int roofSlate = 0x59617a;
  static const int roofBlue = 0x4d5c78;
  static const int roofBrown = 0x6b585c;
  static const int roofTeal = 0x4f6b70;
  static const int trim = 0x8b8496;
  static const int glass = 0x9dc0d4;
  static const int glassDark = 0x53627a;
  static const int shutter = 0x6e6a7a;
  static const int shutterLight = 0x847f92;

  // --- accents ---
  static const int red = 0xe0453f;
  static const int redDeep = 0xb5322f;
  static const int redSoft = 0xef6a60;
  static const int yellow = 0xf4c033;
  static const int yellowDeep = 0xd39c1f;
  static const int black = 0x322e3b;
  static const int blackSoft = 0x453f4f;
  static const int teal = 0x2f9c9a;
  static const int tealDeep = 0x22736f;
  static const int blue = 0x3d6ec4;
  static const int blueDeep = 0x2a4f97;
  static const int orange = 0xef8a3c;
  static const int purple = 0x8f6fb5;

  // --- vegetation ---
  static const int leaf = 0x5aa578;
  static const int leafDeep = 0x3f7f60;
  static const int leafPale = 0x84bd97;
  static const int grass = 0x86ab84;
  static const int trunk = 0x9a8082;
  static const int trunkDark = 0x765f62;

  // --- cherry blossom ---
  static const int blossom = 0xfbc6d8;
  static const int blossomLight = 0xfff0f4;
  static const int blossomWarm = 0xfedde2;
  static const int blossomDeep = 0xf0a3c0;
  static const int petal = 0xfcd9e4;
  static const int petalDeep = 0xf6bccf;

  // --- railway ---
  static const int railMetal = 0x6b6472;
  static const int railHead = 0xc2bcc4;
  static const int sleeper = 0x6d6576;
  static const int sleeperLight = 0x847b8c;
  static const int gateYellow = 0xf4c033;
  static const int gateBlack = 0x322e3b;
  static const int signalRed = 0xf2453c;
  static const int signalOff = 0x6a3b44;
  static const int cabinet = 0xd8d5da;
  static const int cabinetTop = 0xb6b2bc;

  // --- train ---
  static const int trainBody = 0xf7f2e6;
  static const int trainBodyShade = 0xe6dfd0;
  static const int trainStripe = 0x2f7fd0;
  static const int trainStripe2 = 0x3fae9a;
  static const int trainWindow = 0x3a4258;
  static const int trainWindowLit = 0x6b7794;
  static const int trainSkirt = 0x9aa0ad;
  static const int trainRoof = 0xbdb8bd;
  static const int trainDoor = 0xeae4d8;

  // --- metal / misc props ---
  static const int metal = 0xb8bcc6;
  static const int metalDark = 0x878b96;
  static const int metalWarm = 0xc9c0b4;
  static const int vendWhite = 0xf8f5f0;
  static const int vendRed = 0xdb4038;
  static const int vendTeal = 0x2e9a98;
  static const int cat = 0xf0e6da;
  static const int catDark = 0x6a5f63;
  static const int shrineStone = 0xcfcad2;
  static const int shrineBib = 0xd8453f;

  /// Wall tones, indexable the way the reference's `wall:` numbers address them.
  static const List<int> walls = [
    wallWhite, wallCream, wallBlue, wallBeige, wallGray, wallPink, wallTea, wallSage,
  ];
  static const List<int> roofs = [
    roofSlate, roofBlue, roofBrown, roofTeal,
  ];

  /// Bright can/bottle colours for vending machine shelves.
  static const List<int> drinks = [
    0xe0453f, 0xf4c033, 0x3d6ec4, 0x2f9c9a, 0xef8a3c, 0x8f6fb5,
    0x5aa578, 0xf4f2f6, 0xe86f9c, 0x44b4d8, 0xc94f7a, 0x9dbb3c,
  ];
}

/// Colour helpers. Filament renders in linear space and converts back to sRGB
/// for display, so vertex colours fed to an unlit material must be *linear*
/// for the on-screen pixel to match the intended sRGB hex.
class C {
  const C._();

  /// sRGB 0..1 channels from a 0xRRGGBB int.
  static Vector3 srgb(int hex) {
    return Vector3(
      ((hex >> 16) & 0xff) / 255.0,
      ((hex >> 8) & 0xff) / 255.0,
      (hex & 0xff) / 255.0,
    );
  }

  static double _channelToLinear(double c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Linear 0..1 channels from a 0xRRGGBB int (sRGB→linear, per channel).
  static Vector3 lin(int hex) {
    final s = srgb(hex);
    return Vector3(_channelToLinear(s.x), _channelToLinear(s.y), _channelToLinear(s.z));
  }

  /// Relative luminance of an sRGB hex (0..1), for tuning value relationships.
  static double lum(int hex) {
    final s = srgb(hex);
    return 0.2126 * s.x + 0.7152 * s.y + 0.0722 * s.z;
  }

  static double _channelToSrgb(double c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055;
  }

  /// Convert a linear-space colour to sRGB (the display transform). The WebGL
  /// canvas in the Thermion web build has no output colour conversion, so baked
  /// vertex colours must be written in sRGB for the on-screen pixel to match
  /// the intended palette hex.
  static Vector3 toSrgb(Vector3 lin) {
    return Vector3(
      _channelToSrgb(lin.x),
      _channelToSrgb(lin.y),
      _channelToSrgb(lin.z),
    );
  }

  /// Inverse of [toSrgb]: sRGB 0..1 → linear 0..1 (per channel).
  static Vector3 fromSrgb(Vector3 srgb) {
    return Vector3(
      _channelToLinear(srgb.x),
      _channelToLinear(srgb.y),
      _channelToLinear(srgb.z),
    );
  }

  /// Linear mix of two sRGB hexes by t, returned as linear-space Vector3.
  static Vector3 mix(int a, int b, double t) {
    final la = lin(a);
    final lb = lin(b);
    return la * (1 - t) + lb * t;
  }

  /// Multiply a linear colour by a scalar (for brightness tweens).
  static Vector3 scale(Vector3 c, double k) => c * k;

  /// Pack a linear Vector3 (alpha=1) into a Float32 RGBA list.
  static Float32List rgba32(Vector3 c) =>
      Float32List.fromList([c.x, c.y, c.z, 1.0]);
}
