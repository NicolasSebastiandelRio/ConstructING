import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/domain/crypto/secure_erase.dart';

void main() {
  group('SecureEraseService (IO) - CU-59 (borrado seguro, RNF_C_05)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cu59');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<File> crearBinario(String nombre, int bytes) async {
      final file = File('${tmp.path}/$nombre');
      await file.writeAsBytes(
        List<int>.generate(bytes, (i) => (i * 17 + 3) % 251),
      );
      return file;
    }

    test('paso 2/3/4: re-escritura multi-pase, eliminación y verificación',
        () async {
      final binario = await crearBinario('ev.jpg', 512);
      final service = const SecureEraseService();

      final result = await service.eraseFile(
        binario.path,
        patrones: [0x00, 0xFF, 0x00],
      );

      // Poscondición: el binario ya no puede recuperarse del disco.
      expect(await binario.exists(), isFalse);
      expect(result.archivoInexistente, isFalse);
      expect(result.pasadas, 4); // 3 patrón + 1 cierre pseudoaleatorio
      expect(result.bytes, 512);
    });

    test('Alt.: binario ya inexistente → resultado con flag y sin pasadas',
        () async {
      const service = SecureEraseService();
      final result = await service.eraseFile('${tmp.path}/no_existe.jpg');
      expect(result.archivoInexistente, isTrue);
      expect(result.pasadas, 0);
      expect(result.bytes, 0);
    });

    test('patrones por defecto con hash cargo: 3 pasadas + cierre', () async {
      final binario = await crearBinario('ev_default.jpg', 10);
      const service = SecureEraseService();
      final result = await service.eraseFile(binario.path);
      expect(result.pasadas, SecureEraseService.patronesPorDefecto.length + 1);
      expect(await binario.exists(), isFalse);
    });
  });
}
