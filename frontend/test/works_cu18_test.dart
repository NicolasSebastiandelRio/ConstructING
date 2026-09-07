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
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_state.dart';
import 'package:constructing_mobile/features/works/presentation/screens/works_dashboard_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _FakeSecureStoragePlatform(this.store);

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

/// Data source de obras configurable para el dashboard (CU-18).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource(this.works);

  final List<WorkModel> works;
  String? lastPropietarioId;
  bool? lastArchivedOnly;
  int getWorksCalls = 0;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async {
    getWorksCalls++;
    lastPropietarioId = propietarioId;
    lastArchivedOnly = archivedOnly;
    return works;
  }

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> getWorkById(String id) async => works.firstWhere((w) => w.id == id);

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Fabrica un JWT de prueba vigente (exp = ahora + 1 hora).
String _validToken() {
  const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'sub': 'user-1',
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  })));
  return '$header.$payload.dGVzdC1maXJtYQ';
}

Map<String, String> _sessionStore(String role) => {
      'jwt_token': _validToken(),
      'user_id': 'user-1',
      'user_name': 'Dueño López',
      'user_email': 'dueño@gmail.com',
      'user_role': role,
    };

WorkModel _obra(String nombre) => WorkModel(
      id: 'w-$nombre',
      nombre: nombre,
      direccion: 'Calle 123',
      fechaInicio: '2026-09-01',
      estado: 'En Planificación',
      latitud: -34.6,
      longitud: -58.4,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'user-1',
    );

Future<_FakeWorksDataSource> _pumpDashboard(
  WidgetTester tester, {
  required String role,
  required List<WorkModel> works,
}) async {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(_sessionStore(role));
  final worksDataSource = _FakeWorksDataSource(works);

  // Los providers van POR ENCIMA del MaterialApp (igual que en main.dart):
  // solo así las rutas pusheadas (ficha) heredan los blocs.
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(
            authRemoteDataSource: _FakeAuthDataSource(),
            secureStorage: const FlutterSecureStorage(),
          ),
        ),
        BlocProvider<WorksBloc>(
          create: (_) => WorksBloc(worksRemoteDataSource: worksDataSource),
        ),
      ],
      child: MaterialApp(
        home: WorksDashboardScreen(userRole: role),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return worksDataSource;
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorksRemoteDataSource.getWorks (CU-18)', () {
    test('sin filtro pide GET /works sin query de propietario', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json([], 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform({});

      final works = await dataSource.getWorks();

      expect(captured.method, 'GET');
      expect(captured.path, '/works');
      expect(captured.queryParameters.containsKey('propietarioId'), isFalse);
      expect(works, isEmpty);
    });

    test('con propietarioId pide "Mis Obras" por query param', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json([
          {
            'id': 'w1',
            'nombre': 'Obra A1',
            'direccion': 'Calle A1',
            'fechaInicio': '2026-09-01',
            'estado': 'En Planificación',
            'propietarioId': 'user-1',
          },
        ], 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform({});

      final works = await dataSource.getWorks(propietarioId: 'user-1');

      expect(captured.queryParameters['propietarioId'], 'user-1');
      expect(works, hasLength(1));
      expect(works.first.nombre, 'Obra A1');
    });
  });

  group('WorksBloc FetchWorksEvent (CU-18)', () {
    test('propaga el filtro de propietario al data source', () async {
      final dataSource = _FakeWorksDataSource([]);
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]),
      );

      bloc.add(const FetchWorksEvent(propietarioId: 'user-1'));
      await expectation;
      expect(dataSource.lastPropietarioId, 'user-1');
      await bloc.close();
    });
  });

  group('WorksDashboardScreen (CU-18)', () {
    testWidgets('Propietario sin obras ve el Empty State de la spec (Alt. 2.2)',
        (tester) async {
      final dataSource = await _pumpDashboard(tester, role: 'Propietario', works: []);

      // "Mis Obras": el dashboard filtra por el ID de la sesión.
      expect(dataSource.lastPropietarioId, 'user-1');
      expect(find.text('Aún no tienes obras asignadas'), findsOneWidget);
    });

    testWidgets('Profesional pide el listado general sin filtro', (tester) async {
      final dataSource = await _pumpDashboard(tester, role: 'Profesional', works: []);

      expect(dataSource.lastPropietarioId, isNull);
      expect(find.text('Aún no tienes obras asignadas'), findsOneWidget);
    });

    testWidgets('Flujo Normal: renderiza las obras vinculadas (paso 4)', (tester) async {
      await _pumpDashboard(tester, role: 'Propietario', works: [_obra('Obra A1'), _obra('Obra A2')]);

      expect(find.text('Obra A1'), findsOneWidget);
      expect(find.text('Obra A2'), findsOneWidget);
      expect(find.text('Aún no tienes obras asignadas'), findsNothing);
    });

    testWidgets('CU-30 paso 4: al volver de la ficha recarga el listado', (tester) async {
      final dataSource =
          await _pumpDashboard(tester, role: 'Profesional', works: [_obra('Obra A1')]);
      expect(dataSource.getWorksCalls, 1);

      // Entra a la ficha y vuelve: el dashboard debe refrescar.
      await tester.tap(find.text('Obra A1'));
      await tester.pumpAndSettle();
      expect(find.text('Ubicación'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(dataSource.getWorksCalls, 2);
      expect(find.text('Obra A1'), findsOneWidget);
    });
  });
}