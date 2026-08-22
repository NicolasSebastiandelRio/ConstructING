import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRemoteDataSource authRemoteDataSource;
  final FlutterSecureStorage secureStorage;

  AuthBloc({
    required this.authRemoteDataSource,
    required this.secureStorage,
  }) : super(AuthInitial()) {
    
    on<LoginButtonPressed>((event, emit) async {
      emit(AuthLoading());
      try {
        // CU-01: Validar credenciales contra el backend
        final result = await authRemoteDataSource.login(event.email, event.password);
        
        // CU-05: Gestionar sesión persistente guardando el JWT
        final token = result['access_token'];
        await secureStorage.write(key: 'jwt_token', value: token);
        await secureStorage.write(key: 'user_role', value: result['user'].rol);

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
  }
}