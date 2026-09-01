// What does the GLB path do to vertex colours? Packs a tiny quad with four
// known LINEAR colours through rawToGlb + loadGltfFromBuffer, captures the
// float RT, and prints what comes out — the exact bake→rt1 transform.
//
//   xvfb-run -a -s "-screen 0 512x512x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/repro_glb_color.dart /tmp/glbcol.bin
import 'dart:io';
import 'dart:math' as math;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_sakura_dart/src/glb.dart';

Future<void> main(List<String> argv) async {
  const w = 256, h = 256;
  final outPath = argv.isNotEmpty ? argv.first : '/tmp/glbcol.bin';

  // four known linear colours: pure red, half green, quarter blue, 0.7 grey
  final positions = Float32List.fromList([
    -1.0, -1.0, 0,
     1.0, -1.0, 0,
     1.0,  1.0, 0,
    -1.0,  1.0, 0,
  ]);
  final normals = Float32List.fromList([
    0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1,
  ]);
  // Write PRE-DECODED values (sRGB→linear of the target linear color): the
  // gltfio unlit material sRGB-encodes COLOR_0, so decode(c) written comes
  // back as encode(decode(c)) = c.
  final colors = Float32List.fromList([
    1.0, 0.0, 0.0, 1.0, // pure red (decode(1)=1)
    0.0, 0.214041, 0.0, 1.0, // half green (decode(0.5))
    0.0, 0.0, 0.050876, 1.0, // quarter blue (decode(0.25))
    0.44721, 0.44721, 0.44721, 1.0, // grey 0.7 (decode(0.7))
  ]);
  final glb = rawToGlb(positions, normals, colors);

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);
  final v = ThermionViewerFFI(app: app);
  await v.initialized;
  await app.renderManager.attach(v.view, sc);
  await v.view.setViewport(w, h);
  await app.setClearOptions(0, 0, 0, 1);
  await v.setToneMapper(await ToneMapper.linear(app));
  await v.setBloom(false, 0);
  final cam = await v.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(near: 0.1, far: 100, aspect: 1.0, focalLength: focal);
  await cam.lookAt(Vector3(0, 0, 4), focus: Vector3(0, 0, 0), up: Vector3(0, 1, 0));

  await v.loadGltfFromBuffer(glb);
  final res = await app.capture(sc,
      view: v.view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  final data = res.first.$2;
  final f = ByteData.sublistView(data);
  // sample the four quadrants at 25% offsets
  for (final (label, fy, fx) in [
    ('BL red   ', 0.75, 0.25), ('BR green ', 0.75, 0.75),
    ('TR blue  ', 0.25, 0.75), ('TL grey  ', 0.25, 0.25)]) {
    final x = (fx * w).toInt(), y = (fy * h).toInt();
    final o = (y * w + x) * 16;
    final r = f.getFloat32(o, Endian.little);
    final g = f.getFloat32(o + 4, Endian.little);
    final b = f.getFloat32(o + 8, Endian.little);
    File(outPath).writeAsStringSync('$label $r $g $b\n', mode: FileMode.append);
  }
  print('wrote $outPath');
}
