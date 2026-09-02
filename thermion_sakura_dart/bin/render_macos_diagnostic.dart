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
  stdout.writeln('wrote ' + path);
}

Future<Uint8List> _capture(
    FFIFilamentApp app, SwapChain swapChain, View view) async {
  for (var frame = 0; frame < 2; frame++) {
    await app.capture(swapChain,
        view: view,
        pixelDataFormat: PixelDataFormat.RGBA,
        pixelDataType: PixelDataType.FLOAT);
  }
  final result = await app.capture(swapChain,
      view: view,
      pixelDataFormat: PixelDataFormat.RGBA,
      pixelDataType: PixelDataType.FLOAT);
  return result.first.$2;
}

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    stderr.writeln('This diagnostic is intended for macOS/Metal.');
    exitCode = 64;
    return;
  }

  const width = 1600, height = 900;
  final prefix = arguments.isEmpty ? '/tmp/sakura_macos' : arguments.first;
  await FFIFilamentApp.create(
      config: FFIFilamentConfig(backend: Backend.METAL));
  final app = FilamentApp.instance! as FFIFilamentApp;
  final swapChain = await app.createHeadlessSwapChain(width, height);
  final viewer = ThermionViewerFFI(app: app);
  await viewer.initialized;
  await viewer.view.setViewport(width, height);
  await app.renderManager.attach(viewer.view, swapChain);

  final outputColor = await app.createTexture(width, height,
      flags: {
        TextureUsage.TEXTURE_USAGE_COLOR_ATTACHMENT,
        TextureUsage.TEXTURE_USAGE_SAMPLEABLE,
        TextureUsage.TEXTURE_USAGE_BLIT_SRC,
      },
      textureFormat: TextureFormat.RGBA32F);
  final outputDepth = await app.createTexture(width, height,
      flags: {TextureUsage.TEXTURE_USAGE_DEPTH_ATTACHMENT},
      textureFormat: TextureFormat.DEPTH32F);
  final outputTarget = await app.createRenderTarget(width, height,
      color: outputColor, depth: outputDepth);
  await viewer.view.setRenderTarget(outputTarget);

  final scene = await SakuraApp.create(viewer);
  final sceneBytes = await _capture(app, swapChain, viewer.view);
  await _writeCapturePng(sceneBytes, width, height, prefix + '.scene.png');
  final finalBytes = await _capture(app, swapChain, scene.outputView);
  await File(prefix + '.final.rgba32f').writeAsBytes(finalBytes);
  await _writeCapturePng(finalBytes, width, height, prefix + '.final.png');
  exit(0);
}
