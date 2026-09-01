/// Composition-first owned Dart port of the east mouth in `tunnel.js`.
///
/// The surrounding height field already exists in `hills.dart`; this closes its
/// railway-facing edge with the 6.6 m horseshoe portal, a dark lined bore,
/// maintenance walk, access furniture and the engineered rock cutting visible
/// from the east-tunnel fidelity viewpoint.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geom/three_geom.dart';
import 'east_attributed_geometry_data.dart';
import 'east_bore_geometry_data.dart';
import 'east_portal_geometry_data.dart';
import 'hills.dart' show hillFieldAt, hillSurfaceY;
import 'make_props.dart' show makeCone;
import 'pixel_text.dart';
import 'source_geometry.dart';
import 'street.dart' show groundY, terrainDrop;
import 'tunnel_dressing_data.dart';

const _face = Mat(0xc2bbbf, tint: 0x6a6288, bands: '3');
const _faceDark = Mat(0xa19ba2, tint: 0x655d84, bands: '3');
const _ring = Mat(0xb6b0bb, tint: 0x605878, bands: '3');
const _coping = Mat(0xd6d2da, tint: 0x6f6790, bands: '3');
const _bore = Mat(0x565269, unlit: true, noOutline: true);
const _boreDeep = Mat(0x322f42, unlit: true, noOutline: true);
const _boreRib = Mat(0x504c63, unlit: true, noOutline: true);
const _boreFloor = Mat(0x3d3a4e, unlit: true, noOutline: true);
const _boreConc = Mat(0x7c778e, unlit: true, noOutline: true);
const _metal = Mat(0xb8bcc6, tint: 0x666090, bands: '3');
const _metalDark = Mat(0x878b96, tint: 0x5c5680, bands: '3');
const _fenceMesh = Mat(0xa8b4bc, unlit: true, noOutline: true);
const _concreteDark = Mat(0x96909f, tint: 0x655d84, bands: '3');
const _grass = Mat(0x6f9667, tint: 0x5b6f8c, bands: '3');
const _tuftDark = Mat(0x7a9c78, tint: 0x5b6f8c, bands: '3');
const _tuftLight = Mat(0xb2c894, tint: 0x5b6f8c, bands: '3');
const _shrubMats = <Mat>[
  Mat(0x5aa578, tint: 0x5b6f8c, bands: '3'),
  Mat(0x3f7f60, tint: 0x5b6f8c, bands: '3'),
  Mat(0x84bd97, tint: 0x5b6f8c, bands: '3'),
];
const _groveCanopyMats = <Mat>[
  Mat(0x8ab682, tint: 0x5b6f8c, bands: '3'),
  Mat(0x5d926e, tint: 0x5b6f8c, bands: '3'),
  Mat(0x3f6b52, tint: 0x5b6f8c, bands: '3'),
];
const _rock = Mat(0x77758b, tint: 0x56506f, bands: '3');
const _rockLight = Mat(0xa59ca0, tint: 0x68617d, bands: '3');
const _warm = Mat(0xffd76e, unlit: true, noOutline: true);
const _gravel = Mat(0xa9a3ab, tint: 0x6a6288, bands: '3');
const _timber = Mat(0xc0a582, tint: 0x6f6790, bands: '3');
const _timberDark = Mat(0x80684e, tint: 0x514b70, bands: '3');

final List<Tri> _sourcePortalGeometry =
    decodeSourceGeometry(eastPortalGeometryBase64);
final List<Tri> _sourceBoreGeometry =
    decodeSourceGeometry(eastBoreGeometryBase64);
final List<Tri> _sourceAttributedGeometry =
    decodeSourceGeometry(eastAttributedGeometryBase64);

List<Tri> _sourcePortal() {
  final result = List<Tri>.of(_sourcePortalGeometry);
  final text = <Part>[];
  appendPixelText(text, '東山トンネル',
      x: 107.575,
      y: 8.38,
      z: 0,
      height: .27,
      charWidth: .225,
      spacing: .025,
      depth: .035,
      ry: -math.pi / 2,
      mat: _faceDark);
  result.addAll(bake(text));
  return result;
}

