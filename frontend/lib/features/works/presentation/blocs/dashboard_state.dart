import 'package:equatable/equatable.dart';

import '../../../notifications/domain/entities/app_notification.dart';

/// Estados del Dashboard de Obras (CU-66).
abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

/// CU-66: el consolidado se está calculando.
class DashboardLoading extends DashboardState {}

/// CU-66 paso 4: consolidado listo para las tarjetas resumen, el gráfico de
/// hitos por obra y la lista de últimas alertas.
class DashboardLoaded extends DashboardState {
  /// CU-66 paso 2: cantidad de obras activas (las provistas en el evento).
  final int obrasActivas;

  /// CU-66 paso 2: hitos NO certificados (`Pendiente` + `En Ejecución`).
  final int hitosPendientes;

  /// CU-66 paso 2: hitos en estado `Certificado`.
  final int hitosCertificados;

  /// Total de hitos relevados en las obras activas.
  final int hitosTotales;

  /// CU-66 paso 2: alertas recientes = notificaciones NO leídas del usuario.
  final int alertasRecientes;

  /// Las 3 alertas más recientes (para las tarjetas de "Últimas alertas").
  final List<AppNotification> ultimasAlertas;

  /// Insumo del gráfico de barras: `obraId` → hitos totales de esa obra.
  final Map<String, int> hitosPorObra;

  /// Insumo de la barra de progreso por obra: `obraId` → hitos certificados.
  final Map<String, int> certificadosPorObra;

  const DashboardLoaded({
    required this.obrasActivas,
    required this.hitosPendientes,
    required this.hitosCertificados,
    required this.hitosTotales,
    required this.alertasRecientes,
    required this.ultimasAlertas,
    required this.hitosPorObra,
    required this.certificadosPorObra,
  });

  /// Progreso de certificación de una obra (0.0 a 1.0); 0 si no tiene hitos.
  double progresoDeObra(String obraId) {
    final total = hitosPorObra[obraId] ?? 0;
    if (total <= 0) return 0.0;
    return (certificadosPorObra[obraId] ?? 0) / total;
  }

  @override
  List<Object?> get props => [
        obrasActivas,
        hitosPendientes,
        hitosCertificados,
        hitosTotales,
        alertasRecientes,
        ultimasAlertas,
        hitosPorObra,
        certificadosPorObra,
      ];
}

/// CU-66 Alt.: el consolidado no pudo calcularse.
class DashboardError extends DashboardState {
  final String message;

  const DashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}
