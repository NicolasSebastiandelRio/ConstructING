import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

Future<Milestone> _crearHito(
  MilestoneLocalDataSource dao, {
  String nombre = 'Hito',
  MilestoneStatus estado = MilestoneStatus.pendiente,
}) async {
  final created =
      await dao.create(obraId: 'w1', nombre: nombre, duracionDias: 3);
  if (estado != MilestoneStatus.pendiente) {
    await dao.update(created.copyWith(estado: estado));
  }
  return created;
}

void main() {
  group('MilestonesBloc RequestMilestoneCertification - CU-50', () {
    test('Flujo Normal: hito En Ejecución con evidencia entra en flujo de certificación',
        () async {
      final daos = await openSharedTestDaos('cu50');
      final hito =
          await _crearHito(daos.milestones, estado: MilestoneStatus.enEjecucion);
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      bloc.add(RequestMilestoneCertification(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<MilestonesLoading>(),
          isA<MilestoneCertificationReady>(),
        ]),
      );

      final ready = bloc.state as MilestoneCertificationReady;
      expect(ready.hitoId, hito.id);
      expect(ready.hitoNombre, 'Hito');
      // Poscondición: entra en flujo de certificación; el estado técnico
      // sigue En Ejecución hasta completar la doble firma (CU-52+).
      expect(
        (await daos.milestones.getById(hito.id))?.estado,
        MilestoneStatus.enEjecucion,
      );
    });

    test('Alt. 2.1/2.2: sin evidencia bloquea con el mensaje exacto de la spec',
        () async {
      final daos = await openSharedTestDaos('cu50b');
      final hito =
          await _crearHito(daos.milestones, estado: MilestoneStatus.enEjecucion);

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<MilestonesLoading>(),
          isA<MilestoneCertificationBlocked>(),
        ]),
      );
      bloc.add(RequestMilestoneCertification(hitoId: hito.id));
      await expectation;

      final blocked = bloc.state as MilestoneCertificationBlocked;
      expect(blocked.hitoId, hito.id);
      expect(
        blocked.message,
        'No se puede certificar: debe cargar evidencia visual del avance',
      );
      // Bloqueado: el hito permanece En Ejecución (retorno al detalle).
      expect(
        (await daos.milestones.getById(hito.id))?.estado,
        MilestoneStatus.enEjecucion,
      );
    });

    test('una evidencia ya sincronizada (caché liberado) habilita el cierre',
        () async {
      final daos = await openSharedTestDaos('cu50c');
      final hito =
          await _crearHito(daos.milestones, estado: MilestoneStatus.enEjecucion);
      await seedEvidence(
        daos.evidences,
        hitoId: hito.id,
        obraId: hito.obraId,
        sincronizada: true,
      );

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      bloc.add(RequestMilestoneCertification(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<MilestonesLoading>(),
          isA<MilestoneCertificationReady>(),
        ]),
      );
    });

    test('Precondición: un hito Pendiente no puede solicitar el cierre',
        () async {
      final daos = await openSharedTestDaos('cu50d');
      final hito = await _crearHito(daos.milestones);

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<MilestonesLoading>(),
          isA<MilestoneCertificationBlocked>(),
        ]),
      );
      bloc.add(RequestMilestoneCertification(hitoId: hito.id));
      await expectation;

      expect((bloc.state as MilestoneCertificationBlocked).message,
          contains('En Ejecución'));
    });

    test('hito inexistente → error', () async {
      final daos = await openSharedTestDaos('cu50e');
      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const RequestMilestoneCertification(hitoId: 'fantasma'));
      await expectation;

      expect((bloc.state as MilestonesError).message,
          contains('ya no existe'));
    });

    test('el avance directo a Certificado queda bloqueado: se exige CU-50',
        () async {
      final daos = await openSharedTestDaos('cu50f');
      final hito =
          await _crearHito(daos.milestones, estado: MilestoneStatus.enEjecucion);
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(AdvanceMilestoneStatus(hitoId: hito.id));
      await expectation;

      expect((bloc.state as MilestonesError).message, contains('CU-50'));
      expect(
        (await daos.milestones.getById(hito.id))?.estado,
        MilestoneStatus.enEjecucion,
      );
    });

    test('deja traza de auditoría de la solicitud (CU-60 transitorio)',
        () async {
      final daos = await openSharedTestDaos('cu50g');
      final hito =
          await _crearHito(daos.milestones, estado: MilestoneStatus.enEjecucion);
      await seedEvidence(daos.evidences, hitoId: hito.id, obraId: hito.obraId);

      final bloc = MilestonesBloc(
        dataSource: daos.milestones,
        evidenceDao: daos.evidences,
      );
      addTearDown(bloc.close);

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      bloc.add(RequestMilestoneCertification(hitoId: hito.id));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<MilestonesLoading>(),
          isA<MilestoneCertificationReady>(),
        ]),
      );

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('certificación solicitada') &&
            l.contains('hito=${hito.id}') &&
            l.contains('estado=En Ejecución')),
        isTrue,
      );
    });
  });

  group('AdvanceStatusDialog Certificar Etapa - CU-50 paso 1 (widget)', () {
    testWidgets('Alt. 2.2: sin evidencia retorna al detalle con el mensaje exacto',
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
      // Sin DAO de evidencias → fail-closed: cuenta cero evidencias.
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

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('CERTIFICAR ETAPA'), findsOneWidget);

      await tester.tap(find.text('Certificar Etapa'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
              'No se puede certificar: debe cargar evidencia visual del avance'),
        ),
        findsOneWidget,
      );
      // Alt. 2.2: retorna al detalle del hito (el diálogo se cerró).
      expect(find.text('CERTIFICAR ETAPA'), findsNothing);
      expect(find.textContaining('En Ejecución'), findsWidgets);
      expect((await dao.getById('h1'))?.estado, MilestoneStatus.enEjecucion);
    });

    testWidgets('los hitos En Ejecución ofrecen Certificar Etapa (CU-50)',
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

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('CERTIFICAR ETAPA'), findsOneWidget);
      expect(
        find.textContaining('cierre formal de la etapa "Cimientos"'),
        findsOneWidget,
      );
    });
  });
}
