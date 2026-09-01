/// Sakura Crossing — world builder.  Renders into a [ThermionViewer].
///
/// This is the port of the reference `src/world/*` modules. Geometry is built
/// flat-shaded and cel-baked into per-vertex colours (see `Mesh` / `CelShader`),
/// then rendered with a single unlit vertex-colour material. Lighting, fog and
/// camera match the reference's opening frame.
library;

import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:vector_math/vector_math_64.dart';

import 'cel.dart';
import 'glb.dart';
import 'materials_gen.dart';
import 'mesh.dart';
import 'palette.dart';
import 'world/world.dart';

Vector3 _norm(Vector3 v) => v..normalize();

/// The two-light anime setup, pinned to the flat authoring frame (the reference
/// seats lights to the local surface frame so the district is lit the same way
/// everywhere; for the opening frame that is the flat origin).
CelShader makeCelShader() {
  return CelShader(
    sunDir: _norm(Vector3(-52, 62, 56)),
    fillDir: _norm(Vector3(48, 26, -44)),
    bounceDir: _norm(Vector3(10, -18, 40)),
  );
}

class World {
  World(this.viewer, this.app, this.cel);
  final ThermionViewer viewer;
  final FFIFilamentApp app;
  final CelShader cel;
  final List<ThermionAsset> assets = [];
}

/// Spawn (matches the reference Player default).
final Vector3 spawnPos = Vector3(1.85, 0, 13.6);
const double spawnYaw = 0.20;
const double spawnPitch = -0.008;
const double eyeHeight = 1.62;
const double fovDeg = 46.0;

/// Build the world into [viewer]. Returns a controller.
///
/// Everything bakes into one [Mesh] (flat-shaded, cel-baked per-face colours)
/// which is packed into a single GLB and loaded through gltfio — the only
/// geometry path that renders on the Thermion web build.
Future<World> buildWorld(ThermionViewer viewer, FFIFilamentApp app) async {
  final cel = makeCelShader();
  final world = World(viewer, app, cel);

  final m = buildWorldMesh(cel);
  final mainAsset = await viewer.loadGltfFromBuffer(meshToGlb(m));
  world.assets.add(mainAsset);
  return world;
}
