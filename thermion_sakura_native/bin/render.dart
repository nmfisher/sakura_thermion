// Sakura Crossing — native render: linear cel scene + a depth pass, both to
// float colour render targets.
//
//   viewer1: cel-baked scene (linear) -> RT1 (RGBA32F)   -> rt1.bin
//   viewerD: same geometry, depth-encoding material      -> RTd (RGBA32F) -> depth.bin
//
// tool/finale.py does the depth second-difference ink + GRADE_SHADER + FXAA on
// the two bins to produce the final image. (The scene's depth texture cannot
// be sampled from a Thermion custom material — it reads back zero — so the
// depth is written to a colour target instead.)
//
//   xvfb-run -a -s "-screen 0 1600x900x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 dart run bin/render.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_sakura/src/glb.dart';
import 'package:thermion_sakura/src/materials_gen.dart';
import 'package:thermion_sakura/src/palette.dart';
import 'package:thermion_sakura/src/scene.dart';
import 'package:thermion_sakura/src/world/world.dart';
import 'package:vector_math/vector_math_64.dart';

Vector3 _fwd(double y, double p) {
  final c = math.cos(p);
  return Vector3(-math.sin(y) * c, math.sin(p), -math.cos(y) * c);
}

Future<void> main(List<String> argv) async {
  const w = 1600, h = 900;
  final outDir = argv.isNotEmpty ? argv.first : '/tmp/sakura_out';

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  // Build the world mesh once (shared by the cel and depth passes).
  print('Building world mesh...');
  final mesh = buildWorldMesh(makeCelShader());

  // ---------- viewer 1: cel scene -> RT1 ----------
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
  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  final eye = Vector3(spawnPos.x, eyeHeight, spawnPos.z);
  await cam1.lookAt(eye, focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));
  await v1.loadGltfFromBuffer(meshToGlb(mesh));
  print('Rendering scene -> RT1...');
  final sceneRes = await app.capture(sc, view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.rt1.bin').writeAsBytes(sceneRes.first.$2);
  print('  wrote $outDir.rt1.bin');

  // ---------- viewer D: depth-encoding pass -> RTd ----------
  final vD = ThermionViewerFFI(app: app);
  await vD.initialized;
  await app.renderManager.attach(vD.view, sc);
  final rtdColor = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE, TextureUsage.TEXTURE_USAGE_BLIT_SRC},
      textureFormat: TextureFormat.RGBA32F);
  final rtd = await app.createRenderTarget(w, h, color: rtdColor);
  await vD.view.setRenderTarget(rtd);
  await vD.view.setViewport(w, h);
  // clear depth-RT colour to far (reverse-Z 0 = far)
  await app.setClearOptions(0.0, 0.0, 0.0, 1.0);
  await vD.setToneMapper(await ToneMapper.linear(app));
  await vD.setBloom(false, 0);
  await vD.view.setPostProcessing(false);
  final camD = await vD.getActiveCamera();
  await camD.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await camD.lookAt(eye, focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));
  final depthMat = await app.createMaterial(sakuraDepthEncFilamat);
  final depthInst = await depthMat.createInstance() as FFIMaterialInstance;
  // positions-only geometry, depth-encoding material
  final depthGeo = Geometry(Float32List.fromList(mesh.positions), mesh.indices);
  await vD.createGeometry(depthGeo, materialInstances: [depthInst]);
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
