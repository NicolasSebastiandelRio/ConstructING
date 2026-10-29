/// RF_03 (ajuste post-MVP): validación y normalización del archivo de
/// evidencia.
///
/// La evidencia final SIEMPRE queda en **JPG/JPEG**. Si el usuario elige una
/// imagen en otro formato —típico en el celular, donde las capturas de
/// pantalla son PNG— no se rechaza: se **convierte** automáticamente a JPEG
/// antes de estampar la marca (ver `EvidenceEditOps`). Solo se rechaza lo que
/// no es una imagen procesable (archivo vacío o binario inválido).
///
/// La detección es por CONTENIDO (firma JPEG), no por extensión: un PNG
/// renombrado a `.jpg` se detecta igual, y un JPEG sin extensión (habitual en
/// las `blob:` URL del navegador) se acepta sin conversión.
abstract final class EvidenceFileValidator {
  /// Mensaje cuando el archivo está vacío o no se pudo leer.
  static const String emptyMessage =
      'El archivo seleccionado está vacío o no se pudo leer.';

  /// Mensaje cuando el contenido no es una imagen que se pueda procesar.
  static const String notImageMessage =
      'El archivo seleccionado no es una imagen válida.';

  /// Firma JPEG: todo JPG/JPEG válido arranca con SOI (FF D8) y el primer
  /// marcador (FF).
  static const List<int> jpegSignature = [0xFF, 0xD8, 0xFF];

  /// ¿Los bytes corresponden ya a una imagen JPEG?
  static bool esJpeg(List<int> bytes) {
    if (bytes.length < jpegSignature.length) return false;
    for (var i = 0; i < jpegSignature.length; i++) {
      if (bytes[i] != jpegSignature[i]) return false;
    }
    return true;
  }

  /// Motivo por el que el archivo no puede usarse ni convirtiéndolo.
  ///
  /// Devuelve `null` cuando hay contenido para intentar la conversión: el
  /// formato se resuelve después, decodificando la imagen.
  static String? rechazo(List<int> bytes, {String? path}) {
    if (bytes.isEmpty) return emptyMessage;
    return null;
  }
}
