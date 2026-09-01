import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    stderr.writeln(
      'This diagnostic is intended for macOS/Metal. Use render_post.dart '
      'directly on other platforms.',
    );
    exitCode = 64;
    return;
  }

  String prefix = '/tmp/sakura_macos';
  final forwarded = <String>[];
  for (final argument in arguments) {
    if (!argument.startsWith('--') && prefix == '/tmp/sakura_macos') {
      prefix = argument;
    } else {
      forwarded.add(argument);
    }
  }

  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      'bin/render_post.dart',
      '--capture-prefix=$prefix',
      '--output=$prefix.final.rgba32f',
      ...forwarded,
    ],
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    exitCode = code;
    return;
  }

  stdout.writeln('macOS diagnostic captures:');
  stdout.writeln('  $prefix.shadow.png  light-space caster pass');
  stdout.writeln('  $prefix.scene.png   scene before post-processing');
  stdout.writeln('  $prefix.final.png   final post-processed image');
}
