import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/domain/checksum/evidence_checksum.dart';
import 'package:constructing_mobile/features/evidence/domain/datastamp/datastamp.dart';
import 'package:constructing_mobile/features/evidence/domain/limits/video_limit.dart';

/// CU-36 (DataStamp), CU-38 (límites de video) y CU-45 (checksum).
void main() {
  group('CU-36 - DataStamp (RNF_S_04 / RNF_E_01)', () {
    test('construye la capa de alto contraste con metadatos periciales', () {
      final lines = DataStamp.buildLines(
        fechaCaptura: DateTime(2026, 9, 19, 14, 5),
        latitud: -34.6037,
        longitud: -58.3816,
        precisionMetros: 4.2,
        nota: 'Fisura menor en viga V3',
        hitoNombre: 'Estructura',
      );
      expect(lines, containsAll(<Matcher>[
        contains('ConstructING · 19/09/2026 14:05'),
        contains('Lat: -34.603700  Lon: -58.381600 (±4 m)'),
        contains('Hito: Estructura'),
        contains('Nota: Fisura menor en viga V3'),
      ]));
    });

    test('sin nota la línea correspondiente no se compone', () {
      final lines = DataStamp.buildLines(
        fechaCaptura: DateTime(2026, 9, 19, 14, 5),
        latitud: -34.6037,
        longitud: -58.3816,
        precisionMetros: 4,
      );
      expect(lines.where((l) => l.startsWith('Nota:')), isEmpty);
    });

    test('composeText unifica la marca como texto persistible', () {
      final text = DataStamp.composeText(
        const ['ConstructING · 19/09/2026 14:05', 'Lat: -34.6'],
      );
      expect(text, 'ConstructING · 19/09/2026 14:05 | Lat: -34.6');
    });
  });

  group('CU-38 - Validar Límite de tamaño y duración (RNF_E_06)', () {
    test('paso 4: video bajo los límites retorna True (null)', () {
      final result = VideoLimitValidator.validate(
        sizeBytes: 10 * 1024 * 1024,
        durationSeconds: 25,
      );
      expect(result, isNull);
    });

    test('Alt. 4.1/4.2: excede los 15 MB deniega con el mensaje exacto', () {
      final result = VideoLimitValidator.validate(
        sizeBytes: 15 * 1024 * 1024 + 1,
        durationSeconds: 10,
      );
      expect(result, VideoLimitValidator.exceededMessage);
      expect(
        result,
        'El video supera los 30 segundos o 15 MB permitidos',
      );
    });

    test('Alt. 4.1/4.2: 30 segundos o más deniega', () {
      final result = VideoLimitValidator.validate(
        sizeBytes: 1024,
        durationSeconds: 30,
      );
      expect(result, VideoLimitValidator.exceededMessage);
    });
  });

  group('CU-45 - Checksum (RNF_C_03)', () {
    test('SHA-256 del archivo original (vector conocido)', () {
      // SHA-256 de "Constructing" en hex (verificado con Node crypto).
      const expected =
          'A8CD42DFD3777C8EC98C720D60A62EB0688AD98FC5BA1BDEF0F3EA2BCDED1080';
      final actual = EvidenceChecksum.sha256OfBytes(
        Uint8List.fromList('Constructing'.codeUnits),
      );
      expect(actual, expected);
    });
  });
}
