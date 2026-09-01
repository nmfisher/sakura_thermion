// Diagnostic: render the RT1 depth texture through sakura_depthraw so we can see
// whether depth is sampled and whether Filament is reverse-Z.
//   R = raw depth sample, G = linearised view distance / 120, B = 0
import 'dart:io';
import 'dart:math' as math;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:vector_math/vector_math_64.dart';

Vector3 _fwd(double y, double p) {
  final c = math.cos(p);
  return Vector3(-math.sin(y) * c, math.sin(p), -math.cos(y) * c);
}

Future<void> main(List<String> argv) async {
  const w = 800, h = 450;
  final out = argv.isNotEmpty ? argv.first : '/tmp/depth_diag.png';
  final matPath = '/workspace/thermion_sakura/materials/sakura_depthraw.filamat';

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  final v1 = ThermionViewerFFI(app: app);
  await v1.initialized;
  await app.renderManager.attach(v1.view, sc);
  final rt1Color = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE},
      textureFormat: TextureFormat.RGBA32F);
  final rt1Depth = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE},
      textureFormat: TextureFormat.DEPTH32F);
  final rt1 = await app.createRenderTarget(w, h, color: rt1Color, depth: rt1Depth);
  await v1.view.setRenderTarget(rt1);
  await v1.view.setViewport(w, h);
  await app.setClearOptions(0, 0, 0, 1.0);
  await v1.setToneMapper(await ToneMapper.linear(app));
  final cam1 = await v1.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam1.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);
  final eye = Vector3(spawnPos.x, eyeHeight, spawnPos.z);
  await cam1.lookAt(eye, focus: eye + _fwd(spawnYaw, spawnPitch), up: Vector3(0, 1, 0));
  await buildWorld(v1, app);
  await app.capture(sc, view: v1.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);

  final v2 = ThermionViewerFFI(app: app);
  await v2.initialized;
  await app.renderManager.attach(v2.view, sc);
  final rt2Color = await app.createTexture(w, h,
      flags: {TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT, TextureUsage.TEXTURE_USAGE_SAMPLEABLE, TextureUsage.TEXTURE_USAGE_BLIT_SRC},
      textureFormat: TextureFormat.RGBA32F);
  final rt2 = await app.createRenderTarget(w, h, color: rt2Color);
  await v2.view.setRenderTarget(rt2);
  await v2.view.setViewport(w, h);
  await v2.setToneMapper(await ToneMapper.linear(app));
  await v2.view.setPostProcessing(false);

  final mat = await app.createMaterial(await File(matPath).readAsBytes());
  final inst = await mat.createInstance() as FFIMaterialInstance;
  final sampler = await app.createTextureSampler(
      minFilter: TextureMinFilter.NEAREST, magFilter: TextureMagFilter.NEAREST,
      wrapS: TextureWrapMode.CLAMP_TO_EDGE, wrapT: TextureWrapMode.CLAMP_TO_EDGE);
  await inst.setParameterTexture('tDepth', rt1Depth as dynamic, sampler as dynamic);
  final geo = Geometry(Float32List.fromList([-1, -1, 0.5, 3, -1, 0.5, -1, 3, 0.5]), [0, 1, 2]);
  await v2.createGeometry(geo, materialInstances: [inst]);
  final cam2 = await v2.getActiveCamera();
  await cam2.setProjection(Projection.Orthographic, -1, 1, -1, 1, 0.0, 1.0);

  for (int i = 0; i < 3; i++) {
    await app.capture(sc, view: v2.view,
        pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  }
  final res = await app.capture(sc, view: v2.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  await File('/tmp/depth_diag.bin').writeAsBytes(res.first.$2);
  // write as a simple 8-bit PNG (values are already display-ish 0..1)
  final png = await pixelBufferToPng(res.first.$2, w, h, hasAlpha: true, isFloat: true);
  await File(out).writeAsBytes(png);
  print('wrote $out + /tmp/depth_diag.bin');
  exit(0);
}
