import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/acta_download_cubit.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/acta_download_state.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

import 'milestones_test_helpers.dart';

/// Trazo sintético de firma: línea recta de [length] px con 3 puntos.
List<SignaturePoint> _trazo({
  double length = 200,
  int t0 = 1000,
  int dt = 150,
}) => [
      SignaturePoint(x: 0, y: 0, t: t0),
      SignaturePoint(x: length / 2, y: 0, t: t0 + dt),
      SignaturePoint(x: length, y: 0, t: t0 + 2 * dt),
    ];

void main() {
  group('CertificationBloc pipeline completo - CU-57 (freeze tras CU-52/56)',
      () {
    test('poscondición: el hito queda "Certificado" y encolado para la nube',
        () async {
      final daos = await openSharedTestDaos('cu57a');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);

      final bloc = CertificationBloc(
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        actaGenerator: (payload) async => Uint8List.fromList([37, 80, 68, 70]),
        persistActa: ({required Uint8List bytes, required String fileName}) async =>
            '/caché/$fileName',
      );
      addTearDown(bloc.close);

      final loaded = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await loaded;

      final flow = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      final captured = bloc.state as CertificationSignatureCaptured;
      // CU-57 paso 2: el hito pasó a "Certificado".
      expect(captured.hito.estado, MilestoneStatus.certificado);
      final enBd = await daos.milestones.getById(hito.id);
      expect(enBd?.estado, MilestoneStatus.certificado);
      // Transacción inmutable: encolada para subirse con el cierre (CU-44).
      expect(enBd?.esSincronizado, isFalse);
      expect(captured.actaPath, '/caché/acta_${hito.id}.pdf');
    });

    test('deja traza de auditoría del congelamiento (CU-60 transitorio)',
        () async {
      final daos = await openSharedTestDaos('cu57b');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);

      final bloc = CertificationBloc(
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        actaGenerator: (payload) async => Uint8List.fromList([37, 80, 68, 70]),
        persistActa: ({required Uint8List bytes, required String fileName}) async =>
            '/caché/$fileName',
      );
      addTearDown(bloc.close);

      final loaded = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await loaded;

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      final flow = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('registros congelados (CU-57)') &&
            l.contains('hito=${hito.id}') &&
            l.contains('estado=Certificado')),
        isTrue,
      );
    });
  });

  group('MilestoneLocalDataSource - CU-57 permisos inactivos', () {
    test('Update inactivo sobre un hito certificado', () async {
      final daos = await openSharedTestDaos('cu57c');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await daos.milestones.freeze(hito.id);

      await expectLater(
        daos.milestones.update(hito.copyWith(descripcion: 'Editado')),
        throwsA(isA<CacheStorageException>()),
      );
    });

    test('Delete inactivo sobre un hito certificado', () async {
      final daos = await openSharedTestDaos('cu57d');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await daos.milestones.freeze(hito.id);

      await expectLater(
        daos.milestones.delete(hito.id),
        throwsA(isA<CacheStorageException>()),
      );
      // Grabados en piedra: el hito sigue en la BD.
      expect((await daos.milestones.getById(hito.id))?.estado,
          MilestoneStatus.certificado);
    });

    test('freeze fail-closed: solo desde "En Ejecución"', () async {
      final daos = await openSharedTestDaos('cu57e');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Pendiente', duracionDias: 3);
      await expectLater(
        daos.milestones.freeze(hito.id),
        throwsA(isA<CacheStorageException>()),
      );
      await daos.milestones.update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await daos.milestones.freeze(hito.id);
      // Idempotencia: congelar dos veces falla.
      await expectLater(
        daos.milestones.freeze(hito.id),
        throwsA(isA<CacheStorageException>()),
      );
    });
  });

  group('EvidenceLocalDataSource - CU-57 registros hijos congelados', () {
    test('nuevas cargas inactivas sobre un hito certificado', () async {
      final daos = await openSharedTestDaos('cu57f');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);
      await daos.milestones.freeze(hito.id);

      await expectLater(
        seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId),
        throwsA(isA<CacheStorageException>()),
      );
    });

    test('Update/Delete inactivos sobre la evidencia del hito certificado',
        () async {
      final daos = await openSharedTestDaos('cu57g');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final evidencia = await seedEvidence(
        daos.evidences,
        hitoId: hito.id,
        obraId: hito.obraId,
      );
      await daos.milestones.freeze(hito.id);

      await expectLater(
        daos.evidences.updateArchivo(evidencia.id, 'otro.jpg'),
        throwsA(isA<CacheStorageException>()),
      );
      await expectLater(
        daos.evidences.updateChecksum(evidencia.id, 'nuevo-hash'),
        throwsA(isA<CacheStorageException>()),
      );
      await expectLater(
        daos.evidences.delete(evidencia.id),
        throwsA(isA<CacheStorageException>()),
      );
      // La evidencia quedó grabada en piedra.
      expect(await daos.evidences.listByHito(hito.id), hasLength(1));
    });

    test('la sincronización sigue operativa tras el congelamiento (CU-44)',
        () async {
      final daos = await openSharedTestDaos('cu57h');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final evidencia = await seedEvidence(
        daos.evidences,
        hitoId: hito.id,
        obraId: hito.obraId,
      );
      await daos.milestones.freeze(hito.id);

      // MarkSynced (bookkeeping de la nube) NO está congelado.
      await daos.evidences.markSynced(evidencia.id);
      final fila = await daos.evidences.listByHito(hito.id);
      expect(fila.single.esSincronizado, isTrue);
      expect(fila.single.archivo, isEmpty);
      // El hito congelado también puede marcar su subida.
      await daos.milestones.markSynced(hito.id);
      expect((await daos.milestones.getById(hito.id))?.esSincronizado, isTrue);
    });
  });
}
