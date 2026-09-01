import 'dart:io';
import 'dart:typed_data';

Uint8List decodeHillSurface(Uint8List compressed) =>
    Uint8List.fromList(ZLibDecoder().convert(compressed));
