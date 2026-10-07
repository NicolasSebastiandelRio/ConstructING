import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

import 'milestones_test_helpers.dart';

/// Trazo sintético: línea recta de [length] px con 3 puntos.
List<SignaturePoint> _trazo({
  double length = 200,
  int t0 = 1000,
  int dt = 150,
}) => [
      SignaturePoint(x: 0, y: 0, t: t0),
      SignaturePoint(x: length / 2, y: 0, t: t0 + dt),
      SignaturePoint(x: length, y: 0, t: t0 + 2 * dt),
    ];

/// Motor de PDF falso: captura el payload para asertar la firma colegiada.
class _SpyGenerator {
  final payloads = <ActaPayload>[];

  Future<Uint8List> generate(ActaPayload payload) async {
    payloads.add(payload);
    return Uint8List.fromList([37, 80, 68, 70]);
  }
}

/// BD temporal compartida + escritor de Audit Log con acceso a su DAO.
Future<({
  LocalDatabase db,
  MilestoneLocalDataSource milestones,
  EvidenceLocalDataSource evidences,
  CertificationLocalDataSource certifications,
  AuditLogLocalDataSource auditDao,
  AuditLogWriter auditWriter,
})> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path =
      '${Directory.systemTemp.path}/df_${nombre}_${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  final dao = AuditLogLocalDataSource(localDatabase: localDb);
  return (
    db: localDb,
    milestones: MilestoneLocalDataSource(localDatabase: localDb),
    evidences: EvidenceLocalDataSource(localDatabase: localDb),
    certifications: CertificationLocalDataSource(localDatabase: localDb),
    auditDao: dao,
    auditWriter: AuditLogWriter(
      dataSource: dao,
      userIdReader: () async => 'test-user',
    ),
  );
}

