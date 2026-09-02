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
import 'dart:ui' show ImageFilter, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/services.dart' as services;
import 'package:logging/logging.dart';
import 'package:thermion_dart/thermion_dart.dart' hide Transform, VoidCallback;
import 'package:thermion_dart/src/filament/src/implementation/ffi_color_grading.dart';
import 'package:thermion_sakura_dart/thermion_sakura_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_material.dart';
import 'package:thermion_flutter/thermion_flutter.dart' hide Transform;
import 'package:thermion_sakura_dart/src/materials_gen.dart';
import 'package:thermion_sakura_dart/src/mesh.dart';
import 'package:thermion_sakura_dart/src/palette.dart';
import 'package:thermion_sakura_dart/src/ref_geo.dart';
import 'package:thermion_sakura_dart/src/scene.dart';
import 'package:thermion_sakura_dart/src/world/sky.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void _logError(String context, Object error, StackTrace? stackTrace) {
  stderr.writeln('$context: $error');
  if (stackTrace != null) stderr.writeln(stackTrace);
}

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
        '${record.time} ${record.level.name} ${record.loggerName}: ${record.message}');
    if (record.error != null) stderr.writeln(record.error);
    if (record.stackTrace != null) stderr.writeln(record.stackTrace);
  });
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logError('Unhandled Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _logError('Unhandled asynchronous error', error, stackTrace);
    return true;
  };
  runApp(const SakuraExplorerApp());
}

Future<Uint8List> _loadSakuraPackageAsset(String path) async {
  final data = await rootBundle.load('packages/thermion_sakura_dart/lib/$path');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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

// ─────────────────────────────────────────────────────────────────────────────
// UI
// ─────────────────────────────────────────────────────────────────────────────
class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key});

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

