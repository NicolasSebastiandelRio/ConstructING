import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/conformidad_roles.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/domain/stroke_metadata.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

/// Trazo sintético válido (supera la longitud mínima del CU-52).
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
  final LocalDatabase db;
  final MilestoneLocalDataSource milestones;
  final EvidenceLocalDataSource evidences;
  final CertificationLocalDataSource certifications;
  final PendingConformidadDataSource pendientes;
  final AuditLogLocalDataSource auditDao;
  final AuditLogWriter auditWriter;

  const _Ctx({
    required this.db,
    required this.milestones,
    required this.evidences,
    required this.certifications,
    required this.pendientes,
    required this.auditDao,
    required this.auditWriter,
  });

  CertificationBloc sesion({
    required _SpyGenerator motor,
    String firmante = ConformidadRoles.profesional,
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
        actaGenerator: motor.generate,
      );

  Future<Milestone> hitoEnEjecucion({String nombre = 'Cimientos'}) async {
    final hito = await milestones.create(
      obraId: 'w1',
      nombre: nombre,
      duracionDias: 3,
    );
    return milestones.update(
      hito.copyWith(estado: MilestoneStatus.enEjecucion),
    );
  }
}

Future<_Ctx> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path =
      '${Directory.systemTemp.path}/gd_${nombre}_${DateTime.now().microsecondsSinceEpoch}.db';
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
    db: localDb,
    milestones: MilestoneLocalDataSource(localDatabase: localDb),
    evidences: EvidenceLocalDataSource(localDatabase: localDb),
    certifications: CertificationLocalDataSource(localDatabase: localDb),
    pendientes: PendingConformidadDataSource(localDatabase: localDb),
    auditDao: auditDao,
    auditWriter: AuditLogWriter(
      dataSource: auditDao,
      userIdReader: () async => 'test-user',
    ),
  );
}

