// Sakura Crossing — REALTIME TOON on the EXTRACTED reference geometry.
//
// = render_toon.dart's realtime cel material + realtime GPU sun shadow map,
//   applied to the REFERENCE'S OWN meshes (ref_geo.bin, geometry identical to
//   the three.js scene by construction), viewed through render_ref.dart's
//   planet-surface camera. No baked cel, no CPU shadows — all lighting and
//   shadows are computed per pixel every frame.
//
//   xvfb-run -a -s "-screen 0 1600x900x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/render_realtime_ref.dart [geo.bin] [outPrefix]
//   Env: PX/PZ/EYE/YAW/PITCH override the spawn camera.
import 'dart:io';
import 'dart:math' as math;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_texture.dart';
import 'package:thermion_sakura_dart/src/materials_gen.dart';
import 'package:thermion_sakura_dart/src/mesh.dart';
import 'package:thermion_sakura_dart/src/palette.dart';
import 'package:thermion_sakura_dart/src/ref_geo.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:thermion_sakura_dart/src/world/sky.dart';

// ---- planet surface frame (ported from the reference planet.js) ----
// The extracted geometry lives on a sphere of radius R centred below the
// origin, so the camera uses the reference's spherical surface frame
// (basisAt/positionAt). At spawn this maps to near world-origin.
const double _R = 160.0;
final Vector3 _pCenter = Vector3(0, -_R, 0);

Vector3 _normalAt(double x, double z) {
  final la = x / _R, ph = z / _R;
  final cp = math.cos(ph);
  return Vector3(math.sin(la) * cp, math.cos(la) * cp, math.sin(ph));
}

Vector3 _positionAt(double x, double y, double z) =>
    _normalAt(x, z) * (_R + y) + _pCenter;

void _basisAt(double x, double z, Vector3 up, Vector3 east, Vector3 north) {
  final la = x / _R, ph = z / _R;
  final sl = math.sin(la),
      cl = math.cos(la),
      sp = math.sin(ph),
      cp = math.cos(ph);
  up.setValues(sl * cp, cl * cp, sp);
  east.setValues(cl, -sl, 0);
  north.setValues(-sl * sp, -cl * sp, cp);
}

/// Camera (eye + forward + up) on the sphere, matching the reference. Reads
/// flat pos/yaw/pitch from env (PX,PZ,EYE,YAW,PITCH), defaulting to spawn.
void _spawnCamera(Vector3 eye, Vector3 fwd, Vector3 up) {
  final px = double.parse(Platform.environment['PX'] ?? '1.85');
  final pz = double.parse(Platform.environment['PZ'] ?? '13.6');
  final eyeH = double.parse(Platform.environment['EYE'] ?? '1.62');
  final yaw = double.parse(Platform.environment['YAW'] ?? '0.20');
  final pitch = double.parse(Platform.environment['PITCH'] ?? '-0.008');
  eye.setFrom(_positionAt(px, eyeH, pz));
  final u = Vector3.zero(), e = Vector3.zero(), n = Vector3.zero();
  _basisAt(px, pz, u, e, n);
  final cp = math.cos(pitch), sp = math.sin(pitch);
  final cy = math.cos(yaw), sy = math.sin(yaw);
  fwd
    ..setFrom(e * (-sy * cp))
    ..addScaled(u, sp)
    ..addScaled(n, -cy * cp);
  up.setFrom(u);
}

