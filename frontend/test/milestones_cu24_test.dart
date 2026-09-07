import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/domain/graph/milestone_graph.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

const _a = Milestone(id: 'a', obraId: 'w1', nombre: 'A', duracionDias: 3);
const _b = Milestone(id: 'b', obraId: 'w1', nombre: 'B', duracionDias: 2);
const _c = Milestone(id: 'c', obraId: 'w1', nombre: 'C', duracionDias: 4);
const _d = Milestone(id: 'd', obraId: 'w1', nombre: 'D', duracionDias: 1);

void main() {
  group('MilestoneGraph - CU-24 paso 2 (detección en memoria)', () {
    test('cadena lineal y diamante no son ciclos', () {
      expect(MilestoneGraph.hasCycle({'b': {'a'}, 'c': {'b'}}), isFalse);
      expect(
        MilestoneGraph.hasCycle({
          'b': {'a'},
          'c': {'a'},
          'd': {'b', 'c'},
        }),
        isFalse,
      );
      expect(MilestoneGraph.hasCycle({}), isFalse);
    });

    test('detecta ciclo directo A<->B (Alt. 2.1 de la spec)', () {
      expect(
        MilestoneGraph.hasCycle({'a': {'b'}, 'b': {'a'}}),
        isTrue,
      );
    });

    test('detecta auto-dependencia', () {
      expect(MilestoneGraph.hasCycle({'a': {'a'}}), isTrue);
    });

    test('detecta ciclo largo A->B->C->A', () {
      expect(
        MilestoneGraph.hasCycle({'b': {'a'}, 'c': {'b'}, 'a': {'c'}}),
        isTrue,
      );
    });

    test('wouldCreateCycle evalúa el grafo resultante', () {
      // Cadena A->B->C: que C dependa de A cierra el ciclo... no: C ya
      // depende de B que depende de A; agregar A como predecesor de C no
      // crea ciclo (A no depende de C). En cambio B->A sí lo crea.
      expect(
        MilestoneGraph.wouldCreateCycle(
          existing: {'b': {'a'}, 'c': {'b'}},
          hitoId: 'c',
          newPredecessors: {'a', 'b'},
        ),
        isFalse,
      );
      expect(
        MilestoneGraph.wouldCreateCycle(
          existing: {'b': {'a'}, 'c': {'b'}},
          hitoId: 'a',
          newPredecessors: {'c'},
        ),
        isTrue,
      );
      expect(
        MilestoneGraph.wouldCreateCycle(
          existing: {'b': {'a'}},
          hitoId: 'b',
          newPredecessors: {},
        ),
        isFalse,
      );
    });
  });

  group('MilestoneLocalDataSource.dependencyMap - CU-24 (BD local)', () {
    test('devuelve el mapa hito -> predecesores acotado a la obra', () async {
      final dao = await openTestDao('cu24');
      await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 3);
      await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 2);
      await dao.create(obraId: 'w9', nombre: 'Otra', duracionDias: 1);
      final ids = (await dao.listByObra('w1')).map((m) => m.id).toList();
      final other = (await dao.listByObra('w9')).single.id;
      await dao.addDependency(hitoId: ids[1], predecesorId: ids[0]);
      await dao.addDependency(hitoId: other, predecesorId: ids[0]);

      final map = await dao.dependencyMap('w1');

      expect(map.keys.toSet(), ids.toSet());
      expect(map[ids[1]], {ids[0]});
      expect(map[ids[0]], isEmpty);
    });
  });

  group('MilestonesBloc SetDependenciesRequested - CU-24', () {
    test('guarda las aristas y refresca con el mapa', () async {
      final dao = await openTestDao('cu24');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 3);
      final b = await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 2);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: b.id,
        predecesorIds: [a.id],
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      final loaded = bloc.state as MilestonesLoaded;
      expect(loaded.edges[b.id], {a.id});
      expect(await dao.predecessorIds(b.id), [a.id]);
    });

    test('bloquea el ciclo con el mensaje exacto sin tocar la BD (Alt. 2.2)', () async {
      final dao = await openTestDao('cu24');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 3);
      final b = await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 2);
      await dao.addDependency(hitoId: b.id, predecesorId: a.id);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      // A depende de B cuando B ya depende de A → ciclo.
      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: a.id,
        predecesorIds: [b.id],
      ));
      await expectation;

      final error = bloc.state as MilestonesError;
      expect(error.message, 'Referencia circular detectada');
      expect(await dao.predecessorIds(a.id), isEmpty);
    });

    test('rechaza predecesores de otra obra y el hito inexistente', () async {
      final dao = await openTestDao('cu24');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 3);
      final other = await dao.create(obraId: 'w9', nombre: 'Otra', duracionDias: 1);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      var expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: a.id,
        predecesorIds: [other.id],
      ));
      await expectation;
      expect((bloc.state as MilestonesError).message, contains('no pertenecen'));

      expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const SetDependenciesRequested(
        obraId: 'w1',
        hitoId: 'fantasma',
        predecesorIds: [],
      ));
      await expectation;
    });
  });

  group('DependenciesDialog + sección - CU-24 pasos 1-3', () {
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

    Future<void> openDialogForFirst(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.link_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('AGREGAR PREDECESOR'), findsOneWidget);
    }

    testWidgets('lista candidatos sin el propio y guarda la selección', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([_a, _b]);
      await pumpSection(tester, dao);
      await openDialogForFirst(tester);

      // Solo B es candidato para A (A se excluye a sí mismo).
      expect(find.byType(CheckboxListTile), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('B')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('A'),
        ),
        findsNothing,
      );

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Guardar dependencias'));
      await tester.pumpAndSettle();

      expect(find.text('Dependencias guardadas.'), findsOneWidget);
      expect(find.text('AGREGAR PREDECESOR'), findsNothing);
      final edges = await dao.predecessorIds('a');
      expect(edges, ['b']);
    });

    testWidgets('rechaza en vivo la selección que cierra un ciclo (Alt. 2.2)', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([_a, _b, _c, _d]);
      // B depende de A: si A pasa a depender de B hay ciclo A<->B.
      dao.seedEdges({'b': {'a'}});
      await pumpSection(tester, dao);
      await openDialogForFirst(tester);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();

      // Mensaje exacto de la spec y el tilde no queda marcado.
      expect(find.text('Referencia circular detectada'), findsOneWidget);
      final tile =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first);
      expect(tile.value, isFalse);
      expect(await dao.predecessorIds('a'), isEmpty);
    });

    testWidgets('sin dos hitos no ofrece vincular (precondición)', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([_a]);
      await pumpSection(tester, dao);

      expect(find.byIcon(Icons.link_outlined), findsNothing);
    });

    testWidgets('la ficha muestra "Depende de" con los nombres', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([_a, _b]);
      dao.seedEdges({'b': {'a'}});
      await pumpSection(tester, dao);

      expect(find.text('Depende de: A'), findsOneWidget);
    });
  });
}
