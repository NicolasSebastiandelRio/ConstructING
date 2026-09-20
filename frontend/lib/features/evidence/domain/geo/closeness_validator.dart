import 'dart:math' as math;

/// Resultado de la validación de cercanía (CU-35).
class DistanceCheck {
  /// Distancia radial calculada entre el dispositivo y el ancla de la obra.
  final double distanciaMetros;

  /// Radio perimetral admitido (margen de error permitido).
  final double radioMetros;

  const DistanceCheck({
    required this.distanciaMetros,
    required this.radioMetros,
  });

  /// Paso 4: la distancia debe ser menor al margen de error permitido.
  bool get allowed => distanciaMetros < radioMetros;
}

/// CU-35 (Validar Cercanía al punto de Obra, RF_03/RF_04).
///
/// Calcula la distancia radial en metros entre las coordenadas actuales del
/// dispositivo y las coordenadas ancla de la obra (CU-15) mediante la
/// Fórmula de Haversine (paso 2), y verifica que sea menor al radio
/// perimetral (paso 4).
///
/// Sin ancla de obra registrada la validación falla cerrado (no hay fehaica
/// geográfica confirmable).
class ClosenessValidator {
  /// Radio perimetral por defecto: margen de error admitido para la
  /// captura dentro del terreno oficial.
  static const double defaultRadiusMeters = 200.0;

  /// Mensaje exacto del Alt. 4.2 de la especificación.
  static const String outsideMessage =
      'Se encuentra fuera de los límites de la obra';

  /// Fórmula de Haversine (paso 2): distancia esférica en metros entre
  /// dos pares lat/long en grados.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// CU-35 flujo normal: `true` si el dispositivo está dentro del radio.
  /// Si el ancla de la obra no existe (CU-15 sin coordenadas) deniega.
  static DistanceCheck check({
    required double latitudDispositivo,
    required double longitudDispositivo,
    required double? latitudObra,
    required double? longitudObra,
    double radiusMeters = defaultRadiusMeters,
  }) {
    if (latitudObra == null || longitudObra == null) {
      // Sin ancla no se puede confirmar la fehaica: falla cerrado.
      return DistanceCheck(
        distanciaMetros: double.infinity,
        radioMetros: radiusMeters,
      );
    }
    final distance = distanceMeters(
      latitudDispositivo,
      longitudDispositivo,
      latitudObra,
      longitudObra,
    );
    return DistanceCheck(
      distanciaMetros: distance,
      radioMetros: radiusMeters,
    );
  }

  static double _degToRad(double degrees) => degrees * math.pi / 180.0;
}
