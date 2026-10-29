import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/certification/data/acta_pdf_generator.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/conformidad_roles.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

List<SignaturePoint> _trazo({double length = 250, int t0 = 1000}) => [
      SignaturePoint(x: 0, y: 0, t: t0),
      SignaturePoint(x: length / 2, y: 0, t: t0 + 150),
      SignaturePoint(x: length, y: 0, t: t0 + 300),
    ];

class _SpyGenerator {
  final payloads = <ActaPayload>[];

  Future<Uint8List> generate(ActaPayload payload) async {
    payloads.add(payload);
    return Uint8List.fromList([37, 80, 68, 70]);
  }
}

class _Ctx {
  final MilestoneLocalDataSource milestones;
  final EvidenceLocalDataSource evidences;
  final CertificationLocalDataSource certifications;
  final PendingConformidadDataSource pendientes;
  final AuditLogWriter auditWriter;

  const _Ctx({
    required this.milestones,
    required this.evidences,
    required this.certifications,
    required this.pendientes,
    required this.auditWriter,
  });

  CertificationBloc sesion({
    required String firmante,
    required _SpyGenerator motor,
    String? nombreFirmante,
    String? propietarioNombre,
    bool dobleFirma = true,
  }) =>
      CertificationBloc(
        milestoneDao: milestones,
        evidenceDao: evidences,
        certificationDao: certifications,
        pendingConformidadDao: pendientes,
        auditLog: auditWriter,
        firmante: firmante,
        requiereDobleFirma: dobleFirma,
        obraNombre: 'Torre Aurora',
        propietarioNombre: propietarioNombre,
        nombreFirmante: nombreFirmante,
        actaGenerator: motor.generate,
      );
}

Future<_Ctx> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/nm_${nombre}_'
      '${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  final auditDao = AuditLogLocalDataSource(localDatabase: localDb);
  return _Ctx(
    milestones: MilestoneLocalDataSource(localDatabase: localDb),
    evidences: EvidenceLocalDataSource(localDatabase: localDb),
    certifications: CertificationLocalDataSource(localDatabase: localDb),
    pendientes: PendingConformidadDataSource(localDatabase: localDb),
    auditWriter: AuditLogWriter(
      dataSource: auditDao,
      userIdReader: () async => 'test-user',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-56 - nombreDelFirmante', () {
    test('el Propietario usa el nombre de la obra (dato maestro)', () {
      expect(
        nombreDelFirmante(
            ConformidadRoles.propietario, 'Juan desde sesión', 'Juan Gómez'),
        'Juan Gómez',
      );
    });

    test('sin dato maestro cae al nombre de la sesión', () {
      expect(
        nombreDelFirmante(ConformidadRoles.propietario, 'Juan Gómez', null),
        'Juan Gómez',
      );
    });

    test('el Profesional usa SIEMPRE su nombre de sesión', () {
      expect(
        nombreDelFirmante(
            ConformidadRoles.profesional, 'Ing. Ana Pérez', 'Juan Gómez'),
        'Ing. Ana Pérez',
      );
    });

    test('sin nombres disponibles devuelve null (no inventa)', () {
      expect(nombreDelFirmante(ConformidadRoles.profesional, null, null), isNull);
      expect(nombreDelFirmante(ConformidadRoles.propietario, '   ', null), isNull);
    });
  });

  group('CU-56/CU-57 - nombres en el acta colegiada', () {
    test(
        'el nombre del primer firmante se PERSISTE en el borrador y ambos '
        'nombres llegan al acta compilada', () async {
      final ctx = await _contexto('colegiada');
      final motor = _SpyGenerator();
      final hito = await ctx.milestones.create(
          obraId: 'w1', nombre: 'Estructura', duracionDias: 10);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      // Etapa 1 — Profesional con nombre de sesión.
      final blocPro = ctx.sesion(
        firmante: ConformidadRoles.profesional,
        motor: motor,
        nombreFirmante: 'Ing. Ana Pérez',
      );
      addTearDown(blocPro.close);
      blocPro.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
          blocPro.stream, emitsThrough(isA<CertificationSummaryReady>()));
      blocPro.add(SignatureStrokeCommitted(points: _trazo(t0: 100)));
      blocPro.add(const SignatureConfirmationRequested());
      await expectLater(
          blocPro.stream, emitsThrough(isA<CertificationAwaitingOtherParty>()));

      // El nombre sobrevive entre sesiones junto al borrador de conformidad.
      final borrador = await ctx.pendientes.findPending(hito.id);
      expect(borrador!.primerFirmanteNombre, 'Ing. Ana Pérez');

      // Etapa 2 — Propietario (otra sesión) cierra el acta.
      final blocOwner = ctx.sesion(
        firmante: ConformidadRoles.propietario,
        motor: motor,
        nombreFirmante: 'Sr. Juan Gómez',
        propietarioNombre: 'Sr. Juan Gómez',
      );
      addTearDown(blocOwner.close);
      blocOwner.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(blocOwner.stream,
          emitsThrough(isA<CertificationSecondSignaturePending>()));
      final pendiente = blocOwner.state as CertificationSecondSignaturePending;
      // El nombre restaurado llega a la UI/acta desde el borrador.
      expect(pendiente.nombrePrimerFirmante, 'Ing. Ana Pérez');

      blocOwner.add(SignatureStrokeCommitted(points: _trazo(t0: 500)));
      blocOwner.add(const SignatureConfirmationRequested());
      await expectLater(blocOwner.stream,
          emitsThrough(isA<CertificationSignatureCaptured>()));

      final payload = motor.payloads.single;
      expect(payload.nombreFirmante, 'Ing. Ana Pérez');
      expect(payload.nombreSegundoFirmante, 'Sr. Juan Gómez');
      // CU-56 paso 1: el Propietario también queda en los datos maestros.
      expect(payload.propietarioNombre, 'Sr. Juan Gómez');
    });

    test('firma simple: el nombre del firmante viaja en el payload', () async {
      final ctx = await _contexto('simple');
      final motor = _SpyGenerator();
      final hito = await ctx.milestones.create(
          obraId: 'w1', nombre: 'Instalaciones', duracionDias: 5);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final bloc = ctx.sesion(
        firmante: ConformidadRoles.profesional,
        motor: motor,
        nombreFirmante: 'Ing. Ana Pérez',
        dobleFirma: false,
      );
      addTearDown(bloc.close);
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(bloc.stream, emitsThrough(isA<CertificationSummaryReady>()));
      bloc.add(SignatureStrokeCommitted(points: _trazo()));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
          bloc.stream, emitsThrough(isA<CertificationSignatureCaptured>()));

      expect(motor.payloads.single.nombreFirmante, 'Ing. Ana Pérez');
    });
  });
}
