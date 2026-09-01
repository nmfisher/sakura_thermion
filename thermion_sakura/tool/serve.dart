// Local dev server for Sakura Crossing. Serves web/ with the cross-origin
// isolation headers the multithreaded Emscripten build needs (SharedArrayBuffer).
//
//   dart run tool/serve.dart [--port 8080]
//
// Then open http://localhost:8080/ in Chrome.
import 'dart:io';

void main(List<String> args) async {
  final portArg = args.cast<String?>().firstWhere(
    (a) => a != null && a.startsWith('--port='),
    orElse: () => null,
  );
  final port = portArg == null
      ? 8080
      : int.parse(portArg.substring('--port='.length));
  final webDir = Directory('web');
  if (!webDir.existsSync()) {
    stderr.writeln('No web/ directory found; run from thermion_sakura root.');
    exit(1);
  }

  const isolatedHeaders = {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'cross-origin',
    'Cache-Control': 'no-store',
  };

  final mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.mjs': 'application/javascript; charset=utf-8',
    '.wasm': 'application/wasm',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.glb': 'model/gltf-binary',
    '.ktx': 'image/ktx',
    '.ktx2': 'image/ktx2',
    '.filamat': 'application/octet-stream',
    '.css': 'text/css; charset=utf-8',
  };

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('Serving ${webDir.path} with COOP/COEP on http://localhost:$port');
  await for (final request in server) {
    final requested =
        request.uri.path == '/' ? '/index.html' : request.uri.path;
    final file = File(
      '${webDir.absolute.path}${requested.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync() ||
        !file.absolute.path.startsWith(webDir.absolute.path)) {
      request.response.statusCode = HttpStatus.notFound;
      isolatedHeaders.forEach((k, v) => request.response.headers.add(k, v));
      await request.response.close();
      continue;
    }
    final ext = file.path.substring(file.path.lastIndexOf('.'));
    request.response.headers.contentType =
        ContentType.parse(mime[ext] ?? 'application/octet-stream');
    isolatedHeaders.forEach((k, v) => request.response.headers.add(k, v));
    await file.openRead().pipe(request.response);
  }
}