class _ExplorerPageState extends State<ExplorerPage>
    with WidgetsBindingObserver {
  static const _mouseCaptureChannel =
      services.MethodChannel('sakura_thermion/mouse_capture');
  static const _lookSensitivity = .0022;
  final _log = Logger('Explorer');
  final Set<services.PhysicalKeyboardKey> _heldKeys = {};
  Timer? _walkTimer;
  bool _mouseCaptured = false;
  // The path field is an OPTIONAL override (e.g. /tmp/ref_geo.bin for the full
  // scene). Empty = use the bundled asset.
  late final TextEditingController _pathCtrl = TextEditingController();

  /// What the current viewer is loading: the bundled asset by default, or a
  /// file path the user entered. Changing this remounts the viewer.
  String _source = 'asset:$_bundledGeoAsset';

  /// false = reference extracted geometry (.bin); true = ported Dart modules.
  bool _ported = true;
  String? _error;
  bool _building = true;
  bool _ready = false;
  bool _helpOpen = false;
  bool _menuOpen = true;
  bool _started = false;
  SakuraApp? _portedScene;

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
    WidgetsBinding.instance.addObserver(this);
    services.HardwareKeyboard.instance.addHandler(_handleKey);
    // The bundled asset loads automatically on startup (see build → ViewerWidget
    // with _source defaulting to the asset). No /tmp dependency.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.HardwareKeyboard.instance.removeHandler(_handleKey);
    _walkTimer?.cancel();
    unawaited(_setMouseCaptured(false));
    final scene = _portedScene;
    if (scene != null) unawaited(scene.dispose());
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final scene = _portedScene;
    if (scene != null) {
      unawaited(scene.prepareForPlatformResize());
    }
  }

  bool _handleKey(services.KeyEvent event) {
    final key = event.physicalKey;
    if (key == services.PhysicalKeyboardKey.keyW ||
        key == services.PhysicalKeyboardKey.keyA ||
        key == services.PhysicalKeyboardKey.keyS ||
        key == services.PhysicalKeyboardKey.keyD ||
        key == services.PhysicalKeyboardKey.shiftLeft ||
        key == services.PhysicalKeyboardKey.shiftRight) {
      if (event is services.KeyUpEvent) {
        _heldKeys.remove(key);
      } else if (!_menuOpen) {
        _heldKeys.add(key);
      }
    }
    if (_menuOpen && event is! services.KeyUpEvent) {
      if (key == services.PhysicalKeyboardKey.keyW ||
          key == services.PhysicalKeyboardKey.keyA ||
          key == services.PhysicalKeyboardKey.keyS ||
          key == services.PhysicalKeyboardKey.keyD ||
          key == services.PhysicalKeyboardKey.shiftLeft ||
          key == services.PhysicalKeyboardKey.shiftRight) {
        return true;
      }
    }
    if (event is services.KeyDownEvent &&
        key == services.PhysicalKeyboardKey.keyR &&
        !_menuOpen) {
      final scene = _portedScene;
      if (scene != null) unawaited(scene.resetCamera());
      return true;
    }
    if (event is! services.KeyDownEvent ||
        key != services.PhysicalKeyboardKey.escape) {
      return false;
    }
    if (!_ready) return false;
    unawaited(_setMouseCaptured(false));
    setState(() {
      _started = true;
      _menuOpen = !_menuOpen;
    });
    _portedScene?.setPaused(_menuOpen);
    return true;
  }

  void _enterScene() {
    setState(() {
      _started = true;
      _menuOpen = false;
    });
    _portedScene?.setPaused(false);
    if (_ported) unawaited(_setMouseCaptured(true));
  }

  Future<void> _setMouseCaptured(bool captured) async {
    if (_mouseCaptured == captured) return;
    _mouseCaptured = captured;
    if (!captured) _heldKeys.clear();
    if (mounted) setState(() {});
    if (!Platform.isMacOS) return;
    try {
      await _mouseCaptureChannel
          .invokeMethod<void>(captured ? 'capture' : 'release');
    } catch (error, stackTrace) {
      _log.warning('mouse capture failed', error, stackTrace);
    }
  }

  void _startWalkTimer() {
    _walkTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_menuOpen || !_ready || !_ported || _heldKeys.isEmpty) return;
      final fast = _heldKeys.contains(services.PhysicalKeyboardKey.shiftLeft) ||
          _heldKeys.contains(services.PhysicalKeyboardKey.shiftRight);
      final step = fast ? .13 : .065;
      final forward = (_heldKeys.contains(services.PhysicalKeyboardKey.keyW)
              ? step
              : 0.0) -
          (_heldKeys.contains(services.PhysicalKeyboardKey.keyS) ? step : 0.0);
      final right = (_heldKeys.contains(services.PhysicalKeyboardKey.keyD)
              ? step
              : 0.0) -
          (_heldKeys.contains(services.PhysicalKeyboardKey.keyA) ? step : 0.0);
      unawaited(_portedScene?.controlCamera(right: right, forward: forward) ??
          Future<void>.value());
    });
  }

  void _look(services.PointerHoverEvent event) {
    if (!_mouseCaptured || _menuOpen || !_ported) return;
    unawaited(_portedScene?.controlCamera(
          yaw: event.delta.dx * _lookSensitivity,
          // Intentionally inverted: moving the mouse up looks down.
          pitch: -event.delta.dy * _lookSensitivity,
        ) ??
        Future<void>.value());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The viewer (or a placeholder until a geometry path is chosen).
          Positioned.fill(
            child: MouseRegion(
              cursor: _mouseCaptured
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              onHover: _look,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  if (_ready && !_menuOpen) unawaited(_setMouseCaptured(true));
                },
                child: ViewerWidget(
                  key: ValueKey('${_ported ? 'ported' : 'ref'}:$_source'),
                  manipulatorType: _ported
                      ? ManipulatorType.NONE
                      : ManipulatorType.FREE_FLIGHT,
                  initialCameraPosition: Vector3(1.85, 1.0, 13.7),
                  postProcessing: false,
                  background: const Color.fromARGB(255, 230, 236, 247),
                  initial: const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xFF14141C)),
                  ),
                  onViewerAvailable: (viewer) async {
                    // The ported builder renders its shadow map synchronously via
                    // Filament's capture path.  Do not let Flutter's frame
                    // scheduler drive the same Renderer between capture's
                    // beginFrame/render/endFrame calls: on Metal that can fill
                    // Filament's FrameInfo queue and leave the capture readback
                    // waiting forever.
                    final plugin = ThermionFlutterPlugin.instance;
                    plugin.pauseFrameScheduler();
                    try {
                      if (_ported) {
                        _portedScene = await SakuraApp.create(
                          viewer,
                          loadPackageAsset: _loadSakuraPackageAsset,
                          runtimeAnimations: true,
                          groundedCamera: true,
                        );
                        _portedScene!.setPaused(_menuOpen);
                        _startWalkTimer();
                      } else {
                        final geo = await loadGeoBytes(_source);
                        await buildSakuraScene(viewer, geo);
                      }
                      if (mounted) {
                        setState(() {
                          _building = false;
                          _ready = true;
                        });
                      }
                    } catch (e, st) {
                      _log.severe('scene build failed', e, st);
                      if (mounted) {
                        setState(() {
                          _building = false;
                          _error = '$e';
                        });
                      }
                    } finally {
                      plugin.resumeFrameScheduler();
                    }
                  },
                ),
              ),
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
                      onChanged: (i) {
                        final scene = _portedScene;
                        if (scene != null) unawaited(scene.dispose());
                        unawaited(_setMouseCaptured(false));
                        setState(() {
                          _ported = i == 1;
                          _portedScene = null;
                          _building = true;
                          _ready = false;
                          _error = null;
                        });
                      },
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
                    color: Colors.black.withValues(alpha: 0.6),
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
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                    'mouse captured · WASD = grounded walk · Esc = release',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ),
          if (_helpOpen)
            _HelpOverlay(onClose: () => setState(() => _helpOpen = false)),
          if (_menuOpen)
            _SakuraMenu(
              paused: _started,
              ready: _ready,
              onEnter: _enterScene,
            ),
        ],
      ),
    );
  }
}

