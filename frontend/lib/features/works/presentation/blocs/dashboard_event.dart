import 'package:equatable/equatable.dart';

/// Eventos del Dashboard de Obras (CU-66).
abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// CU-66 paso 1/2: el usuario abre el Dashboard y se solicita el consolidado
/// de sus obras activas.
///
/// [obraIds] son las obras vigentes que la vista ya conoce (las emite el
/// `WorksBloc` en `WorksLoaded`); el Dashboard NO vuelve a consultar obras.
/// [obraNombres] es opcional y solo alimenta las etiquetas del gráfico de
/// barras (clave = `obraId`); si falta, el gráfico rotula con el id acortado.
class LoadDashboard extends DashboardEvent {
  /// Usuario del que se cuentan las alertas recientes (CU-66 paso 2).
  final String usuarioId;

  /// Obras activas sobre las que se consolidan los hitos.
  final List<String> obraIds;

  /// Nombres legibles por obra para el gráfico (opcional).
  final Map<String, String> obraNombres;

  const LoadDashboard({
    required this.usuarioId,
    required this.obraIds,
    this.obraNombres = const {},
  });

  @override
  List<Object?> get props => [usuarioId, obraIds, obraNombres];
}
