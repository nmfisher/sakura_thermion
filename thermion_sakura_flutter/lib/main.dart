// Sakura Crossing — interactive realtime-toon explorer.
//
// Loads the reference's extracted geometry (ref_geo*.bin) into a live Thermion
// viewer with the realtime cel material, painted sky, and per-face CPU cast
// shadows — the same scene render_realtime_ref.dart renders headless. You can
// fly around it (WASD + mouse-look, or drag/pinch on touch) to inspect the
// geometry, cel bands, shadows, and sky. Ported mode also runs the same live
// depth ink, anime grade, vignette, and FXAA finale as the fidelity renderer.
//
// The geometry file is large (r60 ≈ 110 MB, full ≈ 460 MB) and not bundled.
// Point the app at a copy on disk (default /tmp/ref_geo_r60.bin) via the path
// field in the top bar.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logging/logging.dart';
import 'package:thermion_dart/thermion_dart.dart' hide VoidCallback;
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_sakura_dart/src/sakura_post_process.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_texture.dart';
import 'package:thermion_flutter/thermion_flutter.dart' hide Transform;
import 'package:thermion_sakura_dart/src/materials_gen.dart';
import 'package:thermion_sakura_dart/src/mesh.dart';
import 'package:thermion_sakura_dart/src/palette.dart';
import 'package:thermion_sakura_dart/src/post_settings.dart';
import 'package:thermion_sakura_dart/src/ref_geo.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:thermion_sakura_dart/src/geom/tri_packed.dart';
import 'package:thermion_sakura_dart/src/geom/three_geom.dart' show Tri;
import 'package:thermion_sakura_dart/src/geom/planet.dart';
import 'package:thermion_sakura_dart/src/world_ref/ported_scene.dart';
import 'package:thermion_sakura_dart/src/world/sky.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  runApp(const SakuraExplorerApp());
}

