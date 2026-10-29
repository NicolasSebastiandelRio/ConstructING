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
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

/// Trazo sintético: línea recta de [length] px con 3 puntos.
List<SignaturePoint> _trazo({
  double length = 200,
  int t0 = 1000,
  int dt = 150,
}) =>
    [
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

/// Contexto de prueba: una sola BD temporal ffi compartida por todos los DAOs
/// del flujo de certificación (hitos, evidencias, actas selladas, borradores
/// de conformidad y audit log).
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

  /// Bloc del CU-51/CU-52 como una SESIÓN con un rol concreto (doble firma).
  CertificationBloc sesion({
    required _SpyGenerator motor,
    String firmante = ConformidadRoles.profesional,
    bool dobleFirma = true,
    String? obraNombre,
    String? propietarioNombre,
  }) =>
      CertificationBloc(
        milestoneDao: milestones,
        evidenceDao: evidences,
        certificationDao: certifications,
        pendingConformidadDao: pendientes,
        auditLog: auditWriter,
        firmante: firmante,
        requiereDobleFirma: dobleFirma,
        obraNombre: obraNombre,
        propietarioNombre: propietarioNombre,
        actaGenerator: motor.generate,
      );

  /// Hito listo para certificar (En Ejecución + evidencia visual cargada).
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

void main() {
  // El Audit Log (CU-60) lee la sesión vía secure_storage: exige binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CertificationBloc DOBLE FIRMA - CU-57 (conformidad colegiada)', () {
    test(
        'etapa 1 (Profesional): la primera firma queda EN ESPERA y ESTA '
        'sesión queda bloqueada — sin PDF, sin sello y sin congelamiento',
        () async {
      final ctx = await _contexto('df1');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();
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

      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );

      final espera = bloc.state as CertificationAwaitingOtherParty;
      // CU-57: el mismo rol NO vuelve a firmar — lienzo inhabilitado.
      expect(espera.signaturePadEnabled, isFalse);
      expect(espera.message, contains('Profesional'));
      expect(espera.message, contains('Propietario'));

      // CU-57 NO ejecutado todavía: hito editable y sin sello.
      final hitoVigente = await ctx.milestones.getById(hito.id);
      expect(hitoVigente!.estado, MilestoneStatus.enEjecucion);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
      expect(motor.payloads, isEmpty); // el acta aún NO se compila.

      // La primera firma quedó PERSISTIDA como borrador de conformidad.
      final borrador = await ctx.pendientes.findPending(hito.id);
      expect(borrador, isNotNull);
      expect(borrador!.primerFirmante, ConformidadRoles.profesional);
      expect(borrador.primerTrazos, hasLength(1));

      // Guard: trazo + confirmación sobre el estado bloqueado NO tienen
      // efecto (no se re-firma, no se degrada el estado, no se sella).
      final bloqueado = bloc.state;
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 300)));
      bloc.add(const SignatureConfirmationRequested());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(bloc.state, bloqueado);
      expect(motor.payloads, isEmpty);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
      expect((await ctx.pendientes.findPending(hito.id))!.primerTrazos,
          hasLength(1));
    });

    test(
        'etapa 2 (Propietario, OTRA sesión): restaura el borrador, aporta la '
        'segunda firma y recién ahí se compila el PDF colegiado, se congela '
        '(CU-57), se sella (CU-59) y se audita (CU-60)',
        () async {
      final ctx = await _contexto('df2');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion(nombre: 'Estructura');

      // Sesión A — Profesional responsable: abre la conformidad colegiada.
      final blocA = ctx.sesion(motor: motor);
      addTearDown(blocA.close);
      blocA.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      blocA.add(SignatureStrokeCommitted(points: _trazo(length: 230, t0: 100)));
      blocA.add(const SignatureConfirmationRequested());
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );

      // Sesión B — Propietario: entra después y DEBE restaurar el borrador
      // (primera firma del profesional) directamente en etapa 2.
      final blocB = ctx.sesion(
        motor: motor,
        firmante: ConformidadRoles.propietario,
        obraNombre: 'Torre Aurora',
        propietarioNombre: 'Ana Pérez',
      );
      addTearDown(blocB.close);
      blocB.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocB.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );
      final restaurada = blocB.state as CertificationSecondSignaturePending;
      expect(restaurada.primerFirmante, ConformidadRoles.profesional);
      expect(restaurada.trazosPrimeraFirma, hasLength(1));
      expect(restaurada.metadatosPrimeraFirma.longitudTotalPx, greaterThan(0));
      expect(restaurada.signaturePadEnabled, isTrue);

      // Etapa 2: firma del propietario → cierre colegiado completo.
      blocB.add(SignatureStrokeCommitted(points: _trazo(length: 260, t0: 500)));
      blocB.add(const SignatureConfirmationRequested());
      await expectLater(
        blocB.stream,
        emitsInOrder([
          isA<CertificationSecondSignaturePending>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );

      // Poscondición CU-57: congelamiento lógico e inmediato.
      final congelado = await ctx.milestones.getById(hito.id);
      expect(congelado!.estado, MilestoneStatus.certificado);

      // CU-56: el acta compilada lleva las DOS firmas (colegiada real).
      final payload = motor.payloads.single;
      expect(payload.conDobleFirma, isTrue);
      expect(payload.firmante, ConformidadRoles.profesional);
      expect(payload.segundoFirmante, ConformidadRoles.propietario);
      expect(payload.trazosSegundaFirma, hasLength(1));
      expect(payload.metadatosSegundaFirma, isNotNull);
      expect(payload.fechaSegundaConformidad, isNotNull);
      // CU-56 paso 1: el acta lleva los datos maestros del proyecto.
      expect(payload.obraNombre, 'Torre Aurora');
      expect(payload.propietarioNombre, 'Ana Pérez');

      // CU-59: sello con hash del documento consolidado y ambos firmantes.
      final sello = await ctx.certifications.findByHito(hito.id);
      expect(sello, isNotNull);
      expect(sello!.firmante, ConformidadRoles.profesional);
      expect(sello.firmante2, ConformidadRoles.propietario);
      expect(sello.hashSha256, hasLength(64));

      // CU-60: huella imborrable del firmado colegiado.
      final huellas = await ctx.auditDao.listAll();
      final selloAudit = huellas.firstWhere((r) => r.accion == 'acta_sellada');
      expect(selloAudit.detalle, contains('firmante2=Propietario'));
      expect(selloAudit.detalle, contains('hash='));

      // El borrador se descarta: no queda pendiente para un tercer intento.
      expect(await ctx.pendientes.findPending(hito.id), isNull);
    });

    test(
        'CU-52 Alt. 2.1/2.2 en la etapa 2: la firma inválida del Propietario '
        'NO descarta la conformidad del profesional; mensaje visible y lienzo '
        'limpio para reintentar',
        () async {
      final ctx = await _contexto('df3');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();

      final blocA = ctx.sesion(motor: motor);
      addTearDown(blocA.close);
      blocA.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      blocA.add(SignatureStrokeCommitted(points: _trazo(length: 240, t0: 100)));
      blocA.add(const SignatureConfirmationRequested());
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );

      final blocB = ctx.sesion(
        motor: motor,
        firmante: ConformidadRoles.propietario,
      );
      addTearDown(blocB.close);
      blocB.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocB.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSecondSignaturePending>(),
        ]),
      );

      // Trazo MUY corto (punto accidental, RNF_U_05).
      blocB.add(SignatureStrokeCommitted(points: [
        SignaturePoint(x: 0, y: 0, t: 900),
        SignaturePoint(x: 8, y: 0, t: 950),
      ]));
      blocB.add(const SignatureConfirmationRequested());
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final rechazado = blocB.state as CertificationSecondSignaturePending;
      // La primera firma sigue intacta y el hito SIN congelar.
      expect(rechazado.primerFirmante, ConformidadRoles.profesional);
      expect(rechazado.trazosPrimeraFirma, hasLength(1));
      expect(rechazado.message, isNotNull);
      expect(rechazado.strokes, isEmpty); // CU-53: lienzo limpio.
      expect(motor.payloads, isEmpty); // sin sello ni PDF.
      final hitoVigente = await ctx.milestones.getById(hito.id);
      expect(hitoVigente!.estado, MilestoneStatus.enEjecucion);
      // El borrador del profesional NO se descarta (la conformidad sigue viva).
      final borrador = await ctx.pendientes.findPending(hito.id);
      expect(borrador, isNotNull);
      expect(borrador!.primerTrazos, hasLength(1));

      // Reintento válido completa el flujo colegiado.
      blocB.add(SignatureStrokeCommitted(points: _trazo(length: 300, t0: 1500)));
      blocB.add(const SignatureConfirmationRequested());
      await expectLater(
        blocB.stream,
        emitsInOrder([
          isA<CertificationSecondSignaturePending>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      final congelado = await ctx.milestones.getById(hito.id);
      expect(congelado!.estado, MilestoneStatus.certificado);
      expect(motor.payloads.single.conDobleFirma, isTrue);
    });

    test('firma simple (requiereDobleFirma=false) se mantiene operativa',
        () async {
      final ctx = await _contexto('df4');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion(nombre: 'Instalaciones');
      final bloc = ctx.sesion(motor: motor, dobleFirma: false);
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
      expect(motor.payloads.single.conDobleFirma, isFalse);
      expect(motor.payloads.single.segundoFirmante, isNull);
      // Sin doble firma no queda borrador colegiado.
      expect(await ctx.pendientes.findPending(hito.id), isNull);
    });

    test(
        'el mismo rol NO puede volver a firmar: re-cargar el resumen con la '
        'primera firma pendiente emite bloqueo (sin lienzo ni sello)',
        () async {
      final ctx = await _contexto('df5');
      final motor = _SpyGenerator();
      final hito = await ctx.hitoEnEjecucion();

      final blocA = ctx.sesion(motor: motor);
      addTearDown(blocA.close);
      blocA.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      blocA.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      blocA.add(const SignatureConfirmationRequested());
      await expectLater(
        blocA.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );

      // El profesional REABRE el resumen: su firma ya está registrada → el
      // estado BLOQUEA el lienzo (guard del bloc) y el hito sigue sin
      // certificar.
      final blocB = ctx.sesion(
        motor: motor,
        firmante: ConformidadRoles.profesional,
      );
      addTearDown(blocB.close);
      blocB.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
        blocB.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationAwaitingOtherParty>(),
        ]),
      );
      final chequeoAwaiting = isA<CertificationAwaitingOtherParty>();
      final estado = blocB.state as CertificationAwaitingOtherParty;
      expect(estado.message, contains('Profesional'));
      expect(estado.signaturePadEnabled, isFalse);

      // Confirmar de nuevo NO genera efectos: el guard lo bloquea.
      blocB.add(SignatureStrokeCommitted(points: _trazo(length: 300)));
      blocB.add(const SignatureConfirmationRequested());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(blocB.state, chequeoAwaiting);
      expect(motor.payloads, isEmpty);
      final hitoVigente = await ctx.milestones.getById(hito.id);
      expect(hitoVigente!.estado, MilestoneStatus.enEjecucion);
      expect(await ctx.certifications.findByHito(hito.id), isNull);
    });
  });
}
