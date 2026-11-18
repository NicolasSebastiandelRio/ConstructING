import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// CU-54 paso 4 (web): dispara la descarga del navegador del PDF del acta
/// (blob + anclaje con atributo download). El navegador la guarda en la
/// carpeta de descargas del usuario; se devuelve el nombre del archivo.
Future<String> saveActaFile({
  required Uint8List bytes,
  required String fileName,
  String? directoryOverride,
}) async {
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return fileName;
}

/// En web no hay caché de archivos local para el acta: la búsqueda local
/// no aplica y el flujo va directo al servidor central (paso 2).
Future<Uint8List?> readLocalActa({
  required String hitoId,
  String? directoryOverride,
}) async => null;
