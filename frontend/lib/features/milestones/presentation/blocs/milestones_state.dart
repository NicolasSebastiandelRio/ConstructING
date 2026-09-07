import 'package:equatable/equatable.dart';

import '../../domain/cpm/critical_path.dart';
import '../../domain/entities/milestone.dart';

abstract class MilestonesState extends Equatable {
  const MilestonesState();

  @override
  List<Object?> get props => [];
}

class MilestonesInitial extends MilestonesState {}

class MilestonesLoading extends MilestonesState {}

class MilestonesLoaded extends MilestonesState {
  final List<Milestone> milestones;

  /// Mapa hito → predecesores de la obra (CU-24 paso 2 en memoria y base de
  /// CU-29). Se recarga junto con la lista en cada mutación.
  final Map<String, Set<String>> edges;

  /// Cronograma CPM por hito para el roadmap (CU-29 display). Vacío si aún
  /// no se calculó o el grafo quedó circular.
  final Map<String, CpmNodeSchedule> schedules;

  const MilestonesLoaded({
    required this.milestones,
    this.edges = const {},
    this.schedules = const {},
  });

  @override
  List<Object?> get props => [milestones, edges, schedules];
}

class MilestonesError extends MilestonesState {
  final String message;

  const MilestonesError({required this.message});

  @override
  List<Object?> get props => [message];
}