void main() {
  // El Audit Log (CU-60) lee la sesión vía secure_storage: exige binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CertificationBloc DOBLE FIRMA - CU-57 (conformidad colegiada)', () {
    test(
        'etapa 1: primera firma queda EN ESPERA de la otra parte (el '
        'congelamiento y el sello aún NO se ejecutan)', () async {
      final ctx = await _contexto('df1');
      final motores = _SpyGenerator();
      final hito = await ctx.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final bloc = CertificationBloc(
        milestoneDao: ctx.milestones,
        evidenceDao: ctx.evidences,
        certificationDao: ctx.certifications,
        auditLog: ctx.auditWriter,
        requiereDobleFirma: true,
        actaGenerator: motores.generate,
      );
      addTearDown(bloc.close);

      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );

      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );

      final pendiente = bloc.state as CertificationSecondSignaturePending;
      expect(pendiente.primerFirmante, 'Profesional');
      expect(pendiente.strokes, isEmpty); // lienzo limpio (CU-53)
      expect(pendiente.trazosPrimeraFirma, hasLength(1));
      expect(pendiente.hito.id, hito.id);
      // CU-57 NO ejecutado todavía: hito sigue editable y sin sello.
      final hitoVigente = await ctx.milestones.getById(hito.id);
      expect(hitoVigente!.estado, MilestoneStatus.enEjecucion);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
      // El acta aún NO se compila.
      expect(motores.payloads, isEmpty);
    });

    test(
        'etapa 2: la otra parte firma → PDF colegiado, congelamiento (CU-57), '
        'sello (CU-59) y huella de auditoría (CU-60) de ambas partes',
        () async {
      final ctx = await _contexto('df2');
      final motores = _SpyGenerator();
      final hito = await ctx.milestones
          .create(obraId: 'w1', nombre: 'Estructura', duracionDias: 10);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final bloc = CertificationBloc(
        milestoneDao: ctx.milestones,
        evidenceDao: ctx.evidences,
        certificationDao: ctx.certifications,
        auditLog: ctx.auditWriter,
        requiereDobleFirma: true,
        actaGenerator: motores.generate,
      );
      addTearDown(bloc.close);

      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      // Etapa 1: firma del profesional.
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 230, t0: 100)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );
      // Etapa 2: firma del propietario.
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 260, t0: 500)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSecondSignaturePending>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );

      // Poscondición CU-57: congelamiento lógico e inmediato.
      final congelado = await ctx.milestones.getById(hito.id);
      expect(congelado!.estado, MilestoneStatus.certificado);

      // CU-56: el acta compilada lleva las DOS firmas (colegiada).
      final payload = motores.payloads.single;
      expect(payload.conDobleFirma, isTrue);
      expect(payload.firmante, 'Profesional');
      expect(payload.segundoFirmante, 'Propietario');
      expect(payload.trazosSegundaFirma, hasLength(1));
      expect(payload.metadatosSegundaFirma, isNotNull);
      expect(payload.fechaSegundaConformidad, isNotNull);

      // CU-59: sello lógico con hash del documento consolidado, tabla con
      // la conformidad colegiada de ambos roles.
      final sello = await ctx.certifications.findByHito(hito.id);
      expect(sello, isNotNull);
      expect(sello!.firmante, 'Profesional');
      expect(sello.firmante2, 'Propietario');
      expect(sello.hashSha256, hasLength(64));

      // CU-60: huella imborrable del firmado colegiado.
      final huellas = await ctx.auditDao.listAll();
      final selloAudit = huellas.firstWhere((r) => r.accion == 'acta_sellada');
      expect(selloAudit.detalle, contains('firmante2=Propietario'));
      expect(selloAudit.detalle, contains('hash='));
    });

    test(
        'CU-52 Alt. 2.1/2.2 en la etapa 2: firma inválida NO descarta la '
        'conformidad pendiente; mensaje visible y lienzo limpio para reintentar',
        () async {
      final ctx = await _contexto('df3');
      final motores = _SpyGenerator();
      final hito = await ctx.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final bloc = CertificationBloc(
        milestoneDao: ctx.milestones,
        evidenceDao: ctx.evidences,
        certificationDao: ctx.certifications,
        auditLog: ctx.auditWriter,
        requiereDobleFirma: true,
        actaGenerator: motores.generate,
      );
      addTearDown(bloc.close);

      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 240, t0: 100)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );

      // Segundo actor: trazo MUY corto (punto accidental, RNF_U_05).
      bloc.add(SignatureStrokeCommitted(points: [
        SignaturePoint(x: 0, y: 0, t: 900),
        SignaturePoint(x: 8, y: 0, t: 950),
      ]));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );
      final rechazado = bloc.state as CertificationSecondSignaturePending;
      // La primera firma sigue intacta y el hito SIN congelar.
      expect(rechazado.primerFirmante, 'Profesional');
      expect(rechazado.trazosPrimeraFirma, hasLength(1));
      expect(rechazado.message, isNotNull);
      expect(motores.payloads, isEmpty); // sin sello ni PDF
      final hitoVigente = await ctx.milestones.getById(hito.id);
      expect(hitoVigente!.estado, MilestoneStatus.enEjecucion);

      // Reintento válido completa el flujo colegiado.
      bloc.add(
          SignatureStrokeCommitted(points: _trazo(length: 300, t0: 1500)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      final congelado = await ctx.milestones.getById(hito.id);
      expect(congelado!.estado, MilestoneStatus.certificado);
      expect(motores.payloads.single.conDobleFirma, isTrue);
    });

    test('firma simple (requiereDobleFirma=false) se mantiene operativa',
        () async {
      final ctx = await _contexto('df4');
      final motores = _SpyGenerator();
      final hito = await ctx.milestones
          .create(obraId: 'w1', nombre: 'Instalaciones', duracionDias: 5);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));
      final bloc = CertificationBloc(
        milestoneDao: ctx.milestones,
        evidenceDao: ctx.evidences,
        certificationDao: ctx.certifications,
        auditLog: ctx.auditWriter,
        requiereDobleFirma: false,
        actaGenerator: motores.generate,
      );
      addTearDown(bloc.close);

      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      expect(motores.payloads.single.conDobleFirma, isFalse);
      expect(motores.payloads.single.segundoFirmante, isNull);
    });
  });
}
