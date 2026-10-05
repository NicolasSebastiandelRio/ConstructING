import '../entities/signature_stroke.dart';

/// Resultado de la validación del trazo (CU-52 Alt. 2.1).
class SignatureStrokeCheck {
  final bool allowed;
  final String? reason;

  const SignatureStrokeCheck.allowed()
      : allowed = true,
        reason = null;

  const SignatureStrokeCheck.denied(this.reason) : allowed = false;
}

/// Guard de firma manuscrita (CU-52, RF_05 + RNF_U_05).
///
/// Valida en el paso 2 del CU-52 que el trazo realizado supere la longitud
/// mínima permitida: descarta firmas inválidas y puntos accidentales. Ante
/// rechazo, el sistema ejecuta el CU-53 (Limpiar Trazo), pide reintentar y
/// bloquea la confirmación.
class SignatureStrokeValidator {
  /// Longitud mínima total de la firma, en píxeles lógicos.
  static const double minLengthPx = 120.0;

  /// Mensaje para el Alt. 2.2: pide reintentar tras limpiar el lienzo.
  static const String invalidStrokeMessage =
      'Firma inválida o punto accidental: limpie el lienzo y vuelva a trazar su firma.';

  static SignatureStrokeCheck validate({
    required List<SignatureStroke> strokes,
    double minLengthPx = SignatureStrokeValidator.minLengthPx,
  }) {
    final total =
        strokes.fold<double>(0.0, (sum, stroke) => sum + stroke.lengthPx);
    if (total < minLengthPx) {
      return const SignatureStrokeCheck.denied(invalidStrokeMessage);
    }
    return const SignatureStrokeCheck.allowed();
  }
}