class _SakuraMenu extends StatelessWidget {
  const _SakuraMenu({
    required this.paused,
    required this.ready,
    required this.onEnter,
  });

  final bool paused;
  final bool ready;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF3A334E);
    const paper = Color(0xFFFBF5EA);
    const red = Color(0xFFCF5C62);
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0, .48, 1],
              colors: [Color(0x7A424A70), Color(0x38DE8C97), Color(0x61F6E5DB)],
            ),
          ),
          alignment: Alignment.center,
          child: CustomPaint(
            painter: const _MenuBackdropPainter(),
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth <= 520 || constraints.maxHeight <= 570;
              final medium = !narrow && constraints.maxWidth <= 720;
              final panelWidth = math.min(medium ? 620.0 : 780.0,
                  constraints.maxWidth - (narrow ? 28 : 48));
              final artWidth = narrow
                  ? panelWidth
                  : (medium ? 132.0 : panelWidth * .78 / 2.20);
              // CSS specifies a minimum height; its two-row control strip makes
              // the intrinsic desktop card slightly taller in the start state.
              final panelHeight = narrow ? null : (medium ? 450.0 : 462.0);
              final art = SizedBox(
                width: artWidth,
                height: narrow ? 88 : panelHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: red,
                    border: Border(
                      right: narrow
                          ? BorderSide.none
                          : const BorderSide(color: ink, width: 2),
                      bottom: narrow
                          ? const BorderSide(color: ink, width: 2)
                          : BorderSide.none,
                    ),
                  ),
                  child: CustomPaint(
                    painter: const _MenuArtPainter(),
                    child: Stack(children: [
                      const Positioned(
                        left: 21,
                        top: 20,
                        child: Text('NIHONMACHI · 05:42 PM',
                            style: TextStyle(
                                color: Color(0xDBFFF8EF),
                                fontFamily: 'monospace',
                                fontSize: 10,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (!narrow)
                        const Positioned(
                          right: 17,
                          top: 18,
                          child: _VerticalText('春の日本街'),
                        )
                      else
                        const Positioned(
                          left: 22,
                          top: 39,
                          child: Text('春の日本街',
                              style: TextStyle(
                                  color: Color(0xFFFFF8EF),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3)),
                        ),
                      Positioned(
                        left: narrow ? null : (artWidth - 150) / 2,
                        right: narrow ? 8 : null,
                        top: narrow ? -31 : panelHeight! * .46 - 75,
                        child: Transform.scale(
                            scale: narrow ? .48 : (medium ? .72 : 1),
                            alignment: narrow
                                ? Alignment.centerRight
                                : Alignment.center,
                            child: const _CrossingMark()),
                      ),
                      if (!medium && !narrow)
                        const Positioned(
                          left: 22,
                          bottom: 26,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('WALK SLOWLY',
                                    style: TextStyle(
                                        color: Color(0xFFFFF8EF),
                                        fontSize: 11,
                                        letterSpacing: 1.32,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text('桜の季節',
                                    style: TextStyle(
                                        color: Color(0xFFFFF8EF),
                                        fontSize: 17,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.w800)),
                              ]),
                        ),
                    ]),
                  ),
                ),
              );
              final copy = ColoredBox(
                color: paper,
                child: CustomPaint(
                  painter: const _RuledPaperPainter(),
                  child: Padding(
                    padding: narrow
                        ? const EdgeInsets.fromLTRB(34, 26, 24, 22)
                        : medium
                            ? const EdgeInsets.fromLTRB(38, 34, 28, 27)
                            : const EdgeInsets.fromLTRB(46, 42, 46, 34),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(width: 24, height: 3, color: red),
                          const SizedBox(width: 9),
                          Text(
                              paused
                                  ? 'INTERMISSION · PAUSED'
                                  : 'A QUIET SPRING WALK',
                              style: const TextStyle(
                                  color: Color(0xFF746B82),
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 15),
                        Text('SAKURA',
                            style: TextStyle(
                                color: ink,
                                height: .9,
                                fontSize: narrow ? 35 : 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2.3)),
                        Text('CROSSING',
                            style: TextStyle(
                                color: red,
                                shadows: const [
                                  Shadow(color: ink, offset: Offset(2, 2))
                                ],
                                height: .9,
                                fontSize: narrow ? 35 : 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2.3)),
                        const SizedBox(height: 14),
                        const Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('桜踏切',
                                  style: TextStyle(
                                      color: ink,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 5.3)),
                              SizedBox(width: 12),
                              Text('SAKURA CROSSING',
                                  style: TextStyle(
                                      color: Color(0xFF7D7489),
                                      fontFamily: 'monospace',
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1)),
                            ]),
                        SizedBox(height: narrow ? 16 : 22),
                        Text(
                          paused
                              ? 'The scene is waiting where you left it. Adjust the music volume, then continue your walk when you’re ready.'
                              : '沿着樱花盛开的日本街慢慢散步。穿过铁道、商店街与河岸，\n看一座三渲二小镇在黄昏里醒来。',
                          style: const TextStyle(
                              color: Color(0xFF625B70),
                              fontSize: 13,
                              height: 1.72),
                        ),
                        SizedBox(height: narrow ? 14 : 18),
                        const Wrap(spacing: 7, runSpacing: 7, children: [
                          _Control(label: 'WASD', action: 'Move'),
                          _Control(label: 'Mouse', action: 'Look'),
                          _Control(label: 'E', action: 'Interact'),
                          _Control(label: 'Shift', action: 'Run'),
                          _Control(label: 'V', action: 'E-Bike'),
                          _Control(label: 'M', action: 'Music'),
                          _Control(label: 'C', action: 'Coordinates'),
                        ]),
                        const SizedBox(height: 20),
                        if (paused) ...[
                          const _AudioControl(),
                          const SizedBox(height: 18),
                        ],
                        if (narrow)
                          const SizedBox(height: 4)
                        else
                          const Spacer(),
                        _MenuButton(
                          enabled: ready,
                          label: ready
                              ? (paused ? 'Resume Walk' : '进入日本街')
                              : 'Building Sakura Crossing…',
                          onPressed: onEnter,
                        ),
                        if (!narrow) ...[
                          const SizedBox(height: 16),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('3D SCENE · 2D ANIMATION SPIRIT',
                                    style: _menuFootStyle),
                                Text(paused ? 'ESC TO PAUSE' : 'CLICK TO BEGIN',
                                    style: _menuFootStyle),
                              ]),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              return Container(
                width: panelWidth,
                height: panelHeight,
                decoration: BoxDecoration(
                  color: paper,
                  border: Border.all(color: ink, width: 2),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x3B3A334E), offset: Offset(10, 12)),
                    BoxShadow(
                        color: Color(0x66302B42),
                        blurRadius: 70,
                        spreadRadius: -28,
                        offset: Offset(0, 28)),
                  ],
                ),
                child: Stack(children: [
                  narrow
                      ? SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [art, copy]))
                      : Row(children: [art, Expanded(child: copy)]),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            border: Border.all(color: const Color(0x2E3A334E))),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

