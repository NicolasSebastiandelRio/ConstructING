import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../../notifications/data/datasources/notification_local_data_source.dart';
import '../../../notifications/domain/entities/app_notification.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// BLoC del Dashboard de Obras (CU-66).
///
/// Consolida, sobre las obras activas que ya conoce la vista (CU-18), la
/// cantidad de obras activas, el avance de certificación de los hitos
/// (RF_02 / CU-57) y las alertas recientes del usuario (CU-67..CU-72).
///
/// Fail-closed (misma convención que el resto de los blocs): si un DAO no se
/// inyecta, su conteo queda en 0 y las listas vacías — nunca abre una
/// `LocalDatabase()` real por su cuenta (los tests inyectan fakes).
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  /// CU-66: fuente de hitos (`listByObra`). Null → todo el bloque de hitos en 0.
  final MilestoneLocalDataSource? milestonesDao;

  /// CU-66 paso 2: fuente de alertas del usuario (`listByUsuario`,
  /// `countUnread`). Null → alertas en 0 y lista vacía.
  final NotificationLocalDataSource? notificationDao;

  DashboardBloc({this.milestonesDao, this.notificationDao})
      : super(DashboardLoading()) {
    on<LoadDashboard>(_onLoadDashboard);
  }

  /// CU-66 pasos 2-4: recorre las obras activas sumando hitos por estado y
  /// arma los insumos del gráfico; agrega las alertas no leídas del usuario.
  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading());
    try {
      var hitosPendientes = 0;
      var hitosCertificados = 0;
      final hitosPorObra = <String, int>{};
      final certificadosPorObra = <String, int>{};

      final dao = milestonesDao;
      for (final obraId in event.obraIds) {
        final hitos = dao == null ? const <Milestone>[] : await dao.listByObra(obraId);
        var certificados = 0;
        for (final hito in hitos) {
          if (hito.estado == MilestoneStatus.certificado) {
            certificados++;
          }
        }
        // CU-66 paso 2: "pendientes" = todos los NO certificados
        // (Pendiente + En Ejecución).
        hitosCertificados += certificados;
        hitosPendientes += hitos.length - certificados;
        hitosPorObra[obraId] = hitos.length;
        certificadosPorObra[obraId] = certificados;
      }

      var alertasRecientes = 0;
      var ultimasAlertas = const <AppNotification>[];
      final alertasDao = notificationDao;
      if (alertasDao != null) {
        alertasRecientes = await alertasDao.countUnread(event.usuarioId);
        final bandeja = await alertasDao.listByUsuario(event.usuarioId);
        // Defensa: el DAO ya devuelve descendente (CU-70 paso 2), pero el
        // orden se reafirma aquí para no depender del proveedor.
        final ordenadas = List<AppNotification>.of(bandeja)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        ultimasAlertas = ordenadas.take(3).toList();
      }

      emit(DashboardLoaded(
        obrasActivas: event.obraIds.length,
        hitosPendientes: hitosPendientes,
        hitosCertificados: hitosCertificados,
        hitosTotales: hitosPendientes + hitosCertificados,
        alertasRecientes: alertasRecientes,
        ultimasAlertas: ultimasAlertas,
        hitosPorObra: hitosPorObra,
        certificadosPorObra: certificadosPorObra,
      ));
    } catch (e) {
      emit(DashboardError(message: _message(e)));
    }
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}
