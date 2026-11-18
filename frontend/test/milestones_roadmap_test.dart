import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/domain/schedule/milestone_schedule.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  group('MilestoneScheduleView - roadmap (fechas + restantes)', () {
    test('ancla el rango a la fecha de inicio de la obra', () {
      final view = MilestoneScheduleView.resolve(
        obraStart: DateTime(2026, 9, 1),
        earlyStart: 10,
        earlyFinish: 15,
        durationDays: 5,
        isCritical: false,
        now: DateTime(2026, 9, 1),
      );

      expect(view.startDate, DateTime(2026, 9, 11));
      expect(view.endDate, DateTime(2026, 9, 16));
      expect(view.remainingDays, 5);
      expect(MilestoneScheduleView.format(view.startDate), '11/09/2026');
      expect(MilestoneScheduleView.format(view.endDate), '16/09/2026');
    });

    test('los restantes bajan con el paso de los días (nunca negativos)', () {
      MilestoneScheduleView resolve(DateTime now) =>
          MilestoneScheduleView.resolve(
            obraStart: DateTime(2026, 9, 1),
            earlyStart: 10,
            earlyFinish: 15,
            durationDays: 5,
            isCritical: true,
            now: now,
          );

      expect(resolve(DateTime(2026, 9, 1)).remainingDays, 5);
      expect(resolve(DateTime(2026, 9, 13)).remainingDays, 3);
      expect(resolve(DateTime(2026, 9, 20)).remainingDays, 0);
      expect(resolve(DateTime(2026, 8, 20)).remainingDays, 5);
    });

    test('formato fecha argentino con ceros', () {
      expect(MilestoneScheduleView.format(DateTime(2026, 1, 5)), '05/01/2026');
    });
  });

  group('MilestonesBloc expone el cronograma en el estado', () {
    test('Loaded trae schedules con ES/EF tras vincular', () async {
      final dao = await openTestDao('roadmap');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(const CreateMilestoneRequested(
          obraId: 'w1', nombre: 'A', duracionDias: 10));
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
      var loaded = bloc.state as MilestonesLoaded;
      final ids = {for (final m in loaded.milestones) m.nombre: m.id};

      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: ids['B']!,
        predecesorIds: [ids['A']!],
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      loaded = bloc.state as MilestonesLoaded;
      final schedules = loaded.schedules;
      expect(schedules[ids['A']]?.earlyStart, 0);
      expect(schedules[ids['A']]?.earlyFinish, 10);
      expect(schedules[ids['B']]?.earlyStart, 10);
      expect(schedules[ids['B']]?.earlyFinish, 12);
    });
  });

  group('Hoja de Ruta cronológica - roadmap en ficha', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      required FakeMilestoneDao dao,
      required String obraFechaInicio,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonesSection(
              obraId: 'w1',
              isProfesional: true,
              dataSource: dao,
              obraFechaInicio: obraFechaInicio,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ordena cronológicamente y muestra fechas y restantes',
        (tester) async {
      final today = DateTime.now();
      final dao = FakeMilestoneDao();
      // Inserción en orden inverso al cronológico para probar el orden.
      dao.seed(const [
        Milestone(id: 'b', obraId: 'w1', nombre: 'Techo', duracionDias: 2),
        Milestone(id: 'a', obraId: 'w1', nombre: 'Cimientos', duracionDias: 10),
      ]);
      dao.seedEdges({
        'b': {'a'},
      });
      await pumpSection(tester, dao: dao, obraFechaInicio: _iso(today));

      // Orden cronológico: Cimientos (día 0-10) antes que Techo (día 10-12).
      final dyA = tester.getTopLeft(find.text('Cimientos')).dy;
      final dyB = tester.getTopLeft(find.text('Techo')).dy;
      expect(dyA, lessThan(dyB));

      final endA = today.add(const Duration(days: 10));
      expect(
        find.text(
          '${MilestoneScheduleView.format(today)} → ${MilestoneScheduleView.format(endA)}',
        ),
        findsOneWidget,
      );
      expect(find.text('Quedan 10 días'), findsOneWidget);
      expect(find.text('Quedan 2 días'), findsOneWidget);
    });

    testWidgets('sin ancla muestra días relativos', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'a', obraId: 'w1', nombre: 'Cimientos', duracionDias: 10),
      ]);
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

      // Sin obraFechaInicio no hay fechas ni restantes, solo duración relativa.
      expect(find.text('10 días · Pendiente'), findsOneWidget);
      expect(find.textContaining('Quedan'), findsNothing);
      expect(find.textContaining('→'), findsNothing);
    });
  });
}