class SakuraExplorerApp extends StatelessWidget {
  const SakuraExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sakura Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: const ExplorerPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Planet-surface camera frame (ported from render_realtime_ref / planet.js).
// The extracted geometry lives on a sphere of radius R below the origin.
// ─────────────────────────────────────────────────────────────────────────────
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

void _spawnCamera(Vector3 eye, Vector3 fwd, Vector3 up) {
  const px = 1.85, pz = 13.6, eyeH = 1.62, yaw = 0.20, pitch = -0.008;
  eye.setFrom(_positionAt(px, eyeH, pz));
  final u = Vector3.zero(), e = Vector3.zero(), n = Vector3.zero();
  _basisAt(px, pz, u, e, n);
  final cp = math.cos(pitch),
      sp = math.sin(pitch),
      cy = math.cos(yaw),
      sy = math.sin(yaw);
  fwd
    ..setFrom(e * (-sy * cp))
    ..addScaled(u, sp)
    ..addScaled(n, -cy * cp);
  up.setFrom(u);
}

/// The bundled, gzip-compressed reference geometry (radius-60 subset around
/// spawn — the practical exploration default; the full bin is ~460 MB, too big
/// to ship). Committed under assets/ and auto-loaded on startup.
const _bundledGeoAsset = 'assets/ref_geo_r60.bin.gz';

/// Load geometry bytes from a bundled gzip [asset:...] source, a `*.bin.gz`
/// file, or a raw `*.bin` file. Returns the raw (decompressed) geometry bytes.
Future<Uint8List> loadGeoBytes(String source) async {
  Uint8List raw;
  if (source.startsWith('asset:')) {
    final key = source.substring('asset:'.length);
    final data = await rootBundle.load(key);
    raw = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } else {
    raw = await File(source).readAsBytes();
  }
  if (source.endsWith('.gz')) {
    return Uint8List.fromList(gzip.decode(raw));
  }
  return raw;
}

/// Build the realtime toon scene (geometry + sky + lights + camera) in [viewer]
/// from the extracted geometry [geo] bytes. Throws on parse errors.
Future<void> buildSakuraScene(ThermionViewer viewer, Uint8List geo) async {
  final log = Logger('SakuraScene');
  final app = viewer.app as FFIFilamentApp;

  final cel = makeCelShader();
  final sunColorI = cel.sunColor * cel.sunI;
  final fillColorI = cel.fillColor * cel.fillI;
  final bounceColorI = cel.bounceColor * cel.bounceI;
  final hemiSkyI = cel.hemiSky * cel.hemiI;
  final hemiGroundI = cel.hemiGround * cel.hemiI;
  final tint = C.lin(0x6c5f8c);

  final eye0 = Vector3.zero(), fwd0 = Vector3.zero(), up0 = Vector3.zero();
  _spawnCamera(eye0, fwd0, up0);

  log.info('  ${geo.length} bytes; packing...');
  final cpuShadow =
      SunShadowMap(refGeoPositions(geo, onlyLit: true), cel.sunDir);
  final packed = refGeoToPacked(geo, cpuShadow);
  log.info('  ${packed.positions.length ~/ 3} scene verts');

  // LIVE grade: ACES + slopeOffsetPower (≈ the reference's GRADE_SHADER) + sat.
  // Post ON enables the grade + FXAA; produces the graded anime look directly.
  final fog = C.lin(Pal.fog);
  await app.setClearOptions(fog.x, fog.y, fog.z, 1.0);
  await viewer.setBloom(false, 0);
  await viewer.setPostProcessing(true);
  final gradeB = FFIColorGradingBuilder(
    await withPointerCallback<TColorGradingBuilder>(
        (cb) => ColorGradingBuilder_createRenderThread(cb)),
    app,
  )
    ..toneMapper(await ToneMapper.aces(app))
    ..slopeOffsetPower(Vector3(0.88, 0.85, 0.92), Vector3(0.032, 0.032, 0.032),
        Vector3(1.0, 1.0, 1.0))
    ..saturation(1.12);
  await viewer.view.setColorGrading(await gradeB.build());

  // Realtime toon material.
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
  await toonInst.setParameterFloat('cameraNear', 0.25);
  await toonInst.setParameterFloat('encodeDepth', 0.0);

  await viewer.createGeometry(
    Geometry(packed.positions, packed.indices,
        normals: packed.normals,
        colors: packed.colors,
        uvs: packed.uvs,
        uvs1: packed.uvs1,
        attribute0: packed.attribute0),
    materialInstances: [toonInst],
  );

  // Painted sky dome + clouds (same as render_realtime_ref).
  final skyMesh = Mesh(makeCelShader());
  buildSky(skyMesh, eye0, radius: 500, eye: eye0);
  final skyGeo = skyMesh.build();
  final skyCols = skyGeo.colors;
  for (int i = 0; i < skyCols.length; i += 4) {
    final d = C.fromSrgb(Vector3(skyCols[i], skyCols[i + 1], skyCols[i + 2]));
    skyCols[i] = d.x;
    skyCols[i + 1] = d.y;
    skyCols[i + 2] = d.z;
  }
  final skyMat = await app.createMaterial(sakuraSkyFilamat);
  final skyInst = await skyMat.createInstance();
  await viewer.createGeometry(skyGeo, materialInstances: [skyInst]);

  // Camera: the reference's spawn framing.
  final cam = await viewer.getActiveCamera();
  final focal = 12.0 / math.tan(46 * math.pi / 180 * 0.5);
  await cam.setLensProjection(
      near: 0.25, far: 600, aspect: 16 / 9, focalLength: focal);
  await cam.lookAt(eye0, focus: eye0 + fwd0, up: up0);
  // Fog ≈ the reference's THREE.Fog(0xe6ecf7, 44, 205): atmospheric depth.
  await viewer.view.setFogOptions(FogOptions(
    enabled: true,
    distance: 44,
    density: 0.01,
    heightFalloff: 0,
    maximumOpacity: 1.0,
    linearColor: fog,
  ));
  log.info('scene ready');
}

/// Build the PORTED scene (assembled from ported Dart modules — no extracted
/// .bin) in [viewer]: street + houses + trees + poles, cel-shaded with a flat
/// (non-planet) framing camera. The reproducible-code counterpart to
/// [buildSakuraScene]; grows as more modules are ported.
Future<void> buildPortedFilamentScene(ThermionViewer viewer) async {
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
  final viewport = await viewer.view.getViewport();
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
  log.info('ported scene ready');
}

// ─────────────────────────────────────────────────────────────────────────────
// UI
// ─────────────────────────────────────────────────────────────────────────────
class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key});

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

class _ExplorerPageState extends State<ExplorerPage> {
  final _log = Logger('Explorer');
  // The path field is an OPTIONAL override (e.g. /tmp/ref_geo.bin for the full
  // scene). Empty = use the bundled asset.
  late final TextEditingController _pathCtrl = TextEditingController();