Future<void> main(List<String> argv) async {
  const w = 1600, h = 900;
  final geoPath = argv.isNotEmpty ? argv.first : '/tmp/ref_geo_r60.bin';
  final outDir = argv.length > 1 ? argv[1] : '/tmp/sakura_rref';

  // cel.dart's two-light + bounce + hemisphere setup, folded to colour*intensity.
  final cel = makeCelShader();
  final cameraPx = double.parse(Platform.environment['PX'] ?? '1.85');
  final cameraPz = double.parse(Platform.environment['PZ'] ?? '13.6');
  final surfaceUp = Vector3.zero();
  final surfaceEast = Vector3.zero();
  final surfaceNorth = Vector3.zero();
  _basisAt(cameraPx, cameraPz, surfaceUp, surfaceEast, surfaceNorth);
  Vector3 worldLight(Vector3 local) =>
      (surfaceEast * local.x + surfaceUp * local.y + surfaceNorth * local.z)
        ..normalize();
  final sunDir = worldLight(cel.sunDir);
  final fillDir = worldLight(cel.fillDir);
  final bounceDir = worldLight(cel.bounceDir);
  final sunColorI = cel.sunColor * cel.sunI;
  final fillColorI = cel.fillColor * cel.fillI;
  final bounceColorI = cel.bounceColor * cel.bounceI;
  final hemiSkyI = cel.hemiSky * cel.hemiI;
  final hemiGroundI = cel.hemiGround * cel.hemiI;
  final tint = C.lin(0x6c5f8c);

  // planet-frame spawn camera (eye ≈ world origin at spawn).
  final eye0 = Vector3.zero(), fwd0 = Vector3.zero(), up0 = Vector3.zero();
  _spawnCamera(eye0, fwd0, up0);

  print('Loading $geoPath ...');
  final geo = await File(geoPath).readAsBytes();
  print('  ${geo.length} bytes; packing for realtime toon material...');
  // CPU sun shadow map (same as render_ref / the reference): cell=1, bias=6,
  // deliberately lenient so only genuinely occluded faces are flagged. The
  // earlier realtime GPU shadow map (ortho + NEAREST 2048) was ~25x finer and
  // flagged surface acne + dense-geometry self-occlusion, over-shadowing the
  // whole scene (mean 123 vs ref 148). Per-face shadow is packed into COLOR0.a
  // by refGeoToPacked; the toon material reads it (no GPU shadow pass needed).
  final cpuShadow = SunShadowMap(refGeoPositions(geo, onlyLit: true), sunDir);
  final packed = refGeoToPacked(geo, cpuShadow);
  print('  ${packed.positions.length ~/ 3} scene verts');

  await FFIFilamentApp.create(
      config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  // ---- viewer 1: realtime toon scene -> RT1 (float, linear) ----
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
  // Clear to fog (same as render_ref): the painted sky dome AND the toon world
  // are both drawn on this one view, so any uncovered pixel reads as distant
  // fog. (An earlier sentinel-clear + separate-sky-view + finale-composite
  // scheme was abandoned: Filament clamps the clear colour to [0,1], so the
  // sentinel leaked through as graded garbage, and the world geometry covered
  // the whole frame leaving nothing to composite.)
  await app.setClearOptions(fog.x, fog.y, fog.z, 1.0);
  await v1.setToneMapper(await ToneMapper.linear(app));
  await v1.setBloom(false, 0);
  await v1.view.setPostProcessing(false);
  // Force a LINEAR color grade so Filament's default sRGB OETF does NOT encode
  // the float RT (without this, linear cel values become sRGB in the RT and the
  // downstream grade double-encodes -> blown highlights). Same as render_ref.
  final linTM = await ToneMapper.linear(app);
  final linCGB = FFIColorGradingBuilder(
    await withPointerCallback<TColorGradingBuilder>(
        (cb) => ColorGradingBuilder_createRenderThread(cb)),
    app,
  );
  linCGB.toneMapper(linTM);
  final linCG = await linCGB.build();
  await v1.view.setColorGrading(linCG);

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
  await toonInst.setParameterFloat('shadowEnabled', 0.0);
  await toonInst.setParameterFloat('shadowDebug', 0.0);
  await toonInst.setParameterFloat('cameraNear', .25);
  await toonInst.setParameterFloat('encodeDepth', 0.0);
  await toonInst.setParameterFloat3('fogColor', fog.x, fog.y, fog.z);
  await toonInst.setParameterFloat('fogNear', 44.0);
  await toonInst.setParameterFloat('fogFar', 205.0);
  // The branch is disabled, but Filament still requires every declared
  // sampler to be bound before draw submission.
  final unusedShadow = await app.createTexture(1, 1,
      flags: {TextureUsage.TEXTURE_USAGE_SAMPLEABLE},
      textureFormat: TextureFormat.RGBA8);
  final unusedShadowSampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST,
      magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE,
      wrapT: TextureWrapMode.CLAMP_TO_EDGE);
  await toonInst.setParameterTexture('shadowMap', unusedShadow as FFITexture,
      unusedShadowSampler as FFITextureSampler);

  // ---- toon scene geometry (the reference's own extracted meshes) ----
  // uvs/uvs1 MUST be passed: the toon material reads its per-face normal from
  // UV0/UV1.x and the per-material ramp id from UV1.y. Without them the Geometry
  // ctor substitutes all-zero UVs, collapsing every face to one cel band.
  await v1.createGeometry(
      Geometry(packed.positions, packed.indices,
          normals: packed.normals,
          colors: packed.colors,
          uvs: packed.uvs,
          uvs1: packed.uvs1,
          attribute0: packed.attribute0),
      materialInstances: [toonInst]);

  // ---- painted sky (rebuilt from sky.dart; extracted sky meshes are skipped) ----
  // Drawn on the SAME view as the toon world (like render_ref): the dome is an
  // unlit vertex-colour geometry at radius 500 (behind all world geometry), the
  // world is nearer and overdraws it. No isolation or compositing needed.
  final skyMesh = Mesh(makeCelShader());
  buildSky(skyMesh, Vector3.zero(), radius: 500, eye: eye0);
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
  final skyMat = await app.createMaterial(sakuraVcolorFilamat);
  final skyInst = await skyMat.createInstance();
  await v1.createGeometry(skyGeo, materialInstances: [skyInst]);
  await app.flush();

  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(
      near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await cam1.lookAt(eye0, focus: eye0 + fwd0, up: up0);

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
  // Uses the SAME geometry as the colour pass (packed) so ink creases align
  // with visible silhouettes — an earlier version used the filtered caster
  // list, whose extra back-face / occluded geometry inked over smooth cel.
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
  await camD.lookAt(eye0, focus: eye0 + fwd0, up: up0);
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
