import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/certification/presentation/screens/certification_summary_screen.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
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

Future<({
  LocalDatabase db,
  MilestoneLocalDataSource milestones,
  EvidenceLocalDataSource evidences,
})> _daos(String prefix) => openSharedTestDaos(prefix);

Future<Milestone> _crearHito(
  MilestoneLocalDataSource dao, {
  String nombre = 'Hito',
  MilestoneStatus estado = MilestoneStatus.enEjecucion,
}) async {
  final created =
      await dao.create(obraId: 'w1', nombre: nombre, duracionDias: 3);
  if (estado != MilestoneStatus.pendiente) {
    await dao.update(created.copyWith(estado: estado));
  }
  return created;
}

/// DAO de evidencias en memoria para widget tests (sin BD real).
class FakeEvidenceDao implements EvidenceLocalDataSource {
  final Map<String, Evidence> _store = {};

  void seed(List<Evidence> evidences) {
    for (final evidence in evidences) {
      _store[evidence.id] = evidence;
    }
  }

  @override
  Future<Evidence> create({
    required String hitoId,
    required String obraId,
    required EvidenceType tipo,
    required String archivo,
    String? nota,
    required double latitud,
    required double longitud,
    required double precisionMetros,
    required DateTime fechaCaptura,
    double? duracionSeg,
    required int tamanoBytes,
    required String checksum,
    required String marcaTexto,
    bool fueraDeObra = false,
  }) async {
    final evidence = Evidence(
      id: 'e-${_store.length + 1}',
      hitoId: hitoId,
      obraId: obraId,
      tipo: tipo,
      archivo: archivo,
      nota: nota,
      latitud: latitud,
      longitud: longitud,
      precisionMetros: precisionMetros,
      fechaCaptura: fechaCaptura,
      duracionSeg: duracionSeg,
      tamanoBytes: tamanoBytes,
      checksum: checksum,
      marcaTexto: marcaTexto,
      fueraDeObra: fueraDeObra,
    );
    _store[evidence.id] = evidence;
    return evidence;
  }

  @override
  Future<int> countByHito(String hitoId) async =>
      _store.values.where((e) => e.hitoId == hitoId).length;

  @override
  Future<List<Evidence>> listByHito(String hitoId) async =>
      _store.values.where((e) => e.hitoId == hitoId).toList();

  @override
  Future<List<Evidence>> listByObra(String obraId) async =>
      _store.values.where((e) => e.obraId == obraId).toList();

  @override
  Future<List<Evidence>> listPendingSync() async =>
      _store.values.where((e) => !e.esSincronizado).toList();

  @override
  Future<void> markSynced(String id) async {
    final current = _store[id];
    if (current != null) {
      _store[id] = current.copyWith(esSincronizado: true);
    }
  }

  @override
  Future<void> updateArchivo(String id, String archivo) async {
    final current = _store[id];
    if (current != null) {
      _store[id] = current.copyWith(archivo: archivo);
    }
  }

  @override
  Future<void> updateChecksum(String id, String checksum) async {}

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

/// Tabla de certificaciones en memoria para widget tests (sin BD real).
class FakeCertificationDao implements CertificationLocalDataSource {
  @override
  Future<CertificationRecord> insert(CertificationRecord record) async =>
      record;

  @override
  Future<CertificationRecord?> findByHito(String hitoId) async => null;
}

/// DAO de auditoría que falla rápido: los widget tests no disponen de BD
/// real; el writer es best-effort (la huella no interrumpe el flujo).
class _AuditDaoFailFast implements AuditLogLocalDataSource {
  @override
  Future<AuditLogRecord> insert(AuditLogRecord record) async {
    throw const CacheStorageException('sin BD local en widget tests');
  }

  @override
  Future<List<AuditLogRecord>> listByObra(String obraId) async => const [];

