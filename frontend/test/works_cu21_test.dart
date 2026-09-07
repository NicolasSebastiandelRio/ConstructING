import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:constructing_mobile/features/auth/data/models/user_model.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_state.dart';
import 'package:constructing_mobile/features/works/presentation/screens/work_detail_screen.dart';
import 'package:constructing_mobile/features/works/presentation/screens/works_dashboard_screen.dart';

import 'milestones_test_helpers.dart';

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _FakeSecureStoragePlatform([Map<String, String>? seed]) : store = Map.of(seed ?? {});

  final Map<String, String> store;

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => store[key];

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    store[key] = value;
  }

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(store);

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      store.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => store.clear();
}

class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDioClient extends DioClient {
  _FakeDioClient(this.dioOverride);

  final Dio dioOverride;

  @override
  Dio get dio => dioOverride;
}

Dio _buildDio(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
  dio.httpClientAdapter = _FakeHttpAdapter(handler);
  return dio;
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

WorkModel _obra({required String estado}) => WorkModel(
      id: 'w1',
      nombre: 'Obra Archivable',
      direccion: 'Calle 123',
      fechaInicio: '2026-09-01',
      estado: estado,
      latitud: null,
      longitud: null,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'prop-1',
    );

class _FakeAuthDataSource implements AuthRemoteDataSource {
  @override
  Future<Map<String, dynamic>> login(String email, String password, String role) =>
      throw UnimplementedError();

  @override
  Future<UserModel> register({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? matricula,
    String? invitationCode,
  }) =>
      throw UnimplementedError();
}

/// Fabrica un JWT de prueba vigente (exp = ahora + 1 hora).
String _validToken() {
  const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'sub': 'user-1',
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  })));
  return '$header.$payload.dGVzdC1maXJtYQ';
}

