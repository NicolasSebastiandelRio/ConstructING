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
import 'package:constructing_mobile/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:constructing_mobile/features/notifications/data/notification_dispatcher.dart';
import 'package:constructing_mobile/features/notifications/data/notification_dispatcher_factory.dart';
import 'package:constructing_mobile/features/notifications/domain/entities/app_notification.dart';

List<SignaturePoint> _trazo({double length = 250, int t0 = 1000}) => [
      SignaturePoint(x: 0, y: 0, t: t0),
      SignaturePoint(x: length / 2, y: 0, t: t0 + 150),
      SignaturePoint(x: length, y: 0, t: t0 + 300),
    ];

class _SpyGenerator {
  Future<Uint8List> generate(ActaPayload payload) async =>
      Uint8List.fromList([37, 80, 68, 70]);
}

class _Ctx {
  final LocalDatabase db;
  final MilestoneLocalDataSource milestones;
  final EvidenceLocalDataSource evidences;
  final CertificationLocalDataSource certifications;
  final PendingConformidadDataSource pendientes;
  final NotificationLocalDataSource notifications;
  final AuditLogWriter auditWriter;

  const _Ctx({
    required this.db,
    required this.milestones,
    required this.evidences,
    required this.certifications,
    required this.pendientes,
    required this.notifications,
    required this.auditWriter,
  });

  /// Sesión del CU-51 con el motor de alertas (CU-67/CU-68) conectado.
  CertificationBloc sesion({
    required String firmante,
    required NotificationDispatcher dispatcher,
    String? profesionalId,
  }) =>
      CertificationBloc(
        milestoneDao: milestones,
        evidenceDao: evidences,
        certificationDao: certifications,
        pendingConformidadDao: pendientes,
        auditLog: auditWriter,
        firmante: firmante,
        requiereDobleFirma: true,
        obraNombre: 'Torre Aurora',
        actaGenerator: _SpyGenerator().generate,
        notificationDispatcher: dispatcher,
        profesionalId: profesionalId,
        propietarioDeObra: (obraId) async =>
            obraId == 'w1' ? 'owner-1' : null,
      );
}

