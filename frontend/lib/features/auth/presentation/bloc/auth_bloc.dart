import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/security/jwt_session.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/models/user_model.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRemoteDataSource authRemoteDataSource;
  final FlutterSecureStorage secureStorage;

  AuthBloc({
    required this.authRemoteDataSource,
    required this.secureStorage,
  }) : super(AuthInitial()) {
    on<RestoreSessionRequested>((event, emit) async {
      emit(AuthSessionChecking());
      final token = await secureStorage.read(key: 'jwt_token');
      final userId = await secureStorage.read(key: 'user_id');
      final userName = await secureStorage.read(key: 'user_name');
      final userEmail = await secureStorage.read(key: 'user_email');
      final userRole = await secureStorage.read(key: 'user_role');

      // CU-05 / RNF_S_01: un token expirado debe invalidar la sesión local y
      // obligar a re-autenticarse, evitando una sesión "zombie" sin vigencia.
      if (token == null || JwtSession.isExpired(token)) {
        await secureStorage.deleteAll();
        emit(AuthInitial());
        return;
      }

      if (userId == null || userName == null || userEmail == null || userRole == null) {
        await secureStorage.deleteAll();
        emit(AuthInitial());
        return;
      }

      emit(
        AuthAuthenticated(
          user: UserModel(
            id: userId,
            nombre: userName,
            email: userEmail,
            rol: userRole,
          ),
        ),
      );
    });
    
    on<LoginButtonPressed>((event, emit) async {
      emit(AuthLoading());
      try {
        // CU-01: Validar credenciales contra el backend
        final result = await authRemoteDataSource.login(
          event.email,
          event.password,
          event.role,
        );
        
        // CU-05: Gestionar sesión persistente guardando el JWT
        final token = result['access_token'];
        await secureStorage.write(key: 'jwt_token', value: token);
        await secureStorage.write(key: 'user_role', value: result['user'].rol);
        await secureStorage.write(key: 'user_id', value: result['user'].id);
        await secureStorage.write(key: 'user_name', value: result['user'].nombre);
        await secureStorage.write(key: 'user_email', value: result['user'].email);

        // Emitimos éxito
        emit(AuthAuthenticated(user: result['user']));
      } catch (e) {
        emit(AuthError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    on<LogoutRequested>((event, emit) async {
      emit(AuthLoading());
      await secureStorage.deleteAll(); // Borramos sesión local
      emit(AuthInitial());
    });

    add(RestoreSessionRequested());
  }
}