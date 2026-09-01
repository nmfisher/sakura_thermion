// Vertex-colour repro: does createGeometry bind the COLOR attribute?
//
// Renders a single quad with four distinct vertex colours (red/green/blue/
// yellow) through the createGeometry path, with the sakura unlit vertex-colour
// material (requires: [position, color]).
//
//   xvfb-run -a -s "-screen 0 512x512x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/repro_colors.dart /tmp/repro_colors.ppm
//
// A correct render shows the quad split into red / green / blue / yellow
// quadrants. If the COLOR attribute never binds, the quad reads whatever the
// driver left in the colour slot — typically black or white.
import 'dart:io';
import 'dart:math' as math;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_sakura_dart/src/materials_gen.dart';

Future<void> main(List<String> argv) async {
  const w = 512, h = 512;
  final outPath = argv.isNotEmpty ? argv.first : '/tmp/repro_colors.ppm';
  final log = File('/tmp/repro_progress.log');
  void step(String s) {
    log.writeAsStringSync('$s\n', mode: FileMode.append);
    print(s);
  }

  step('step 1: create app');
  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);

  step('step 2: viewer');
  final v = ThermionViewerFFI(app: app);
  await v.initialized;
  await app.renderManager.attach(v.view, sc);
  await v.view.setViewport(w, h);
  await app.setClearOptions(0.25, 0.25, 0.28, 1.0);
  await v.setToneMapper(await ToneMapper.linear(app));
  await v.setBloom(false, 0);

  step('step 3: camera');
  final cam = await v.getActiveCamera();
  // Same lens convention as the sakura renderers (46° vertical fov).
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(near: 0.1, far: 100, aspect: w / h, focalLength: focal);
  await cam.lookAt(Vector3(0, 0, 4), focus: Vector3(0, 0, 0), up: Vector3(0, 1, 0));

  // A 3x3 quad at the origin: bottom-left red, bottom-right green,
  // top-right blue, top-left yellow. CCW from the camera.
  final positions = Float32List.fromList([
    -1.5, -1.5, 0, // 0: red (bl)
     1.5, -1.5, 0, // 1: green (br)
     1.5,  1.5, 0, // 2: blue (tr)
    -1.5,  1.5, 0, // 3: yellow (tl)
  ]);
  final colors = Float32List.fromList([
    1.0, 0.0, 0.0, 1.0,
    0.0, 1.0, 0.0, 1.0,
    0.0, 0.0, 1.0, 1.0,
    1.0, 1.0, 0.0, 1.0,
  ]);
  final indices = [0, 1, 2, 0, 2, 3];

  step('step 4: material');
  final mat = await app.createMaterial(sakuraVcolorFilamat);
  final inst = await mat.createInstance();
  final geo = Geometry(positions, indices, colors: colors);
  step('step 5: createGeometry');
  await v.createGeometry(geo, materialInstances: [inst]);

  step('step 6: capture');
  final res = await app.capture(sc,
      view: v.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  final data = res.first.$2; // RGBA32F little-endian
  final n = w * h;

  // Convert RGBA float -> 8-bit RGB, write PPM P6 (no encoder needed).
  final f = ByteData.sublistView(data);
  final rgb = Uint8List(n * 3);
  for (int i = 0; i < n; i++) {
    rgb[i * 3] = (f.getFloat32(i * 16, Endian.little) * 255).clamp(0, 255).toInt();
    rgb[i * 3 + 1] = (f.getFloat32(i * 16 + 4, Endian.little) * 255).clamp(0, 255).toInt();
    rgb[i * 3 + 2] = (f.getFloat32(i * 16 + 8, Endian.little) * 255).clamp(0, 255).toInt();
  }
  final ppm = BytesBuilder();
  ppm.add('P6\n$w $h\n255\n'.codeUnits);
  ppm.add(rgb);
  File(outPath).writeAsBytesSync(ppm.toBytes());
  print('wrote $outPath');
}
