import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

Future<String> _crear(
  MilestoneLocalDataSource dao, {
  String nombre = 'Hito',
  MilestoneStatus estado = MilestoneStatus.pendiente,
}) async {
  final created = await dao.create(obraId: 'w1', nombre: nombre, duracionDias: 3);
  if (estado != MilestoneStatus.pendiente) {
    await dao.update(created.copyWith(estado: estado));
  }
  return created.id;
}

void main() {
  group('MilestonesBloc AdvanceMilestoneStatus - CU-26', () {
    test('inicia un Pendiente sin predecesores (Flujo Normal)', () async {
      final dao = await openTestDao('cu26');
      final id = await _crear(dao);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(AdvanceMilestoneStatus(hitoId: id));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      expect((await dao.getById(id))?.estado, MilestoneStatus.enEjecucion);
    });

    test('inicia si los predecesores están Certificados (CU-28 autoriza)', () async {
      final dao = await openTestDao('cu26');
      final cert = await dao.create(obraId: 'w1', nombre: 'Base', duracionDias: 2);
      await dao.update(cert.copyWith(estado: MilestoneStatus.certificado));
      final id = await _crear(dao, nombre: 'Top');
      await dao.addDependency(hitoId: id, predecesorId: cert.id);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(AdvanceMilestoneStatus(hitoId: id));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      expect((await dao.getById(id))?.estado, MilestoneStatus.enEjecucion);
    });

    test('deniega el inicio con predecesor pendiente intacto (CU-28 Alt. 2.2)', () async {
      final dao = await openTestDao('cu26');
      final base = await dao.create(obraId: 'w1', nombre: 'Base', duracionDias: 2);
      final id = await _crear(dao, nombre: 'Top');
      await dao.addDependency(hitoId: id, predecesorId: base.id);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(AdvanceMilestoneStatus(hitoId: id));
      await expectation;

      expect((await dao.getById(id))?.estado, MilestoneStatus.pendiente);
      final error = bloc.state as MilestonesError;
      expect(error.message, contains('bloqueado'));
      expect(error.message, contains('Base'));
    });

    test('certifica un En Ejecución sin revalidar predecesores', () async {
      final dao = await openTestDao('cu26');
      final base = await dao.create(obraId: 'w1', nombre: 'Base', duracionDias: 2);
      final running = await dao.create(obraId: 'w1', nombre: 'Top', duracionDias: 2);
      await dao.update(running.copyWith(estado: MilestoneStatus.enEjecucion));
      await dao.addDependency(hitoId: running.id, predecesorId: base.id);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(AdvanceMilestoneStatus(hitoId: running.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      expect((await dao.getById(running.id))?.estado, MilestoneStatus.certificado);
    });

    test('rechaza avanzar un Certificado o un hito inexistente', () async {
      final dao = await openTestDao('cu26');
      final done = await _crear(dao, estado: MilestoneStatus.certificado);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      var expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(AdvanceMilestoneStatus(hitoId: done));
      await expectation;
      expect((bloc.state as MilestonesError).message, contains('certificado'));

      expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const AdvanceMilestoneStatus(hitoId: 'fantasma'));
      await expectation;
    });

    test('deja traza de auditoría del cambio (CU-26 paso 4 transitorio)', () async {
      final dao = await openTestDao('cu26');
      final id = await _crear(dao);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      bloc.add(AdvanceMilestoneStatus(hitoId: id));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('hito=$id') &&
            l.contains('Pendiente → En Ejecución')),
        isTrue,
      );
    });
  });

  group('AdvanceStatusDialog + tiles - CU-26 paso 1', () {
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

    testWidgets('confirma el inicio y refresca con éxito', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Cimientos', duracionDias: 5),
      ]);
      await pumpSection(tester, dao);

      await tester.tap(find.byIcon(Icons.play_arrow_outlined));
      await tester.pumpAndSettle();
      expect(find.text('INICIAR HITO'), findsOneWidget);

      await tester.tap(find.text('Iniciar'));
      await tester.pumpAndSettle();

      expect(find.text('Hito en ejecución.'), findsOneWidget);
      expect(find.text('INICIAR HITO'), findsNothing);
      expect((await dao.getById('h1'))?.estado, MilestoneStatus.enEjecucion);
      expect(find.textContaining('En Ejecución'), findsWidgets);
    });

    testWidgets('denegado por CU-28: permanece abierto con el mensaje', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'a', obraId: 'w1', nombre: 'Base', duracionDias: 2),
        const Milestone(id: 'b', obraId: 'w1', nombre: 'Top', duracionDias: 2),
      ]);
      dao.seedEdges({'b': {'a'}});
      await pumpSection(tester, dao);

      // El segundo play corresponde al hito Top (bloqueado por Base).
      await tester.tap(find.byIcon(Icons.play_arrow_outlined).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('bloqueado'),
        ),
        findsOneWidget,
      );
      expect(find.text('INICIAR HITO'), findsOneWidget);
      expect((await dao.getById('b'))?.estado, MilestoneStatus.pendiente);
    });

    testWidgets('los hitos Certificados no ofrecen avance', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Hecho',
          duracionDias: 5,
          estado: MilestoneStatus.certificado,
        ),
      ]);
      await pumpSection(tester, dao);

      expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.link_outlined), findsNothing);
    });
  });
}
