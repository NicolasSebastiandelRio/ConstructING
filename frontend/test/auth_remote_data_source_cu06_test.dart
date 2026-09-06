import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';

/// Adaptador HTTP en memoria para aislar las llamadas de red en pruebas.
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

/// Subclase de DioClient que expone el Dio fake en lugar del real.
class _FakeDioClient extends DioClient {
  _FakeDioClient(this.dioOverride);

  final Dio dioOverride;

  @override
  Dio get dio => dioOverride;
}

void main() {
  group('AuthRemoteDataSource.register (CU-06)', () {
    late Dio dio;
    late AuthRemoteDataSource dataSource;

    test('envía nombre, email, rol y matrícula al endpoint /auth/register', () async {
      late RequestOptions captured;
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode({
            'id': 'u1',
            'nombre': 'Ana García',
            'email': 'ana@gmail.com',
            'rol': 'Profesional',
            'role': 'Profesional',
            'matricula': 'ING-123',
            'message': 'Usuario registrado exitosamente',
          }),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      dataSource = AuthRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      final user = await dataSource.register(
        nombre: 'Ana García',
        email: 'ana@gmail.com',
        password: 'secreto1',
        rol: 'Profesional',
        matricula: 'ING-123',
      );

      expect(captured.path, '/auth/register');
      expect(captured.data, {
        'nombre': 'Ana García',
        'email': 'ana@gmail.com',
        'password': 'secreto1',
        'role': 'Profesional',
        'matricula': 'ING-123',
      });

      expect(user.id, 'u1');
      expect(user.nombre, 'Ana García');
      expect(user.email, 'ana@gmail.com');
      expect(user.rol, 'Profesional');
    });

    test('propaga el mensaje "correo ya en uso" cuando el backend devuelve 409', () async {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'message': 'El correo ya se encuentra en uso. Por favor, inicie sesión',
          }),
          409,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      dataSource = AuthRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await expectLater(
        dataSource.register(
          nombre: 'Otro',
          email: 'dupe@gmail.com',
          password: 'secreto1',
          rol: 'Propietario',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('El correo ya se encuentra en uso'),
          ),
        ),
      );
    });
  });
}