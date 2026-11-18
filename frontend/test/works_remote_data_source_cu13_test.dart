import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';

/// Almacenamiento seguro en memoria (mismo patrón que auth_bloc_cu05_test).
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async {
    return store[key];
  }

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    store[key] = value;
  }

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async {
    return Map.of(store);
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async {
    return store.containsKey(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.createWork (CU-13)', () {
    test('envía POST a /works con nombre, dirección, fecha y correo del propietario', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({
          'id': 'w1',
          'nombre': 'Edificio Central',
          'direccion': 'Av. Libertador 1234',
          'descripcion': 'Torre residencial',
          'fechaInicio': '2026-09-01',
          'estado': 'En Planificación',
          'propietarioId': 'prop-1',
        }, 201);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final work = await dataSource.createWork({
        'nombre': 'Edificio Central',
        'direccion': 'Av. Libertador 1234',
        'fechaInicio': '2026-09-01',
        'propietarioEmail': 'dueño@gmail.com',
      });

      expect(captured.method, 'POST');
      expect(captured.path, '/works');
      expect(captured.data, {
        'nombre': 'Edificio Central',
        'direccion': 'Av. Libertador 1234',
        'fechaInicio': '2026-09-01',
        'propietarioEmail': 'dueño@gmail.com',
      });

      // CU-13 Poscondición: la obra nace "En Planificación".
      expect(work.id, 'w1');
      expect(work.estado, 'En Planificación');
      expect(work.propietarioId, 'prop-1');
    });

    test('propaga el error cuando el propietario no existe (CU-14 Alt. 2.1)', () async {
      final dio = _buildDio(
        (options) async => _json(
          {'message': "El propietario con identificador 'x@gmail.com' no existe en el sistema."},
          400,
        ),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.createWork({
          'nombre': 'Obra X',
          'direccion': 'Calle 1',
          'fechaInicio': '2026-09-01',
          'propietarioEmail': 'x@gmail.com',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no existe en el sistema'),
          ),
        ),
      );
    });
  });
}