Future<_Ctx> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/tr_${nombre}_'
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
    db: localDb,
    milestones: MilestoneLocalDataSource(localDatabase: localDb),
    evidences: EvidenceLocalDataSource(localDatabase: localDb),
    certifications: CertificationLocalDataSource(localDatabase: localDb),
    pendientes: PendingConformidadDataSource(localDatabase: localDb),
    notifications: NotificationLocalDataSource(localDatabase: localDb),
    auditWriter: AuditLogWriter(
      dataSource: auditDao,
      userIdReader: () async => 'test-user',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-67/CU-68 - motor de alertas del Sprint 6', () {
    test(
        'CU-68: tras la conformidad del profesional se alerta al Propietario '
        'que el acta está lista para firmar (alta prioridad) y, al sellarse, '
        'CU-67 avisa el cierre del hito', () async {
      final ctx = await _contexto('cert');
      final dispatcher =
          NotificationDispatcher(local: ctx.notifications);

      final hito = await ctx.milestones.create(
          obraId: 'w1', nombre: 'Estructura', duracionDias: 10);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      // Etapa 1 — Profesional: registra la primera conformidad.
      final blocPro = ctx.sesion(
        firmante: ConformidadRoles.profesional,
        dispatcher: dispatcher,
      );
      addTearDown(blocPro.close);
      blocPro.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(blocPro.stream,
          emitsThrough(isA<CertificationSummaryReady>()));
      blocPro.add(SignatureStrokeCommitted(points: _trazo(t0: 100)));
      blocPro.add(const SignatureConfirmationRequested());
      await expectLater(blocPro.stream,
          emitsThrough(isA<CertificationAwaitingOtherParty>()));

      // CU-68: alerta de firma dirigida al Propietario.
      var bandeja = await ctx.notifications.listByUsuario('owner-1');
      expect(bandeja, hasLength(1));
      expect(bandeja.single.tipo, NotificationTipo.firma);
      expect(bandeja.single.prioridad, NotificationPrioridad.alta);
      expect(bandeja.single.titulo, 'Acta lista para firmar');
      expect(bandeja.single.obraId, 'w1');
      expect(bandeja.single.hitoId, hito.id);
      expect(bandeja.single.mensaje, contains('Estructura'));
      expect(bandeja.single.mensaje, contains('espera su firma'));
      expect(bandeja.single.leida, isFalse);

      // Etapa 2 — Propietario: cierra la conformidad colegiada.
      final blocOwner = ctx.sesion(
        firmante: ConformidadRoles.propietario,
        dispatcher: dispatcher,
        profesionalId: 'prof-1',
      );
      addTearDown(blocOwner.close);
      blocOwner.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(blocOwner.stream,
          emitsThrough(isA<CertificationSecondSignaturePending>()));
      blocOwner.add(SignatureStrokeCommitted(points: _trazo(t0: 500)));
      blocOwner.add(const SignatureConfirmationRequested());
      await expectLater(blocOwner.stream,
          emitsThrough(isA<CertificationSignatureCaptured>()));

      // CU-67: el cierre del hito emite la "Actualización de Obra".
      bandeja = await ctx.notifications.listByUsuario('owner-1');
      expect(bandeja, hasLength(2));
      final cierre =
          bandeja.firstWhere((n) => n.tipo == NotificationTipo.avance);
      expect(cierre.titulo, contains('Torre Aurora'));
      expect(cierre.mensaje, contains('cierre del hito'));
      expect(cierre.mensaje, contains('Estructura'));
      expect(cierre.hitoId, hito.id);
      // El hito quedó efectivamente congelado (CU-57).
      expect((await ctx.milestones.getById(hito.id))!.estado,
          MilestoneStatus.certificado);

      // CU-67 contraparte: el PROFESIONAL también recibe su alerta. Antes de
      // este cambio la campana del profesional quedaba siempre vacía.
      final bandejaProfesional =
          await ctx.notifications.listByUsuario('prof-1');
      expect(bandejaProfesional, hasLength(1));
      expect(bandejaProfesional.single.titulo,
          'El propietario firmó el acta');
      expect(bandejaProfesional.single.leida, isFalse);
      expect(bandejaProfesional.single.mensaje, contains('Estructura'));
    });

    test('el despachador de producción se construye y persiste la alerta',
        () async {
      final ctx = await _contexto('factory');
      final dispatcher = buildNotificationDispatcher(database: ctx.db);

      await dispatcher.notifyAvanceDeObra(
        propietarioId: 'owner-1',
        obraId: 'w1',
        obraNombre: 'Torre Aurora',
        hitoNombre: 'Fundaciones',
        causa: 'evidencia de Foto cargada',
      );

      expect(await ctx.notifications.countUnread('owner-1'), 1);
    });

    test('sin propietario resoluble no se generan alertas (best-effort)',
        () async {
      final ctx = await _contexto('sinowner');
      final dispatcher = NotificationDispatcher(local: ctx.notifications);
      final hito = await ctx.milestones.create(
          obraId: 'otra-obra', nombre: 'Sin dueño', duracionDias: 5);
      await ctx.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final bloc = ctx.sesion(
        firmante: ConformidadRoles.profesional,
        dispatcher: dispatcher,
      );
      addTearDown(bloc.close);
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await expectLater(
          bloc.stream, emitsThrough(isA<CertificationSummaryReady>()));
      bloc.add(SignatureStrokeCommitted(points: _trazo()));
      bloc.add(const SignatureConfirmationRequested());
      await expectLater(
          bloc.stream, emitsThrough(isA<CertificationAwaitingOtherParty>()));

      expect(await ctx.notifications.listByUsuario('owner-1'), isEmpty);
    });

    test('CU-67: el dispatcher persiste la alerta con su prioridad y tipo',
        () async {
      final ctx = await _contexto('disp');
      final dispatcher = NotificationDispatcher(local: ctx.notifications);

      await dispatcher.notifyAvanceDeObra(
        propietarioId: 'owner-1',
        obraId: 'w1',
        obraNombre: 'Torre Aurora',
        hitoNombre: 'Fundaciones',
        causa: 'cierre del hito',
        hitoId: 'h1',
      );
      await dispatcher.notifySolicitudDeFirma(
        propietarioId: 'owner-1',
        obraId: 'w1',
        obraNombre: 'Torre Aurora',
        hitoNombre: 'Estructura',
        hitoId: 'h2',
      );

      final bandeja = await ctx.notifications.listByUsuario('owner-1');
      expect(bandeja, hasLength(2));
      expect(bandeja.map((n) => n.tipo).toSet(),
          {NotificationTipo.avance, NotificationTipo.firma});
      // CU-71: al no haber preferencia guardada, el default es "correo activo"
      // y la bandeja in-app recibe igualmente la alerta.
      expect(await ctx.notifications.countUnread('owner-1'), 2);
    });
  });
}
