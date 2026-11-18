import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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

const _updatedWork = {
  'id': 'w1',
  'nombre': 'Obra Editada',
  'direccion': 'Nueva Dirección 456',
  'fechaInicio': '2026-09-01',
  'estado': 'En Planificación',
  'propietarioId': 'prop-1',
};

/// Data source en memoria para probar el bloc sin red.
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failUpdateWith});

  final Exception? failUpdateWith;
  Map<String, dynamic>? lastUpdate;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => [WorkModel.fromJson(_updatedWork)];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    lastUpdate = {'id': id, ...workData};
    if (failUpdateWith != null) throw failUpdateWith!;
    return WorkModel.fromJson(_updatedWork);
  }

  @override
  Future<WorkModel> getWorkById(String id) async => WorkModel.fromJson(_updatedWork);

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.updateWork (CU-17)', () {
    test('envía PATCH a /works/:id con los datos editados y parsea la obra', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json(_updatedWork, 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final work = await dataSource.updateWork('w1', {
        'nombre': 'Obra Editada',
        'direccion': 'Nueva Dirección 456',
      });

      expect(captured.method, 'PATCH');
      expect(captured.path, '/works/w1');
      expect(captured.data, {'nombre': 'Obra Editada', 'direccion': 'Nueva Dirección 456'});
      expect(work.id, 'w1');
      expect(work.nombre, 'Obra Editada');
    });

    test('propaga el bloqueo de obra archivada (400 de precondición)', () async {
      final dio = _buildDio(
        (options) async => _json({'message': 'No se puede modificar una obra archivada.'}, 400),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.updateWork('w1', {'nombre': 'X'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('obra archivada'),
          ),
        ),
      );
    });
  });

  group('WorksBloc UpdateWorkEvent (CU-17 paso 4)', () {
    test('emite Loading y luego Loaded tras actualizar y refrescar', () async {
      final dataSource = _FakeWorksDataSource();
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]),
      );

      bloc.add(const UpdateWorkEvent(id: 'w1', workData: {'nombre': 'Obra Editada'}));
      await expectation;
      expect(dataSource.lastUpdate, {'id': 'w1', 'nombre': 'Obra Editada'});
      await bloc.close();
    });

    test('emite Loading y luego Error si el backend rechaza (obra archivada)', () async {
      final dataSource =
          _FakeWorksDataSource(failUpdateWith: Exception('No se puede modificar una obra archivada.'));
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorksLoading>(), isA<WorksError>()]),
      );

      bloc.add(const UpdateWorkEvent(id: 'w1', workData: {'nombre': 'X'}));
      await expectation;
      await bloc.close();
    });
  });
}