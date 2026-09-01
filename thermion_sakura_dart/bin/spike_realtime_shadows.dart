// Decisive spike: does the HEADLESS viewer support Filament lit materials +
// realtime shadows? Mirrors the known-good materials_pbr example (IBL +
// ubershader + sun) but with a ground plane under a box so a shadow can fall.
//
//   xvfb-run -a -s "-screen 0 640x480x24" \
//     env LD_PRELOAD=/lib/aarch64-linux-gnu/libstdc++.so.6 \
//     dart run bin/spike_realtime_shadows.dart /tmp/spike3.ppm
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:vector_math/vector_math_64.dart';

Future<void> main(List<String> argv) async {
  const w = 640, h = 480;
  final outPath = argv.isNotEmpty ? argv.first : '/tmp/spike3.ppm';
  const assets = '/workspace/examples/assets/';

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final sc = await app.createHeadlessSwapChain(w, h);
  final v = ThermionViewerFFI(app: app);
  await v.initialized;
  await app.renderManager.attach(v.view, sc);
  await v.view.setViewport(w, h);
  final viewShadows = Platform.environment['VIEW_SHADOWS'] != '0';
  await v.view.setShadowsEnabled(viewShadows);
  await app.setClearOptions(0.1, 0.1, 0.15, 1.0);

  // known-good PBR environment (mirrors materials_pbr.dart)
  await v.loadSkybox('${assets}default_env_skybox.ktx');
  await v.loadIbl('${assets}default_env_ibl.ktx');

  // sun angled so the box's shadow casts toward +x,+z (toward the camera) and is visible
  final sun = await v.addDirectLight(
      DirectLight.sun(direction: Vector3(0.5, -1.0, 0.5), castShadows: true));
  await app.lightManager.setShadowOptions(
      sun,
      ShadowOptions(
        mapSize: 2048,
        shadowCascades: 1,
        cascadeSplitPositions: const [1.0],
        constantBias: 0.005,
        normalBias: 0.5,
        shadowFar: 60.0,
        shadowNearHint: 0.0,
        shadowFarHint: 60.0,
        stable: true,
      ));
  await app.flush();

  // ubershader lit material (known-good), uniform base colour
  final mat = await app.createUbershaderMaterial();
  await mat.setRoughnessFactor(1.0);
  await mat.setMetallicFactor(0.0);
  await mat.setBaseColorFactor(0.9, 0.9, 0.9, 1.0);
  final inst = mat.materialInstance;

  // ground plane 14x14 at y=0
  const g = 7.0;
  final groundGeo = Geometry(
    Float32List.fromList([-g, 0, -g, g, 0, -g, g, 0, g, -g, 0, g]),
    [0, 2, 1, 0, 3, 2], // CCW when viewed from +Y — the original [0,1,2,0,2,3]
    // winding put the normal DOWN, so the receiver never got sun light and
    // no shadow could appear (the box-winding gotcha from mesh.dart).
    normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]),
    uvs: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
  );
  final ground = await v.createGeometry(groundGeo, materialInstances: [inst]);
  await ground.setReceiveShadows(true);
  await ground.setCastShadows(false);

  // box 3x3x3 at y=3
  const s = 1.5;
  final c = [-s, s];
  final bPos = <double>[], bNrm = <double>[];
  final bIdx = <int>[];
  int vc = 0;
  void quad(List<double> p0, List<double> p1, List<double> p2, List<double> p3, List<double> n) {
    for (final p in [p0, p1, p2, p3]) { bPos.addAll(p); bNrm.addAll(n); }
    bIdx.addAll([vc, vc + 1, vc + 2, vc, vc + 2, vc + 3]);
    vc += 4;
  }
  const y0 = 3.0, y1 = 6.0;
  quad([c[0],y0,c[0]],[c[1],y0,c[0]],[c[1],y1,c[0]],[c[0],y1,c[0]],[0,0,-1.0]);
  quad([c[1],y0,c[0]],[c[1],y0,c[1]],[c[1],y1,c[1]],[c[1],y1,c[0]],[1.0,0,0]);
  quad([c[1],y0,c[1]],[c[0],y0,c[1]],[c[0],y1,c[1]],[c[1],y1,c[1]],[0,0,1.0]);
  quad([c[0],y0,c[1]],[c[0],y0,c[0]],[c[0],y1,c[0]],[c[0],y1,c[1]],[-1.0,0,0]);
  quad([c[0],y1,c[0]],[c[1],y1,c[0]],[c[1],y1,c[1]],[c[0],y1,c[1]],[0,1.0,0]);
  quad([c[0],y0,c[1]],[c[1],y0,c[1]],[c[1],y0,c[0]],[c[0],y0,c[0]],[0,-1.0,0]);
  final boxGeo = Geometry(Float32List.fromList(bPos), bIdx, normals: Float32List.fromList(bNrm));
  final box = await v.createGeometry(boxGeo, materialInstances: [inst]);
  final castOn = Platform.environment['NO_SHADOW'] != '1';
  await box.setCastShadows(castOn);
  await box.setReceiveShadows(true);
  await app.flush();

  final cam = await v.getActiveCamera();
  final focal = 28.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(near: 0.1, far: 200, aspect: w / h, focalLength: focal);
  await cam.lookAt(Vector3(10, 9, 10), focus: Vector3(0, 3, 0), up: Vector3(0, 1, 0));
  await app.flush();

  for (int i = 0; i < 2; i++) {
    await app.capture(sc, view: v.view,
        pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  }
  final res = await app.capture(sc, view: v.view,
      pixelDataFormat: PixelDataFormat.RGBA, pixelDataType: PixelDataType.FLOAT);
  final f = ByteData.sublistView(res.first.$2);
  final n = w * h;
  final rgb = Uint8List(n * 3);
  for (int i = 0; i < n; i++) {
    rgb[i * 3] = (f.getFloat32(i * 16, Endian.little) * 255).clamp(0, 255).toInt();
    rgb[i * 3 + 1] = (f.getFloat32(i * 16 + 4, Endian.little) * 255).clamp(0, 255).toInt();
    rgb[i * 3 + 2] = (f.getFloat32(i * 16 + 8, Endian.little) * 255).clamp(0, 255).toInt();
  }
  await File(outPath).writeAsBytes((BytesBuilder()..add('P6\n$w $h\n255\n'.codeUnits)..add(rgb)).toBytes());
  print('wrote $outPath');
}
