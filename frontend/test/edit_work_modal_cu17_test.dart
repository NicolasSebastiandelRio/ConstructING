import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/widgets/edit_work_modal.dart';

/// Data source falso con comportamiento configurable (CU-17).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failUpdateWith});

  final Exception? failUpdateWith;
  String? lastUpdateId;
  Map<String, dynamic>? lastUpdatePayload;
  int updateCalls = 0;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => const [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    updateCalls++;
    lastUpdateId = id;
    lastUpdatePayload = Map.of(workData);
    if (failUpdateWith != null) throw failUpdateWith!;
    return WorkModel.fromJson({
      'id': id,
      'nombre': workData['nombre'],
      'direccion': workData['direccion'],
      'fechaInicio': workData['fechaInicio'],
      'estado': 'En Planificación',
      'propietarioId': 'prop-1',
    });
  }

  @override
  Future<WorkModel> getWorkById(String id) async => throw UnimplementedError();

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

WorkModel _obraBase() => const WorkModel(
      id: 'w1',
      nombre: 'Obra Original',
      direccion: 'Calle Original 123',
      descripcion: 'Descripción original',
      fechaInicio: '2026-09-01',
      estado: 'En Planificación',
      latitud: -34.6,
      longitud: -58.4,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'prop-1',
    );

Future<void> _pumpEditModal(WidgetTester tester, _FakeWorksDataSource dataSource) async {
  final bloc = WorksBloc(worksRemoteDataSource: dataSource);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (pageContext) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(pageContext).push(
                MaterialPageRoute(
                  builder: (_) => BlocProvider<WorksBloc>.value(
                    value: bloc,
                    child: Scaffold(body: EditWorkModal(work: _obraBase())),
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

void main() {
  group('EditWorkModal - CU-17 (Modificar Información de Obra)', () {
    testWidgets('precarga los campos con los datos actuales (paso 2)', (tester) async {
      await _pumpEditModal(tester, _FakeWorksDataSource());

      final fields = find.byType(TextFormField);
      expect((tester.widget(fields.at(0)) as TextFormField).controller?.text, 'Obra Original');
      expect((tester.widget(fields.at(1)) as TextFormField).controller?.text, 'Calle Original 123');
      expect((tester.widget(fields.at(2)) as TextFormField).controller?.text, 'Descripción original');
      // El correo del propietario arranca vacío (= conservar el actual).
      expect((tester.widget(fields.at(3)) as TextFormField).controller?.text, isEmpty);
    });

    testWidgets('valida los campos y no envía si el nombre queda vacío (CU-16)', (tester) async {
      final dataSource = _FakeWorksDataSource();
      await _pumpEditModal(tester, dataSource);

      await tester.enterText(find.byType(TextFormField).at(0), '');
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pump();

      expect(find.text('El nombre es obligatorio'), findsOneWidget);
      expect(dataSource.updateCalls, 0);
      expect(find.text('EDITAR OBRA'), findsOneWidget);
    });

    testWidgets('guarda los cambios, cierra e informa éxito tras persistir (pasos 3-4)',
        (tester) async {
      final dataSource = _FakeWorksDataSource();
      await _pumpEditModal(tester, dataSource);

      await tester.enterText(find.byType(TextFormField).at(0), 'Obra Renombrada');
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(dataSource.updateCalls, 1);
      expect(dataSource.lastUpdateId, 'w1');
      expect(dataSource.lastUpdatePayload, containsPair('nombre', 'Obra Renombrada'));
      expect(find.text('Obra actualizada exitosamente.'), findsOneWidget);
      expect(find.text('EDITAR OBRA'), findsNothing);
    });

    testWidgets('ante un error del backend permanece abierto mostrando el mensaje',
        (tester) async {
      final dataSource = _FakeWorksDataSource(
        failUpdateWith: Exception('No se puede modificar una obra archivada.'),
      );
      await _pumpEditModal(tester, dataSource);

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(dataSource.updateCalls, 1);
      expect(find.textContaining('obra archivada'), findsOneWidget);
      expect(find.text('Obra actualizada exitosamente.'), findsNothing);
      expect(find.text('EDITAR OBRA'), findsOneWidget);
    });
  });
}