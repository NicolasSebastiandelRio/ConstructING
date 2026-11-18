import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:constructing_mobile/features/auth/data/models/user_model.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_state.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/auth/presentation/screens/welcome_screen.dart';
import 'package:constructing_mobile/features/works/presentation/screens/works_dashboard_screen.dart';

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
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return store.containsKey(key);
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

class _EmptyWorksDataSource implements WorksRemoteDataSource {
  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkModel> getWorkById(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) async {
    throw UnimplementedError();
  }

  @override
  Future<void> archiveWork(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin sesión almacenada se muestra la pantalla de bienvenida',
      (WidgetTester tester) async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRemoteDataSource: _FakeAuthDataSource(),
              secureStorage: const FlutterSecureStorage(),
            ),
          ),
          BlocProvider<WorksBloc>(
            create: (context) => WorksBloc(
              worksRemoteDataSource: _EmptyWorksDataSource(),
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => BlocBuilder<AuthBloc, AuthState>(
              bloc: BlocProvider.of<AuthBloc>(context),
              builder: (context, state) {
                if (state is AuthAuthenticated) {
                  return WorksDashboardScreen(userRole: state.user.rol);
                }
                return const WelcomeScreen();
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('ConstructING'), findsWidgets);
    expect(find.text('Iniciar Sesión'), findsWidgets);
  });
}