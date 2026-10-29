import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/cpm/critical_path.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

void main() {
  group('CriticalPath - CU-29 pasos 1-2 (QA-04: algoritmo de grafos)', () {
    test('grafo vacío: duración cero sin críticos', () {
      const result = CriticalPathResult(schedules: {}, projectDuration: 0);

      expect(result.projectDuration, 0);
      expect(result.criticalIds, isEmpty);
    });

    test('nodo único: todo en cero con holgura cero', () {
      final result = CriticalPath.calculate(
        durations: const {'a': 5},
        predecessors: const {},
      );

      expect(result.projectDuration, 5);
      expect(result.criticalIds, {'a'});
      final a = result.schedules['a']!;
      expect((a.earlyStart, a.earlyFinish, a.lateStart, a.lateFinish), (0, 5, 0, 5));
      expect(a.slack, 0);
      expect(a.isCritical, isTrue);
    });

    test('cadena lineal: todo crítico con fechas encadenadas', () {
      final result = CriticalPath.calculate(
        durations: const {'a': 3, 'b': 2},
        predecessors: const {
          'b': {'a'},
        },
      );

      expect(result.projectDuration, 5);
      expect(result.criticalIds, {'a', 'b'});
      final b = result.schedules['b']!;
      expect((b.earlyStart, b.earlyFinish), (3, 5));
      expect((b.lateStart, b.lateFinish), (3, 5));
    });

    test('diamante: rama larga crítica, rama corta con holgura', () {
      // A(3) -> B(2) -> D(1) = 6 días; A(3) -> C(5) -> D(1) = 9 días.
      final result = CriticalPath.calculate(
        durations: const {'a': 3, 'b': 2, 'c': 5, 'd': 1},
        predecessors: const {
          'b': {'a'},
          'c': {'a'},
          'd': {'b', 'c'},
        },
      );

      expect(result.projectDuration, 9);
      expect(result.criticalIds, {'a', 'c', 'd'});
      final b = result.schedules['b']!;
      expect((b.earlyStart, b.earlyFinish), (3, 5));
      expect((b.lateStart, b.lateFinish), (6, 8));
      expect(b.slack, 3);
      expect(b.isCritical, isFalse);
      expect(result.schedules['c']!.slack, 0);
    });

    test('ramas desconectadas: manda la más larga', () {
      final result = CriticalPath.calculate(
        durations: const {'a': 4, 'b': 2},
        predecessors: const {},
      );

      expect(result.projectDuration, 4);
      expect(result.criticalIds, {'a'});
      final b = result.schedules['b']!;
      expect((b.earlyStart, b.earlyFinish), (0, 2));
      expect((b.lateStart, b.lateFinish), (2, 4));
      expect(b.slack, 2);
    });

    test('hito de duración cero como evento del cronograma', () {
      final result = CriticalPath.calculate(
        durations: const {'a': 0, 'b': 3},
        predecessors: const {
          'b': {'a'},
        },
      );

      expect(result.projectDuration, 3);
      expect(result.criticalIds, {'a', 'b'});
      expect(result.schedules['a']!.slack, 0);
    });

    test('ciclo: lanza CriticalPathException (defensa, CU-24 lo impide)', () {
      expect(
        () => CriticalPath.calculate(
          durations: const {'a': 1, 'b': 1},
          predecessors: const {
            'a': {'b'},
            'b': {'a'},
          },
        ),
        throwsA(isA<CriticalPathException>()),
      );
    });

    test('obra realista de 6 hitos con valores dorados', () {
      // Cimientos(5) -> Muros(8) -> Techo(6) -> Pintura(3) = 22 días.
      // Instalaciones(4) tras Muros en paralelo; Piso(2) tras Instalaciones.
      final result = CriticalPath.calculate(
        durations: const {
          'cim': 5,
          'mur': 8,
          'tec': 6,
          'pin': 3,
          'ins': 4,
          'pis': 2,
        },
        predecessors: const {
          'mur': {'cim'},
          'tec': {'mur'},
          'pin': {'tec'},
          'ins': {'mur'},
          'pis': {'ins'},
        },
      );

      expect(result.projectDuration, 22);
      expect(result.criticalIds, {'cim', 'mur', 'tec', 'pin'});
      // Rama paralela: ins ES=13 EF=17 LS=16 LF=20; pis ES=17 EF=19 LS=20 LF=22.
      expect(result.schedules['ins']!.slack, 3);
      expect(result.schedules['pis']!.slack, 3);
      expect(result.schedules['pin']!.earlyStart, 19);
    });
  });

  group('MilestoneLocalDataSource.setCritical - CU-29 paso 4 (BD local)', () {
    test('marca y desmarca críticos por obra en transacción', () async {
      final dao = await openTestDao('cu29');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 3);
      final b = await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 2);
      final other =
          await dao.create(obraId: 'w9', nombre: 'Otra', duracionDias: 9);

      await dao.setCritical(obraId: 'w1', criticalIds: {a.id});
      expect((await dao.getById(a.id))?.esCritico, isTrue);
      expect((await dao.getById(b.id))?.esCritico, isFalse);
      expect((await dao.getById(other.id))?.esCritico, isFalse);

      await dao.setCritical(obraId: 'w1', criticalIds: {});
      expect((await dao.getById(a.id))?.esCritico, isFalse);
    });
  });

  group('MilestonesBloc recalcula tras mutar (CU-29 precondición)', () {
    Future<Map<String, String>> crearCadena(
      MilestonesBloc bloc,
      MilestoneLocalDataSource dao,
    ) async {
      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'A', duracionDias: 3));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'B', duracionDias: 2));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      final Map<String, String> ids = {
        for (final m in await dao.listByObra('w1')) m.nombre: m.id,
      };
      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: ids['B']!,
        predecesorIds: [ids['A']!],
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      return ids;
    }

    test('cadena A->B: ambos críticos tras crear y vincular', () async {
      final dao = await openTestDao('cu29');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final ids = await crearCadena(bloc, dao);

      final loaded = bloc.state as MilestonesLoaded;
      final flags = {for (final m in loaded.milestones) m.nombre: m.esCritico};
      expect(flags, {'A': true, 'B': true});
      expect((await dao.getById(ids['A']!))?.esCritico, isTrue);
    });

    test('rama paralela corta queda no crítica y la cadena sigue crítica',
        () async {
      final dao = await openTestDao('cu29');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      await crearCadena(bloc, dao);
      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'Corta', duracionDias: 1));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      final loaded = bloc.state as MilestonesLoaded;
      final flags = {for (final m in loaded.milestones) m.nombre: m.esCritico};
      expect(flags, {'A': true, 'B': true, 'Corta': false});
    });

    test('eliminar reequilibra los flags (sin huérfanos críticos)', () async {
      final dao = await openTestDao('cu29');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final ids = await crearCadena(bloc, dao);
      // CU-27 exige desvincular antes de borrar: se limpia la arista B->A.
      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: ids['B']!,
        predecesorIds: const [],
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      bloc.add(DeleteMilestoneRequested(hitoId: ids['B']!));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      final loaded = bloc.state as MilestonesLoaded;
      expect(loaded.milestones.map((m) => m.nombre), ['A']);
      expect(loaded.milestones.single.esCritico, isTrue);
    });
  });

  group('Resaltado de críticos - CU-29 poscondición', () {
    Future<void> pumpSection(WidgetTester tester, FakeMilestoneDao dao) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonesSection(
              obraId: 'w1',
              isProfesional: true,
              dataSource: dao,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('el hito crítico muestra el badge CRÍTICA', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'a',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          esCritico: true,
        ),
        const Milestone(
          id: 'b',
          obraId: 'w1',
          nombre: 'Pintura veloz',
          duracionDias: 1,
        ),
      ]);
      await pumpSection(tester, dao);

      expect(find.text('CRÍTICA'), findsOneWidget);
    });

    testWidgets('sin críticos no hay badges', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'a', obraId: 'w1', nombre: 'Cimientos', duracionDias: 5),
      ]);
      await pumpSection(tester, dao);

      expect(find.text('CRÍTICA'), findsNothing);
    });
  });
}
