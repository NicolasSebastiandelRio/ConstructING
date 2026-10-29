import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/audit/presentation/bloc/audit_report_bloc.dart';
import 'package:constructing_mobile/features/audit/presentation/bloc/audit_report_state.dart';
import 'package:constructing_mobile/features/audit/presentation/screens/audit_report_screen.dart';

Future<LocalDatabase> _openDb(String prefix) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/ar_${prefix}_'
      '${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  return localDb;
}

AuditLogRecord _registro({
  required String id,
  required DateTime createdAt,
  String usuarioId = 'u-prof',
  String accion = 'hito_modificado',
  String? obraId = 'w1',
  String? coordenadas = '-34.60368,-58.38156',
  String? detalle = 'nombre=Fundaciones',
}) =>
    AuditLogRecord(
      id: id,
      usuarioId: usuarioId,
      accion: accion,
      detalle: detalle,
      obraId: obraId,
      coordenadas: coordenadas,
      createdAt: createdAt,
    );

/// DAO de auditoría en memoria para widget tests.
///
/// Los `testWidgets` corren en una zona de fake-async donde la E/S real de
/// sqflite-ffi NO progresa: abrir la BD dentro de un widget test cuelga la
/// suite. Este fake reproduce el contrato del DAO real (descendente; el BLoC
/// del CU-63 es quien ordena cronológicamente).
class _FakeAuditLogDao extends AuditLogLocalDataSource {
  _FakeAuditLogDao() : super(localDatabase: LocalDatabase());

  final List<AuditLogRecord> _store = [];

  void seed(List<AuditLogRecord> registros) => _store.addAll(registros);

  @override
  Future<List<AuditLogRecord>> listByObra(String obraId) async =>
      _store.where((r) => r.obraId == obraId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-63 - Reporte de Auditoría (BLoC)', () {
    test('consulta los registros de la obra ORDENADOS CRONOLÓGICAMENTE',
        () async {
      final db = await _openDb('a');
      final dao = AuditLogLocalDataSource(localDatabase: db);
      await dao.insert(_registro(
          id: 'r3', createdAt: DateTime(2026, 10, 3, 18, 30)));
      await dao.insert(_registro(
          id: 'r1', createdAt: DateTime(2026, 10, 1, 8, 5)));
      await dao.insert(_registro(
          id: 'r2', createdAt: DateTime(2026, 10, 2, 12, 0)));
      // De otra obra: no debe aparecer en la hoja forense.
      await dao.insert(_registro(
          id: 'ajena',
          obraId: 'w2',
          createdAt: DateTime(2026, 10, 4, 9, 0)));

      final bloc = AuditReportBloc(local: dao);
      addTearDown(bloc.close);
      bloc.add(const LoadAuditReport(obraId: 'w1'));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<AuditReportLoading>(),
          isA<AuditReportLoaded>(),
        ]),
      );

      final estado = bloc.state as AuditReportLoaded;
      // Cronológico ascendente: el más antiguo primero.
      expect(estado.registros.map((r) => r.id).toList(), ['r1', 'r2', 'r3']);
    });

    test('resuelve el nombre del actor (CU-63 paso 4: "quién")', () async {
      final db = await _openDb('b');
      final dao = AuditLogLocalDataSource(localDatabase: db);
      await dao.insert(_registro(
          id: 'r1', createdAt: DateTime(2026, 10, 1), usuarioId: 'u-prof'));
      await dao.insert(_registro(
          id: 'r2',
          createdAt: DateTime(2026, 10, 2),
          usuarioId: 'u-owner'));

      final bloc = AuditReportBloc(
        local: dao,
        usuarioNombre: (id) async =>
            id == 'u-prof' ? 'Ing. Ana Pérez' : 'Sr. Juan Gómez',
      );
      addTearDown(bloc.close);
      bloc.add(const LoadAuditReport(obraId: 'w1'));
      await expectLater(bloc.stream, emitsThrough(isA<AuditReportLoaded>()));

      final estado = bloc.state as AuditReportLoaded;
      expect(estado.actorDe(estado.registros[0]), 'Ing. Ana Pérez');
      expect(estado.actorDe(estado.registros[1]), 'Sr. Juan Gómez');
    });

    test('sin resolutor de nombres cae al identificador del usuario',
        () async {
      final db = await _openDb('c');
      final dao = AuditLogLocalDataSource(localDatabase: db);
      await dao.insert(_registro(
          id: 'r1', createdAt: DateTime(2026, 10, 1), usuarioId: 'u-prof'));

      final bloc = AuditReportBloc(local: dao);
      addTearDown(bloc.close);
      bloc.add(const LoadAuditReport(obraId: 'w1'));
      await expectLater(bloc.stream, emitsThrough(isA<AuditReportLoaded>()));

      final estado = bloc.state as AuditReportLoaded;
      expect(estado.actorDe(estado.registros.single), 'u-prof');
    });
  });

  group('CU-63 - Reporte de Auditoría (widget)', () {
    testWidgets('renderiza quién, el instante exacto y la ubicación',
        (tester) async {
      final dao = _FakeAuditLogDao()
        ..seed([
          _registro(
            id: 'r1',
            createdAt: DateTime(2026, 10, 1, 8, 5, 9),
            usuarioId: 'u-prof',
            accion: 'hito_modificado',
            coordenadas: '-34.60368,-58.38156',
            detalle: 'nombre=Fundaciones duracion=7',
          ),
        ]);

      await tester.pumpWidget(MaterialApp(
        home: AuditReportScreen(
          obraId: 'w1',
          obraNombre: 'Torre Aurora',
          auditLogDao: dao,
          usuarioNombre: (_) async => 'Ing. Ana Pérez',
        ),
      ));
      await tester.pumpAndSettle();

      // CU-63 paso 4: quién · instante exacto · ubicación.
      expect(find.text('Ing. Ana Pérez'), findsOneWidget);
      expect(find.text('01/10/2026 08:05:09'), findsOneWidget);
      expect(find.text('-34.60368,-58.38156'), findsOneWidget);
      expect(find.text('hito_modificado'), findsOneWidget);
      expect(find.text('nombre=Fundaciones duracion=7'), findsOneWidget);
    });

    testWidgets('muestra "Sin ubicación registrada" cuando no hay coordenadas',
        (tester) async {
      final dao = _FakeAuditLogDao()
        ..seed([
          _registro(
            id: 'r1',
            createdAt: DateTime(2026, 10, 1, 8, 5, 9),
            coordenadas: null,
          ),
        ]);

      await tester.pumpWidget(MaterialApp(
        home: AuditReportScreen(
          obraId: 'w1',
          obraNombre: 'Torre Aurora',
          auditLogDao: dao,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin ubicación registrada'), findsOneWidget);
    });

    testWidgets('obra sin registros muestra su empty state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditReportScreen(
          obraId: 'w-vacia',
          obraNombre: 'Obra sin trazas',
          auditLogDao: _FakeAuditLogDao(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(AuditReportScreen.emptyStateMessage), findsOneWidget);
      expect(find.text('Sin registros de auditoría para esta obra'),
          findsOneWidget);
    });
  });
}
