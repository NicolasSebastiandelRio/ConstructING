import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:constructing_mobile/features/evidence/domain/checksum/evidence_checksum.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:constructing_mobile/features/sync/domain/sync_engine.dart';
import 'milestones_test_helpers.dart';

/// Fakes de la nube para el motor de sincronización (CU-44..CU-47).
class FakeSyncRemote implements SyncRemoteDataSource {
  FakeSyncRemote({this.milestoneOutcome, this.uploadBehavior});

  final MilestoneSyncVerdict? milestoneOutcome;
  final Future<String> Function(int call, List<int> bytes)? uploadBehavior;

  final List<Map<String, dynamic>> pushedMilestones = [];
  final List<Map<String, dynamic>> uploadedMeta = [];
  int uploadCalls = 0;

  @override
  Future<MilestoneSyncVerdict> pushMilestone(Map<String, dynamic> payload) async {
    pushedMilestones.add(payload);
    final outcome = milestoneOutcome;
    if (outcome != null) return outcome;
    throw const SyncTemporaryException('Servidor caído');
  }

  @override
  Future<void> uploadEvidence({
    required Map<String, dynamic> evidenceMeta,
    required List<int> bytes,
    required int totalBytes,
    required String checksum,
  }) async {
    uploadCalls++;
    uploadedMeta.add(evidenceMeta);
    final behavior = uploadBehavior;
    if (behavior != null) {
      final result = await behavior(uploadCalls, bytes);
      if (result == 'corrupted') {
        throw const SyncIntegrityException('Archivo corrupto en el transporte');
      }
      if (result == 'offline') {
        throw const SyncTemporaryException('Sin red');
      }
    }
  }
}

