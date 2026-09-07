import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/new_milestone_modal.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/edit_milestone_modal.dart';

import 'milestones_test_helpers.dart';

void main() {
  group('Milestone - entidad y validación (CU-23 + CU-16)', () {
    test('valida nombre obligatorio y duración no negativa', () {
      expect(Milestone.validateNombre(''), 'El nombre del hito es obligatorio.');
      expect(Milestone.validateNombre(null), 'El nombre del hito es obligatorio.');
      expect(Milestone.validateNombre('Cimientos'), isNull);

      expect(Milestone.validateDuracion(''), 'La duración estimada es obligatoria.');
      expect(Milestone.validateDuracion('-3'),
          'La duración debe ser un número mayor o igual a 0.');
      expect(Milestone.validateDuracion('abc'),
          'La duración debe ser un número mayor o igual a 0.');
      expect(Milestone.validateDuracion('0'), isNull);
      expect(Milestone.validateDuracion('10'), isNull);
    });

    test('etiquetas de estado exactas de la spec', () {
      expect(MilestoneStatus.pendiente.label, 'Pendiente');
      expect(MilestoneStatus.enEjecucion.label, 'En Ejecución');
      expect(MilestoneStatus.certificado.label, 'Certificado');
      expect(MilestoneStatus.fromLabel('En Ejecución'), MilestoneStatus.enEjecucion);
      expect(MilestoneStatus.fromLabel('¿?'), MilestoneStatus.pendiente);
    });

    test('roundtrip a la fila local preservando flags', () {
      const milestone = Milestone(
        id: 'h1',
        obraId: 'w1',
        nombre: 'Cimientos',
        duracionDias: 10,
      );
      final restored = Milestone.fromLocalDb(
        milestone.toLocalDb(nowIso: '2026-09-06T00:00:00.000Z'),
      );

      expect(restored, milestone);
      expect(restored.estado, MilestoneStatus.pendiente);
      expect(restored.esCritico, isFalse);
      expect(restored.esSincronizado, isFalse);
    });
  });

  group('MilestoneLocalDataSource - CU-23 paso 4 (BD local)', () {
    test('crea el hito en Pendiente, sin sincronizar', () async {
      final dao = await openTestDao('cu23');

      final created = await dao.create(
        obraId: 'w1',
        nombre: 'Cimientos',
        descripcion: 'Excavación y platea',
        duracionDias: 10,
      );

      expect(created.id, isNotEmpty);
      expect(created.estado, MilestoneStatus.pendiente);
      expect(created.esSincronizado, isFalse);

      final list = await dao.listByObra('w1');
      expect(list, hasLength(1));
      expect(list.first.nombre, 'Cimientos');
    });

    test('rechaza nombre vacío y duración negativa sin persistir', () async {
      final dao = await openTestDao('cu23');

      await expectLater(
        dao.create(obraId: 'w1', nombre: '  ', duracionDias: 5),
        throwsA(isA<CacheStorageException>()),
      );
      await expectLater(
        dao.create(obraId: 'w1', nombre: 'X', duracionDias: -1),
        throwsA(isA<CacheStorageException>()),
      );
      expect(await dao.listByObra('w1'), isEmpty);
    });

    test('listByObra filtra por obra y ordena por creación', () async {
      final dao = await openTestDao('cu23');
      await dao.create(obraId: 'w1', nombre: 'Primero', duracionDias: 1);
      await dao.create(obraId: 'w2', nombre: 'Otra obra', duracionDias: 1);
      await dao.create(obraId: 'w1', nombre: 'Segundo', duracionDias: 2);

      final list = await dao.listByObra('w1');
      expect(list.map((m) => m.nombre), ['Primero', 'Segundo']);
    });
  });

  group('MilestonesBloc - CU-23 (Hoja de Ruta)', () {
    test('LoadMilestones emite Loaded con la lista local', () async {
      final dao = await openTestDao('cu23');
      await dao.create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 10);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );
      bloc.add(const LoadMilestones(obraId: 'w1'));
      await expectation;

      final loaded = bloc.state as MilestonesLoaded;
      expect(loaded.milestones, hasLength(1));
    });

    test('CreateMilestoneRequested inválido emite Error sin persistir', () async {
      final dao = await openTestDao('cu23');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const CreateMilestoneRequested(obraId: 'w1', nombre: '', duracionDias: 5));
      await expectation;
      expect(await dao.listByObra('w1'), isEmpty);
    });

    test('CreateMilestoneRequested válido persiste y refresca', () async {
      final dao = await openTestDao('cu23');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(const CreateMilestoneRequested(
        obraId: 'w1',
        nombre: 'Cimientos',
        descripcion: 'Excavación',
        duracionDias: 10,
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      final loaded = bloc.state as MilestonesLoaded;
      expect(loaded.milestones.single.nombre, 'Cimientos');
    });
  });

  group('NewMilestoneModal + MilestonesSection (CU-23 pasos 1-3)', () {
    /// Los widget tests usan DAO fake en memoria: abrir FFI real dentro de
    /// testWidgets cuelga la finalización del test en este entorno (el DAO
    /// real queda cubierto por el grupo anterior, con tests planos).
    testWidgets('resalta faltantes y no envía (Alt. CU-16)', (tester) async {
      final dao = FakeMilestoneDao();
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<MilestonesBloc>.value(
              value: bloc,
              child: const NewMilestoneModal(obraId: 'w1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pump();

      expect(find.text('El nombre del hito es obligatorio.'), findsOneWidget);
      expect(find.text('La duración estimada es obligatoria.'), findsOneWidget);
      expect(dao.createCalls, 0);
      expect(find.text('AÑADIR HITO'), findsOneWidget);
    });

    testWidgets('completa el flujo: guarda, cierra e informa éxito', (tester) async {
      final dao = FakeMilestoneDao();
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (pageContext) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(pageContext).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider<MilestonesBloc>.value(
                        value: bloc,
                        child: const Scaffold(body: NewMilestoneModal(obraId: 'w1')),
                      ),
                    ),
                  ),
                  child: const Text('Abrir alta'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir alta'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Cimientos');
      await tester.enterText(fields.at(1), 'Excavación y platea');
      await tester.enterText(fields.at(2), '10');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Hito registrado en la Hoja de Ruta.'), findsOneWidget);
      expect(find.text('AÑADIR HITO'), findsNothing);
      expect(dao.createCalls, 1);
      expect((await dao.listByObra('w1')).single.nombre, 'Cimientos');
    });

    testWidgets('la sección lista los hitos y oculta el alta si no es Profesional',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Cimientos', duracionDias: 10),
      ]);

      // Sección REAL con DAO fake inyectado.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonesSection(
              obraId: 'w1',
              isProfesional: false,
              dataSource: dao,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOJA DE RUTA'), findsOneWidget);
      expect(find.text('Cimientos'), findsOneWidget);
      expect(find.text('10 días · Pendiente'), findsOneWidget);
      expect(find.text('Añadir Hito'), findsNothing);
    });

    testWidgets('el Profesional ve el botón Añadir Hito', (tester) async {
      final dao = FakeMilestoneDao();

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

      expect(find.text('Añadir Hito'), findsOneWidget);
      expect(find.text('No hay hitos registrados en este proyecto todavía.'),
          findsOneWidget);
    });
  });

  group('MilestoneLocalDataSource.getById + update - CU-25 (BD local)', () {
    test('getById recupera y update persiste descripción y duración', () async {
      final dao = await openTestDao('cu23');
      final created = await dao.create(
        obraId: 'w1',
        nombre: 'Cimientos',
        descripcion: 'Vieja',
        duracionDias: 10,
      );

      expect(await dao.getById(created.id), isNotNull);
      expect(await dao.getById('inexistente'), isNull);

      await dao.update(created.copyWith(descripcion: 'Nueva', duracionDias: 15));
      final updated = await dao.getById(created.id);
      expect(updated?.descripcion, 'Nueva');
      expect(updated?.duracionDias, 15);
      expect(updated?.nombre, 'Cimientos');
    });
  });

  group('MilestonesBloc UpdateMilestoneRequested - CU-25', () {
    test('actualiza un hito Pendiente y refresca', () async {
      final dao = await openTestDao('cu23');
      final created = await dao.create(
        obraId: 'w1',
        nombre: 'Cimientos',
        descripcion: 'Vieja',
        duracionDias: 10,
      );
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      bloc.add(UpdateMilestoneRequested(
        id: created.id,
        descripcion: 'Nueva',
        duracionDias: 15,
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesLoaded>()]),
      );

      final loaded = bloc.state as MilestonesLoaded;
      expect(loaded.milestones.single.descripcion, 'Nueva');
      expect(loaded.milestones.single.duracionDias, 15);
    });

    test('bloquea la edición de un hito no Pendiente (precondición)', () async {
      final dao = await openTestDao('cu23');
      final created = await dao.create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 10);
      await dao.update(created.copyWith(estado: MilestoneStatus.enEjecucion));
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(UpdateMilestoneRequested(
        id: created.id,
        descripcion: 'Hack',
        duracionDias: 99,
      ));
      await expectation;

      final untouched = await dao.getById(created.id);
      expect(untouched?.descripcion, isNull);
      expect(untouched?.duracionDias, 10);
      final error = bloc.state as MilestonesError;
      expect(error.message, contains('Pendiente'));
    });

    test('falla si el hito ya no existe', () async {
      final dao = await openTestDao('cu23');
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<MilestonesLoading>(), isA<MilestonesError>()]),
      );
      bloc.add(const UpdateMilestoneRequested(id: 'fantasma', duracionDias: 5));
      await expectation;
    });
  });

  group('EditMilestoneModal + sección - CU-25 pasos 1-3', () {
    Future<void> pumpEdit(
      WidgetTester tester,
      MilestonesBloc bloc,
      Milestone milestone,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (pageContext) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(pageContext).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider<MilestonesBloc>.value(
                        value: bloc,
                        child: Scaffold(body: EditMilestoneModal(milestone: milestone)),
                      ),
                    ),
                  ),
                  child: const Text('Abrir edición'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir edición'));
      await tester.pumpAndSettle();
    }

    testWidgets('precarga descripción y duración; el nombre es solo lectura',
        (tester) async {
      final dao = FakeMilestoneDao();
      const milestone = Milestone(
        id: 'h1',
        obraId: 'w1',
        nombre: 'Cimientos',
        descripcion: 'Vieja',
        duracionDias: 10,
      );
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);
      await pumpEdit(tester, bloc, milestone);

      expect(find.text('EDITAR HITO'), findsOneWidget);
      expect(find.text('Cimientos'), findsOneWidget);
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      expect((tester.widget(fields.at(0)) as TextFormField).controller?.text, 'Vieja');
      expect((tester.widget(fields.at(1)) as TextFormField).controller?.text, '10');
    });

    testWidgets('guarda los cambios, cierra e informa éxito', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          descripcion: 'Vieja',
          duracionDias: 10,
        ),
      ]);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);
      await pumpEdit(tester, bloc, (await dao.getById('h1'))!);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Nueva');
      await tester.enterText(fields.at(1), '15');
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();

      expect(find.text('Hito actualizado.'), findsOneWidget);
      expect(find.text('EDITAR HITO'), findsNothing);
      final updated = await dao.getById('h1');
      expect(updated?.descripcion, 'Nueva');
      expect(updated?.duracionDias, 15);
      expect(updated?.nombre, 'Cimientos');
    });

    testWidgets('valida la duración y no envía si es inválida', (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Cimientos', duracionDias: 10),
      ]);
      final bloc = MilestonesBloc(dataSource: dao);
      addTearDown(bloc.close);
      await pumpEdit(tester, bloc, (await dao.getById('h1'))!);

      await tester.enterText(find.byType(TextFormField).at(1), '-3');
      await tester.tap(find.text('Actualizar'));
      await tester.pump();

      expect(
        find.text('La duración debe ser un número mayor o igual a 0.'),
        findsOneWidget,
      );
      expect(dao.updateCalls, 0);
      expect(find.text('EDITAR HITO'), findsOneWidget);
    });

    testWidgets('la sección solo ofrece Editar en hitos Pendiente (Profesional)',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(id: 'h1', obraId: 'w1', nombre: 'Pendiente Uno', duracionDias: 5),
        const Milestone(
          id: 'h2',
          obraId: 'w1',
          nombre: 'En Curso',
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

      // Un solo botón de edición: el del hito Pendiente.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });
  });
}
