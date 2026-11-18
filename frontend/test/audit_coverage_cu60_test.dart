import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/audit/presentation/screens/audit_report_screen.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_bloc.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_event.dart';
import 'package:constructing_mobile/features/milestones/presentation/blocs/milestones_state.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_state.dart';

WorkModel _obra({String id = 'w1', String nombre = 'Torre Aurora'}) =>
    WorkModel(
      id: id,
      nombre: nombre,
      direccion: 'Calle 1',
      latitud: -34.6037,
      longitud: -58.3816,
      fechaInicio: '2026-01-01',
      estado: 'En Ejecución',
      progreso: 0,
      profesionalId: 'prof-1',
    );

/// Backend de obras simulado: responde OK para que el BLoC llegue a auditar.
class _FakeWorks implements WorksRemoteDataSource {
  @override
  Future<List<WorkModel>> getWorks({
    String? propietarioId,
    bool archivedOnly = false,
  }) async =>
      [_obra()];

  @override
  Future<WorkModel> getWorkById(String id) async => _obra(id: id);

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) async =>
      _obra(nombre: workData['nombre']?.toString() ?? 'Torre');

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async =>
      _obra(id: id);

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) async =>
      _obra(id: id);

  @override
  Future<void> archiveWork(String id) async {}

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) async =>
      throw UnimplementedError();
}

class _Ctx {
  final LocalDatabase db;
  final AuditLogLocalDataSource auditDao;
  final AuditLogWriter auditWriter;

  const _Ctx({
    required this.db,
    required this.auditDao,
    required this.auditWriter,
  });
}

Future<_Ctx> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/au_${nombre}_'
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
  final dao = AuditLogLocalDataSource(localDatabase: localDb);
  return _Ctx(
    db: localDb,
    auditDao: dao,
    auditWriter: AuditLogWriter(
      dataSource: dao,
      userIdReader: () async => 'prof-1',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-60 - acciones de la OBRA auditadas (WorksBloc)', () {
    test('alta, edición, cambio de estado y archivado dejan huella', () async {
      final ctx = await _contexto('obras');
      final bloc = WorksBloc(
        worksRemoteDataSource: _FakeWorks(),
        auditLog: ctx.auditWriter,
      );
      addTearDown(bloc.close);

      bloc.add(CreateWorkEvent(workData: {'nombre': 'Torre Nueva'}));
      await expectLater(bloc.stream, emitsThrough(isA<WorksLoaded>()));

      bloc.add(UpdateWorkEvent(id: 'w1', workData: {'nombre': 'Torre Editada'}));
      await expectLater(bloc.stream, emitsThrough(isA<WorksLoaded>()));

      bloc.add(UpdateWorkStatusEvent(id: 'w1', estado: 'Completado'));
      await expectLater(bloc.stream, emitsThrough(isA<WorksLoaded>()));

      bloc.add(ArchiveWorkEvent(id: 'w1'));
      await expectLater(bloc.stream, emitsThrough(isA<WorksLoaded>()));

      final acciones =
          (await ctx.auditDao.listAll()).map((h) => h.accion).toSet();
      expect(
        acciones,
        containsAll([
          'obra_creada',
          'obra_modificada',
          'obra_estado_actualizado',
          'obra_archivada',
        ]),
      );
      final estado = (await ctx.auditDao.listAll())
          .firstWhere((h) => h.accion == 'obra_estado_actualizado');
      expect(estado.detalle, contains('Completado'));
    });
  });

  group('CU-60 - acciones de la HOJA DE RUTA auditadas', () {
    test('cambiar las dependencias de un hito deja huella', () async {
      final ctx = await _contexto('deps');
      final milestones = MilestoneLocalDataSource(localDatabase: ctx.db);
      final a =
          await milestones.create(obraId: 'w1', nombre: 'Base', duracionDias: 2);
      final b = await milestones.create(
          obraId: 'w1', nombre: 'Estructura', duracionDias: 3);

      final bloc = MilestonesBloc(
        dataSource: milestones,
        auditLog: ctx.auditWriter,
      );
      addTearDown(bloc.close);

      bloc.add(SetDependenciesRequested(
        obraId: 'w1',
        hitoId: b.id,
        predecesorIds: [a.id],
      ));
      await expectLater(
          bloc.stream, emitsThrough(isA<MilestonesLoaded>()));

      final huellas = await ctx.auditDao.listByObra('w1');
      final dependencias =
          huellas.where((h) => h.accion == 'dependencias_actualizadas');
      expect(dependencias, hasLength(1));
      expect(dependencias.single.detalle, contains(b.id));
    });
  });

  group('CU-63 - el reporte traduce los códigos internos', () {
    test('acciones conocidas en lenguaje natural', () {
      expect(accionLegible('hito_creado'), 'Hito creado');
      expect(accionLegible('hito_iniciado'), 'Hito iniciado');
      expect(accionLegible('conformidad_firmada'), 'Firma registrada');
      expect(accionLegible('acta_sellada'), 'Acta firmada y sellada');
      expect(accionLegible('evidencia_cargada'), 'Evidencia cargada');
      expect(accionLegible('obra_archivada'), 'Obra archivada');
    });

    test('un código desconocido se humaniza, no se oculta', () {
      expect(accionLegible('accion_nueva_del_futuro'),
          'Accion nueva del futuro');
      expect(accionLegible(''), 'Acción registrada');
    });
  });
}