  /// What the current viewer is loading: the bundled asset by default, or a
  /// file path the user entered. Changing this remounts the viewer.
  String _source = 'asset:$_bundledGeoAsset';

  /// false = reference extracted geometry (.bin); true = ported Dart modules.
  bool _ported = false;
  String? _error;
  bool _building = true;
  bool _ready = false;
  bool _helpOpen = false;

  Future<void> _load() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) {
      setState(() => _error = 'Not found: $path');
      return;
    }
    _log.info('switching geometry source to $path');
    setState(() {
      _source = path;
      _error = null;
      _building = true;
      _ready = false;
    });
  }

  @override
  void initState() {
    super.initState();
    Logger.root.onRecord.listen((r) => debugPrint(r.toString()));
    // The bundled asset loads automatically on startup (see build → ViewerWidget
    // with _source defaulting to the asset). No /tmp dependency.
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The viewer (or a placeholder until a geometry path is chosen).
          Positioned.fill(
            child: ViewerWidget(
              key: ValueKey('${_ported ? 'ported' : 'ref'}:$_source'),
              manipulatorType: ManipulatorType.FREE_FLIGHT,
              initialCameraPosition: Vector3(1.85, 1.0, 13.7),
              postProcessing: false,
              background: const Color.fromARGB(255, 230, 236, 247),
              initial: const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF14141C)),
              ),
              onViewerAvailable: (viewer) async {
                try {
                  if (_ported) {
                    await buildPortedFilamentScene(viewer);
                  } else {
                    final geo = await loadGeoBytes(_source);
                    await buildSakuraScene(viewer, geo);
                  }
                  if (mounted)
                    setState(() {
                      _building = false;
                      _ready = true;
                    });
                } catch (e, st) {
                  _log.severe('scene build failed', e, st);
                  if (mounted)
                    setState(() {
                      _building = false;
                      _error = '$e';
                    });
                }
              },
            ),
          ),
          // Top bar: path field + load + help.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    // Scene-source toggle: reference extracted geometry vs ported Dart.
                    _Segmented(
                      labels: const ['Reference', 'Ported'],
                      index: _ported ? 1 : 0,
                      onChanged: (i) => setState(() {
                        _ported = i == 1;
                        _building = true;
                        _ready = false;
                        _error = null;
                      }),
                    ),
                    const SizedBox(width: 10),
                    if (!_ported) ...[
                      const Text('ref_geo',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _pathCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                'override path (e.g. /tmp/ref_geo.bin) — empty = bundled',
                            hintStyle: const TextStyle(color: Colors.white38),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Colors.lightBlue),
                            ),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _building ? null : () => _load(),
                        child: const Text('Load'),
                      ),
                    ], // end if (!_ported)
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Help',
                      icon:
                          const Icon(Icons.help_outline, color: Colors.white70),
                      onPressed: () => setState(() => _helpOpen = !_helpOpen),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Loading / status chip.
          if (_building || _error != null)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _building
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 10),
                          Text('Building realtime toon scene…',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                        ])
                      : Text(_error ?? '',
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                ),
              ),
            ),
          if (_ready)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('drag = look · WASD = move · scroll = dolly',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ),
          if (_helpOpen)
            _HelpOverlay(onClose: () => setState(() => _helpOpen = false)),
        ],
      ),
    );
  }
}

class _HelpOverlay extends StatelessWidget {
  const _HelpOverlay({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => onClose(),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 460),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sakura Explorer',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                  'This is the realtime toon scene with the per-pixel cel material, '
                  'painted sky, shadows, and the live depth-ink, anime-grade, vignette, '
                  'and FXAA finale. Select Ported to explore the Dart geometry used by '
                  'the fidelity renderer.',
                  style: TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text('Controls (Free-Flight)',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                    '• Drag — look around\n'
                    '• WASD / arrows — move\n'
                    '• Q / E (or Page Up/Down) — up / down\n'
                    '• Scroll — dolly',
                    style: TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                        fontFamily: 'monospace')),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                      onPressed: () => onClose(), child: const Text('Got it')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny two-segment toggle for switching the scene source.
class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: i == index ? Colors.lightBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                      color: i == index ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
        ],
      ),
    );
  }
}
