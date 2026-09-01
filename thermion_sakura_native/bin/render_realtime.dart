// Sakura Crossing — REALTIME render: world geometry lit by real Filament
// lights (sun + IBL) with native shadow maps, instead of baked cel/vertex
// colours. Vertex colours carry only raw LINEAR albedo; a lit Lambert material
// (roughness 1, metallic 0 — the reference MeshToonMaterial is pure diffuse)
// shades it per pixel. The painted sky stays a separate unlit geometry.
//
// Outputs the linear float colour RT (rt1.bin); tool/finale.py does the
// luma second-difference ink + GRADE + FXAA. Tunable via env vars:
//   SUN_I FILL_I BOUNCE_I IBL_I  light intensities
//   NO_SHADOW=1  disable the sun shadow map
//   SHADOW=0     disable view shadows (light still casts)
//
//   xvfb-run -a -s "-screen 0 1600x900x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/render_realtime.dart /tmp/sakura_out
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_sakura/src/materials_gen.dart';
import 'package:thermion_sakura/src/mesh.dart';
import 'package:thermion_sakura/src/palette.dart';
import 'package:thermion_sakura/src/scene.dart';
import 'package:thermion_sakura/src/world/sky.dart';
import 'package:thermion_sakura/src/world/world.dart';
import 'package:vector_math/vector_math_64.dart';

Vector3 _norm(Vector3 v) => v..normalize();
Vector3 _fwd(double y, double p) {
  final c = math.cos(p);
  return Vector3(-math.sin(y) * c, math.sin(p), -math.cos(y) * c);
}

double _env(String k, double d) => double.tryParse(Platform.environment[k] ?? '') ?? d;

