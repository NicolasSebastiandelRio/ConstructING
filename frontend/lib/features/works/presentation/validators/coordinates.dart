/// Validación del ancla geográfica de la obra (CU-15).
///
/// Las coordenadas manuales (flujo alterno 2.2: marcado manual cuando no hay
/// geocodificación automática) deben ser numéricas y estar dentro de los
/// rangos geográficos válidos: latitud -90..90, longitud -180..180.
class Coordinates {
  static const double minLatitude = -90;
  static const double maxLatitude = 90;
  static const double minLongitude = -180;
  static const double maxLongitude = 180;

  static const String latitudeError =
      'La latitud debe ser un número entre -90 y 90.';
  static const String longitudeError =
      'La longitud debe ser un número entre -180 y 180.';

  /// Valida el texto ingresado como latitud. El campo vacío se considera
  /// válido porque las coordenadas son opcionales al crear la obra.
  static String? validateLatitude(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed == null || parsed < minLatitude || parsed > maxLatitude) {
      return latitudeError;
    }
    return null;
  }

  /// Valida el texto ingresado como longitud (mismas reglas que latitud).
  static String? validateLongitude(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed == null || parsed < minLongitude || parsed > maxLongitude) {
      return longitudeError;
    }
    return null;
  }

  /// Parsea el texto a double aceptando coma decimal; retorna null si vacío.
  static double? parseOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
}