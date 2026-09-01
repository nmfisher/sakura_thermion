/// World assembly — a port of the reference `src/world/index.js` focused on
/// the opening frame: sky, street, railway crossing, houses, shop, sakura
/// trees, petals, poles/wires and the crossing-corner cluster. Everything is
/// authored on the flat plane in world coordinates and bakes into one [Mesh].
library;

import 'package:vector_math/vector_math_64.dart';

import '../cel.dart';
import '../mesh.dart';
import 'buildings.dart';
import 'petals.dart';
import 'props.dart';
import 'railway.dart';
import 'sky.dart';
import 'street.dart';
import 'trees.dart';

/// Build the whole crossing world into a single cel-baked [Mesh].
///
/// When [includeSky] is false the painted sky dome is omitted — used by the
/// realtime lit path, which renders the sky as a separate unlit geometry so
/// the sun/IBL do not modulate its pre-mixed palette.
Mesh buildWorldMesh(CelShader cel, {bool includeSky = true}) {
  final m = Mesh(cel);

  // Cast-shadow scene first: buildings, shop, train (boxes) and tree/shrub
  // canopies (spheres), so every cel face ray-tests a *complete* scene and
  // gets real sun-cast shadows (buildings on the road, dappled tree shade).
  _populateShadowScene(m, groundY);

  if (includeSky) {
    // The sky dome is centred on the opening camera so the horizon sits at eye
    // level, like the reference trailing the dome with the camera.
    buildSky(m, Vector3(1.85, 1.62, 13.6));
  }
  // sakura first: their baked cast shadows feed the street below
  final discs = buildSakura(m, groundY);
  m.shadows = ShadowMap(discs);
  buildStreet(m);
  buildRailway(m);
  buildTrain(m);
  buildHouses(m, groundY);
  buildShop(m, groundY);
  buildShrubs(m, groundY);
  buildPetals(m, groundY);
  final poles = buildPoles(m);
  buildWires(m, poles);
  buildCornerCluster(m);

  return m;
}

/// Populate [m.shadowScene] with the world's shadow casters, matching the
/// geometry the builders emit closely enough for plausible cast shadows.
void _populateShadowScene(Mesh m, double Function(double z) groundY) {
  final scene = ShadowScene(maxDist: 100.0);
  // buildings
  for (final d in houseDefs) {
    final y = groundY(d.z);
    final h = 2.72 * d.floors;
    scene.boxes
        .add(ShadowBox(d.x, y + h / 2, d.z, d.w / 2 + 0.3, h / 2, d.d / 2 + 0.3));
  }
  // shop (frontage volume, matches buildShop)
  final zMid = (4.55 + 12.6) / 2;
  final xFront = centerX(zMid) + roadHalf + walkW + 0.12;
  scene.boxes.add(ShadowBox(xFront + 3.6, groundY(zMid) + 3.0, zMid, 3.8, 3.2,
      (12.6 - 4.55) / 2 + 0.3));
  // train carriages (x=-16, x=0, z=0)
  for (final cx in [-16.0, 0.0]) {
    scene.boxes.add(ShadowBox(cx, 1.9, 0, 8.0, 1.6, 1.5));
  }
  // tree canopies — a cluster of spheres per tree (the canopy is a wide mass,
  // not a single blob), so cast shade covers the road/walk realistically.
  for (final s in sakuraSpots) {
    final y = s.y ?? groundY(s.z);
    final trunkH = 2.5 * s.scale;
    final cy = y + trunkH + 1.6;
    final r = 2.6 * s.scale;
    scene.spheres.add(ShadowSphere(s.x, cy, s.z, r));
    scene.spheres.add(ShadowSphere(s.x - 1.6 * s.scale, cy + 0.4, s.z, r * 0.9));
    scene.spheres.add(ShadowSphere(s.x + 1.6 * s.scale, cy + 0.6, s.z, r * 0.9));
    scene.spheres.add(ShadowSphere(s.x, cy + 0.8, s.z - 1.6 * s.scale, r * 0.9));
  }
  // shrubs
  for (final s in shrubSpots) {
    scene.spheres
        .add(ShadowSphere(s.x, groundY(s.z) + s.r * 0.6, s.z, s.r * 1.4));
  }
  m.shadowScene = scene;
}