Future<void> main(List<String> argv) async {
  const w = 1600, h = 900;
  final outDir = argv.isNotEmpty ? argv.first : '/tmp/sakura_out';
  const assets = '/workspace/examples/assets/';

  // Reference two-light directions (surface -> light); the DirectLight direction
  // is the direction light TRAVELS = -dir.
  final sunDir = _norm(Vector3(-52, 62, 56));
  final fillDir = _norm(Vector3(48, 26, -44));
  final bounceDir = _norm(Vector3(10, -18, 40));

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  // ---- world geometry: raw albedo + flat normals (no baked cel/shadow) ----
  print('Building world mesh (realtime albedo)...');
  final cel = makeCelShader();
  final worldMesh = buildWorldMesh(cel, includeSky: false);
  final worldGeo = worldMesh.buildRealtime();
  // painted sky as a separate unlit mesh (sun/IBL must not modulate it)
  final skyMesh = Mesh(makeCelShader());
  buildSky(skyMesh, Vector3(1.85, 1.62, 13.6));
  final skyGeo = skyMesh.build();
  // the vcolour material sRGB-encodes vertex colours on upload; the sky is
  // painted in linear, so pre-decode (same as render_ref.dart).
  final skyCols = skyGeo.colors;
  for (int i = 0; i < skyCols.length; i += 4) {
    final d = C.fromSrgb(Vector3(skyCols[i], skyCols[i + 1], skyCols[i + 2]));
    skyCols[i] = d.x;
    skyCols[i + 1] = d.y;
    skyCols[i + 2] = d.z;
  }

  // ---- viewer: lit scene -> RT1 (float, linear) ----
  final v1 = ThermionViewerFFI(app: app);
  await v1.initialized;
  await app.renderManager.attach(v1.view, sc);
  final rt1Color = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE, TextureUsage.TEXTURE_USAGE_BLIT_SRC},
      textureFormat: TextureFormat.RGBA32F);
  final rt1 = await app.createRenderTarget(w, h, color: rt1Color);
  await v1.view.setRenderTarget(rt1);
  await v1.view.setViewport(w, h);
  final fog = C.lin(Pal.fog);
  await app.setClearOptions(fog.x, fog.y, fog.z, 1.0);
  await v1.setToneMapper(await ToneMapper.linear(app));
  await v1.setBloom(false, 0);
  await v1.view.setShadowsEnabled(Platform.environment['SHADOW'] != '0');

  // IBL for the hemisphere ambient (sky from above, ground bounce below).
  // Intensities are Filament lux-scale; defaults preserve the cel light ratios
  // (sun:fill:bounce:hemi = 2.25:1.08:0.34:1.12) anchored to a sun of ~110000.
  if (Platform.environment['NO_IBL'] != '1') {
    await v1.loadIbl('${assets}default_env_ibl.ktx', intensity: _env('IBL_I', 30000));
  }

  // sun — warm key light, casts the realtime shadow map
  final sunColor = C.lin(Pal.sun);
  final sun = await v1.addDirectLight(DirectLight.sun(
    color: LinearColor(sunColor.x, sunColor.y, sunColor.z),
    direction: -sunDir,
    intensity: _env('SUN_I', 110000),
    castShadows: Platform.environment['NO_SHADOW'] != '1',
  ));
  if (Platform.environment['NO_SHADOW'] != '1') {
    await app.lightManager.setShadowOptions(
        sun,
        ShadowOptions(
          mapSize: 2048,
          shadowCascades: 1,
          cascadeSplitPositions: const [1.0],
          constantBias: _env('SHADOW_BIAS', 0.005),
          normalBias: _env('SHADOW_NBIAS', 0.5),
          shadowFar: _env('SHADOW_FAR', 80.0),
          shadowNearHint: 0.0,
          shadowFarHint: _env('SHADOW_FAR', 80.0),
          stable: true,
          lispsm: false,
          polygonOffsetConstant: 0.0,
          polygonOffsetSlope: 0.0,
          screenSpaceContactShadows: false,
        ));
  }
  // cool fill light from the opposite side (no shadow)
  final fillColor = C.lin(Pal.fill);
  await v1.addDirectLight(DirectLight(
    type: LightType.DIRECTIONAL,
    color: LinearColor(fillColor.x, fillColor.y, fillColor.z),
    direction: -fillDir,
    position: Vector3.zero(),
    intensity: _env('FILL_I', 53000),
    castShadows: false,
  ));
  // soft violet bounce (no shadow)
  final bounceColor = C.lin(0xd8cbe8);
  await v1.addDirectLight(DirectLight(
    type: LightType.DIRECTIONAL,
    color: LinearColor(bounceColor.x, bounceColor.y, bounceColor.z),
    direction: -bounceDir,
    position: Vector3.zero(),
    intensity: _env('BOUNCE_I', 16600),
    castShadows: false,
  ));
  await app.flush();

  // lit Lambert material; geometry cast + receive shadows
  final litMat = await app.createMaterial(sakuraLitFilamat);
  final litInst = await litMat.createInstance() as FFIMaterialInstance;
  final worldAsset = await v1.createGeometry(worldGeo, materialInstances: [litInst]);
  await worldAsset.setCastShadows(true);
  await worldAsset.setReceiveShadows(true);

  // painted sky (unlit vertex colour; no lighting, no shadow)
  final skyMat = await app.createMaterial(sakuraVcolorFilamat);
  final skyInst = await skyMat.createInstance();
  await v1.createGeometry(skyGeo, materialInstances: [skyInst]);
  await app.flush();

  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  final eye = Vector3(spawnPos.x, eyeHeight, spawnPos.z);
  await cam1.lookAt(eye, focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));

  print('Rendering realtime lit scene -> RT1...');
  for (int i = 0; i < 2; i++) {
    await app.capture(sc, view: v1.view,
        pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  }
  final sceneRes = await app.capture(sc, view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.rt1.bin').writeAsBytes(sceneRes.first.$2);
  print('  wrote $outDir.rt1.bin');

  // ---- viewer D: depth-encoding pass -> RTd (for finale's depth-ink) ----
  final vD = ThermionViewerFFI(app: app);
  await vD.initialized;
  await app.renderManager.attach(vD.view, sc);
  final rtdColor = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE, TextureUsage.TEXTURE_USAGE_BLIT_SRC},
      textureFormat: TextureFormat.RGBA32F);
  final rtdDepth = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
      textureFormat: TextureFormat.DEPTH32F);
  final rtd = await app.createRenderTarget(w, h, color: rtdColor, depth: rtdDepth);
  await vD.view.setRenderTarget(rtd);
  await vD.view.setViewport(w, h);
  await app.setClearOptions(0, 0, 0, 1);
  await vD.setToneMapper(await ToneMapper.linear(app));
  await vD.setBloom(false, 0);
  await vD.view.setPostProcessing(false);
  await vD.view.setFrustumCullingEnabled(false);
  final camD = await vD.getActiveCamera();
  await camD.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await camD.lookAt(eye, focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));
  final depthMat = await app.createMaterial(sakuraDepthEncFilamat);
  final depthInst = await depthMat.createInstance() as FFIMaterialInstance;
  final positions = Float32List.fromList(worldMesh.positions);
  final nVert = positions.length ~/ 3;
  final idx = Uint32List(nVert);
  for (int i = 0; i < nVert; i++) idx[i] = i;
  await vD.createGeometry(Geometry(positions, idx), materialInstances: [depthInst]);
  for (int i = 0; i < 2; i++) {
    await app.capture(sc, view: vD.view,
        pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  }
  final depthRes = await app.capture(sc, view: vD.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.depth.bin').writeAsBytes(depthRes.first.$2);
  print('  wrote $outDir.depth.bin');

  stdout.writeln('SIZE $w $h');
  exit(0);
}
