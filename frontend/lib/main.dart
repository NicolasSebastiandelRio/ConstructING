import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/network/dio_client.dart';
import 'core/network/connectivity_cubit.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/storage/local_database.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/auth/presentation/screens/welcome_screen.dart';
import 'features/evidence/data/datasources/evidence_local_data_source.dart';
import 'features/evidence/gateway/capture_gateway.dart';
import 'features/milestones/data/datasources/milestone_local_data_source.dart';
import 'features/sync/data/datasources/sync_remote_data_source.dart';
import 'features/sync/domain/sync_engine.dart';
import 'features/sync/presentation/bloc/sync_status_cubit.dart';
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

  // 3. Infraestructura offline-first: BD local + motor de sincronización
  // (CU-44 al CU-47, PT-06).
  const captureGateway = LiveCaptureGateway();
  final localDatabase = LocalDatabase();
  final milestoneDao = MilestoneLocalDataSource(localDatabase: localDatabase);
  final evidenceDao = EvidenceLocalDataSource(localDatabase: localDatabase);
  final syncEngine = SyncEngine(
    milestones: milestoneDao,
    evidences: evidenceDao,
    remote: HttpSyncRemoteDataSource(dioClient: dioClient),
    evidenceReader: (path) => captureGateway.readBytes(path),
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
        // Estado global de conectividad Online/Offline (CU-43, PT-06).
        BlocProvider<ConnectivityCubit>(
          create: (context) => ConnectivityCubit(
            monitor: buildProductionMonitor(dioClient.dio),
          )..start(),
        ),
        // Estado global de sincronización (CU-48/CU-49): se despierta con
        // las transiciones a online del CU-43 y expone el panel de estado.
        BlocProvider<SyncStatusCubit>(
          create: (context) {
            final cubit = SyncStatusCubit(
              engine: syncEngine,
              isOnline: () =>
                  context.read<ConnectivityCubit>().state ==
                  ConnectivityStatus.online,
            );
            cubit.listenOnline(
              context.read<ConnectivityCubit>().stream
                  .map((s) => s == ConnectivityStatus.online)
                  .where((online) => online),
            );
            cubit.refresh();
            return cubit;
          },
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