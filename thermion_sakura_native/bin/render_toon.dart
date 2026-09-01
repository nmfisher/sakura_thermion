// Sakura Crossing — REALTIME TOON render. World geometry carries raw LINEAR
// albedo (COLOR0.rgb) + a face flag (COLOR0.a: 0 = lit cel face, 1 = unlit
// accent). A custom unlit material cel-shades it per pixel — an exact GPU port
// of cel.dart (sun + fill + bounce + hemisphere, 3-band ramp, violet shadow
// tint, 1/PI Lambert gain) — using flat normals from screen-space derivatives.
//
// NO baked vertex colours, NO baked shadows: the cel is computed every frame
// and cast shadows come from a realtime sun shadow map (Step 2). The painted
// sky stays a separate unlit geometry.
//
//   xvfb-run -a -s "-screen 0 1600x900x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/render_toon.dart /tmp/sakura_out
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_texture.dart';
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

Future<void> main(List<String> argv) async {
  const w = 1600, h = 900;
  final outDir = argv.isNotEmpty ? argv.first : '/tmp/sakura_out';

  // cel.dart's two-light + bounce + hemisphere setup, folded to colour*intensity.
  final cel = makeCelShader();
  final sunColorI = cel.sunColor * cel.sunI;
  final fillColorI = cel.fillColor * cel.fillI;
  final bounceColorI = cel.bounceColor * cel.bounceI;
  final hemiSkyI = cel.hemiSky * cel.hemiI;
  final hemiGroundI = cel.hemiGround * cel.hemiI;
  final tint = C.lin(0x6c5f8c);

  await FFIFilamentApp.create(
      config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  print('Building world mesh (realtime toon)...');
  final worldMesh = buildWorldMesh(cel, includeSky: false);
  final worldGeo = worldMesh.buildRealtime();
  final skyMesh = Mesh(cel);
  buildSky(skyMesh, Vector3(1.85, 1.62, 13.6));
  final skyGeo = skyMesh.build();
  // vcolour material sRGB-encodes vertex colours on upload; the sky is painted
  // in linear, so pre-decode (same as render_ref.dart).
  final skyCols = skyGeo.colors;
  for (int i = 0; i < skyCols.length; i += 4) {
    final d = C.fromSrgb(Vector3(skyCols[i], skyCols[i + 1], skyCols[i + 2]));
    skyCols[i] = d.x;
    skyCols[i + 1] = d.y;
    skyCols[i + 2] = d.z;
  }

  // ---- viewer 1: toon cel scene -> RT1 (float, linear) ----
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
  await v1.setToneMapper(await ToneMapper.linear(app));
  await v1.setBloom(false, 0);

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
  await toonInst.setParameterFloat('shadowEnabled', 1.0);
  await toonInst.setParameterFloat('shadowDebug', 0.0);
  await toonInst.setParameterFloat('shadowBias', 0.0008);

  // ---- realtime sun shadow map (manual shadow mapping) ----
  // Render the world's real geometry from an orthographic sun camera into a
  // sampleable depth texture; the toon material samples it to drop the sun
  // term where a nearer caster occludes the point.
  final sun = cel.sunDir; // surface -> sun (unit)
  // scene bounds (world geometry only — the sky dome is excluded)
  double mnX = 1e18,
      mnY = 1e18,
      mnZ = 1e18,
      mxX = -1e18,
      mxY = -1e18,
      mxZ = -1e18;
  final pos = worldMesh.positions;
  for (int i = 0; i < pos.length; i += 3) {
    mnX = math.min(mnX, pos[i]);
    mxX = math.max(mxX, pos[i]);
    mnY = math.min(mnY, pos[i + 1]);
    mxY = math.max(mxY, pos[i + 1]);
    mnZ = math.min(mnZ, pos[i + 2]);
    mxZ = math.max(mxZ, pos[i + 2]);
  }
  final center =
      Vector3((mnX + mxX) * 0.5, (mnY + mxY) * 0.5, (mnZ + mxZ) * 0.5);
  // sun-basis: fwd = direction the camera looks = -sun (light travel); build a
  // stable right/up from the world up.
  final fwd = -sun;
  final wup = Vector3(0, 1, 0);
  var right = fwd.cross(wup);
  if (right.length < 1e-6) right = Vector3(1, 0, 0);
  right.normalize();
  final up = right.cross(fwd)..normalize();
  final sunEye = center + sun * 120.0;
  // project the 8 bounds corners into the sun basis to size the ortho frustum
  double lr = 0, rr = 0, br = 0, tr = 0, nr = 1e18, fr2 = -1e18;
  for (final cx in [mnX, mxX]) {
    for (final cy in [mnY, mxY]) {
      for (final cz in [mnZ, mxZ]) {
        final d = Vector3(cx, cy, cz) - sunEye;
        final rv = d.dot(right), uv = d.dot(up), fv = d.dot(fwd);
        lr = math.min(lr, rv);
        rr = math.max(rr, rv);
        br = math.min(br, uv);
        tr = math.max(tr, uv);
        nr = math.min(nr, fv);
        fr2 = math.max(fr2, fv);
      }
    }
  }
  const margin = 6.0;
  final vS = ThermionViewerFFI(app: app);
  await vS.initialized;
  await app.renderManager.attach(vS.view, sc);
  final shSize = 2048;
  final shColor = await app.createTexture(shSize, shSize,
      flags: {
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_BLIT_SRC
      },
      textureFormat: TextureFormat.RGBA32F);
  final shDepth = await app.createTexture(shSize, shSize,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
      textureFormat: TextureFormat.DEPTH32F);
  final shRT = await app.createRenderTarget(shSize, shSize,
      color: shColor, depth: shDepth);
  await vS.view.setRenderTarget(shRT);
  await vS.view.setViewport(shSize, shSize);
  await vS.view.setPostProcessing(false);
  await vS.view.setFrustumCullingEnabled(false);
  await vS.view.setShadowsEnabled(false);
  final camS = await vS.getActiveCamera();
  await camS.setProjection(Projection.Orthographic, lr - margin, rr + margin,
      br - margin, tr + margin, math.max(0.1, nr - margin), fr2 + margin);
  await camS.lookAt(sunEye, focus: center, up: wup);
  final shMat = await app.createMaterial(sakuraDepthEncFilamat);
  final shInst = await shMat.createInstance() as FFIMaterialInstance;
  await vS.createGeometry(
      Geometry(Float32List.fromList(worldMesh.positions), worldMesh.indices),
      materialInstances: [shInst]);
  await app.flush();
  for (int i = 0; i < 2; i++) {
    await app.capture(sc,
        view: vS.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
  }
  // DEBUG: dump the sun shadow map so we can confirm it rendered (depth from sun).
  final shDump = await app.capture(sc,
      view: vS.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  if (Platform.environment['SHADOW_DEBUG'] == '1') {
    await File('$outDir.shadowmap.bin').writeAsBytes(shDump.first.$2);
    print('  (debug) wrote $outDir.shadowmap.bin');
  }
  // sunVP = projection * view, read back from the camera (convention-safe).
  final sunProj = await camS.getProjectionMatrix();
  final sunView = await camS.getViewMatrix();
  var sunVP = sunProj * sunView;
  if (Platform.environment['SHADOW_DEBUG'] == '1') {
    // sanity: scene centre should map to NDC roughly in [-1,1]
    Vector3 toNdc(Vector3 p) {
      final r = sunVP * Vector4(p.x, p.y, p.z, 1.0);
      return Vector3(r.x / r.w, r.y / r.w, r.z / r.w);
    }

    final c = toNdc(center);
    print('DEBUG sunVP center NDC=$c');
  }
  // See render_post.dart: transpose the world-to-light matrix at the FFI
  // material boundary.
  await toonInst.setParameterMat4('sunLightVP', sunVP.transposed());
  // NEAREST filtering: anime shadows are crisp/hard-edged (a cel band), not soft.
  final shSampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST, magFilter: TextureMagFilter.NEAREST);
  await toonInst.setParameterTexture(
      'shadowMap', shColor as FFITexture, shSampler as FFITextureSampler);

  await v1.createGeometry(worldGeo, materialInstances: [toonInst]);

  final skyMat = await app.createMaterial(sakuraVcolorFilamat);
  final skyInst = await skyMat.createInstance();
  await v1.createGeometry(skyGeo, materialInstances: [skyInst]);
  await app.flush();

  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(
      near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  final eye = Vector3(spawnPos.x, eyeHeight, spawnPos.z);
  await cam1.lookAt(eye,
      focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));

  print('Rendering realtime toon scene -> RT1...');
  for (int i = 0; i < 2; i++) {
    await app.capture(sc,
        view: v1.view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
  }
  final sceneRes = await app.capture(sc,
      view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  await File('$outDir.rt1.bin').writeAsBytes(sceneRes.first.$2);
  print('  wrote $outDir.rt1.bin');

  // ---- viewer D: depth-encoding pass -> RTd (for finale's depth-ink) ----
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
  await vD.setToneMapper(await ToneMapper.linear(app));
  await vD.setBloom(false, 0);
  await vD.view.setPostProcessing(false);
  await vD.view.setFrustumCullingEnabled(false);
  final camD = await vD.getActiveCamera();
  await camD.setLensProjection(
      near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await camD.lookAt(eye,
      focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));
  final depthMat = await app.createMaterial(sakuraDepthEncFilamat);
  final depthInst = await depthMat.createInstance() as FFIMaterialInstance;
  // positions + the mesh's REAL triangle indices (the depth pass must match the
  // scene topology — sequential [0,1,2,...] indices re-triangulate the
  // shared-vertex faces into garbage and the depth-ink fires everywhere).
  final positions = Float32List.fromList(worldMesh.positions);
  await vD.createGeometry(Geometry(positions, worldMesh.indices),
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