void _box(List<Part> p, double w, double h, double d, Mat m, double x, double y,
    double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  p.add(Part(boxGeometry(w, h, d), trs(x, y, z, rx, ry, rz), m));
}

void _cyl(List<Part> p, double r, double h, int n, Mat m, double x, double y,
    double z,
    [double rx = 0, double ry = 0, double rz = 0]) {
  p.add(Part(cylGeometry(r, r, h, n), trs(x, y, z, rx, ry, rz), m));
}

void _member(List<Part> p, Vector3 a, Vector3 b, double r, Mat m) {
  final d = b - a;
  if (d.length < 1e-4) return;
  final mid = (a + b) * .5;
  final q = quatFromUnitVectors(Vector3(0, 1, 0), d.normalized());
  p.add(Part(
      cylGeometry(r, r, d.length, 7), composePRS(mid, q, Vector3.all(1)), m));
}

/// A filled horseshoe in a plane perpendicular to the railway.
List<Tri> _opening(double x, Mat material,
    {double inset = 0,
    double liner = 0,
    double yOffset = 0,
    double zOffset = 0}) {
  final half = 3.3 + liner - inset;
  final spring = 3.2 - inset * .35;
  final arch = 3.3 + liner - inset;
  final boundary = <Vector3>[
    Vector3(x, yOffset - .28, zOffset - half),
    Vector3(x, yOffset + spring, zOffset - half),
    for (var i = 0; i <= 24; i++)
      Vector3(x, yOffset + spring + math.sin(math.pi - i * math.pi / 24) * arch,
          zOffset + math.cos(math.pi - i * math.pi / 24) * half),
    Vector3(x, yOffset - .28, zOffset + half),
  ];
  final center = Vector3(x, yOffset + 2.55, zOffset);
  return [
    for (var i = 0; i < boundary.length; i++)
      Tri(center, boundary[(i + 1) % boundary.length], boundary[i],
          Vector3(-1, 0, 0), material),
  ];
}

void _archBlocks(List<Part> p, double x, Mat mat,
    {double inset = 0, double liner = 0, double depth = .24}) {
  final half = 3.3 + liner - inset;
  final arch = 3.3 + liner - inset;
  final spring = 3.2;
  const n = 18;
  for (var i = 0; i < n; i++) {
    final a = math.pi - (i + .5) * math.pi / n;
    _box(p, depth, .46, .92, mat, x, spring + math.sin(a) * (arch + .20),
        math.cos(a) * (half + .20), -a + math.pi / 2);
  }
  for (final s in [-1.0, 1.0]) {
    _box(p, depth, spring + .2, .46, mat, x, (spring + .2) / 2,
        s * (half + .20));
  }
}

