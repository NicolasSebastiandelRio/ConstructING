import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/domain/geo/closeness_validator.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';

/// CU-34/CU-35: modelo de posición y validación de cercanía (RF_04).
void main() {
  group('CU-34 - DevicePosition', () {
    test('retorna latitud, longitud y precisión en metros (paso 4)', () {
      const position = DevicePosition(
        latitud: -34.6037,
        longitud: -58.3816,
        precisionMetros: 5.0,
      );
      expect(position.latitud, -34.6037);
      expect(position.longitud, -58.3816);
      expect(position.precisionMetros, 5.0);
    });
  });

  group('CU-35 - Validar Cercanía al punto de Obra (Haversine)', () {
    test('paso 2: distancia radial conocida (1° de latitud ≈ 111 km)', () {
      final distance = ClosenessValidator.distanceMeters(0, 0, 1, 0);
      expect(distance, closeTo(111195, 500));
    });

    test('misma posición → distancia 0 y autorizado (paso 4: True)', () {
      final check = ClosenessValidator.check(
        latitudDispositivo: -34.6037,
        longitudDispositivo: -58.3816,
        latitudObra: -34.6037,
        longitudObra: -58.3816,
      );
      expect(check.distanciaMetros, closeTo(0, 1));
      expect(check.allowed, isTrue);
    });

    test('dentro del radio perimetral autoriza (Flujo Normal)', () {
      // ~111 m ≈ 0.001° de latitud (dentro del radio de 200 m).
      final check = ClosenessValidator.check(
        latitudDispositivo: -34.6047,
        longitudDispositivo: -58.3816,
        latitudObra: -34.6037,
        longitudObra: -58.3816,
        radiusMeters: 200,
      );
      expect(check.distanciaMetros, greaterThan(100));
      expect(check.allowed, isTrue);
    });

    test('Alt. 4.1/4.2: fuera del radio perimetral deniega', () {
      final check = ClosenessValidator.check(
        latitudDispositivo: -34.6037,
        longitudDispositivo: -57.3816, // ~100 km al este
        latitudObra: -34.6037,
        longitudObra: -58.3816,
      );
      expect(check.allowed, isFalse);
    });

    test('sin ancla de obra (CU-15 sin coordenadas) falla cerrado', () {
      final check = ClosenessValidator.check(
        latitudDispositivo: -34.6037,
        longitudDispositivo: -58.3816,
        latitudObra: null,
        longitudObra: null,
      );
      expect(check.allowed, isFalse);
    });

    test('mensaje exacto de la especificación (Alt. 4.2)', () {
      expect(
        ClosenessValidator.outsideMessage,
        'Se encuentra fuera de los límites de la obra',
      );
    });
  });
}
