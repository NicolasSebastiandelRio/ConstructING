import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/auth/data/datasources/users_remote_data_source.dart';

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
  group('UsersRemoteDataSource.deleteUser (CU-08)', () {
    test('envía DELETE a /users/:id al inhabilitar', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({}, 204);
      });

      final dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await dataSource.deleteUser('u1');

      expect(captured.method, 'DELETE');
      expect(captured.path, '/users/u1');
    });

    test('propaga el mensaje del backend cuando el usuario no existe', () async {
      final dio = _buildDio(
        (options) async => _json({'message': 'El usuario con ID u9 no fue encontrado.'}, 404),
      );

      final dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await expectLater(
        dataSource.deleteUser('u9'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no fue encontrado'),
          ),
        ),
      );
    });
  });

  group('UsersRemoteDataSource.restoreUser (CU-08 habilitar)', () {
    test('envía POST a /users/:id/restore y parsea el perfil reactivado', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({
          'id': 'u1',
          'nombre': 'Ana García',
          'email': 'ana@gmail.com',
          'rol': 'Propietario',
          'deletedAt': null,
        }, 200);
      });

      final dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      final restored = await dataSource.restoreUser('u1');

      expect(captured.method, 'POST');
      expect(captured.path, '/users/u1/restore');
      expect(restored.id, 'u1');
      expect(restored.deletedAt, isNull);
    });
  });
}