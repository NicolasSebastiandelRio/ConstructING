/// RF_03 (ajuste post-MVP): validación del archivo de evidencia antes de
/// procesarlo.
///
/// La captura acepta únicamente imágenes **JPG/JPEG**. Se valida por
/// CONTENIDO —la firma del archivo— y no por la extensión: un PNG renombrado
/// a `.jpg` también se rechaza, y un JPEG sin extensión (habitual en las
/// `blob:` URL del navegador) se acepta.
///
/// Antes, un PNG llegaba al pipeline de edición/estampado y fallaba de forma
/// no controlada al re-encodear la evidencia.
abstract final class EvidenceFileValidator {
  /// Mensaje mostrado al usuario cuando el archivo no es JPG/JPEG.
  static const String notJpegMessage =
      'Formato no admitido: solo se permiten imágenes JPG o JPEG.';

  /// Mensaje cuando el archivo está vacío o no se pudo leer.
  static const String emptyMessage =
      'El archivo seleccionado está vacío o no se pudo leer.';

  /// Firma JPEG: todo JPG/JPEG válido arranca con SOI (FF D8) y el primer
  /// marcador (FF).
  static const List<int> jpegSignature = [0xFF, 0xD8, 0xFF];

  /// ¿Los bytes corresponden a una imagen JPEG?
  static bool esJpeg(List<int> bytes) {
    if (bytes.length < jpegSignature.length) return false;
    for (var i = 0; i < jpegSignature.length; i++) {
      if (bytes[i] != jpegSignature[i]) return false;
    }
    return true;
  }

  /// Devuelve el mensaje de rechazo, o `null` si el archivo es utilizable.
  ///
  /// [path] se acepta por completitud del contrato (diagnóstico), pero la
  /// decisión es por contenido.
  static String? rechazo(List<int> bytes, {String? path}) {
    if (bytes.isEmpty) return emptyMessage;
    if (!esJpeg(bytes)) return notJpegMessage;
    return null;
  }
}