const _menuFootStyle = TextStyle(
    color: Color(0xFF827989),
    fontFamily: 'monospace',
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: .72);

class _Control extends StatelessWidget {
  const _Control({required this.label, required this.action});
  final String label;
  final String action;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(5, 4, 8, 4),
        decoration: BoxDecoration(
          color: const Color(0xB3FFFCF5),
          border: Border.all(color: const Color(0x383A334E)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF718BAD),
              border: Border.all(color: const Color(0xFF3A334E)),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFFFBF5EA),
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 5),
          Text(action,
              style: const TextStyle(
                  color: Color(0xFF696174),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

class _CrossingMark extends StatelessWidget {
  const _CrossingMark();
  @override
  Widget build(BuildContext context) {
    Widget bar(double angle) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 130,
            height: 23,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF3A334E), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x3D3A334E), offset: Offset(3, 4))
              ],
            ),
            child: Row(
                children: List.generate(
                    5,
                    (index) => Expanded(
                          child: ColoredBox(
                              color: index.isEven
                                  ? const Color(0xFFFFF7E9)
                                  : const Color(0xFFD76268)),
                        ))),
          ),
        );
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(alignment: Alignment.center, children: [
        bar(math.pi / 4),
        bar(-math.pi / 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
              color: const Color(0xFF3A334E),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x57FFF7E9), offset: Offset(2, 3))
              ]),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            _SignalLamp(color: Color(0xFFE77779)),
            SizedBox(width: 8),
            _SignalLamp(color: Color(0xFFF5C7B8)),
          ]),
        ),
      ]),
    );
  }
}

