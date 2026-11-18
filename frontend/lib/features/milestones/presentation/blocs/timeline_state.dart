import 'package:equatable/equatable.dart';

import '../../domain/cpm/critical_path.dart';
import '../../domain/entities/milestone.dart';

/// Estados de la Línea de Tiempo (CU-64, RF_02).
///
/// La pantalla solo pinta: todo el ordenamiento cronológico y el cálculo del
/// cronograma (CPM, CU-29) se resuelven en el bloc para que el widget sea
/// testeable y determinista.
abstract class TimelineState extends Equatable {
  const TimelineState();

  @override
  List<Object?> get props => [];
}

class TimelineInitial extends TimelineState {
  const TimelineInitial();
}

/// CU-64 paso 3: la Línea de Tiempo se está recuperando de la BD local.
class TimelineLoading extends TimelineState {
  const TimelineLoading();
}

/// CU-64 paso 4 (poscondición): Línea de Tiempo lista para graficarse.
class TimelineLoaded extends TimelineState {
  /// Hitos de la obra **ordenados cronológicamente** por inicio temprano
  /// (desempate estable por orden de creación, CU-64 paso 2).
  final List<Milestone> hitos;

  /// Cronograma CPM por hito (CU-29 display: fechas + criticidad). Vacío si
  /// aún no se pudo calcular o el grafo quedó circular (Alt. 2.1/2.2).
  final Map<String, CpmNodeSchedule> schedules;

  /// Mapa hito → predecesores de la obra (CU-24 paso 2 en memoria): dibuja
  /// las conexiones del riel y documenta el orden mostrado.
  final Map<String, Set<String>> edges;

  const TimelineLoaded({
    required this.hitos,
    required this.schedules,
    required this.edges,
  });

  @override
  List<Object?> get props => [hitos, schedules, edges];
}

/// CU-64 Alt. 2.2: la Línea de Tiempo no pudo recuperarse de la BD local.
class TimelineError extends TimelineState {
  final String message;

  const TimelineError({required this.message});

  @override
  List<Object?> get props => [message];
}