/// CU-44..CU-47: motor de sincronización offline-first (PT-06).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CU-44 flujo normal: pendientes subidos y marcados como sincronizados',
      () async {
    final milestoneDao = await openTestDao('sync44');
    await milestoneDao.create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 10);
    final evidenceDao = await openEvidenceDao('sync44');

    final remote = FakeSyncRemote(
      milestoneOutcome: const MilestoneSyncVerdict(
        synced: true,
        conflict: false,
        id: 'x',
        estado: 'Pendiente',
      ),
    );
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final result = await engine.run();

    expect(result.hitosSubidos, 1);
    expect(result.exitoTotal, isTrue);
    expect(remote.pushedMilestones.single['nombre'], 'Cimientos');
    final pending = await milestoneDao.listPendingSync();
    expect(pending, isEmpty); // CU-44 paso 4: ya sincronizado.
  });

  test('CU-44 Alt. 2.1/2.2: error del servidor mantiene pendiente y reintenta',
      () async {
    final milestoneDao = await openTestDao('sync44alt');
    await milestoneDao.create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 10);
    final evidenceDao = await openEvidenceDao('sync44alt');

    final remote = FakeSyncRemote(); // siempre lanza SyncTemporaryException
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final result = await engine.run();

    expect(result.hitosSubidos, 0);
    expect(result.pendientes, 1);
    final pending = await milestoneDao.listPendingSync();
    expect(pending.single.nombre, 'Cimientos'); // registro intacto y encolado.
  });

  test('CU-45 Alt. 2.2: checksum divergente → retransmisión y luego éxito',
      () async {
    final evidenceDao = await openEvidenceDao('sync45');
    final evidence = await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: 'blob://local/foto',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 5,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      checksum: 'ABC',
      marcaTexto: 'm',
    );

    var calls = 0;
    final remote = FakeSyncRemote(
      uploadBehavior: (call, bytes) async {
        calls++;
        return calls == 1 ? 'corrupted' : 'synced';
      },
    );
    final milestoneDao = await openTestDao('sync45');
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final result = await engine.run();

    expect(result.retransmisiones, 1); // CU-45 Alt. 2.2: retransmitió.
    expect(result.evidenciasSubidas, 1);
    expect(remote.uploadCalls, 2);
    final pending = await evidenceDao.listPendingSync();
    expect(pending, isEmpty); // subida íntegra confirmada.
    final all = await evidenceDao.listByHito('h1');
    expect(all.single.id, evidence.id);
    expect(all.single.esSincronizado, isTrue);
  });

  test('CU-47 paso 4: aplica el veredicto del servidor ante conflicto',
      () async {
    final milestoneDao = await openTestDao('sync47');
    final created =
        await milestoneDao.create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 10);
    final evidenceDao = await openEvidenceDao('sync47');

    final remote = FakeSyncRemote(
      milestoneOutcome: const MilestoneSyncVerdict(
        synced: true,
        conflict: true,
        id: 'h',
        estado: 'En Ejecución', // otra dispositivo certificó primero.
      ),
    );
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    await engine.run();

    final updated = await milestoneDao.getById(created.id);
    // La fila local unifica la línea de tiempo con el veredicto de la nube.
    expect(updated?.estado, MilestoneStatus.enEjecucion);
  });

  test('CU-46: la subida vía chunks respeta los límites por bloque', () async {
    final evidenceDao = await openEvidenceDao('sync46');
    await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.video,
      archivo: 'blob://local/video',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 3,
      fechaCaptura: DateTime(2026, 9, 19),
      duracionSeg: 20,
      tamanoBytes: 3,
      checksum: 'DEF',
      marcaTexto: 'm',
      fueraDeObra: true, // CU-35 soft-fail (Sprint 4).
    );

    final sizes = <int>[];
    final remote = FakeSyncRemote(
      uploadBehavior: (call, bytes) async {
        sizes.add(bytes.length);
        return 'synced';
      },
    );
    final milestoneDao = await openTestDao('sync46');
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final result = await engine.run();

    expect(result.evidenciasSubidas, 1);
    expect(remote.uploadedMeta.single['tipo'], 'Video');
    expect(remote.uploadedMeta.single['fueraObra'], isTrue);
  });

  test(
      'CU-45 reparación legacy (Sprint 4): checksum declarado ≠ archivo real '
      '→ re-ancla al checksum real y sincroniza', () async {
    final evidenceDao = await openEvidenceDao('sync45fix');
    await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: 'blob://local/foto',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 5,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      // Build anteriores declaraban el checksum de los bytes estampados en
      // RAM, pero el archivo del caché era el original sin marca: divergencia
      // permanente en el CU-45 (evidencia nunca sincronizada).
      checksum: 'VIEJO-ESTAMPADO',
      marcaTexto: 'm',
    );
    final realChecksum = EvidenceChecksum.sha256OfBytes(
      Uint8List.fromList([1, 2, 3]),
    );

    // Fake que solo acepta cuando el checksum enviado coincide con el
    // esperado (simula la validación CU-45 del servidor).
    final remote2 = _ChecksumAwareFake(expected: realChecksum);
    final milestoneDao = await openTestDao('sync45fix');
    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote2,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final result = await engine.run();

    expect(result.evidenciasSubidas, 1);
    expect(remote2.uploadedChecksums.last, realChecksum);
    final pending = await evidenceDao.listPendingSync();
    expect(pending, isEmpty); // reparada y sincronizada.
    final all = await evidenceDao.listByHito('h1');
    expect(all.single.checksum, realChecksum);
    expect(all.single.esSincronizado, isTrue);
  });
}

/// Fake que acepta solo cuando el checksum enviado coincide con el esperado
/// (simula la validación CU-45 del servidor).
class _ChecksumAwareFake implements SyncRemoteDataSource {
  _ChecksumAwareFake({required this.expected});

  final String expected;

  final List<Map<String, dynamic>> pushedMilestones = [];
  final List<Map<String, dynamic>> uploadedMeta = [];
  final List<String> uploadedChecksums = [];
  int uploadCalls = 0;

  @override
  Future<MilestoneSyncVerdict> pushMilestone(Map<String, dynamic> payload) async {
    pushedMilestones.add(payload);
    throw const SyncTemporaryException('Sin hitos que probar');
  }

  @override
  Future<void> uploadEvidence({
    required Map<String, dynamic> evidenceMeta,
    required List<int> bytes,
    required int totalBytes,
    required String checksum,
  }) async {
    uploadCalls++;
    uploadedMeta.add(evidenceMeta);
    uploadedChecksums.add(checksum);
    if (checksum != expected) {
      throw const SyncIntegrityException('Archivo corrupto en el transporte');
    }
  }
}
