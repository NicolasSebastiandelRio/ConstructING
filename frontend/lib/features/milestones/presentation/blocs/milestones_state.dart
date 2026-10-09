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

  /// CU-57: hito → rol que ya firmó la PRIMERA conformidad y cuyo borrador
  /// espera la segunda firma. Alimenta el estado "esperando su firma" de la
  /// Hoja de Ruta del Propietario y el guard que le impide certificar sin la
  /// conformidad técnica previa del profesional responsable.
  final Map<String, String> pendingFirmantes;

  const MilestonesLoaded({
    required this.milestones,
    this.edges = const {},
    this.schedules = const {},
    this.pendingFirmantes = const {},
  });

  @override
  List<Object?> get props =>
      [milestones, edges, schedules, pendingFirmantes];
}

/// CU-50 poscondición: el hito pasó la validación y entra en flujo de
/// certificación. La UI conecta con el CU-51 (Visualizar Resumen) para
/// iniciar el proceso de doble firma (RF_05). El estado del hito sigue
/// "En Ejecución": pasa a "Certificado" al completar las firmas.
/// Extiende MilestonesLoaded para que la Hoja de Ruta siga visible.
class MilestoneCertificationReady extends MilestonesLoaded {
  final String hitoId;
  final String hitoNombre;

  const MilestoneCertificationReady({
    required this.hitoId,
    required this.hitoNombre,
    required super.milestones,
    super.edges,
    super.schedules,
    super.pendingFirmantes,
  });

  @override
  List<Object?> get props => [...super.props, hitoId, hitoNombre];
}

/// CU-50 Alt. 2.1/2.2: la solicitud de cierre se bloquea (sin evidencia o
/// fuera de precondición). Extiende MilestonesLoaded para que el detalle del
/// hito siga en pantalla mientras el mensaje se informa.
class MilestoneCertificationBlocked extends MilestonesLoaded {
  final String hitoId;

  /// Mensaje exacto de la especificación (Alt. 2.2) o de precondición.
  final String message;

  const MilestoneCertificationBlocked({
    required this.hitoId,
    required this.message,
    required super.milestones,
    super.edges,
    super.schedules,
    super.pendingFirmantes,
  });

  @override
  List<Object?> get props => [...super.props, hitoId, message];
}

class MilestonesError extends MilestonesState {
  final String message;

  const MilestonesError({required this.message});

  @override
  List<Object?> get props => [message];
}
