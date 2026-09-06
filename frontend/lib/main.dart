import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/network/dio_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/auth/presentation/screens/welcome_screen.dart';

// Importaciones del Módulo de Obras (PT-03)
import 'features/works/data/datasources/works_remote_data_source.dart';
import 'features/works/presentation/blocs/works_bloc.dart';
import 'features/works/presentation/screens/works_dashboard_screen.dart';

/// Punto de entrada de ConstructING.
///
/// ESTRATEGIA DE PRODUCTO (ver `core/config/deployment.dart`):
/// desarrollo mobile-first, entrega como URL web (`flutter build web`).
/// No se distribuye como app descargable: el artefacto final vive en
/// `build/web` y se sirve desde hosting estático.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Instanciación de dependencias core y servicios de red
  const secureStorage = FlutterSecureStorage();
  final dioClient = DioClient();

  // 2. Instanciación de Data Sources (Capa de Datos)
  final authRemoteDataSource = AuthRemoteDataSourceImpl(dioClient: dioClient);
  final worksRemoteDataSource = WorksRemoteDataSourceImpl(
    dioClient: dioClient,
    secureStorage: secureStorage,
  );
  runApp(
    MultiBlocProvider(
      providers: [
        // Proveedor global para el flujo de Autenticación (PT-02)
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            authRemoteDataSource: authRemoteDataSource,
            secureStorage: secureStorage,
          ),
        ),
        // Proveedor global para el flujo de Obras y Proyectos (PT-03)
        BlocProvider<WorksBloc>(
          create: (context) => WorksBloc(
            worksRemoteDataSource: worksRemoteDataSource,
          ),
        ),
      ],
      child: const ConstructINGApp(),
    ),
  );
}

class ConstructINGApp extends StatelessWidget {
  const ConstructINGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConstructING',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthRootScreen(),
    );
  }
}

class AuthRootScreen extends StatelessWidget {
  const AuthRootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthSessionChecking) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is AuthAuthenticated) {
          return WorksDashboardScreen(userRole: state.user.rol);
        }
        return const WelcomeScreen();
      },
    );
  }
}