// Retained as a compact procedural fallback/workbench for source audits.
// ignore: unused_element
List<Tri> _portal() {
  final p = <Part>[];
  final face = <Tri>[];
  const x = 107.96;
  // The source portal is a lens between the arched opening and its knoll, not
  // a rectangular facade. Sample the same 15 m bell used by tunnel.js so the
  // concrete falls back into the cutting on either side of the mouth.
  const hw = 3.72;
  const spring = 3.2;
  const copeY = 9.10;
  const step = .40;
  const faceHalf = 10.8;

  double capY(double z) {
    final field = hillFieldAt(108, z);
    final t = z / 15;
    final knoll = t.abs() >= 1 ? 0.0 : 11.4 * math.pow(1 - t * t, 2);
    return groundY(z) - terrainDrop + math.max(field, knoll);
  }

  double baseY(double z) => groundY(z) + math.min(hillFieldAt(108, z), 0) - 1.0;

  final stations = <double>[
    for (var z = -faceHalf; z <= faceHalf + .0001; z += step) z,
    -hw,
    hw,
  ]..sort();
  for (var i = 0; i < stations.length - 1; i++) {
    final za = stations[i], zb = stations[i + 1];
    if (zb - za < 1e-5) continue;
    final ya = capY(za), yb = capY(zb);
    final ca = math.min(ya, copeY), cb = math.min(yb, copeY);
    double lower(double z) {
      if (z.abs() >= hw) return baseY(z);
      final q = math.sqrt(math.max(0, 1 - z * z / (hw * hw)));
      return spring + hw * q;
    }

    final la = lower(za), lb = lower(zb);
    if (ca > la + .02 || cb > lb + .02) {
      final a = Vector3(x, la, za), b = Vector3(x, lb, zb);
      final c = Vector3(x, cb, zb), d = Vector3(x, ca, za);
      face.add(Tri(a, b, c, Vector3(-1, 0, 0), _face));
      face.add(Tri(a, c, d, Vector3(-1, 0, 0), _face));
    }
    if (ya > ca + .02 || yb > cb + .02) {
      final a = Vector3(x + .01, ca, za), b = Vector3(x + .01, cb, zb);
      final c = Vector3(x + .01, yb, zb), d = Vector3(x + .01, ya, za);
      face.add(Tri(a, b, c, Vector3(-1, 0, 0), _grass));
      face.add(Tri(a, c, d, Vector3(-1, 0, 0), _grass));
    }
  }
  _box(p, 1.22, .32, 9.40, _coping, x - .18, 9.10, 0);
  _box(p, 1.18, .14, 8.80, _faceDark, x - .13, 8.83, 0);

  // Proud voussoirs, springing courses and two strong pilasters.
  _archBlocks(p, x - .22, _ring, liner: .42);
  for (final z in [-4.77, 4.77]) {
    _box(p, .30, 8.80, .62, _faceDark, x - .20, 4.40, z);
    _box(p, .40, .18, .78, _faceDark, x - .24, 8.74, z);
  }

  // Name stone and its east-mouth plate.
  _box(p, .20, .66, 2.70, _coping, x - .29, 8.38, 0);
  appendPixelText(p, '東山トンネル',
      x: x - .405,
      y: 8.35,
      z: 0,
      height: .27,
      charWidth: .225,
      spacing: .025,
      depth: .035,
      ry: -math.pi / 2,
      mat: _faceDark);

  // Personnel door on the north wing, including hood, handle and threshold.
  _box(p, .18, 2.42, 1.30, _faceDark, x - .27, 1.34, -5.95);
  _box(p, .12, 2.17, 1.08, _face, x - .39, 1.27, -5.95);
  _box(p, .36, .14, 1.52, _coping, x - .42, 2.51, -5.95);
  _cyl(p, .055, .20, 8, _metalDark, x - .49, 1.28, -5.52, 0, 0, math.pi / 2);
  _box(p, .46, .16, 1.46, _concreteDark, x - .18, .08, -5.95);

  // Stepped wing walls dissolve the formal facade into the cutting.
  for (final s in [-1.0, 1.0]) {
    for (var i = 0; i < 3; i++) {
      final z = s * (7.55 + i * 1.5);
      final h = 4.4 - i;
      _box(p, 1.35, h, 1.62, _faceDark, 108.55 + i * 1.2, h / 2 - .25, z);
      _box(p, 1.55, .15, 1.80, _coping, 108.55 + i * 1.2, h - .18, z);
    }
  }
  return face..addAll(bake(p));
}

