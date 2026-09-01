import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:thermion_dart/src/bindings/src/thermion_dart_js_interop.g.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/thermion_dart.dart' hide NativeLibrary, Image_decode;
import 'package:vector_math/vector_math_64.dart';
import 'package:web/web.dart';

import 'package:thermion_sakura/src/palette.dart';
import 'package:thermion_sakura/src/scene.dart';

Future<void> main() async {
  try {
    await _boot();
  } catch (e, s) {
    final err = document.getElementById('error');
    if (err != null) {
      err.textContent = '$e\n$s';
      (err as HTMLElement).style.display = 'block';
    }
  }
}

void _setLoading(String text) {
  final t = document.getElementById('loading-text');
  if (t != null) t.textContent = text;
}

Vector3 _forward(double yaw, double pitch) {
  final cp = math.cos(pitch);
  return Vector3(-math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp);
}

Future<void> _boot() async {
  Logger.root.onRecord.listen((r) => print(r));

  // Load the Emscripten module that index.html placed on window.thermion_dart.
  NativeLibrary.initBindings('thermion_dart');

  final canvas = document.getElementById("thermion_canvas") as HTMLCanvasElement;
  var w = canvas.clientWidth;
  var h = canvas.clientHeight;
  if (w == 0) w = window.innerWidth;
  if (h == 0) h = window.innerHeight;
  canvas.width = w;
  canvas.height = h;

  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: Backend.OPENGL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final viewer = ThermionViewerFFI(app: app);
  await viewer.initialized;

  var swapChain = await app.createHeadlessSwapChain(w, h);
  await app.renderManager.attach(viewer.view, swapChain);
  await viewer.view.setViewport(w, h);

  // Sky/fog colour as the clear, so the frame is never black before the world
  // draws. Matches the reference's PAL.fog clear.
  final fog = C.srgb(Pal.fog);
  await app.setClearOptions(fog.x, fog.y, fog.z, 1.0);

  // Linear tone mapping: we baked cel colours in display space and want them to
  // pass through unchanged into the output, so disable ACES/grading.
  await viewer.setToneMapper(await ToneMapper.linear(app));
  await viewer.setBloom(false, 0);
  // FXAA cleans the flat-shaded edges (reference post.js FXAA pass).
  await viewer.view.setPostProcessing(true);
  await viewer.setAntiAliasing(false, true, false);
  // Atmospheric fog (reference: THREE.Fog(PAL.fog, 44, 205)) — exponential
  // start at the reference's clear distance.
  // Distance fog is baked into the world geometry (see Mesh._emit), matching
  // the reference's THREE.Fog(44, 205); the real pipeline fog is off so the
  // sky dome and clouds keep their painted colours.
  await viewer.view.setFogOptions(FogOptions(
    enabled: false,
    linearColor: C.srgb(Pal.fog),
    distance: 44,
    density: 0.013,
    maximumOpacity: 0.95,
  ));

  // Camera at the reference spawn, FOV 46° (vertical).
  final camera = await viewer.getActiveCamera();
  final focal = 12.0 / math.tan(fovDeg * math.pi / 180 * 0.5);
  await camera.setLensProjection(near: 0.25, far: 600, aspect: w / h, focalLength: focal);

  final eye = Vector3(spawnPos.x, eyeHeight, spawnPos.z);
  final fwd = _forward(spawnYaw, spawnPitch);
  final target = eye + fwd;
  // View matrix = inverse of the camera model matrix; the web gallery builds
  // the model matrix from look-at and inverts it.
  await camera.setModelMatrix(makeViewMatrix(eye, target, Vector3(0, 1, 0))..invert());
  final mm = await camera.getModelMatrix();
  final pm = await camera.getProjectionMatrix();
  print('camera model: ${mm.storage.take(12).toList()}');
  print('camera proj : ${pm.storage.take(12).toList()}');

  _setLoading('Building the world…');
  final world = await buildWorld(viewer, app);

  _setLoading('Starting render loop…');

  // Start overlay dismiss — the world is already rendering behind it.
  final overlay = document.getElementById('overlay')! as HTMLElement;
  final startBtn = document.getElementById('start-btn');
  final crosshair = document.getElementById('crosshair')!;
  void dismiss(Event _) {
    overlay.className = 'overlay hidden';
    crosshair.className = 'crosshair on';
  }
  startBtn?.addEventListener('click', dismiss.toJS);
  overlay.addEventListener('click', (Event e) {
    final t = e.target;
    if (t is HTMLElement && t.id != 'start-btn') dismiss(e);
  }.toJS);

  // Debounced resize: rebuild the swapchain at the new canvas size.
  Timer? resizeTimer;
  window.addEventListener('resize', (Event _) {
    resizeTimer?.cancel();
    resizeTimer = Timer(const Duration(milliseconds: 150), () async {
      try {
        final nw = canvas.clientWidth;
        final nh = canvas.clientHeight;
        if (nw == 0 || nh == 0) return;
        await app.renderManager.detach(viewer.view);
        await app.destroySwapChain(swapChain);
        swapChain = await app.createHeadlessSwapChain(nw, nh);
        await app.renderManager.attach(viewer.view, swapChain);
        await viewer.view.setViewport(nw, nh);
        await camera.setLensProjection(
          near: 0.25, far: 600, aspect: nw / nh, focalLength: focal);
      } catch (e) {
        print('resize failed: $e');
      }
    });
  }.toJS);

  // Render loop. On web FILAMENT_SINGLE_THREADED is true, so render() is
  // fire-and-forget and the C++ worker drives the rAF loop; this pump only
  // requests a render.
  var firstFrame = true;
  void pump(num _) {
    app.render();
    if (firstFrame) {
      firstFrame = false;
      (document.getElementById('loading') as HTMLElement).setAttribute('hidden', '');
    }
    window.requestAnimationFrame(pump.toJS);
  }

  window.requestAnimationFrame(pump.toJS);
  // touch world so the analyzer doesn't warn about an unused value
  // ignore: unnecessary_statements
  world;
}
