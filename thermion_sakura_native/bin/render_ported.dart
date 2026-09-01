// Render a scene assembled from PORTED world modules (Tri soup → packed →
// realtime toon material), headless, → PNG. The parity harness as modules get
// ported: assemble the scene, render, compare to /tmp/refworld.png.
//
//   xvfb-run -a -s "-screen 0 1600x900x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/render_ported.dart [outPrefix]
import 'dart:io';
import 'dart:math' as math;

import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_sakura/src/geom/tri_packed.dart';
import 'package:thermion_sakura/src/geom/planet.dart';
import 'package:thermion_sakura/src/materials_gen.dart';
import 'package:thermion_sakura/src/palette.dart';
import 'package:thermion_sakura/src/ref_geo.dart';
import 'package:thermion_sakura/src/scene.dart';
import 'package:thermion_sakura/src/world_ref/ported_scene.dart';

Future<void> main(List<String> argv) async {
  const w = 1600, h = 900;
  final outDir = argv.isNotEmpty ? argv.first : '/tmp/sakura_ported';

  final cel = makeCelShader();
  final sunColorI = cel.sunColor * cel.sunI;
  final fillColorI = cel.fillColor * cel.fillI;
  final bounceColorI = cel.bounceColor * cel.bounceI;
  final hemiSkyI = cel.hemiSky * cel.hemiI;
  final hemiGroundI = cel.hemiGround * cel.hemiI;
  final tint = C.lin(0x6c5f8c);

  print('Assembling ported scene...');
  final tris = wrapOnPlanet(buildPortedScene());
  // CPU sun shadow map from lit faces (unlit mats don't cast).
  final lit = <double>[];
  for (final t in tris) {
    if (t.mat.unlit) continue;
    final c = t.centroid;
    lit.addAll([c.x, c.y, c.z]);
  }
  final shadow = SunShadowMap(Float32List.fromList(lit), cel.sunDir);
  final packed = trisToPacked(tris, shadow: shadow);
  print('  ${tris.length} tris, ${packed.positions.length ~/ 3} verts');

  await FFIFilamentApp.create(
      config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  final v1 = ThermionViewerFFI(app: app);
  await v1.initialized;
  await app.renderManager.attach(v1.view, sc);
  final rt1Color = await app.createTexture(w, h,
      flags: {
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_BLIT_SRC
      },
      textureFormat: TextureFormat.RGBA32F);
  final rt1 = await app.createRenderTarget(w, h, color: rt1Color);
  await v1.view.setRenderTarget(rt1);
  await v1.view.setViewport(w, h);
  final fog = C.lin(Pal.fog);
  await app.setClearOptions(fog.x, fog.y, fog.z, 1.0);
  await v1.setBloom(false, 0);
  await v1.view.setPostProcessing(true);
  // LIVE grade: ACES tone mapping + slopeOffsetPower (≈ the finale's shadowTint/
  // lightTint multiplicative tint: ×0.72/0.69/0.80 per channel + lift 0.032) +
  // saturation 1.12. This produces the graded look IN the RT (no offline finale
  // needed), so the live viewer matches the reference's GRADE_SHADER.
  final gradeB = FFIColorGradingBuilder(
      await withPointerCallback<TColorGradingBuilder>(
          (cb) => ColorGradingBuilder_createRenderThread(cb)),
      app)
    ..toneMapper(await ToneMapper.aces(app))
    ..slopeOffsetPower(Vector3(0.88, 0.85, 0.92), Vector3(0.032, 0.032, 0.032),
        Vector3(1.0, 1.0, 1.0))
    ..saturation(1.12);
  await v1.view.setColorGrading(await gradeB.build());

  final toonMat = await app.createMaterial(sakuraToonRTFilamat);
  final toonInst = await toonMat.createInstance() as FFIMaterialInstance;
  await toonInst.setParameterFloat3(
      'sunDir', cel.sunDir.x, cel.sunDir.y, cel.sunDir.z);
  await toonInst.setParameterFloat3(
      'sunColorI', sunColorI.x, sunColorI.y, sunColorI.z);
  await toonInst.setParameterFloat3(
      'fillDir', cel.fillDir.x, cel.fillDir.y, cel.fillDir.z);
  await toonInst.setParameterFloat3(
      'fillColorI', fillColorI.x, fillColorI.y, fillColorI.z);
  await toonInst.setParameterFloat3(
      'bounceDir', cel.bounceDir.x, cel.bounceDir.y, cel.bounceDir.z);
  await toonInst.setParameterFloat3(
      'bounceColorI', bounceColorI.x, bounceColorI.y, bounceColorI.z);
  await toonInst.setParameterFloat3(
      'hemiSkyI', hemiSkyI.x, hemiSkyI.y, hemiSkyI.z);
  await toonInst.setParameterFloat3(
      'hemiGroundI', hemiGroundI.x, hemiGroundI.y, hemiGroundI.z);
  await toonInst.setParameterFloat3('tint', tint.x, tint.y, tint.z);
  await toonInst.setParameterFloat('globalGain', cel.globalGain);
  await toonInst.setParameterFloat('shadowEnabled', 0.0);
  await toonInst.setParameterFloat('shadowDebug', 0.0);

  await v1.createGeometry(
      Geometry(packed.positions, packed.indices,
          normals: packed.normals,
          colors: packed.colors,
          uvs: packed.uvs,
          uvs1: packed.uvs1,
          attribute0: packed.attribute0),
      materialInstances: [toonInst]);

  final cam = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(
      near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  // Planet-frame spawn camera (same framing as the reference).
  final eye = Vector3.zero(), fwd = Vector3.zero(), up = Vector3.zero();
  spawnCamera(eye, fwd, up);
  await cam.lookAt(eye, focus: eye + fwd, up: up);

  // Filament exponential fog ≈ the reference's THREE.Fog(0xe6ecf7, 44, 205):
  // begins past 44 m; density tuned so it reaches strong opacity near 200 m.
  await v1.view.setFogOptions(FogOptions(
    enabled: true,
    distance: 44,
    density: 0.01,
    heightFalloff: 0,
    maximumOpacity: 1.0,
    linearColor: fog,
  ));

  for (int i = 0; i < 2; i++) {
    await app.capture(sc,
        view: v1.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
  }
  final res = await app.capture(sc,
      view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.rt1.bin').writeAsBytes(res.first.$2);
  print('  wrote $outDir.rt1.bin');

  // Depth pass (for finale's depth-ink) — same geometry, depth-encoding material.
  final vD = ThermionViewerFFI(app: app);
  await vD.initialized;
  await app.renderManager.attach(vD.view, sc);
  final rtdColor = await app.createTexture(w, h,
      flags: {
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_BLIT_SRC
      },
      textureFormat: TextureFormat.RGBA32F);
  final rtdDepth = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
      textureFormat: TextureFormat.DEPTH32F);
  final rtd =
      await app.createRenderTarget(w, h, color: rtdColor, depth: rtdDepth);
  await vD.view.setRenderTarget(rtd);
  await vD.view.setViewport(w, h);
  await app.setClearOptions(0, 0, 0, 1);
  await vD.setBloom(false, 0);
  await vD.view.setPostProcessing(false);
  await vD.view.setFrustumCullingEnabled(false);
  final camD = await vD.getActiveCamera();
  await camD.setLensProjection(
      near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await camD.lookAt(eye, focus: eye + fwd, up: up);
  final depthMat = await app.createMaterial(sakuraDepthEncFilamat);
  final depthInst = await depthMat.createInstance() as FFIMaterialInstance;
  await vD.createGeometry(Geometry(packed.positions, packed.indices),
      materialInstances: [depthInst]);
  for (int i = 0; i < 2; i++) {
    await app.capture(sc,
        view: vD.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
  }
  final depthRes = await app.capture(sc,
      view: vD.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.depth.bin').writeAsBytes(depthRes.first.$2);
  print('  wrote $outDir.depth.bin');

  stdout.writeln('SIZE $w $h');
  exit(0);
}