// ignore: unused_element
List<Tri> _boreAndTrack() {
  final out = <Tri>[];
  // A far oversized back cap closes the bore without occluding its lining,
  // refuge lamps and maintenance path. The previous front-plane fill made the
  // opening read as a flat black disc and depth-occluded every authored tunnel
  // detail behind it.
  out.addAll(_opening(138.0, _boreDeep, liner: 5.4));
  // Continuous inner lining between the portal and the back cap. Each quad is
  // wound toward the bore interior, leaving the mouth open while preventing
  // the exterior sky and hillside from showing between the ribs.
  const x0 = 108.06, x1 = 138.0, half = 3.72, spring = 3.2, arch = 3.72;
  for (var i = 0; i < 24; i++) {
    final a0 = math.pi - i * math.pi / 24;
    final a1 = math.pi - (i + 1) * math.pi / 24;
    final ya = spring + math.sin(a0) * arch;
    final za = math.cos(a0) * half;
    final yb = spring + math.sin(a1) * arch;
    final zb = math.cos(a1) * half;
    final a = Vector3(x0, ya, za), b = Vector3(x1, ya, za);
    final c = Vector3(x1, yb, zb), d = Vector3(x0, yb, zb);
    final n = (b - a).cross(c - a).normalized();
    out.add(Tri(a, b, c, n, _bore));
    out.add(Tri(a, c, d, n, _bore));
  }
  for (final side in [-1.0, 1.0]) {
    final bottom = Vector3(x0, -.28, side * half);
    final farBottom = Vector3(x1, -.28, side * half);
    final farTop = Vector3(x1, spring, side * half);
    final top = Vector3(x0, spring, side * half);
    final verts = side < 0
        ? [bottom, farBottom, farTop, top]
        : [top, farTop, farBottom, bottom];
    final n = (verts[1] - verts[0]).cross(verts[2] - verts[0]).normalized();
    out.add(Tri(verts[0], verts[1], verts[2], n, _bore));
    out.add(Tri(verts[0], verts[2], verts[3], n, _bore));
  }
  final p = <Part>[];
  // Alternating lining rings carry depth into the otherwise unlit hole.
  for (var x = 109.4; x <= 136.0; x += 3.0) {
    _archBlocks(p, x, _boreRib, inset: .12, depth: .10);
  }
  _box(p, 29.7, .20, 8.9, _boreFloor, 123.0, -.10, 0);
  _box(p, 30.5, .50, 1.35, _boreConc, 123.0, .25, 3.72);
  _box(p, 33.0, .10, .18, _boreRib, 122.5, .57, 3.12);
  // Warm refuge lamps, smaller and dimmer with distance.
  for (var i = 0; i < 7; i++) {
    final x = 110.2 + i * 4.0;
    _box(p, .08, .20, .34, _warm, x, 2.24, 3.18);
    _box(p, .18, .32, .46, _boreDeep, x + .03, 2.24, 3.22);
  }
  out.addAll(bake(p));
  return out;
}