/// Data source en memoria para el bloc y las pantallas (CU-21).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failArchiveWith, this.detailEstado = 'Completado'});

  final Exception? failArchiveWith;
  final String detailEstado;
  String? lastArchiveId;
  int archiveCalls = 0;
  String? lastPropietarioId;
  bool? lastArchivedOnly;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async {
    lastPropietarioId = propietarioId;
    lastArchivedOnly = archivedOnly;
    return const [];
  }

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> getWorkById(String id) async => _obra(estado: detailEstado);

  @override
  Future<void> archiveWork(String id) async {
    archiveCalls++;
    lastArchiveId = id;
    if (failArchiveWith != null) throw failArchiveWith!;
  }

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.archiveWork (CU-21)', () {
    test('envía DELETE a /works/:id al archivar', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({}, 204);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await dataSource.archiveWork('w1');

      expect(captured.method, 'DELETE');
      expect(captured.path, '/works/w1');
    });

    test('propaga la precondición "obra no completada" (400)', () async {
      final dio = _buildDio(
        (options) async => _json({'message': "Solo se puede archivar una obra en estado 'Completado'."}, 400),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.archiveWork('w1'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Completado'),
          ),
        ),
      );
    });

    test('getWorks con archivedOnly pide el historial por query param', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json([], 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await dataSource.getWorks(archivedOnly: true);

      expect(captured.queryParameters['archived'], 'true');
    });
  });

  group('WorksBloc ArchiveWorkEvent (CU-21 paso 4)', () {
    test('emite Loading y luego Loaded tras archivar y refrescar', () async {
      final dataSource = _FakeWorksDataSource();
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]),
      );

      bloc.add(const ArchiveWorkEvent(id: 'w1'));
      await expectation;
      expect(dataSource.lastArchiveId, 'w1');
      await bloc.close();
    });

    test('el refresco conserva el filtro vigente (historial)', () async {
      final dataSource = _FakeWorksDataSource();
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      bloc.add(const FetchWorksEvent(archivedOnly: true));
      await expectLater(bloc.stream, emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]));
      expect(dataSource.lastArchivedOnly, isTrue);

      bloc.add(const ArchiveWorkEvent(id: 'w1'));
      await expectLater(bloc.stream, emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]));
      expect(dataSource.lastArchivedOnly, isTrue);
      await bloc.close();
    });
  });

  group('Diálogo Archivar Proyecto (CU-21 paso 1)', () {
    Future<void> pumpFicha(
      WidgetTester tester,
      _FakeWorksDataSource dataSource, {
      FakeMilestoneDao? milestonesDao,
    }) async {
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
                        child: WorkDetailScreen(
                          work: _obra(estado: 'Completado'),
                          userRole: 'Profesional',
                          milestonesDao: milestonesDao,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir ficha'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir ficha'));
      await tester.pumpAndSettle();
    }

    Future<void> openArchiveDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivar Proyecto'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirma, archiva, informa y vuelve al dashboard', (tester) async {
      final dataSource = _FakeWorksDataSource();
      await pumpFicha(tester, dataSource);
      await openArchiveDialog(tester);

      expect(find.text('ARCHIVAR PROYECTO'), findsOneWidget);

      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();

      expect(dataSource.archiveCalls, 1);
      expect(dataSource.lastArchiveId, 'w1');
      expect(find.text('Obra archivada. Se movió al historial.'), findsOneWidget);
      // El diálogo se cerró y la ficha también (volvió al dashboard).
      expect(find.text('ARCHIVAR PROYECTO'), findsNothing);
      expect(find.text('Abrir ficha'), findsOneWidget);
    });

    testWidgets('cancelar cierra sin modificar la BD (flujo alterno)', (tester) async {
      final dataSource = _FakeWorksDataSource();
      await pumpFicha(tester, dataSource);
      await openArchiveDialog(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(dataSource.archiveCalls, 0);
      expect(find.text('ARCHIVAR PROYECTO'), findsNothing);
      // La ficha sigue abierta.
      expect(find.text('Obra Archivable'), findsWidgets);
    });

    testWidgets('ante un error del backend permanece abierto mostrando el mensaje',
        (tester) async {
      final dataSource = _FakeWorksDataSource(
        failArchiveWith: Exception("Solo se puede archivar una obra en estado 'Completado'."),
      );
      await pumpFicha(tester, dataSource);
      await openArchiveDialog(tester);

      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();

      expect(dataSource.archiveCalls, 1);
      expect(find.textContaining('Completado'), findsWidgets);
      expect(find.text('ARCHIVAR PROYECTO'), findsOneWidget);
    });

    testWidgets('CU-21 Alt 2.1: con hitos En Ejecución bloquea e indica pendientes',
        (tester) async {
      final dataSource = _FakeWorksDataSource();
      final milestonesDao = FakeMilestoneDao();
      milestonesDao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Muros',
          duracionDias: 8,
          estado: MilestoneStatus.enEjecucion,
        ),
        const Milestone(
          id: 'h2',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.certificado,
        ),
      ]);
      await pumpFicha(tester, dataSource, milestonesDao: milestonesDao);
      await openArchiveDialog(tester);

      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();

      // Mensaje exacto de la spec + obra intacta + diálogo abierto.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('deben cerrarse todas las tareas pendientes'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Muros'), findsWidgets);
      expect(dataSource.archiveCalls, 0);
      expect(find.text('ARCHIVAR PROYECTO'), findsOneWidget);
    });

    testWidgets('sin hitos en ejecución el guard deja archivar', (tester) async {
      final dataSource = _FakeWorksDataSource();
      final milestonesDao = FakeMilestoneDao();
      milestonesDao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.certificado,
        ),
      ]);
      await pumpFicha(tester, dataSource, milestonesDao: milestonesDao);
      await openArchiveDialog(tester);

      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();

      expect(dataSource.archiveCalls, 1);
      expect(find.text('Obra archivada. Se movió al historial.'), findsOneWidget);
    });
  });

  group('Ficha de obra archivada (CU-21 poscondición)', () {
    testWidgets('oculta el menú operativo: la obra es inalterable', (tester) async {
      // La BD confirma la obra como archivada (la ficha prioriza lo traído).
      final dataSource = _FakeWorksDataSource(detailEstado: 'Archivado');
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WorksBloc>.value(
            value: bloc,
            child: WorkDetailScreen(work: _obra(estado: 'Archivado'), userRole: 'Profesional'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('Dashboard Activas/Historial (CU-21 paso 4)', () {
    Future<_FakeWorksDataSource> pumpDashboard(WidgetTester tester) async {
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform({
        'jwt_token': _validToken(),
        'user_id': 'user-1',
        'user_name': 'Ing. Pérez',
        'user_email': 'prof@gmail.com',
        'user_role': 'Profesional',
      });
      final dataSource = _FakeWorksDataSource();
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>(
                create: (_) => AuthBloc(
                  authRemoteDataSource: _FakeAuthDataSource(),
                  secureStorage: const FlutterSecureStorage(),
                ),
              ),
              BlocProvider<WorksBloc>(
                create: (_) => WorksBloc(worksRemoteDataSource: dataSource),
              ),
            ],
            child: const WorksDashboardScreen(userRole: 'Profesional'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return dataSource;
    }

    testWidgets('el chip Historial pide archivadas y muestra su empty state', (tester) async {
      final dataSource = await pumpDashboard(tester);
      expect(dataSource.lastArchivedOnly, isFalse);

      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();

      expect(dataSource.lastArchivedOnly, isTrue);
      expect(find.text('No hay obras archivadas en el historial'), findsOneWidget);

      await tester.tap(find.text('Activas'));
      await tester.pumpAndSettle();

      expect(dataSource.lastArchivedOnly, isFalse);
      expect(find.text('Aún no tienes obras asignadas'), findsOneWidget);
    });
  });
}