class _SignalLamp extends StatelessWidget {
  const _SignalLamp({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFF7E9), width: 2),
        ),
      );
}

class _VerticalText extends StatelessWidget {
  const _VerticalText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Column(
        children: text.characters
            .map((character) => Text(character,
                style: const TextStyle(
                    color: Color(0xFFFFF8EF),
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(color: Color(0x593A334E), offset: Offset(1, 1))
                    ])))
            .toList(),
      );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton(
      {required this.enabled, required this.label, required this.onPressed});
  final bool enabled;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(color: Color(0xFF3A334E), offset: Offset(5, 5))
        ]),
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 51,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color:
                    enabled ? const Color(0xFFCF5C62) : const Color(0xFFB99A9D),
                border: Border.all(color: const Color(0xFF3A334E), width: 2)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFFFFFAF0),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFFFAF0))),
                      child: const Text('→',
                          style: TextStyle(
                              color: Color(0xFFFFFAF0), fontSize: 16))),
                ]),
          ),
        ),
      );
}

class _AudioControl extends StatelessWidget {
  const _AudioControl();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: const Color(0xBDF2E5D6),
          border: Border.all(color: const Color(0xFF3A334E), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x33718BAD), offset: Offset(4, 4))
          ],
        ),
        child: const Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('♪  BACKGROUND MUSIC',
                style: TextStyle(
                    color: Color(0xFF3A334E),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3)),
            Text('34%',
                style: TextStyle(
                    color: Color(0xFF746B82),
                    fontFamily: 'monospace',
                    fontSize: 11)),
          ]),
          SizedBox(height: 8),
          _VolumeTrack(),
        ]),
      );
}

