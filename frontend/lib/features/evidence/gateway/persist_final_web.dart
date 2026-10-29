import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Versión web: regenera una `blob:` URL nueva con los bytes estampados.
/// (Las blob: URLs del picker viven solo durante la sesión actual.)
Future<String> createBlobUrlFromBytes(Uint8List bytes) async {
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/jpeg'),
  );
  return web.URL.createObjectURL(blob);
}

/// No aplicable en web (se usa la variante blob); nunca se invoca porque
/// `persistFinal` redirige por [kIsWeb].
Future<String> writeSiblingFile(Uint8List bytes, String originalPath) async {
  throw UnsupportedError('persistFinal por archivo no existe en web');
}
