import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/network/dio_client.dart';
import 'core/network/connectivity_cubit.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/storage/local_database.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/auth/presentation/screens/welcome_screen.dart';
import 'features/audit/data/audit_log_writer.dart';
import 'features/audit/data/datasources/audit_log_local_data_source.dart';
import 'features/evidence/data/datasources/evidence_local_data_source.dart';
import 'features/evidence/domain/crypto/secure_erase.dart';
import 'features/evidence/gateway/capture_gateway.dart';
import 'features/milestones/data/datasources/milestone_local_data_source.dart';
import 'features/notifications/data/datasources/notification_local_data_source.dart';
import 'features/notifications/data/datasources/notification_remote_data_source.dart';
import 'features/notifications/presentation/bloc/notifications_bloc.dart';
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
    // CU-59 (PT-07): borrado seguro del binario local post-sincronización
    // (re-escritura con patrón + eliminación, RNF_C_05).
    secureEraser: (archivo) async =>
        const SecureEraseService().eraseFile(archivo),
  );

  // Diagnóstico de arranque (RNF_C_02): deja constancia del estado REAL del
  // caché local para detectar pérdidas de datos entre sesiones o navegadores.
  unawaited(() async {
    try {
      final db = await localDatabase.database;
      final versionRows = await db.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? '?'
          : versionRows.first.values.first.toString();
      final hitos = await db.rawQuery('SELECT COUNT(*) AS c FROM milestones');
      final evidencias =
          await db.rawQuery('SELECT COUNT(*) AS c FROM evidences');
      // Desglose por obra: permite distinguir "no hay datos" de "los datos
      // están bajo otra obra" (causa típica de hitos que parecen perdidos).
      final porObra = await db.rawQuery(
          'SELECT obra_id, COUNT(*) AS c FROM milestones GROUP BY obra_id');
      final desglose = porObra
          .map((r) => '${r['obra_id']}=${r['c']}')
          .join(', ');
      debugPrint(
        '[DB] caché local: version=$version '
        'hitos=${hitos.first['c']} evidencias=${evidencias.first['c']} '
        'porObra={$desglose}',
      );
    } catch (e) {
      debugPrint('[DB] no se pudo leer el caché local: $e');
    }
  }());

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
            // CU-60: huella de alta/edición/estado/archivado de la obra.
            auditLog: AuditLogWriter(
              dataSource: AuditLogLocalDataSource(
                  localDatabase: localDatabase),
            ),
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
        // Sprint 6 (RF_10): bandeja de notificaciones in-app, badge de la
        // campana (CU-70/CU-72) y preferencias de canal (CU-71). El cron
        // diario de retrasos (CU-69) lo arranca el Dashboard con las obras
        // vigentes; el servidor además tiene su propio cron.
        BlocProvider<NotificationsBloc>(
          create: (_) => NotificationsBloc(
            dao: NotificationLocalDataSource(localDatabase: localDatabase),
            remote: NotificationRemoteDataSource(dioClient: dioClient),
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
      // Scroll físico global: sin elasticidad, sin estiramiento del
      // contenido ni indicador de over-scroll en ninguna vista (ver
      // AppScrollBehavior).
      scrollBehavior: const AppScrollBehavior(),
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