class _VolumeTrack extends StatelessWidget {
  const _VolumeTrack();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 20,
        child: Stack(alignment: Alignment.centerLeft, children: [
          Container(
              height: 6,
              decoration: BoxDecoration(
                  color: const Color(0xFFDDD4CA),
                  border: Border.all(color: const Color(0xFF3A334E)))),
          FractionallySizedBox(
              widthFactor: .34,
              child: Container(height: 4, color: const Color(0xFFCF5C62))),
          const Positioned(
              left: 96,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(0xFFFBF5EA),
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                        BorderSide(color: Color(0xFF3A334E), width: 2))),
                child: SizedBox(width: 17, height: 17),
              )),
        ]),
      );
}

class _MenuArtPainter extends CustomPainter {
  const _MenuArtPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stripe = Paint()..color = const Color(0x29FFF6E8);
    for (double x = -size.height; x < size.width + size.height; x += 36) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0),
          stripe..strokeWidth = 2);
    }
    canvas.save();
    canvas.translate(-size.width * .28, size.height - 44);
    canvas.rotate(-8 * math.pi / 180);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 1.5, 142),
        Paint()..color = const Color(0xFF6F88A9));
    canvas.drawLine(
        Offset.zero,
        Offset(size.width * 1.5, 0),
        Paint()
          ..color = const Color(0xFF3A334E)
          ..strokeWidth = 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MenuBackdropPainter extends CustomPainter {
  const _MenuBackdropPainter();
  @override
  void paint(Canvas canvas, Size size) {
    void dots(double tileW, double tileH, double ox, double oy, double radius,
        Color color) {
      final paint = Paint()..color = color;
      for (double x = ox; x < size.width + tileW; x += tileW) {
        for (double y = oy; y < size.height + tileH; y += tileH) {
          canvas.drawCircle(Offset(x, y), radius, paint);
        }
      }
    }

    dots(92, 86, 11, 14, 2, const Color(0x9EFFF5EE));
    dots(138, 126, 113, 30, 3, const Color(0xA3FFD5DB));
    dots(108, 116, 80, 95, 2, const Color(0x94FFF4EB));
    dots(154, 142, 37, 108, 2, const Color(0x8AFFCFD8));

    final diameter = math.max(420.0, size.width * .42);
    final center = Offset(size.width + diameter * .32, -diameter * .05);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x24463E5B);
    canvas.drawCircle(center, diameter / 2, ring);
    ring
      ..strokeWidth = 34
      ..color = const Color(0x14FFF4EB);
    canvas.drawCircle(center, diameter / 2 + 18, ring);
    ring
      ..strokeWidth = 36
      ..color = const Color(0x0FD16D78);
    canvas.drawCircle(center, diameter / 2 + 70, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RuledPaperPainter extends CustomPainter {
  const _RuledPaperPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x1F718BAD)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRect(Rect.fromLTWH(28, 0, 1, size.height),
        Paint()..color = const Color(0x40CF5C62));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
