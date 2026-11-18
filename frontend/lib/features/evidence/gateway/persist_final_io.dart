import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// Versión móvil/desktop: escribe los bytes estampados como archivo hermano
/// del temporal del picker (mismo directorio de caché de la app) y devuelve
/// la ruta definitiva del caché.
Future<String> writeSiblingFile(
  Uint8List bytes,
  String originalPath,
) async {
  final original = File(originalPath);
  final dir = original.parent.path;
  final out = File('$dir/${const Uuid().v4()}.jpg');
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}

/// No aplicable en móvil/desktop (se usa la variante de archivo); nunca se
/// invoca porque `persistFinal` redirige por `kIsWeb`.
Future<String> createBlobUrlFromBytes(Uint8List bytes) async {
  throw UnsupportedError('persistFinal por blob no existe fuera de web');
}
