import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_texture.dart';

import 'geom/planet.dart';
import 'geom/three_geom.dart' show Tri;
import 'geom/tri_packed.dart';
import 'materials_gen.dart';
import 'mesh.dart';
import 'palette.dart';
import 'post_settings.dart';
import 'sakura_post_process.dart';
import 'scene.dart';
import 'world/sky.dart';
import 'world_ref/ported_scene.dart';

class SakuraFilamentScene {
  final SakuraPostProcess postProcess;

  const SakuraFilamentScene({required this.postProcess});

  View get outputView => postProcess.view;

  Future<void> prepareForPlatformResize() =>
      postProcess.prepareForPlatformOutputReplacement();
}

/// Build the PORTED scene (assembled from ported Dart modules — no extracted
/// .bin) in [viewer]: street + houses + trees + poles, cel-shaded with a flat
/// (non-planet) framing camera. The reproducible-code counterpart to
/// [buildSakuraScene]; grows as more modules are ported.
Future<SakuraFilamentScene> buildPortedFilamentScene(
    ThermionViewer viewer) async {
  final log = Logger('PortedScene');
  final app = viewer.app as FFIFilamentApp;

  final cel = makeCelShader();
  final sunColorI = cel.sunColor * cel.sunI;
  final fillColorI = cel.fillColor * cel.fillI;
  final bounceColorI = cel.bounceColor * cel.bounceI;
  final hemiSkyI = cel.hemiSky * cel.hemiI;
  final hemiGroundI = cel.hemiGround * cel.hemiI;
  final tint = C.lin(0x6c5f8c);

  log.info('assembling ported scene...');
  final casterFlat = <Tri>[];
  final casterGroups = <String, List<Tri>>{};
  final flatTris = buildPortedScene(
      shadowCasters: casterFlat, shadowCasterGroups: casterGroups);
  final tris = wrapOnPlanet(flatTris);
  final packed = trisToPacked(tris);
  log.info('  ${tris.length} tris, ${packed.positions.length ~/ 3} verts');

  final surfaceUp = Vector3.zero();
  final surfaceEast = Vector3.zero();
  final surfaceNorth = Vector3.zero();
  planetBasis(1.85, 13.6, surfaceUp, surfaceEast, surfaceNorth);
  Vector3 worldLight(Vector3 local) =>
      (surfaceEast * local.x + surfaceUp * local.y + surfaceNorth * local.z)
        ..normalize();
  final sunDir = worldLight(cel.sunDir);
  final fillDir = worldLight(cel.fillDir);
  final bounceDir = worldLight(cel.bounceDir);

  final fog = C.lin(Pal.fog);
  // The scene color target's alpha carries reverse view depth for the exact
  // screen-space ink pass. Clear alpha 0 denotes the sky/infinite depth.
  await app.setClearOptions(fog.x, fog.y, fog.z, 0.0);
  await viewer.setBloom(false, 0);
  await viewer.setPostProcessing(false);
  await viewer.view.setBlendMode(BlendMode.opaque);
  final linTM = await ToneMapper.linear(app);
  final linCGB = FFIColorGradingBuilder(
    await withPointerCallback<TColorGradingBuilder>(
        (cb) => ColorGradingBuilder_createRenderThread(cb)),
    app,
  )..toneMapper(linTM);
  await viewer.view.setColorGrading(await linCGB.build());

  final toonMat = await app.createMaterial(sakuraToonRTFilamat);
  final toonInst = await toonMat.createInstance() as FFIMaterialInstance;
  await toonInst.setParameterFloat3('sunDir', sunDir.x, sunDir.y, sunDir.z);
  await toonInst.setParameterFloat3(
      'sunColorI', sunColorI.x, sunColorI.y, sunColorI.z);
  await toonInst.setParameterFloat3('fillDir', fillDir.x, fillDir.y, fillDir.z);
  await toonInst.setParameterFloat3(
      'fillColorI', fillColorI.x, fillColorI.y, fillColorI.z);
  await toonInst.setParameterFloat3(
      'bounceDir', bounceDir.x, bounceDir.y, bounceDir.z);
  await toonInst.setParameterFloat3(
      'bounceColorI', bounceColorI.x, bounceColorI.y, bounceColorI.z);
  await toonInst.setParameterFloat3(
      'hemiSkyI', hemiSkyI.x, hemiSkyI.y, hemiSkyI.z);
  await toonInst.setParameterFloat3(
      'hemiGroundI', hemiGroundI.x, hemiGroundI.y, hemiGroundI.z);
  await toonInst.setParameterFloat3('tint', tint.x, tint.y, tint.z);
  await toonInst.setParameterFloat('globalGain', cel.globalGain);
  // A static spawn-centred cascade is enough for the opening composition and
  // preserves per-pixel tree silhouettes on the train and road. It replaces
  // the old face-centroid CPU flag, which could only darken whole triangles.
  // Offset by a fraction of a shadow texel so the nearest-sampled PCF grid
  // aligns with the reference's filtered shadow raster at the spawn view.
  final shadowCenter = planetPosition(2.05, 0, 13.8);
  final shadowEye =
      shadowCenter + sunDir * math.sqrt(52 * 52 + 62 * 62 + 56 * 56);
  const shadowSize = 2048;
  final shadowView = ThermionViewerFFI(app: app);
  await shadowView.initialized;
  await shadowView.view.setViewport(shadowSize, shadowSize);
  await shadowView.view.setPostProcessing(false);
  await shadowView.view.setFrustumCullingEnabled(false);
  final shadowColor = await app.createTexture(shadowSize, shadowSize,
      flags: {
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_BLIT_SRC,
      },
      textureFormat: TextureFormat.RGBA32F);
  final shadowDepth = await app.createTexture(shadowSize, shadowSize,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
      textureFormat: TextureFormat.DEPTH32F);
  final shadowTarget = await app.createRenderTarget(shadowSize, shadowSize,
      color: shadowColor, depth: shadowDepth);
  await shadowView.view.setRenderTarget(shadowTarget);
  final shadowCamera = await shadowView.getActiveCamera();
  await shadowCamera.setProjection(
      Projection.Orthographic, -35.75, 35.75, -35.75, 35.75, 1, 200);
  await shadowCamera.lookAt(shadowEye,
      focus: shadowCenter, up: Vector3(0, 1, 0));
  final shadowMat = await app.createMaterial(sakuraDepthEncFilamat);
  // Only the two opening-shot casters whose light-space footprints overlap
  // visible receivers. The previous house_7-only map darkened most of the
  // train and left foreground, while omitting the real cherry silhouettes.
  final raisedTrees = [
    ...(casterGroups['sakura_4'] ?? const <Tri>[]),
    ...(casterGroups['sakura_12'] ?? const <Tri>[]),
    ...(casterGroups['poles'] ?? const <Tri>[]),
  ]
      .where(
          (t) => !t.mat.unlit && math.max(t.a.y, math.max(t.b.y, t.c.y)) > .55)
      .toList();
  final casterPacked = trisToPacked(wrapOnPlanet(raisedTrees));
  await shadowView.createGeometry(
      Geometry(casterPacked.positions, casterPacked.indices),
      materialInstances: [await shadowMat.createInstance()]);
  final sunVP = await shadowCamera.getProjectionMatrix() *
      await shadowCamera.getViewMatrix();
  // Matrix4's column-major storage needs transposing at Thermion's native
  // material-parameter boundary (the native renderer uses the same contract).
  await toonInst.setParameterMat4('sunLightVP', sunVP.transposed());
  await toonInst.setParameterFloat('shadowBias', .0008);
  await toonInst.setParameterFloat('shadowStrength', 1.30);
  await toonInst.setParameterFloat('shadowEnabled', 1.0);
  await toonInst.setParameterFloat('shadowDebug', 0.0);
  final shadowSampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST,
      magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE,
      wrapT: TextureWrapMode.CLAMP_TO_EDGE);
  await toonInst.setParameterTexture('shadowMap', shadowColor as FFITexture,
      shadowSampler as FFITextureSampler);

  final shadowSwapChains = app.renderManager
      .getAttachedSwapChains(viewer.view)
      .toList(growable: false);
  for (final swapChain in shadowSwapChains) {
    await app.renderManager.attach(shadowView.view, swapChain);
  }
  await app.setClearOptions(0, 0, 0, 0);
  if (shadowSwapChains.isNotEmpty) {
    await app.capture(shadowSwapChains.first, view: shadowView.view);
    await app.capture(shadowSwapChains.first, view: shadowView.view);
  }
  await toonInst.setParameterTexture('shadowMap', shadowColor, shadowSampler);
  await app.flush();
  for (final swapChain in shadowSwapChains) {
    await app.renderManager.detach(shadowView.view, swapChain: swapChain);
  }
  await app.setClearOptions(fog.x, fog.y, fog.z, 0.0);
  viewer.onDispose(() async {
    await shadowView.dispose();
    await shadowTarget.destroy();
    await shadowColor.destroy();
    await shadowDepth.destroy();
    await shadowSampler.dispose();
    await shadowMat.destroy();
  });
  await toonInst.setParameterFloat('cameraNear', 0.25);
  await toonInst.setParameterFloat('encodeDepth', 1.0);
  await toonInst.setParameterFloat3('fogColor', fog.x, fog.y, fog.z);
  await toonInst.setParameterFloat('fogNear', 44.0);
  await toonInst.setParameterFloat('fogFar', 205.0);

  await viewer.createGeometry(
    Geometry(packed.positions, packed.indices,
        normals: packed.normals,
        colors: packed.colors,
        uvs: packed.uvs,
        uvs1: packed.uvs1,
        attribute0: packed.attribute0),
    materialInstances: [toonInst],
  );

  final eye = Vector3.zero(), fwd = Vector3.zero(), up = Vector3.zero();
  spawnCamera(eye, fwd, up);

  // Painted sky dome.
  final skyMesh = Mesh(makeCelShader());
  buildSky(skyMesh, eye, radius: 500, eye: eye);
  final skyGeo = skyMesh.build();
  final skyMat = await app.createMaterial(sakuraSkyFilamat);
  await viewer.createGeometry(skyGeo,
      materialInstances: [await skyMat.createInstance()]);

  // Planet-frame spawn camera (the ported scene is wrapped onto the sphere).
  final cam = await viewer.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(
      near: 0.25, far: 600, aspect: 16 / 9, focalLength: focal);
  await cam.lookAt(eye, focus: eye + fwd, up: up);
  await viewer.view.setFogOptions(FogOptions(
    enabled: true,
    distance: 44,
    density: 0.01,
    heightFalloff: 0,
    maximumOpacity: 1.0,
    linearColor: fog,
  ));

  // Reference post pipeline: depth second-difference ink followed by the
  // split-tone grade. SakuraPostProcess redirects the main view into a float
  // scene target and sends this fullscreen pass to the Flutter output target.
  var flutterOutputTarget = await viewer.view.getRenderTarget();
  for (var attempt = 0;
      flutterOutputTarget == null && attempt < 300;
      attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    flutterOutputTarget = await viewer.view.getRenderTarget();
  }
  if (flutterOutputTarget == null) {
    throw StateError('Flutter did not bind a render target to the Sakura view');
  }

  final viewport = await viewer.view.getViewport();
  SakuraPostProcess? resultPost;
  if (viewport.width > 0 && viewport.height > 0) {
    final postMat = await app.createMaterial(sakuraPostFilamat);
    final postInst = await postMat.createInstance() as FFIMaterialInstance;
    final shadowTint = C.lin(0xada8d0);
    final lightTint = C.lin(0xfff7e8);
    final ink = C.lin(Pal.ink);
    await postInst.setParameterFloat3(
        'shadowTint', shadowTint.x, shadowTint.y, shadowTint.z);
    await postInst.setParameterFloat3(
        'lightTint', lightTint.x, lightTint.y, lightTint.z);
    await postInst.setParameterFloat('postResidualStrength', 0.0);
    await postInst.setParameterFloat('uSat', SakuraPostSettings.saturation);
    await postInst.setParameterFloat('uLift', SakuraPostSettings.lift);
    await postInst.setParameterFloat('uWarmth', SakuraPostSettings.warmth);
    await postInst.setParameterFloat('uVignette', SakuraPostSettings.vignette);
    await postInst.setParameterFloat3('inkColor', ink.x, ink.y, ink.z);
    await postInst.setParameterFloat(
        'inkThickness', SakuraPostSettings.inkThickness);
    await postInst.setParameterFloat(
        'inkSensitivity', SakuraPostSettings.inkSensitivity);
    await postInst.setParameterFloat(
        'inkConcave', SakuraPostSettings.inkConcave);
    await postInst.setParameterFloat(
        'inkConcaveAmount', SakuraPostSettings.inkConcaveAmount);
    await postInst.setParameterFloat(
        'inkFadeStart', SakuraPostSettings.inkFadeStart);
    await postInst.setParameterFloat(
        'inkFadeEnd', SakuraPostSettings.inkFadeEnd);
    await postInst.setParameterFloat(
        'inkStrength', SakuraPostSettings.inkStrength);
    await postInst.setParameterFloat(
        'inkSkyDepth', SakuraPostSettings.inkSkyDepth);
    await postInst.setParameterFloat(
        'cameraNear', SakuraPostSettings.cameraNear);
    await postInst.setParameterFloat('debugMode', 0.0);

    final post = await SakuraPostProcess.create(
      app,
      mainView: viewer.view,
      materialInstance: postInst,
      width: viewport.width,
      height: viewport.height,
    );
    resultPost = post;
    post.followPlatformOutputTarget();
    final swapChains = app.renderManager
        .getAttachedSwapChains(viewer.view)
        .toList(growable: false);
    for (final swapChain in swapChains) {
      await app.renderManager.attach(post.view, swapChain, renderOrder: 1);
    }
    viewer.onDispose(() async {
      for (final swapChain in swapChains) {
        await app.renderManager.detach(post.view, swapChain: swapChain);
      }
      await post.destroy();
      await postInst.destroy();
      await postMat.destroy();
    });
  }
  if (resultPost == null) {
    throw StateError('Sakura post-process requires a non-zero viewport');
  }
  log.info('ported scene ready');
  return SakuraFilamentScene(postProcess: resultPost);
}
