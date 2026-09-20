/// CU-38 (Validar Límite de tamaño y duración, RNF_E_06).
///
/// Controla que el video no exceda las cuotas máximas de peso (<15 MB) y
/// duración (<30 s) antes de autorizar su persistencia local (CU-42).
///
/// Prevención doble: el gateway de captura limita la grabación a
/// [maxDurationSeconds] y este validador comprueba el archivo procesado
/// (paso 2: peso en MB + duración en segundos del metadato).
class VideoLimitValidator {
  static const int maxSizeBytes = 15 * 1024 * 1024; // <15 MB
  static const int maxDurationSeconds = 30; // <30 s

  /// Mensaje exacto del Alt. 4.2 de la especificación.
  static const String exceededMessage =
      'El video supera los 30 segundos o 15 MB permitidos';

  /// Retorna null si el archivo está autorizado para persistencia local
  /// (paso 4: True) o el mensaje de la spec si excede el límite (Alt. 4.2).
  ///
  /// [durationSeconds] nulo se trata como cumplimiento (duración desconocida
  /// en el metadato disponible); el gateway ya acotó la grabación a 30 s.
  static String? validate({
    required int sizeBytes,
    double? durationSeconds,
  }) {
    if (sizeBytes > maxSizeBytes) {
      return exceededMessage;
    }
    if (durationSeconds != null && durationSeconds >= maxDurationSeconds) {
      return exceededMessage;
    }
    return null;
  }
}
