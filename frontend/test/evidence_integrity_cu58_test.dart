import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/crypto/evidence_integrity_verifier.dart';
import 'package:constructing_mobile/features/evidence/domain/crypto/secure_erase.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:constructing_mobile/features/sync/domain/sync_engine.dart';

import 'milestones_test_helpers.dart';

/// Remota falsa: valida el checksum recibido contra los bytes (CU-45) y
/// registra el detalle de cada subida (insumo de CU-58/CU-59).
class _RecordingRemote implements SyncRemoteDataSource {
  final Map<String, ({List<int> bytes, String checksum, int total})> subidas =
      {};

  int fallosRestantes = 0;

  @override
  Future<MilestoneSyncVerdict> pushMilestone(Map<String, dynamic> payload) async {
    return MilestoneSyncVerdict(
      synced: true,
      conflict: false,
      id: payload['id'] as String? ?? '',
      estado: payload['estado'] as String? ?? '',
    );
  }

  @override
  Future<void> uploadEvidence({
    required Map<String, dynamic> evidenceMeta,
    required List<int> bytes,
    required int totalBytes,
    required String checksum,
  }) async {
    // CU-45: el servidor valida la integridad del binario recibido.
    final real = EvidenceIntegrityVerifier.sha256OfBytes(bytes);
    if (checksum != real) {
      throw SyncIntegrityException(
          'CU-45 Alt.: divergencia de checksum en el servidor.');
    }
    subidas[evidenceMeta['id'] as String] = (
      bytes: bytes,
      checksum: checksum,
      total: totalBytes
    );
  }
}

void main() {
  group('EvidenceIntegrityVerifier - CU-58 (verificación de integridad)', () {
    late Directory tmp;
    late File archivo;
    late String checksumReal;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cu58');
      archivo = File('${tmp.path}/foto.jpg');
      final bytes = List<int>.generate(300, (i) => i % 251);
      await archivo.writeAsBytes(bytes);
      checksumReal = EvidenceIntegrityVerifier.sha256OfBytes(bytes);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('archivo intacto: ok=true y hash recalculado == checksum almacenado',
        () async {
      final dao = await openEvidenceDao('cu58');
      final evidence = await dao.create(
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: archivo.path,
        nota: 'avance',
        latitud: -34.6,
        longitud: -58.4,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 10, 1),
        tamanoBytes: 300,
        checksum: checksumReal,
        marcaTexto: 'ConstructING',
      );
      final verifier = EvidenceIntegrityVerifier(
        fileReader: (path) => File(path).readAsBytes(),
      );
      final check = await verifier.verify(evidence);
      expect(check.ok, isTrue);
      expect(check.actual, checksumReal);
      expect(check.esperado, checksumReal);
    });

    test('binario manipulado (1 byte alterado): divergencia reportada',
        () async {
      final dao = await openEvidenceDao('cu58x');
      final evidence = await dao.create(
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: archivo.path,
        latitud: -34.6,
        longitud: -58.4,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 10, 1),
        tamanoBytes: 300,
        checksum: checksumReal,
        marcaTexto: 'ConstructING',
      );
      // Manipulación externa: un solo byte del archivo en disco.
      final alterados = List<int>.of(await archivo.readAsBytes());
      alterados[10] = alterados[10] ^ 0x01;
      await archivo.writeAsBytes(alterados);

      final verifier = EvidenceIntegrityVerifier(
        fileReader: (path) => File(path).readAsBytes(),
      );
      final check = await verifier.verify(evidence);
      expect(check.ok, isFalse);
      expect(check.actual, isNot(checksumReal));
      expect(check.esperado, checksumReal);
    });
  });

  group('SyncEngine + CU-58/CU-59: pre-vuelo + borrado seguro', () {
    late Directory tmp;
    late LocalDatabase db;
    late EvidenceLocalDataSource dao;
    late String path;
    late List<int> bytesOrigen;
    late String checksumReal;

    setUp(() async {
      sqfliteFfiInit();
      tmp = await Directory.systemTemp.createTemp('cu58e');
      db = LocalDatabase();
      path =
          '${tmp.path}/engine_${DateTime.now().microsecondsSinceEpoch}.db';
      await db.openLocalDatabase(
        factoryOverride: databaseFactoryFfiNoIsolate,
        nameOverride: path,
      );
      dao = EvidenceLocalDataSource(localDatabase: db);
      addTearDown(db.close);
    });

    tearDown(() async {
      // El borrado seguro elimina el archivo; limpiar solo la BD temp.
      final f = File(path);
      if (await f.exists()) await f.delete();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test(
        'pre-vuelo: divergencia checksum-BD vs. disco se re-ancla y la subida '
        'viaja con el checksum REAL; el binario queda borrado seguro (CU-59)',
        () async {
      bytesOrigen = List<int>.generate(64, (i) => i * 3);
      checksumReal = EvidenceIntegrityVerifier.sha256OfBytes(bytesOrigen);
      final archivo =
          File('${tmp.path}/ev1.jpg')..writeAsBytesSync(bytesOrigen);

      final evidence = await dao.create(
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: archivo.path,
        latitud: -34.6,
        longitud: -58.4,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 10, 1),
        tamanoBytes: bytesOrigen.length,
        checksum: 'checksum-corrupto', // registro desfasado
        marcaTexto: 'ConstructING',
      );

      final remote = _RecordingRemote();
      final borrados = <String>[];
      final engine = SyncEngine(
        milestones: await openTestDao('cu58m'),
        evidences: dao,
        remote: remote,
        evidenceReader: (p) => File(p).readAsBytes(),
        maxIntegrityRetries: 2,
        secureEraser: (archivo) async {
          await const SecureEraseService().eraseFile(archivo);
          borrados.add(archivo);
        },
      );

      final result = await engine.run();

      expect(result.evidenciasSubidas, 1);
      // El sello de la nube corresponde al binario real (CU-58 re-anclaje).
      expect(remote.subidas[evidence.id]!.checksum, checksumReal);
      final actualizada = await dao.listPendingSync();
      expect(actualizada, isEmpty);
      // CU-59: el binario local fue borrado con seguridad tras el volcado.
      expect(borrados, contains(archivo.path));
      expect(await archivo.exists(), isFalse);
    });

    test('binario intacto: subida directa sin retransmisiones ni borrado extra',
        () async {
      bytesOrigen = List<int>.generate(32, (i) => i + 1);
      checksumReal = EvidenceIntegrityVerifier.sha256OfBytes(bytesOrigen);
      final archivo =
          File('${tmp.path}/ev_ok.jpg')..writeAsBytesSync(bytesOrigen);
      await dao.create(
        hitoId: 'h2',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: archivo.path,
        latitud: -34.6,
        longitud: -58.4,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 10, 2),
        tamanoBytes: bytesOrigen.length,
        checksum: checksumReal,
        marcaTexto: 'ConstructING',
      );
      final remote = _RecordingRemote();
      final consolidados = <({String path, bool ausente})>[];
      final engine = SyncEngine(
        milestones: await openTestDao('cu58m2'),
        evidences: dao,
        remote: remote,
        evidenceReader: (p) => File(p).readAsBytes(),
        secureEraser: (archivo) async {
          // CU-59: borrado seguro de producción (re-escritura con patrón).
          await const SecureEraseService().eraseFile(archivo);
          consolidados.add((path: archivo, ausente: !await File(archivo).exists()));
        },
      );
      final result = await engine.run();
      expect(result.evidenciasSubidas, 1);
      expect(result.retransmisiones, 0);
      expect(consolidados, hasLength(1));
      expect(consolidados.single.ausente, isTrue);
    });
  });
}