  @override
  Future<List<AuditLogRecord>> listAll() async => const [];
}

/// Escritor de auditoría fail-fast para widget tests.
final AuditLogWriter fakeAuditWriter = AuditLogWriter(
  dataSource: _AuditDaoFailFast(),
  userIdReader: () async => 'widget-user',
);

void main() {
  group('CertificationBloc CU-51 - Visualizar Resumen a Certificar', () {
    test('Flujo Normal: consulta en BD fechas, multimedia y notas del hito',
        () async {
      final daos = await _daos('cu51a');
      final hito = await _crearHito(daos.milestones, nombre: 'Cimientos');
      await seedEvidence(daos.evidences,
          hitoId: hito.id, obraId: hito.obraId);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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

      final ready = bloc.state as CertificationSummaryReady;
      expect(ready.hito.id, hito.id);
      expect(ready.hito.nombre, 'Cimientos');
      expect(ready.evidencias, hasLength(1));
      // CU-51 poscondición: listo para otorgar conformidad (lienzo vacío).
      expect(ready.strokes, isEmpty);
    });

    test('hito sin evidencias: resumen desplegado igualmente', () async {
      final daos = await _daos('cu51b');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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

      expect((bloc.state as CertificationSummaryReady).evidencias, isEmpty);
    });

    test('hito inexistente → error', () async {
      final daos = await _daos('cu51c');
      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final loaded = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationError>(),
        ]),
      );
      bloc.add(const LoadCertificationSummary(hitoId: 'fantasma'));
      await loaded;

      expect(
        (bloc.state as CertificationError).message,
        contains('ya no existe'),
      );
    });
  });

  group('CertificationBloc CU-52/CU-53 - Firma Manuscrita', () {
    test('Flujo Normal: trazo válido + Confirmar captura la conformidad',
        () async {
      final daos = await _daos('cu52a');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 200)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      final captured = bloc.state as CertificationSignatureCaptured;
      expect(captured.conformidadAt, isA<DateTime>());
      expect(captured.strokes, hasLength(1));
      expect(captured.hito.id, hito.id);
    });

    test('Alt. 2.1/2.2: trazo corto → rechazo, lienzo limpio y confirmación bloqueada',
        () async {
      final daos = await _daos('cu52b');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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
          isA<CertificationSignatureRejected>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 10)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      final rejected = bloc.state as CertificationSignatureRejected;
      expect(
        rejected.message,
        'Firma inválida o punto accidental: limpie el lienzo y vuelva a trazar su firma.',
      );
      // CU-53 ejecutado por el sistema: lienzo en blanco.
      expect(rejected.strokes, isEmpty);
      // El hito no cambia de estado ante una firma inválida.
      expect(
        (await daos.milestones.getById(hito.id))?.estado,
        MilestoneStatus.enEjecucion,
      );
    });

    test('tras el rechazo se puede reintentar y capturar', () async {
      final daos = await _daos('cu52c');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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

      final first = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureRejected>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 10)));
      bloc.add(const SignatureConfirmationRequested());
      await first;

      final retry = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250, t0: 5000)));
      bloc.add(const SignatureConfirmationRequested());
      await retry;

      expect(
        (bloc.state as CertificationSignatureCaptured).strokes,
        hasLength(1),
      );
    });

    test('CU-53: Limpiar Pantalla borra el buffer y el lienzo queda en blanco',
        () async {
      final daos = await _daos('cu53');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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
          predicate<CertificationSummaryReady>(
              (s) => s.strokes.isNotEmpty, 'lienzo con trazo'),
          predicate<CertificationSummaryReady>(
              (s) => s.strokes.isEmpty, 'lienzo en blanco'),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 200)));
      bloc.add(const ClearSignaturePad());
      await flow;
    });

    test('Confirmar sin trazos → rechazo (confirmación bloqueada)', () async {
      final daos = await _daos('cu52d');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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
        emitsInOrder([isA<CertificationSignatureRejected>()]),
      );
      bloc.add(const SignatureConfirmationRequested());
      await flow;
    });

    test('la firma requiere el resumen cargado (precondición CU-52)',
        () async {
      final daos = await _daos('cu52e');
      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final emitted = <CertificationState>[];
      final sub = bloc.stream.listen(emitted.add);
      bloc.add(SignatureStrokeCommitted(points: _trazo()));
      bloc.add(const SignatureConfirmationRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emitted, isEmpty);
      expect(bloc.state, isA<CertificationInitial>());
    });

    test('deja traza de auditoría de la firma capturada (CU-60 transitorio)',
        () async {
      final daos = await _daos('cu52f');
      final hito = await _crearHito(daos.milestones);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au51'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 200)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('firma manuscrita capturada') &&
            l.contains('hito=${hito.id}')),
        isTrue,
      );
    });
  });

  group('CertificationSummaryScreen + SignaturePad (widget) - CU-51/CU-52', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required FakeMilestoneDao milestoneDao,
      required FakeEvidenceDao evidenceDao,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: CertificationSummaryScreen(
          hitoId: 'h1',
          milestoneDao: milestoneDao,
          evidenceDao: evidenceDao,
          // Firma simple de una parte (CU-52 legacy): sin segunda firma.
          requiereDobleFirma: false,
          // CU-55/56/59: seams falsos (sin PDF real, sin disco ni BD).
          actaGenerator: (payload) async =>
              Uint8List.fromList([37, 80, 68, 70]),
          persistActa: ({required Uint8List bytes, required String fileName}) async =>
              'caché/$fileName',
          certificationDao: FakeCertificationDao(),
          auditLog: fakeAuditWriter,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('CU-51: despliega resumen consolidado y habilita el lienzo',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          descripcion: 'Excavación y platea',
          duracionDias: 5,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      final evidenceDao = FakeEvidenceDao();
      evidenceDao.seed([
        Evidence(
          id: 'e1',
          hitoId: 'h1',
          obraId: 'w1',
          tipo: EvidenceType.foto,
          archivo: '',
          nota: 'Fisura menor en V3',
          latitud: -34.6,
          longitud: -58.4,
          precisionMetros: 5,
          fechaCaptura: DateTime(2026, 9, 1, 10, 30),
          tamanoBytes: 1024,
          checksum: 'abc',
          marcaTexto: 'x',
        ),
      ]);

      await pumpScreen(tester, milestoneDao: dao, evidenceDao: evidenceDao);

      expect(find.text('Cimientos'), findsOneWidget);
      expect(find.text('Excavación y platea'), findsOneWidget);
      expect(find.text('Nota: Fisura menor en V3'), findsOneWidget);
      expect(find.byKey(const Key('signature_pad_canvas')), findsOneWidget);
      expect(find.text('Limpiar Pantalla'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      // CU-52 Alt. 2.2: confirmación bloqueada sin trazos.
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('CU-52: trazo válido + Confirmar registra la conformidad',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      final evidenceDao = FakeEvidenceDao();
      evidenceDao.seed([
        Evidence(
          id: 'e1',
          hitoId: 'h1',
          obraId: 'w1',
          tipo: EvidenceType.foto,
          archivo: '',
          latitud: -34.6,
          longitud: -58.4,
          precisionMetros: 5,
          fechaCaptura: DateTime(2026, 9, 1, 10, 30),
          tamanoBytes: 1024,
          checksum: 'abc',
          marcaTexto: 'x',
        ),
      ]);

      await pumpScreen(tester, milestoneDao: dao, evidenceDao: evidenceDao);

      final canvas = find.byKey(const Key('signature_pad_canvas'));
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Con trazo válido, Confirmar queda habilitado.
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Firma registrada: conformidad técnica otorgada.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Alt. 2.2: trazo corto pide reintentar y bloquea la confirmación',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      await pumpScreen(
        tester,
        milestoneDao: dao,
        evidenceDao: FakeEvidenceDao(),
      );

      final canvas = find.byKey(const Key('signature_pad_canvas'));
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      // Alt. 2.2: pide reintentar y el lienzo queda limpio (CU-53).
      expect(
        find.text(
            'Firma inválida o punto accidental: limpie el lienzo y vuelva a trazar su firma.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('CU-53: Limpiar Pantalla vuelve el lienzo a blanco',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      await pumpScreen(
        tester,
        milestoneDao: dao,
        evidenceDao: FakeEvidenceDao(),
      );

      final canvas = find.byKey(const Key('signature_pad_canvas'));
      final gesture = await tester.startGesture(tester.getCenter(canvas));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Limpiar Pantalla'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar'),
            )
            .onPressed,
        isNull,
      );
    });
  });
}
