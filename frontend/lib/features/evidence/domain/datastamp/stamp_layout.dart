import 'dart:math' as math;

/// CU-36: dimensionado de la marca de agua respecto de la imagen.
///
/// Cómputo puro y testeable (sin canvas) para que la marca nunca tape la
/// evidencia: antes el tamaño de fuente estaba fijo (24 px en web), así que
/// una foto recortada —más chica— quedaba cubierta por el texto.
abstract final class StampLayout {
  /// Fracción máxima del alto que puede ocupar la banda de la marca.
  static const double maxBandFraction = 0.45;

  /// Tope de legibilidad: ni microscópico en fotos enormes ni gigante en
  /// recortes chicos.
  static const double minFontSize = 9.0;
  static const double maxFontSize = 40.0;

  /// Tamaño de fuente proporcional al LADO MENOR de la imagen.
  static double fontSizeFor(int width, int height) {
    final base = math.min(width, height).toDouble();
    return (base * 0.042).clamp(minFontSize, maxFontSize);
  }

  /// Margen interno proporcional (usado para el ancho útil del texto).
  static double paddingFor(int width, int height) {
    final base = math.min(width, height).toDouble();
    return (base * 0.022).clamp(4.0, 22.0);
  }

  /// Alto máximo que puede ocupar la banda de la marca.
  static double maxBandHeight(int height) => height * maxBandFraction;

  /// ¿El texto entra en el alto permitido de banda?
  static bool fits({required double textHeight, required int height}) =>
      textHeight <= maxBandHeight(height);
}
