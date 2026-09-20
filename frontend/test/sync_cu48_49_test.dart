import 'package:flutter_test/flutter_test.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:constructing_mobile/features/sync/domain/sync_engine.dart';
import 'package:constructing_mobile/features/sync/presentation/bloc/sync_status_cubit.dart';
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

/// CU-48/CU-49: estado de sincronización y control manual (RNF_U_04/RF_06).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SyncStatusCubit, SyncEngine, EvidenceLocalDataSource)> build({
    required bool Function() isOnline,
    required FakeSyncRemote remote,
  }) async {
    final milestoneDao = await openTestDao('sync48');
    final evidenceDao = await openEvidenceDao('sync48');

    final engine = SyncEngine(
      milestones: milestoneDao,
      evidences: evidenceDao,
      remote: remote,
      evidenceReader: (path) async => [1, 2, 3],
    );
    final cubit = SyncStatusCubit(
      engine: engine,
      isOnline: isOnline,
    );
    addTearDown(cubit.close);
    return (cubit, engine, evidenceDao);
  }

  test('CU-48 paso 4: el panel informa el detalle exacto de la cola', () async {
    final (cubit, _, evidenceDao) = await build(
      isOnline: () => true,
      remote: FakeSyncRemote(
        milestoneOutcome: const MilestoneSyncVerdict(
          synced: true,
          conflict: false,
          id: 'x',
          estado: 'Pendiente',
        ),
      ),
    );
    await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: 'blob://f1',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 3,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      checksum: 'A',
      marcaTexto: 'm',
    );
    await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: 'blob://f2',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 3,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      checksum: 'B',
      marcaTexto: 'm',
    );

    await cubit.refresh();
    final state = cubit.state;
    expect(state.evidenciasPendientes, 2);
    expect(state.detalle, '2 evidencias pendientes de subida');
  });

  test('CU-49 flujo normal: "Sincronizar Ahora" sube los pendientes y notifica',
      () async {
    final (cubit, _, evidenceDao) = await build(
      isOnline: () => true,
      remote: FakeSyncRemote(
        milestoneOutcome: const MilestoneSyncVerdict(
          synced: true,
          conflict: false,
          id: 'x',
          estado: 'Pendiente',
        ),
      ),
    );
    await evidenceDao.create(
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: 'blob://f1',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 3,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      checksum: 'A',
      marcaTexto: 'm',
    );
    await cubit.refresh();

    await cubit.syncNow();
    final state = cubit.state;
    expect(state.pendientes, 0);
    expect(state.ultimoMensaje, contains('Sincronización completa'));
    // CU-44 paso 4: el registro quedó sincronizado y su caché liberado.
    final evidences = await evidenceDao.listByHito('h1');
    expect(evidences.single.esSincronizado, isTrue);
    expect(evidences.single.archivo, isEmpty);
  });

  test('CU-49 Alt.: sin red en el chequeo forzado, el panel lo informa',
      () async {
    final (cubit, _, _) = await build(
      isOnline: () => false,
      remote: FakeSyncRemote(),
    );
    await cubit.syncNow();
    expect(
      cubit.state.ultimoMensaje,
      'Sin conexión: reintente cuando haya red.',
    );
  });
}
