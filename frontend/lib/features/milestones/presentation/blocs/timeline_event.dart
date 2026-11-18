import 'package:equatable/equatable.dart';

/// Eventos de la Línea de Tiempo (CU-64, RF_02).
abstract class TimelineEvent extends Equatable {
  const TimelineEvent();

  @override
  List<Object?> get props => [];
}

/// CU-64 paso 1: el usuario abre la Línea de Tiempo de una obra.
///
/// Dispara la lectura del cronograma completo desde la BD local
/// (offline-first, CU-42): los hitos de la obra y sus dependencias.
class LoadTimeline extends TimelineEvent {
  final String obraId;

  const LoadTimeline({required this.obraId});

  @override
  List<Object?> get props => [obraId];
}
