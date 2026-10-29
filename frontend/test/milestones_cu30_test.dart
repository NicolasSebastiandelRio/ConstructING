import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/data/datasources/estimated_end_writer.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/screens/work_detail_screen.dart';

import 'milestones_test_helpers.dart';

/// Writer falso que registra los intentos de escritura (CU-30).
class _FakeWriter implements EstimatedEndWriter {
  final List<({String obraId, int days})> calls = [];
  Exception? failWith;

  @override
  Future<String> write({
    required String obraId,
    required int projectDurationDays,
  }) async {
    calls.add((obraId: obraId, days: projectDurationDays));
    if (failWith != null) throw failWith!;
    return '2026-09-23';
  }
}

/// Data source de obras falso para el writer (CU-30).
class _FakeWorksDs implements WorksRemoteDataSource {
  String fechaInicio = '2026-01-28';
  String? lastUpdateId;
  Map<String, dynamic>? lastUpdatePayload;
  Exception? failWith;

  WorkModel _obra() => WorkModel(
        id: 'w1',
        nombre: 'Obra',
        direccion: 'Calle 123',
        fechaInicio: fechaInicio,
        fechaFinEstimada: '2026-09-23',
        estado: 'En Planificación',
        latitud: null,
        longitud: null,
        progreso: 0.0,
        profesionalId: 'prof-1',
      );

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => [];

  @override
  Future<WorkModel> getWorkById(String id) async => _obra();

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    if (failWith != null) throw failWith!;
    lastUpdateId = id;
    lastUpdatePayload = Map.of(workData);
    return _obra();
  }

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

void main() {
  group('WorksApiEstimatedEndWriter - CU-30 pasos 1-3', () {
    test('suma la duración al inicio y hace PATCH (con cambio de mes)', () async {
      final works = _FakeWorksDs();
      final writer = WorksApiEstimatedEndWriter(works: works);

      final iso = await writer.write(obraId: 'w1', projectDurationDays: 10);

      // 2026-01-28 + 10 días = 2026-02-07.
      expect(iso, '2026-02-07');
      expect(works.lastUpdateId, 'w1');
      expect(works.lastUpdatePayload, {'fechaFinEstimada': '2026-02-07'});
    });

    test('falla si la obra no tiene fecha de inicio válida', () async {
      final works = _FakeWorksDs()..fechaInicio = 'no-fecha';
      final writer = WorksApiEstimatedEndWriter(works: works);

      await expectLater(
        writer.write(obraId: 'w1', projectDurationDays: 5),
        throwsA(isA<Exception>()),
      );
      expect(works.lastUpdatePayload, isNull);
    });

    test('propaga los errores de red (el bloc los tolera)', () async {
      final works = _FakeWorksDs()..failWith = Exception('Sin conexión');
      final writer = WorksApiEstimatedEndWriter(works: works);

      await expectLater(
        writer.write(obraId: 'w1', projectDurationDays: 5),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MilestonesBloc escribe la fecha estimada tras recalcular (CU-30)', () {
    test('tras crear, invoca al writer con la duración total', () async {
      final dao = await openTestDao('cu30');
      final writer = _FakeWriter();
      final bloc = MilestonesBloc(dataSource: dao, scheduleWriter: writer);
      addTearDown(bloc.close);

      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'A', duracionDias: 7));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      expect(writer.calls, [(obraId: 'w1', days: 7)]);
    });

    test('si el writer falla, el flujo local igual tiene éxito (best-effort)',
        () async {
      final dao = await openTestDao('cu30');
      final writer = _FakeWriter()..failWith = Exception('Sin conexión');
      final bloc = MilestonesBloc(dataSource: dao, scheduleWriter: writer);
      addTearDown(bloc.close);

      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'A', duracionDias: 7));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      expect(writer.calls, hasLength(1));
      expect((await dao.listByObra('w1')).single.nombre, 'A');
    });

    test('sin writer no intenta escribir (flujo clásico)', () async {
      final dao = await openTestDao('cu30');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'A', duracionDias: 7));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
    });
  });

  group('Ficha muestra el fin estimado - CU-30 display', () {
    Future<void> pumpFicha(WidgetTester tester) async {
      final worksBloc = WorksBloc(worksRemoteDataSource: _FakeWorksDs());
      const obra = WorkModel(
        id: 'w1',
        nombre: 'Obra Planificada',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        fechaFinEstimada: '2026-09-23',
        estado: 'En Ejecución',
        latitud: null,
        longitud: null,
        progreso: 0.0,
        profesionalId: 'prof-1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WorksBloc>.value(
            value: worksBloc,
            child: WorkDetailScreen(work: obra, userRole: 'Profesional'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('exhibe la fecha estimada de la ruta crítica', (tester) async {
      await pumpFicha(tester);

      expect(find.text('Fin Estimado (Ruta Crítica)'), findsOneWidget);
      expect(find.text('2026-09-23'), findsOneWidget);
    });
  });
}
