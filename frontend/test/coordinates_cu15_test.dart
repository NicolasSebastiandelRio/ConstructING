import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/works/presentation/validators/coordinates.dart';

void main() {
  group('Coordinates - CU-15 (Establecer Ubicación Geográfica)', () {
    test('acepta latitudes válidas dentro de -90..90', () {
      expect(Coordinates.validateLatitude('-34.6037'), isNull);
      expect(Coordinates.validateLatitude('90'), isNull);
      expect(Coordinates.validateLatitude('-90'), isNull);
      expect(Coordinates.validateLatitude('-34,6037'), isNull); // coma decimal
    });

    test('rechaza latitudes fuera de rango o no numéricas', () {
      expect(Coordinates.validateLatitude('91'), Coordinates.latitudeError);
      expect(Coordinates.validateLatitude('-91'), Coordinates.latitudeError);
      expect(Coordinates.validateLatitude('norte'), Coordinates.latitudeError);
    });

    test('acepta longitudes válidas dentro de -180..180', () {
      expect(Coordinates.validateLongitude('-58.3816'), isNull);
      expect(Coordinates.validateLongitude('180'), isNull);
      expect(Coordinates.validateLongitude('-180'), isNull);
    });

    test('rechaza longitudes fuera de rango o no numéricas', () {
      expect(Coordinates.validateLongitude('181'), Coordinates.longitudeError);
      expect(Coordinates.validateLongitude('oeste'), Coordinates.longitudeError);
    });

    test('los campos vacíos son válidos (coordenadas opcionales)', () {
      expect(Coordinates.validateLatitude(''), isNull);
      expect(Coordinates.validateLatitude(null), isNull);
      expect(Coordinates.validateLongitude('  '), isNull);
      expect(Coordinates.parseOrNull(''), isNull);
    });
  });
}