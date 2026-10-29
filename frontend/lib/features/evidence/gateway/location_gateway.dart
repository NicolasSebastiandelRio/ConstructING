import 'package:geolocator/geolocator.dart';

/// Posición del dispositivo leída por CU-34 (RF_04).
class DevicePosition {
  final double latitud;
  final double longitud;

  /// Precisión reportada por el sensor GPS en metros (paso 4).
  final double precisionMetros;

  const DevicePosition({
    required this.latitud,
    required this.longitud,
    required this.precisionMetros,
  });
}

/// Excepción de geolocalización (CU-34 Alt. 4.1/4.2): falla la triangulación
/// por falta de señal o hardware apagado y obliga al CU-32/33 a abortar.
class GeolocationException implements Exception {
  final String message;

  const GeolocationException(this.message);

  @override
  String toString() => message;
}

/// Gateway del sensor GPS (CU-34: RF_04).
///
/// Solicita las coordenadas actuales en el momento de la captura (paso 1)
/// con timeout de 5 s (paso 3) y retorna latitud, longitud y precisión
/// (paso 4). Inyectable para tests.
abstract class LocationGateway {
  Future<DevicePosition> getCurrentPosition({Duration timeout});
}

/// Implementación de producción sobre el sensor del OS.
class GeolocatorLocationGateway implements LocationGateway {
  const GeolocatorLocationGateway();

  @override
  Future<DevicePosition> getCurrentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const GeolocationException(
          'El GPS del dispositivo está apagado. Actívelo para certificar la evidencia.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        throw const GeolocationException(
          'Debe otorgar permisos de ubicación para continuar.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      ).timeout(timeout);
      return DevicePosition(
        latitud: position.latitude,
        longitud: position.longitude,
        precisionMetros: (position.accuracy as num).toDouble(),
      );
    } on GeolocationException {
      rethrow;
    } on Exception {
      throw const GeolocationException(
        'No se pudo obtener la ubicación del dispositivo (sin señal GPS).',
      );
    }
  }
}
