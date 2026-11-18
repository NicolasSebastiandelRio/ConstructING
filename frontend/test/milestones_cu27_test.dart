import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

const _blockedMessage =
    'No se puede eliminar un hito con progreso o dependencias activas';

void main() {
  group('MilestonesBloc DeleteMilestoneRequested - CU-27', () {
    test('elimina un Pendiente sin edges y refresca (Flujo Normal)', () async {
      final dao = await openTestDao('cu27');
      final created = await dao.create(obraId: 'w1', nombre: 'Temporal', duracionDias: 2);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(DeleteMilestoneRequested(hitoId: created.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      expect(await dao.getById(created.id), isNull);
      expect(await dao.listByObra('w1'), isEmpty);
    });

    test('bloquea En Ejecución y Certificado con el mensaje exacto (Alt. 2.2)',
        () async {
      final dao = await openTestDao('cu27');
      final running = await dao.create(obraId: 'w1', nombre: 'WIP', duracionDias: 2);
      await dao.update(running.copyWith(estado: MilestoneStatus.enEjecucion));
      final done = await dao.create(obraId: 'w1', nombre: 'Hecho', duracionDias: 2);
      await dao.update(done.copyWith(estado: MilestoneStatus.certificado));
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      for (final id in [running.id, done.id]) {
        final expectation = expectLater(
          bloc.stream,
          emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
        );
        bloc.add(DeleteMilestoneRequested(hitoId: id));
        await expectation;
        expect((bloc.state as MilestonesError).message, _blockedMessage);
        expect(await dao.getById(id), isNotNull);
      }
    });

    test('bloquea con predecesores o sucesores aunque esté Pendiente', () async {
      final dao = await openTestDao('cu27');
      final a = await dao.create(obraId: 'w1', nombre: 'A', duracionDias: 1);
      final b = await dao.create(obraId: 'w1', nombre: 'B', duracionDias: 1);
      await dao.addDependency(hitoId: b.id, predecesorId: a.id);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      // A tiene un sucesor (B) y B tiene un predecesor (A): ambos bloqueados.
      for (final id in [a.id, b.id]) {
        final expectation = expectLater(
          bloc.stream,
          emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
        );
        bloc.add(DeleteMilestoneRequested(hitoId: id));
        await expectation;
        expect((bloc.state as MilestonesError).message, _blockedMessage);
      }
      expect(await dao.listByObra('w1'), hasLength(2));
    });

    test('falla si el hito ya no existe', () async {
      final dao = await openTestDao('cu27');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const DeleteMilestoneRequested(hitoId: 'fantasma'));
      await expectation;
    });
  });

  group('DeleteMilestoneDialog + tiles - CU-27 paso 1', () {
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

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('ELIMINAR HITO'), findsOneWidget);
    }

    testWidgets('confirma, elimina, informa y refresca sin el tile', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Temporal', duracionDias: 2),
      ]);
      await pumpSection(tester, dao);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Hito eliminado de la Hoja de Ruta.'), findsOneWidget);
      expect(find.text('ELIMINAR HITO'), findsNothing);
      expect(find.text('Temporal'), findsNothing);
      expect(await dao.getById('h1'), isNull);
    });

    testWidgets('cancelar cierra sin modificar la BD (flujo alterno)', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Temporal', duracionDias: 2),
      ]);
      await pumpSection(tester, dao);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('ELIMINAR HITO'), findsNothing);
      expect(find.text('Temporal'), findsOneWidget);
      expect(await dao.getById('h1'), isNotNull);
    });

    testWidgets('bloqueado por dependencias: permanece abierto con el mensaje',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'a', obraId: 'w1', nombre: 'Base', duracionDias: 1),
        const Milestone(id: 'b', obraId: 'w1', nombre: 'Top', duracionDias: 1),
      ]);
      dao.seedEdges({'b': {'a'}});
      await pumpSection(tester, dao);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(_blockedMessage),
        ),
        findsOneWidget,
      );
      expect(find.text('ELIMINAR HITO'), findsOneWidget);
      expect(await dao.listByObra('w1'), hasLength(2));
    });

    testWidgets('los hitos no Pendiente no ofrecen Eliminar', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'En Curso',
          duracionDias: 2,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      await pumpSection(tester, dao);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });
}