/// Borrador de conformidad tal como lo deja una primera firma (rol [rol]).
PendingConformidad _borrador({
  required String hitoId,
  required String rol,
  DateTime? fecha,
}) {
  final trazos = [SignatureStroke(_trazo())];
  return PendingConformidad(
    hitoId: hitoId,
    obraId: 'w1',
    primerFirmante: rol,
    primerTrazos: [for (final t in trazos) t.toJson()],
    primerMetadatos: StrokeMetadataExtractor.extract(trazos: trazos)
        .toJson(trazos: trazos),
    primerFecha: fecha ?? DateTime(2026, 9, 1, 10),
    createdAt: DateTime(2026, 9, 1, 10),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-57 — guardas de la conformidad colegiada (Propietario)', () {
    test(
        'el Propietario NO puede forzar la certificación sin la conformidad '
        'del profesional responsable: sin borrador no hay lienzo, ni acta, ni '
        'sello, ni congelamiento',
        () async {
      final ctx = await _contexto('g1');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();
      final bloc =
          ctx.sesion(motor: motor, firmante: ConformidadRoles.propietario);
      addTearDown(bloc.close);

      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationFirstSignatureRequired>(),
        ]),
      );

      final bloqueado = bloc.state as CertificationFirstSignatureRequired;
      expect(bloqueado.signaturePadEnabled, isFalse);
      expect(bloqueado.message, contains('profesional responsable'));
      // El resumen sigue desplegado (CU-51 paso 3) en modo lectura.
      expect(bloqueado.hito.id, hito.id);

      // Intento de forzar la firma: trazo + confirmación no tienen efecto.
      bloc.add(SignatureStrokeCommitted(points: _trazo()));
      bloc.add(const SignatureConfirmationRequested());
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(bloc.state, isA<CertificationFirstSignatureRequired>());
      expect((bloc.state as CertificationFirstSignatureRequired).strokes,
          isEmpty);
      // No nace un borrador de conformidad del rol equivocado.
      expect(await ctx.pendientes.findPending(hito.id), isNull);
      expect(motor.payloads, isEmpty);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
      final vigente = await ctx.milestones.getById(hito.id);
      expect(vigente!.estado, MilestoneStatus.enEjecucion);
    });

    test(
        'un borrador que NO nació de la conformidad técnica del profesional '
        'no puede cerrarse: se descarta y el hito vuelve a requerir la primera '
        'firma',
        () async {
      final ctx = await _contexto('g2');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();

      // Borrador inválido: primera firma del Propietario (nunca debería
      // existir — es el estado que dejaba el hueco anterior).
      await ctx.pendientes.save(
        _borrador(hitoId: hito.id, rol: ConformidadRoles.propietario),
      );
      expect(await ctx.pendientes.findPending(hito.id), isNotNull);

      final bloc =
          ctx.sesion(motor: motor, firmante: ConformidadRoles.propietario);
      addTearDown(bloc.close);
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationFirstSignatureRequired>(),
        ]),
      );
      // El borrador inválido quedó descartado: no hay acta que refrendar.
      expect(await ctx.pendientes.findPending(hito.id), isNull);

      // El profesional tampoco puede refrendarlo: ya no existe el borrador.
      final blocPro = ctx.sesion(motor: motor);
      addTearDown(blocPro.close);
      blocPro.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocPro.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      expect(blocPro.state.signaturePadEnabled, isTrue);
      expect(motor.payloads, isEmpty);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
    });

    test(
        'un hito YA certificado no admite una nueva firma: reabrir el resumen '
        'muestra el acta sellada y el lienzo queda inhabilitado',
        () async {
      final ctx = await _contexto('g3');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();
      // Cierre colegiado consumado (poscondición CU-57/CU-59).
      final congelado = await ctx.milestones.freeze(hito.id);
      await ctx.certifications.insert(CertificationRecord(
        actaId: 'acta-1',
        hitoId: congelado.id,
        obraId: congelado.obraId,
        hashSha256: 'a' * 64,
        firmante: ConformidadRoles.profesional,
        firmante2: ConformidadRoles.propietario,
        createdAt: DateTime(2026, 9, 2, 12),
      ));

      final bloc = ctx.sesion(
        motor: motor,
        firmante: ConformidadRoles.propietario,
      );
      addTearDown(bloc.close);
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationAlreadySealed>(),
        ]),
      );
      final sellado = bloc.state as CertificationAlreadySealed;
      expect(sellado.signaturePadEnabled, isFalse);
      expect(sellado.hito.estado, MilestoneStatus.certificado);

      // Forzar una nueva firma no re-sella ni crea un segundo acta.
      bloc.add(SignatureStrokeCommitted(points: _trazo()));
      bloc.add(const SignatureConfirmationRequested());
      bloc.add(const ClearSignaturePad());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(bloc.state, isA<CertificationAlreadySealed>());
      expect(motor.payloads, isEmpty);
      final sello = await ctx.certifications.findByHito(hito.id);
      expect(sello!.actaId, 'acta-1');
      expect(sello.hashSha256, 'a' * 64);
    });

    test(
        'invariante colegiada: el MISMO rol no puede aportar la segunda firma '
        '(no se sella un acta con dos firmas del mismo actor)',
        () async {
      final ctx = await _contexto('g4');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();

      // El profesional firma y su sesión queda bloqueada.
      final bloc = ctx.sesion(motor: motor);
      addTearDown(bloc.close);
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(t0: 100)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );

      // Ni re-trazando sobre el mismo estado bloqueado, ni re-cargando el
      // resumen, el profesional llega a la etapa 2.
      bloc.add(SignatureStrokeCommitted(points: _trazo(t0: 900)));
      bloc.add(const SignatureConfirmationRequested());
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(bloc.state, isA<CertificationAwaitingOtherParty>());
      expect(motor.payloads, isEmpty);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
      final vigente = await ctx.milestones.getById(hito.id);
      expect(vigente!.estado, MilestoneStatus.enEjecucion);
      // La conformidad del profesional sigue viva, esperando al Propietario.
      final borrador = await ctx.pendientes.findPending(hito.id);
      expect(borrador!.primerFirmante, ConformidadRoles.profesional);
    });

    test('roles: solo el profesional abre la conformidad colegiada', () {
      expect(ConformidadRoles.primerFirmante, ConformidadRoles.profesional);
      expect(ConformidadRoles.otraParte(ConformidadRoles.profesional),
          ConformidadRoles.propietario);
      expect(ConformidadRoles.otraParte(ConformidadRoles.propietario),
          ConformidadRoles.profesional);
      expect(
          ConformidadRoles.esPrimerFirmanteValido(ConformidadRoles.profesional),
          isTrue);
      expect(ConformidadRoles.esPrimerFirmanteValido(ConformidadRoles.propietario),
          isFalse);
    });
  });
}
