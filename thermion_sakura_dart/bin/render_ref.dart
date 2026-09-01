// Render the EXTRACTED reference world (ref_geo.bin) with matching cel + depth
// ink + grade. The geometry is already on the planet sphere, so the camera uses
// the reference's spherical surface frame (basisAt/positionAt from planet.js).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_sakura_dart/src/materials_gen.dart';
import 'package:thermion_sakura_dart/src/mesh.dart';
import 'package:thermion_sakura_dart/src/palette.dart';
import 'package:thermion_sakura_dart/src/ref_geo.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:thermion_sakura_dart/src/world/sky.dart';
import 'package:vector_math/vector_math_64.dart';

const double _R = 160.0;
final Vector3 _center = Vector3(0, -_R, 0);

Vector3 _normalAt(double x, double z) {
  final la = x / _R, ph = z / _R;
  final cp = math.cos(ph);
  return Vector3(math.sin(la) * cp, math.cos(la) * cp, math.sin(ph));
}

Vector3 _positionAt(double x, double y, double z) =>
    _normalAt(x, z) * (_R + y) + _center;

/// Surface tangent frame (east, up, north) at flat (x,z), ported from planet.js.
void _basisAt(double x, double z, Vector3 up, Vector3 east, Vector3 north) {
  final la = x / _R, ph = z / _R;
  final sl = math.sin(la), cl = math.cos(la), sp = math.sin(ph), cp = math.cos(ph);
  up.setValues(sl * cp, cl * cp, sp);
  east.setValues(cl, -sl, 0);
  north.setValues(-sl * sp, -cl * sp, cp);
}

/// Camera (eye + forward + up) on the sphere, matching the reference. Reads
/// flat pos/yaw/pitch from env vars (PX,PZ,EYE,YAW,PITCH), defaulting to spawn.
void _spawnCamera(Vector3 eye, Vector3 fwd, Vector3 up) {
  final px = double.parse(Platform.environment['PX'] ?? '1.85');
  final pz = double.parse(Platform.environment['PZ'] ?? '13.6');
  final eyeH = double.parse(Platform.environment['EYE'] ?? '1.62');
  final yaw = double.parse(Platform.environment['YAW'] ?? '0.20');
  final pitch = double.parse(Platform.environment['PITCH'] ?? '-0.008');
  eye.setFrom(_positionAt(px, eyeH, pz));
  final u = Vector3.zero(), e = Vector3.zero(), n = Vector3.zero();
  _basisAt(px, pz, u, e, n);
  // local look direction in the surface frame (matches the reference
  // _forward / YXZ euler), then map into world via the (east, up, north) basis.
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
  final geoPath = argv.isNotEmpty ? argv.first : '/tmp/ref_geo.bin';
  final outPrefix = argv.length > 1 ? argv[1] : '/tmp/sakura_out';

  final geo = await File(geoPath).readAsBytes();
  print('Loaded ${geo.length} bytes of reference geometry; packing for toon material...');
  final cel = makeCelShader();
  final eye0 = Vector3.zero();
  final fwd0 = Vector3.zero();
  final up0 = Vector3.zero();
  _spawnCamera(eye0, fwd0, up0);
  final positions = refGeoPositions(geo);
  print('Baking cel into GLB...');

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

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
  // Set linear color grading to prevent Filament's default sRGB OETF from
  // encoding the float RT. Without this, LINEAR vertex colours become
  // sRGB-encoded in the RT, corrupting the downstream grade.
  final linTM = await ToneMapper.linear(app);
  final linCGB = FFIColorGradingBuilder(
    await withPointerCallback<TColorGradingBuilder>(
        (cb) => ColorGradingBuilder_createRenderThread(cb)),
    app,
  );
  linCGB.toneMapper(linTM);
  final linCG = await linCGB.build();
  await v1.view.setColorGrading(linCG);

  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  await cam1.lookAt(eye0, focus: eye0 + fwd0, up: up0);

  // Bake cel per-vertex (per-material tint, ramp, bounce, shadow) into a GLB.
  // The per-pixel toon material can't use per-vertex tint/rampId because
  // gltfio corrupts UV attributes (linear→sRGB on COLOR_0 is also an issue).
  // Baked cel per-face is accurate for flat geometry and handles every material.
  final glb = refGeoToGlb(geo, cel);
  await v1.loadGltfFromBuffer(glb);
  // The extracted GLB skips the sky meshes (white dome + flat cloud quads are
  // unusable); rebuild the painted sky — gradient dome around the planet at
  // radius 500, puffy clouds, distant hills — from the palette, like the
  // reference sky.js. Rendered as a second unlit vertex-colour geometry.
  final skyMesh = Mesh(makeCelShader());
  buildSky(skyMesh, Vector3.zero(), radius: 500, eye: eye0);
  final skyGeo = skyMesh.build();
  // The unlit vertex-colour material sRGB-ENCODES vertex colours on upload
  // (same as the GLB path — written 0.597 comes out ~0.79 in the RT). The
  // sky is painted in linear, so pre-decode to get the linear sky back.
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
  print('Rendering scene -> RT1 (baked cel GLB)...');
  final sceneRes = await app.capture(sc, view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  await File('$outPrefix.rt1.bin').writeAsBytes(sceneRes.first.$2);

  // depth pass: same positions, depth-encoding material
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
  await camD.lookAt(eye0, focus: eye0 + fwd0, up: up0);
  final depthMat = await app.createMaterial(sakuraDepthEncFilamat);
  final depthInst = await depthMat.createInstance() as FFIMaterialInstance;
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
  await File('$outPrefix.depth.bin').writeAsBytes(depthRes.first.$2);
  print('  wrote $outPrefix.rt1.bin + .depth.bin');
  stdout.writeln('SIZE $w $h');
  exit(0);
}