// ignore: unused_element
List<Tri> _accessAndSlope() {
  final p = <Part>[];
  // North-side cess path and its low block drain.
  _box(p, 22.0, .08, 1.75, const Mat(0xc4bdae, tint: 0x6f6790, bands: '3'),
      98.0, .04, 5.25);
  _box(p, 22.0, .32, .32, _concreteDark, 98.0, .16, 6.22);
  for (var x = 88.0; x < 109.0; x += .82) {
    _box(p, .72, .055, .28, _face, x, .36, 6.05);
  }
  // Safety rail along the line and path edge.
  for (var x = 91.0; x <= 108.0; x += 1.55) {
    _box(p, .055, 1.08, .055, _metal, x, .58, 3.72);
  }
  _box(p, 17.2, .06, .06, _metal, 99.5, 1.05, 3.72);
  _box(p, 17.2, .05, .05, _metalDark, 99.5, .62, 3.72);
  // Dense anti-trespass infill from the source lineside fence. The sparse
  // structural posts alone left most of the reference's vertical line rhythm
  // missing across the tunnel mouth.
  for (var x = 90.3; x <= 108.0; x += .32) {
    _box(p, .035, .50, .035, _metal, x, .78, 3.72);
  }

  // Angular rock revetment on the near north bank.
  // These are the source hillRock instances that contribute to the visible
  // east-mouth cutting.  The source uses detail-0 dodecahedra seated on the
  // hill mesh; the previous hand-authored icosahedron rows overlapped in this
  // low camera and collapsed into one oversized boulder.
  final rockGeo = dodecahedronGeometry(1);
  const rocks = <(double, double, double, double, double, double, int)>[
    (114.8725, 6.6360, 8.2408, .5999, .3466, .5332, 0),
    (119.2787, 6.5589, 8.6970, .6625, .4697, .6578, 0),
    (116.9917, 6.4340, 8.7971, .9071, .5458, .7270, 1),
    (122.3324, 5.6776, 9.4454, .6301, .4717, .6509, 1),
    (121.6219, 5.1091, 9.8342, .4276, .2909, .3700, 0),
    (114.0747, 5.4586, 9.2749, 1.2013, .6622, 1.2278, 0),
    (115.6474, 5.1199, 9.6254, .6835, .5241, .6602, 1),
    (112.7934, 3.3845, 10.5546, .4661, .3022, .3962, 0),
    (113.0787, 3.1514, 10.7414, .3197, .1793, .2860, 1),
    (114.6101, 3.1947, 11.0281, .5089, .3416, .6303, 0),
    (117.6712, 2.8520, 11.8081, .6413, .4269, .7703, 1),
    (104.0498, 1.9891, 9.5266, .8324, .5294, .9553, 0),
    (116.2175, 1.4959, 12.9599, .4967, .2925, .4604, 1),
    (101.8091, 2.1987, 9.7379, .9637, .6241, .8085, 0),
    (115.1862, 1.3877, 12.8381, .3132, .2095, .3595, 0),
    (117.3239, .9834, 13.8177, .5830, .3696, .6542, 0),
    (102.9530, 3.2680, 10.5059, .5115, .3310, .5796, 1),
    (99.7339, 1.8172, 9.9257, .8899, .6021, 1.0260, 0),
    (106.8750, 3.4396, 13.1724, .6821, .4082, .6064, 0),
    (106.6714, 3.8029, 13.0969, .5960, .3651, .4922, 0),
    (98.9241, 1.4975, 10.3257, .5100, .2876, .5174, 1),
  ];
  for (var i = 0; i < rocks.length; i++) {
    final r = rocks[i];
    p.add(Part(
        rockGeo,
        trs(r.$1, r.$2, r.$3, i * .37, i * .71, i * .23, r.$4, r.$5, r.$6),
        r.$7 == 0 ? _rockLight : _rock));
  }
  final tuftBlade = applyMatrix(cylGeometry(0, .055, 1, 4), trs(0, .5, 0));
  for (final t in eastTunnelTuftInstances) {
    p.add(Part(
        tuftBlade,
        composePRS(Vector3(t.$1, t.$2, t.$3),
            Quaternion(t.$7, t.$8, t.$9, t.$10), Vector3(t.$4, t.$5, t.$6)),
        t.$11 == 0 ? _tuftDark : _tuftLight));
  }
  final shrubBlob = icosahedronGeometry(1, 1);
  for (final s in eastTunnelShrubInstances) {
    p.add(Part(
        shrubBlob,
        composePRS(Vector3(s.$1, s.$2, s.$3),
            Quaternion(s.$7, s.$8, s.$9, s.$10), Vector3(s.$4, s.$5, s.$6)),
        _shrubMats[s.$11]));
  }
  // Five source mesh-fence sections follow the north-bank crest. The Three.js
  // logical sample is z=12.8; the ported lattice's visually corresponding crest
  // is z=14.5. Each section gets its own terrain height so the run neither
  // floats at the portal nor buries itself at the outer end of the cutting.
  const fenceZ = 14.5;
  for (var section = 0; section < 5; section++) {
    final xa = 93.0 + section * 3.0;
    final xb = xa + 3.0;
    final baseY = hillSurfaceY((xa + xb) / 2, fenceZ);
    for (var post = 0; post <= 2; post++) {
      _cyl(p, .045, 1.30, 6, _metal, xa + post * 1.5, baseY + .65, fenceZ);
    }
    for (final railY in [.12, 1.25]) {
      _box(p, 3.0, .05, .05, _metal, (xa + xb) / 2, baseY + railY, fenceZ);
    }
    // chainLinkTex fallback: four crossed cells per 1.5 m framed panel.
    for (var panel = 0; panel < 2; panel++) {
      final panelX = xa + panel * 1.5;
      for (var cell = 0; cell < 4; cell++) {
        final ca = panelX + cell * .375;
        final cb = ca + .375;
        _member(p, Vector3(ca, baseY + .13, fenceZ + .012),
            Vector3(cb, baseY + 1.24, fenceZ + .012), .006, _fenceMesh);
        _member(p, Vector3(ca, baseY + 1.24, fenceZ + .014),
            Vector3(cb, baseY + .13, fenceZ + .014), .006, _fenceMesh);
      }
    }
  }
  return bake(p);
}

