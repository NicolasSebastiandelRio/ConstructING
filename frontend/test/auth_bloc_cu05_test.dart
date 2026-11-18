import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:constructing_mobile/features/auth/data/models/user_model.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_state.dart';

const _header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
const _sig = 'dGVzdC1maXJtYQ';

String _token(Map<String, dynamic> payload) {
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$_header.$encoded.$_sig';
}

/// Almacenamiento seguro en memoria para aislar la sesión local (CU-05).
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return store[key];
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(store);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return store.containsKey(key);
  }

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    store.clear();
  }
}

class _FakeAuthDataSource implements AuthRemoteDataSource {
  @override
  Future<Map<String, dynamic>> login(String email, String password, String role) async {
    throw UnimplementedError();
  }

  @override
  Future<UserModel> register({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? matricula,
    String? invitationCode,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStoragePlatform platform;
  late FlutterSecureStorage secureStorage;
  late _FakeAuthDataSource dataSource;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    secureStorage = const FlutterSecureStorage();
    dataSource = _FakeAuthDataSource();
  });

  group('CU-05 Gestionar Sesión Persistente', () {
    test('restaura la sesión si el token almacenado sigue vigente', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      platform.store['jwt_token'] = _token({'sub': 'u1', 'exp': now + 3600});
      platform.store['user_id'] = 'u1';
      platform.store['user_name'] = 'Ana';
      platform.store['user_email'] = 'ana@test.com';
      platform.store['user_role'] = 'Profesional';

      final bloc = AuthBloc(
        authRemoteDataSource: dataSource,
        secureStorage: secureStorage,
      );

      await expectLater(bloc.stream, emitsInOrder(<Matcher>[
        isA<AuthSessionChecking>(),
        isA<AuthAuthenticated>(),
      ]));
      final state = bloc.state;
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'ana@test.com');
      await bloc.close();
    });

    test('purga la sesión y va a login si el token está expirado', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      platform.store['jwt_token'] = _token({'sub': 'u1', 'exp': now - 60});
      platform.store['user_id'] = 'u1';
      platform.store['user_name'] = 'Ana';
      platform.store['user_email'] = 'ana@test.com';
      platform.store['user_role'] = 'Profesional';

      final bloc = AuthBloc(
        authRemoteDataSource: dataSource,
        secureStorage: secureStorage,
      );

      await expectLater(bloc.stream, emitsInOrder(<Matcher>[
        isA<AuthSessionChecking>(),
        isA<AuthInitial>(),
      ]));
      expect(platform.store, isEmpty, reason: 'la sesión local debe limpiarse');
      await bloc.close();
    });

    test('purga la sesión si falta el token (usuario nunca logueado)', () async {
      platform.store['user_id'] = 'u1';
      platform.store['user_name'] = 'Ana';
      platform.store['user_email'] = 'ana@test.com';
      platform.store['user_role'] = 'Profesional';

      final bloc = AuthBloc(
        authRemoteDataSource: dataSource,
        secureStorage: secureStorage,
      );

      await expectLater(bloc.stream, emitsInOrder(<Matcher>[
        isA<AuthSessionChecking>(),
        isA<AuthInitial>(),
      ]));
      await bloc.close();
    });

    test('no restaura sesión si faltan datos del perfil almacenado', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      platform.store['jwt_token'] = _token({'sub': 'u1', 'exp': now + 3600});
      // user_name ausente a propósito

      final bloc = AuthBloc(
        authRemoteDataSource: dataSource,
        secureStorage: secureStorage,
      );

      await expectLater(bloc.stream, emitsInOrder(<Matcher>[
        isA<AuthSessionChecking>(),
        isA<AuthInitial>(),
      ]));
      await bloc.close();
    });
  });
}
