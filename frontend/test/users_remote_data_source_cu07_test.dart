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

void main() {
  group('UsersRemoteDataSource.updateUser (CU-07)', () {
    late Dio dio;
    late UsersRemoteDataSource dataSource;

    test('envía PATCH a /users/:id con solo los campos modificados y parsea el perfil', () async {
      late RequestOptions captured;
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode({
            'id': 'u1',
            'nombre': 'Ana Pérez',
            'email': 'nuevo@gmail.com',
            'rol': 'Propietario',
            'deletedAt': null,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      final updated = await dataSource.updateUser(
        'u1',
        nombre: 'Ana Pérez',
        email: 'nuevo@gmail.com',
      );

      expect(captured.method, 'PATCH');
      expect(captured.path, '/users/u1');
      expect(captured.data, {'nombre': 'Ana Pérez', 'email': 'nuevo@gmail.com'});

      expect(updated.id, 'u1');
      expect(updated.nombre, 'Ana Pérez');
      expect(updated.email, 'nuevo@gmail.com');
      expect(updated.deletedAt, isNull);
    });

    test('propaga "Correo ya registrado" cuando el backend responde 400 (Flujo Alt. 3.2)', () async {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({'message': 'Correo ya registrado'}),
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await expectLater(
        dataSource.updateUser('u1', email: 'tomado@gmail.com'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Correo ya registrado'),
          ),
        ),
      );
    });

    test('parsea deletedAt cuando el usuario está inhabilitado (CU-08/09)', () async {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'id': 'u1',
            'nombre': 'Ana García',
            'email': 'ana@gmail.com',
            'rol': 'Propietario',
            'deletedAt': '2026-08-01T14:30:00.000Z',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      dataSource = UsersRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      final updated = await dataSource.updateUser('u1', nombre: 'Ana García');

      expect(updated.deletedAt, isNotNull);
    });
  });
}