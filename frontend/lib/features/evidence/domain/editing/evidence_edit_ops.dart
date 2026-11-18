import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Resultado de una operación de edición: los bytes nuevos más el tamaño en
/// píxeles de la imagen resultante (la UI lo necesita para mapear el recorte).
class EditedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const EditedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Edición de la evidencia fotográfica: giro y recorte (RF_03).
///
/// Cómputo puro sobre el binario —sin UI ni plugins— para poder ejecutarse en
/// un isolate (RNF_E_01) y testearse sin dispositivo. Siempre se parte de los
/// bytes ORIGINALES para no acumular pérdida por recompresión: el giro y el
/// recorte se aplican en una sola pasada al confirmar.
abstract final class EvidenceEditOps {
  /// Calidad de salida del JPEG editado (coherente con la captura, 88).
  static const int defaultQuality = 88;

  /// Decodifica los bytes; null si el formato no es procesable.
  ///
  /// `decodeImage` puede LANZAR con archivos corruptos o con cabeceras que
  /// algún decodificador (p. ej. PSD) intenta leer fuera de rango; el editor
  /// no debe romperse por una imagen inválida, así que se degrada a null.
  static img.Image? _decode(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Gira la imagen [quarterTurns] × 90° en sentido horario y la reencoda.
  ///
  /// Se usa para la vista previa del editor (una generación de pérdida como
  /// máximo, porque el giro definitivo se hace desde el original).
  static EditedImage? rotate(
    Uint8List bytes,
    int quarterTurns, {
    int quality = defaultQuality,
  }) {
    final decoded = _decode(bytes);
    if (decoded == null) return null;
    final girada = _aplicarGiro(decoded, quarterTurns);
    return EditedImage(
      bytes: Uint8List.fromList(img.encodeJpg(girada, quality: quality)),
      width: girada.width,
      height: girada.height,
    );
  }

  /// Aplica giro + recorte en una sola pasada sobre el original.
  ///
  /// [x], [y], [width] y [height] describen el área a conservar, en píxeles y
  /// relativa a la imagen YA girada (que es la que el usuario ve en el
  /// editor).
  static EditedImage? rotateAndCrop({
    required Uint8List original,
    required int quarterTurns,
    required int x,
    required int y,
    required int width,
    required int height,
    int quality = defaultQuality,
  }) {
    final decoded = _decode(original);
    if (decoded == null) return null;
    final girada = _aplicarGiro(decoded, quarterTurns);

    // Recorte defensivo: nunca fuera de los límites ni con área nula.
    final rx = x.clamp(0, girada.width - 1);
    final ry = y.clamp(0, girada.height - 1);
    final ancho = width.clamp(1, girada.width - rx);
    final alto = height.clamp(1, girada.height - ry);

    final recortada = img.copyCrop(
      girada,
      x: rx,
      y: ry,
      width: ancho,
      height: alto,
    );
    return EditedImage(
      bytes: Uint8List.fromList(img.encodeJpg(recortada, quality: quality)),
      width: recortada.width,
      height: recortada.height,
    );
  }

  /// Normaliza el giro a 0..3 y lo aplica (sentido horario).
  static img.Image _aplicarGiro(img.Image imagen, int quarterTurns) {
    final vueltas = quarterTurns % 4;
    if (vueltas == 0) return imagen;
    return img.copyRotate(imagen, angle: vueltas * 90);
  }
}
