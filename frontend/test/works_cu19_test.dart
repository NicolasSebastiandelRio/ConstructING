import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_state.dart';
import 'package:constructing_mobile/features/works/presentation/screens/work_detail_screen.dart';

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

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

const _fichaJson = {
  'id': 'w1',
  'nombre': 'Edificio Central',
  'direccion': 'Av. Libertador 1234',
  'descripcion': 'Torre residencial de 20 pisos',
  'fechaInicio': '2026-09-01',
  'estado': 'En Ejecución',
  'latitud': -34.6037,
  'longitud': -58.3816,
  'propietarioId': 'prop-1',
  'propietario': {'id': 'prop-1', 'nombre': 'Dueño López', 'email': 'dueño@gmail.com'},
};

/// Data source en memoria para el bloc y la ficha (CU-19).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.detail, this.failDetailWith});

  final WorkModel? detail;
  final Exception? failDetailWith;
  String? lastDetailId;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => const [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> getWorkById(String id) async {
    lastDetailId = id;
    if (failDetailWith != null) throw failDetailWith!;
    return detail ?? WorkModel.fromJson(_fichaJson);
  }

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

WorkModel _snapshot() => const WorkModel(
      id: 'w1',
      nombre: 'Edificio Central',
      direccion: 'Av. Libertador 1234',
      fechaInicio: '2026-09-01',
      estado: 'En Planificación',
      latitud: null,
      longitud: null,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'prop-1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.getWorkById (CU-19)', () {
    test('pide GET /works/:id y parsea propietario anidado y coordenadas', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json(_fichaJson, 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final work = await dataSource.getWorkById('w1');

      expect(captured.method, 'GET');
      expect(captured.path, '/works/w1');
      expect(work.nombre, 'Edificio Central');
      expect(work.descripcion, 'Torre residencial de 20 pisos');
      expect(work.propietarioNombre, 'Dueño López');
      expect(work.propietarioEmail, 'dueño@gmail.com');
      expect(work.latitud, closeTo(-34.6037, 0.0001));
      expect(work.longitud, closeTo(-58.3816, 0.0001));
    });

    test('preserva null cuando la obra no tiene ancla geográfica', () async {
      final dio = _buildDio((options) async {
        final json = Map<String, dynamic>.of(_fichaJson)..remove('latitud')..remove('longitud');
        return _json(json, 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final work = await dataSource.getWorkById('w1');

      expect(work.latitud, isNull);
      expect(work.longitud, isNull);
    });

    test('propaga el 404 cuando la obra no existe', () async {
      final dio = _buildDio(
        (options) async => _json({'message': 'La obra con ID w9 no fue encontrada.'}, 404),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.getWorkById('w9'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no fue encontrada'),
          ),
        ),
      );
    });
  });

  group('WorksBloc FetchWorkDetailEvent (CU-19 paso 2)', () {
    test('emite DetailLoading y luego DetailLoaded con la ficha', () async {
      final dataSource = _FakeWorksDataSource();
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorkDetailLoading>(), isA<WorkDetailLoaded>()]),
      );

      bloc.add(const FetchWorkDetailEvent(id: 'w1'));
      await expectation;
      expect(dataSource.lastDetailId, 'w1');
      final loaded = bloc.state as WorkDetailLoaded;
      expect(loaded.work.nombre, 'Edificio Central');
      await bloc.close();
    });

    test('emite DetailLoading y luego Error si la BD falla', () async {
      final dataSource = _FakeWorksDataSource(failDetailWith: Exception('La obra no fue encontrada.'));
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorkDetailLoading>(), isA<WorksError>()]),
      );

      bloc.add(const FetchWorkDetailEvent(id: 'w9'));
      await expectation;
      await bloc.close();
    });
  });

  group('WorkDetailScreen (CU-19 paso 4)', () {
    Future<void> pumpFicha(WidgetTester tester, _FakeWorksDataSource dataSource) async {
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WorksBloc>.value(
            value: bloc,
            child: WorkDetailScreen(work: _snapshot(), userRole: 'Propietario'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('muestra el snapshot y luego los datos maestros traídos de la BD',
        (tester) async {
      await pumpFicha(tester, _FakeWorksDataSource());

      // Snapshot inmediato (nombre en el AppBar).
      expect(find.text('Edificio Central'), findsWidgets);
      // Datos maestros recuperados (paso 2) y exhibidos (paso 4).
      expect(find.text('Torre residencial de 20 pisos'), findsOneWidget);
      expect(find.text('Dueño López'), findsOneWidget);
      expect(find.text('dueño@gmail.com'), findsOneWidget);
      expect(find.text('-34.6037, -58.3816'), findsOneWidget);
    });

    testWidgets('sin ancla informa "Sin ancla geográfica registrada"', (tester) async {
      final json = Map<String, dynamic>.of(_fichaJson)
        ..remove('latitud')
        ..remove('longitud');
      await pumpFicha(tester, _FakeWorksDataSource(detail: WorkModel.fromJson(json)));

      expect(find.text('Sin ancla geográfica registrada'), findsOneWidget);
    });

    testWidgets('si la BD falla conserva el snapshot e informa el error', (tester) async {
      await pumpFicha(
        tester,
        _FakeWorksDataSource(failDetailWith: Exception('La obra no fue encontrada.')),
      );

      expect(find.text('Edificio Central'), findsWidgets);
      expect(find.textContaining('no fue encontrada'), findsOneWidget);
    });
  });
}