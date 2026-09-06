import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/widgets/new_work_modal.dart';

/// Data source falso con comportamiento configurable (CU-16).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failCreateWith});

  final Exception? failCreateWith;
  Map<String, dynamic>? lastCreatePayload;
  int createCalls = 0;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => const [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) async {
    createCalls++;
    lastCreatePayload = Map.of(workData);
    if (failCreateWith != null) throw failCreateWith!;
    return WorkModel(
      id: 'w1',
      nombre: workData['nombre'] as String,
      direccion: workData['direccion'] as String,
      fechaInicio: workData['fechaInicio'] as String,
      estado: 'En Planificación',
      latitud: -34.6037,
      longitud: -58.3816,
      progreso: 0.0,
      profesionalId: 'prof-1',
    );
  }

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkModel> getWorkById(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) async {
    throw UnimplementedError();
  }

  @override
  Future<void> archiveWork(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) {
    throw UnimplementedError();
  }
}

Future<void> _pumpModal(WidgetTester tester, _FakeWorksDataSource dataSource) async {
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
                    child: const Scaffold(body: NewWorkModal()),
                  ),
                ),
              ),
              child: const Text('Abrir modal'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Abre el modal como una ruta secundaria (igual que el bottom-sheet real).
  await tester.tap(find.text('Abrir modal'));
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Edificio Central');
  await tester.enterText(fields.at(1), 'Av. Libertador 1234');
  await tester.enterText(fields.at(2), 'dueño@gmail.com');
  await tester.pump();
}

void main() {
  group('NewWorkModal - CU-16 (Validar Datos Obligatorios)', () {
    testWidgets('resalta los campos obligatorios faltantes y no envía nada (Alt. 2.2)',
        (tester) async {
      final dataSource = _FakeWorksDataSource();
      await _pumpModal(tester, dataSource);

      await tester.tap(find.text('Crear Proyecto'));
      await tester.pump();

      expect(find.text('El nombre es obligatorio'), findsOneWidget);
      expect(find.text('La dirección es obligatoria'), findsOneWidget);
      expect(find.text('Ingrese un correo de propietario válido'), findsOneWidget);
      expect(dataSource.createCalls, 0);
      // El modal sigue abierto.
      expect(find.text('NUEVO PROYECTO'), findsOneWidget);
    });

    testWidgets('con datos válidos crea la obra y confirma el éxito tras persistir',
        (tester) async {
      final dataSource = _FakeWorksDataSource();
      await _pumpModal(tester, dataSource);
      await _fillRequiredFields(tester);

      await tester.tap(find.text('Crear Proyecto'));
      await tester.pumpAndSettle();

      expect(dataSource.createCalls, 1);
      expect(dataSource.lastCreatePayload, containsPair('propietarioEmail', 'dueño@gmail.com'));
      expect(
        find.text('Obra registrada exitosamente en el sistema.'),
        findsOneWidget,
      );
      // El modal se cierra sólo después de la confirmación del backend.
      expect(find.text('NUEVO PROYECTO'), findsNothing);
    });

    testWidgets('ante un error del backend no confirma éxito y muestra el mensaje',
        (tester) async {
      final dataSource = _FakeWorksDataSource(
        failCreateWith: Exception("El propietario con identificador 'x' no existe en el sistema."),
      );
      await _pumpModal(tester, dataSource);
      await _fillRequiredFields(tester);

      await tester.tap(find.text('Crear Proyecto'));
      await tester.pumpAndSettle();

      expect(dataSource.createCalls, 1);
      expect(find.textContaining('no existe en el sistema'), findsOneWidget);
      expect(find.text('Obra registrada exitosamente en el sistema.'), findsNothing);
      // El modal permanece abierto para corregir.
      expect(find.text('NUEVO PROYECTO'), findsOneWidget);
    });
  });
}