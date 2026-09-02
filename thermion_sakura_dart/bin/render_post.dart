// Headless command-line host for the shared maximum-fidelity SakuraApp.
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:thermion_dart/thermion_dart.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_sakura_dart/thermion_sakura_dart.dart';

Future<void> _writeCapturePng(
    Uint8List bytes, int width, int height, String path) async {
  final pixels = Float32List.view(
      bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
  final output = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      int channel(int index) =>
          (pixels[offset + index].clamp(0.0, 1.0) * 255).round();
      output.setPixelRgba(x, y, channel(0), channel(1), channel(2), channel(3));
    }
  }
  await File(path).writeAsBytes(img.encodePng(output));
  stdout.writeln('wrote $path');
}

String? _argumentValue(List<String> arguments, String name) {
  final prefix = '--$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) return argument.substring(prefix.length);
  }
  return null;
}

Future<void> main(List<String> arguments) async {
  final backend = Platform.isMacOS ? Backend.METAL : Backend.OPENGL;
  stdout.writeln('backend: ${backend.name}');
  await FFIFilamentApp.create(config: FFIFilamentConfig(backend: backend));
  final app = FilamentApp.instance! as FFIFilamentApp;

  const width = 1600, height = 900;
  final swapChain = await app.createHeadlessSwapChain(width, height);
  final viewer = ThermionViewerFFI(app: app);
  await viewer.initialized;
  await viewer.view.setViewport(width, height);
  await app.renderManager.attach(viewer.view, swapChain);

  final sakura = await SakuraApp.create(
    viewer,
    arguments: arguments,
    runtimeAnimations: arguments.contains('--runtime-animations'),
    groundedCamera: arguments.contains('--grounded-camera'),
  );
  final scene = await sakura.captureScene();
  await File('/tmp/sakura_post_scene.bin').writeAsBytes(scene);

  final capturePrefix = _argumentValue(arguments, 'capture-prefix');
  if (capturePrefix != null) {
    await _writeCapturePng(
        scene, sakura.width, sakura.height, '$capturePrefix.scene.png');
  }

  final pixels = await sakura.captureFinal();
  final debugMode = arguments.any((arg) => arg.startsWith('--debug-'));
  final inkEnabled = !arguments.contains('--no-ink');
  final output = _argumentValue(arguments, 'output') ??
      (debugMode
          ? '/tmp/sakura_post_debug.bin'
          : inkEnabled
              ? '/tmp/sakura_post.bin'
              : '/tmp/sakura_post_noink.bin');
  await File(output).writeAsBytes(pixels);
  if (capturePrefix != null) {
    await _writeCapturePng(
        pixels, sakura.width, sakura.height, '$capturePrefix.final.png');
  }
  stdout.writeln('wrote $output (live-graded)');
  stdout.writeln('SIZE ${sakura.width} ${sakura.height}');
  exit(0);
}