// ignore: unused_element
List<Tri> _railsideViewpoint() {
  final p = <Part>[];
  const x = 91.0, z = 7.2, y = 0.0;

  // Exact east railside viewing pad from buildViewpoints(E).
  _box(p, 5.6, .07, 3.4, _gravel, x, y + .035, z);

  // The safety rail occupies the track edge of the pad.
  for (var px = x - 2.8; px <= x + 2.8 + .01; px += 1.4) {
    _cyl(p, .04, 1.05, 7, _metal, px, y + .595, z - 1.5);
  }
  _member(p, Vector3(x - 2.8, y + 1.10, z - 1.5),
      Vector3(x + 2.8, y + 1.10, z - 1.5), .042, _metal);
  _member(p, Vector3(x - 2.8, y + .616, z - 1.5),
      Vector3(x + 2.8, y + .616, z - 1.5), .042, _metal);

  void bench(double bx, double len) {
    // Source benches face the portal (ry = pi for the east viewpoint).
    final q = trs(bx, y + .07, z + .7, 0, math.pi);
    for (var i = 0; i < 3; i++) {
      p.add(Part(boxGeometry(len, .05, .13), q * trs(0, .44, -.16 + i * .16),
          _timber));
    }
    for (var i = 0; i < 2; i++) {
      p.add(Part(boxGeometry(len, .13, .05), q * trs(0, .66 + i * .17, -.22),
          _timber));
    }
    for (final s in [-1.0, 1.0]) {
      p.add(Part(boxGeometry(.07, .52, .07),
          q * trs(s * (len - .3) / 2, .66, -.24, .12), _metalDark));
      p.add(Part(boxGeometry(.08, .44, .42),
          q * trs(s * (len - .3) / 2, .22, -.04), _metalDark));
    }
  }

  bench(x - 1.1, 1.8);
  bench(x + 1.3, 1.4);

  // Fingerpost and cone at the two outer corners of the pad. The generated
  // Japanese trail texture is represented by its timber-backed silhouette.
  _cyl(p, .05, 2.3, 8, _timberDark, x - 3.2, y + 1.15, z + 1.2);
  _cyl(p, .11, .14, 8, _concreteDark, x - 3.2, y + .07, z + 1.2);
  _box(p, 1.15, .29, .12, _timber, x - 3.2, y + 1.9, z + 1.2, 0, math.pi / 2);
  return bake(p)..addAll(makeCone(x: x - 3.2, y: y, z: z - 1.0, ry: .3));
}

// ignore: unused_element
List<Tri> _sourceTunnelCanopies(
    int blossomLightColor, int blossomColor, int blossomDeepColor) {
  final geometry = icosahedronGeometry(1, 1);
  final blossomMats = <Mat>[
    Mat(blossomLightColor, tint: 0xe2c3d2, bands: 'soft'),
    Mat(blossomColor, tint: 0xd8b2c6, bands: 'soft'),
    Mat(blossomDeepColor, tint: 0xc99cba, bands: 'soft'),
  ];
  final parts = <Part>[];
  for (final c in eastTunnelCanopyInstances) {
    final mats = c.$11 == 0 ? _groveCanopyMats : blossomMats;
    parts.add(Part(
        geometry,
        composePRS(Vector3(c.$1, c.$2, c.$3),
            Quaternion(c.$7, c.$8, c.$9, c.$10), Vector3(c.$4, c.$5, c.$6)),
        mats[c.$12],
        planetRigid: true));
  }
  return bake(parts);
}

List<Tri> buildTunnel({
  List<Tri>? shadowCasters,
  List<Tri>? groupedShadowCasters,
  int blossomLightColor = 0xf8e9ed,
  int blossomColor = 0xecb8cc,
  int blossomDeepColor = 0xe598b9,
}) {
  final scene = <Tri>[];
  void add(List<Tri> tris, {bool casts = true}) {
    scene.addAll(tris);
    if (casts) {
      shadowCasters?.addAll(tris);
      groupedShadowCasters?.addAll(tris);
    }
  }

  add(_sourceBoreGeometry, casts: false);
  add(_sourcePortal());
  add(_sourceAttributedGeometry);
  return scene;
}
