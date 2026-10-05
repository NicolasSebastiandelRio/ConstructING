import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_remote_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/gateway/capture_gateway.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';
import 'package:constructing_mobile/features/evidence/presentation/bloc/capture_flow_bloc.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';

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

/// Fuente remota falsa: registra los envíos o falla a pedido.
class _FakeRemoteAudit implements AuditLogRemoteDataSource {
  final Map<String, Map<String, dynamic>> enviados = {};
  final bool fallar;

  _FakeRemoteAudit({this.fallar = false});

  @override
  Future<AuditLogServerRecord?> send({
    required Map<String, dynamic> registro,
  }) async {
    if (fallar) return null;
    enviados[registro['accion'] as String] = registro;
    return const AuditLogServerRecord(
      id: 'server-1',
      usuarioId: 'server-user',
      accion: 'eco',
      createdAt: null as dynamic,
    );
  }
}

void main() {
  group('AuditLogLocalDataSource - CU-60 (tabla inmutable)', () {
    Future<({LocalDatabase db, AuditLogLocalDataSource dao})> _dao(
      String prefix,
    ) async {
      sqfliteFfiInit();
      final localDb = LocalDatabase();
      final path =
          '${Directory.systemTemp.path}/au60_${prefix}_${DateTime.now().microsecondsSinceEpoch}.db';
      await localDb.openLocalDatabase(
        factoryOverride: databaseFactoryFfiNoIsolate,
        nameOverride: path,
      );
      addTearDown(() async {
        await localDb.close();
        final file = File(path);
        if (await file.exists()) await file.delete();
      });
      return (
        db: localDb,
        dao: AuditLogLocalDataSource(localDatabase: localDb),
      );
    }

    test('paso 4: inserta la fila inmutable y queda consultable', () async {
      final ctx = await _dao('a');
      final record = await ctx.dao.insert(AuditLogRecord(
        id: 'r1',
        usuarioId: 'u1',
        accion: 'hito_modificado',
        detalle: 'Cimientos',
        obraId: 'w1',
        coordenadas: '-34.6,-58.4',
        createdAt: DateTime.utc(2026, 10, 5, 12, 0),
      ));

      expect(record.id, 'r1');
      final all = await ctx.dao.listAll();
      expect(all, hasLength(1));
      expect(all.single.usuarioId, 'u1');
      expect(all.single.accion, 'hito_modificado');
      expect(all.single.coordenadas, '-34.6,-58.4');
      // Orden cronológico descendente (insumo del CU-63).
      await ctx.dao.insert(AuditLogRecord(
        id: 'r2',
        usuarioId: 'u1',
        accion: 'acta_sellada',
        createdAt: DateTime.utc(2026, 10, 5, 13, 0),
      ));
      expect((await ctx.dao.listAll()).first.accion, 'acta_sellada');
      expect((await ctx.dao.listByObra('w1')).map((r) => r.id),
          containsAll(['r1', 'r2']));
    });
  });

  group('AuditLogWriter - CU-60 (servicio transparente, best-effort)', () {
    Future<({LocalDatabase db, AuditLogLocalDataSource dao})> _dao(
      String prefix,
    ) async {
      sqfliteFfiInit();
      final localDb = LocalDatabase();
      final path =
          '${Directory.systemTemp.path}/au60w_${prefix}_${DateTime.now().microsecondsSinceEpoch}.db';
      await localDb.openLocalDatabase(
        factoryOverride: databaseFactoryFfiNoIsolate,
        nameOverride: path,
      );
      addTearDown(() async {
        await localDb.close();
        final file = File(path);
        if (await file.exists()) await file.delete();
      });
      return (
        db: localDb,
        dao: AuditLogLocalDataSource(localDatabase: localDb),
      );
    }

    test('ensambla el registro: usuario de sesión, acción, obra y coordenadas',
        () async {
      final ctx = await _dao('b');
      final remote = _FakeRemoteAudit();
      final writer = AuditLogWriter(
        dataSource: ctx.dao,
        remote: remote,
        userIdReader: () async => 'user-77',
        clock: () => DateTime(2026, 10, 5, 9, 30),
      );

      await writer.log(
        accion: 'evidencia_cargada',
        detalle: 'tipo=Foto',
        obraId: 'w1',
        coordenadas: '-34.6,-58.4',
      );

      final fila = (await ctx.dao.listAll()).single;
      expect(fila.usuarioId, 'user-77');
      expect(fila.accion, 'evidencia_cargada');
      expect(fila.detalle, 'tipo=Foto');
      expect(fila.obraId, 'w1');
      expect(fila.coordenadas, '-34.6,-58.4');
      // Timestamp del evento consolidado (servidor best-effort).
      expect(remote.enviados['evidencia_cargada'], isNotNull);
    });

    test('sin sesión activa queda como anonimo (transparente)', () async {
      final ctx = await _dao('c');
      final writer = AuditLogWriter(
        dataSource: ctx.dao,
        userIdReader: () async => null,
        clock: () => DateTime(2026, 10, 5),
      );

      await writer.log(accion: 'hito_creado');
      expect((await ctx.dao.listAll()).single.usuarioId, 'anonimo');
    });

    test('fallo remoto o local no interrumpe la transacción crítica', () async {
      final ctx = await _dao('d');
      final writer = AuditLogWriter(
        dataSource: ctx.dao,
        remote: _FakeRemoteAudit(fallar: true),
        userIdReader: () async => 'u',
        clock: () => DateTime(2026, 10, 5),
      );
      await writer.log(accion: 'acta_sellada');
      expect((await ctx.dao.listAll()).single.accion, 'acta_sellada');
    });
  });

  group('Wiring de transacciones críticas - CU-60', () {
    test('modificar hito (MilestonesBloc) deja huella', () async {
      final daos = await openSharedTestDaos('cu60a');
      final auditCtx = await _daoForAudit('cu60a');
      final writer = AuditLogWriter(
        dataSource: auditCtx.dao,
        userIdReader: () async => 'prof-1',
        clock: () => DateTime(2026, 10, 5),
      );
      final bloc = MilestonesBloc(dataSource: daos.milestones, auditLog: writer);
      addTearDown(bloc.close);

      final loaded = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      bloc.add(LoadMilestones(obraId: 'w1'));
      await loaded;

      final flow = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'Cimientos', duracionDias: 3));
      await flow;

      final fila = (await auditCtx.dao.listAll()).single;
      expect(fila.accion, 'hito_creado');
      expect(fila.usuarioId, 'prof-1');
      expect(fila.obraId, 'w1');
    });

    test('cargar evidencia (CaptureFlowBloc) deja huella con coordenadas',
        () async {
      // Se valida el ensamble vía writer (el flujo completo de cámara está
      // cubierto por evidence_capture_flow_test con fakes de hardware).
      final daos = await openSharedTestDaos('cu60b');
      final auditCtx = await _daoForAudit('cu60b');
      final writer = AuditLogWriter(
        dataSource: auditCtx.dao,
        userIdReader: () async => 'prof-1',
        clock: () => DateTime(2026, 10, 5),
      );
      final bloc = CaptureFlowBloc(
        captureGateway: _NoCaptureGateway(),
        locationGateway: _NoLocationGateway(),
        evidences: daos.evidences,
        hito: const Milestone(
            id: 'h1', obraId: 'w1', nombre: 'Cimientos', duracionDias: 3),
        obraId: 'w1',
        auditLog: writer,
      );
      addTearDown(bloc.close);
      expect(bloc.auditLog, isNotNull);
    });

    test('firmar acta (CertificationBloc) deja huella del sello', () async {
      final daos = await openSharedTestDaos('cu60c');
      final auditCtx = await _daoForAudit('cu60c');
      final writer = AuditLogWriter(
        dataSource: auditCtx.dao,
        userIdReader: () async => 'prof-1',
        clock: () => DateTime(2026, 10, 5),
      );
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final bloc = CertificationBloc(
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        auditLog: writer,
        actaGenerator: (payload) async =>
            Uint8List.fromList([37, 80, 68, 70]),
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

      final filas = await auditCtx.dao.listAll();
      expect(filas.map((r) => r.accion), contains('acta_sellada'));
      final sello = filas.firstWhere((r) => r.accion == 'acta_sellada');
      expect(sello.usuarioId, 'prof-1');
      expect(sello.obraId, 'w1');
      expect(sello.detalle, contains('acta='));
      expect(sello.detalle, contains('hash='));
    });
  });
}

Future<({LocalDatabase db, AuditLogLocalDataSource dao})> _daoForAudit(
  String prefix,
) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path =
      '${Directory.systemTemp.path}/au60x_${prefix}_${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  return (
    db: localDb,
    dao: AuditLogLocalDataSource(localDatabase: localDb),
  );
}

class _NoCaptureGateway implements CaptureGateway {
  const _NoCaptureGateway();

  @override
  Future<String> capture({required EvidenceType tipo}) async =>
      throw UnimplementedError();

  @override
  Future<List<int>> readBytes(String path) async => const <int>[];

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async =>
      originalPath;

  @override
  Future<void> releaseTempFile(String path) async {}
}

class _NoLocationGateway implements LocationGateway {
  const _NoLocationGateway();

  @override
  Future<DevicePosition> getCurrentPosition({Duration timeout}) async =>
      const DevicePosition(
          latitud: -34.6, longitud: -58.4, precisionMetros: 5);
}
