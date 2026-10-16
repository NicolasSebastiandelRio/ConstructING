import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/timeline_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/timeline_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/timeline_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/screens/timeline_screen.dart';

import 'milestones_test_helpers.dart';

/// DAO de evidencias fake para el Detalle Técnico del CU-65.
///
/// Extiende el DAO real para heredar la firma y anular solo el acceso a
/// datos: los widget tests NO abren BD real (el FFI cuelga la finalización
/// del test).
class _FakeEvidenceDao extends EvidenceLocalDataSource {
  _FakeEvidenceDao([List<Evidence> evidences = const []])
      : _evidences = evidences,
        super(localDatabase: LocalDatabase());

  final List<Evidence> _evidences;

  @override
  Future<List<Evidence>> listByHito(String hitoId) async =>
      _evidences.where((e) => e.hitoId == hitoId).toList();
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required FakeMilestoneDao dao,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TimelineScreen(
        obraId: 'w1',
        obraNombre: 'Torre Alfa',
        obraFechaInicio: '2026-01-05',
        dataSource: dao,
        evidenceDao: _FakeEvidenceDao(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CU-64 Línea de Tiempo - TimelineBloc', () {
    test('ordena los hitos por inicio temprano y calcula el cronograma',
        () async {
      final dao = await openTestDao('timeline_order');
      // Se crea PRIMERO el hito dependiente: el orden de creación (y el de
      // la BD) no es el orden cronológico que debe exponer el bloc.
      final fundaciones = await dao.create(
        obraId: 'w1',
        nombre: 'Fundaciones',
        duracionDias: 4,
      );
      final excavacion = await dao.create(
        obraId: 'w1',
        nombre: 'Excavación',
        duracionDias: 3,
      );
      await dao.addDependency(
        hitoId: fundaciones.id,
        predecesorId: excavacion.id,
      );

      final bloc = TimelineBloc(dataSource: dao);
      addTearDown(bloc.close);
      // Se escucha ANTES de despachar el evento (el stream del bloc no
      // reemite estados pasados).
      final loaded =
          bloc.stream.firstWhere((state) => state is TimelineLoaded);
      bloc.add(const LoadTimeline(obraId: 'w1'));
      final state = await loaded as TimelineLoaded;

      // CU-64 paso 2: orden cronológico por inicio temprano.
      expect(
        state.hitos.map((h) => h.nombre).toList(),
        ['Excavación', 'Fundaciones'],
      );
      // CU-29: cronograma calculado y aristas recuperadas.
      expect(state.schedules.length, 2);
      expect(state.schedules[excavacion.id]!.earlyStart, 0);
      expect(state.schedules[fundaciones.id]!.earlyStart, 3);
      expect(state.edges[fundaciones.id], contains(excavacion.id));
    });

    test('ante un grafo circular no explota: cronograma vacío y línea de '
        'tiempo igual visible', () async {
      final dao = await openTestDao('timeline_cycle');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 2);
      final b = await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 2);
      await dao.addDependency(hitoId: a.id, predecesorId: b.id);
      await dao.addDependency(hitoId: b.id, predecesorId: a.id);

      final bloc = TimelineBloc(dataSource: dao);
      addTearDown(bloc.close);
      final loaded =
          bloc.stream.firstWhere((state) => state is TimelineLoaded);
      bloc.add(const LoadTimeline(obraId: 'w1'));
      final state = await loaded as TimelineLoaded;

      // CU-64 Alt. 2.1/2.2: sin cronograma, pero la obra se sigue mostrando.
      expect(state.schedules, isEmpty);
      expect(state.hitos.length, 2);
      expect(state.edges.length, 2);
    });
  });

  group('CU-64 Línea de Tiempo - pantalla', () {
    testWidgets('con hitos muestra la línea de tiempo vertical con ambos '
        'nombres y su secuencia', (tester) async {
      final dao = FakeMilestoneDao()
        ..seed([
          const Milestone(
            id: 'h1',
            obraId: 'w1',
            nombre: 'Excavación',
            duracionDias: 3,
          ),
          const Milestone(
            id: 'h2',
            obraId: 'w1',
            nombre: 'Fundaciones',
            duracionDias: 4,
          ),
        ]);

      await _pumpTimeline(tester, dao: dao);

      expect(find.text('Excavación'), findsOneWidget);
      expect(find.text('Fundaciones'), findsOneWidget);
      expect(find.text('HITO 1 DE 2'), findsOneWidget);
      expect(find.text('HITO 2 DE 2'), findsOneWidget);
      // Rango de fechas anclado al inicio de obra (DD/MM/AAAA).
      expect(find.text('05/01/2026 → 08/01/2026'), findsOneWidget);
      expect(find.textContaining('Quedan'), findsNWidgets(2));
    });

    testWidgets('sin hitos muestra EXACTAMENTE el mensaje del Alt. 2.1/2.2',
        (tester) async {
      await _pumpTimeline(tester, dao: FakeMilestoneDao());

      expect(find.text(TimelineScreen.emptyStateMessage), findsOneWidget);
      expect(
        find.text('Aún no se han registrado avances en este proyecto'),
        findsOneWidget,
      );
    });

    testWidgets('tocar un hito navega al Detalle Técnico (CU-65 paso 1)',
        (tester) async {
      final dao = FakeMilestoneDao()
        ..seed([
          const Milestone(
            id: 'h1',
            obraId: 'w1',
            nombre: 'Excavación',
            descripcion: 'Retiro de suelo vegetal',
            duracionDias: 3,
          ),
        ]);

      await _pumpTimeline(tester, dao: dao);
      await tester.ensureVisible(find.text('Excavación'));
      await tester.tap(find.text('Excavación'));
      await tester.pumpAndSettle();

      expect(find.text('DETALLE TÉCNICO DEL HITO'), findsOneWidget);
      expect(find.text('Retiro de suelo vegetal'), findsOneWidget);
      // El fake de evidencias evita abrir la BD real dentro del test.
      expect(
        find.text('Sin evidencia registrada para esta etapa'),
        findsOneWidget,
      );
    });
  });
}
