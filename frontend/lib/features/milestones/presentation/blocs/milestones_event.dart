import 'package:equatable/equatable.dart';

abstract class MilestonesEvent extends Equatable {
  const MilestonesEvent();

  @override
  List<Object?> get props => [];
}

/// Carga la Hoja de Ruta de una obra desde la BD local.
class LoadMilestones extends MilestonesEvent {
  final String obraId;

  const LoadMilestones({required this.obraId});

  @override
  List<Object?> get props => [obraId];
}

/// CU-23: crea un hito (pasos 1-3) y refresca la Hoja de Ruta.
class CreateMilestoneRequested extends MilestonesEvent {
  final String obraId;
  final String nombre;
  final String? descripcion;
  final int duracionDias;

  const CreateMilestoneRequested({
    required this.obraId,
    required this.nombre,
    this.descripcion,
    required this.duracionDias,
  });

  @override
  List<Object?> get props => [obraId, nombre, descripcion, duracionDias];
}

/// CU-25: edita descripción/duración de un hito (el nombre no se toca,
/// según la spec: "Modifica la duración o descripción").
/// Los datos del propietario viajan solo para la notificación posterior al
/// guardado ("uno de sus hitos fue modificado"); no se persisten.
class UpdateMilestoneRequested extends MilestonesEvent {
  final String id;
  final String? descripcion;
  final int duracionDias;
  final String? propietarioEmail;
  final String? propietarioNombre;

  const UpdateMilestoneRequested({
    required this.id,
    this.descripcion,
    required this.duracionDias,
    this.propietarioEmail,
    this.propietarioNombre,
  });

  @override
  List<Object?> get props =>
      [id, descripcion, duracionDias, propietarioEmail, propietarioNombre];
}

/// CU-24 pasos 1+3: reemplaza el conjunto de predecesores de un hito por la
/// selección confirmada en el diálogo.
class SetDependenciesRequested extends MilestonesEvent {
  final String obraId;
  final String hitoId;
  final List<String> predecesorIds;

  const SetDependenciesRequested({
    required this.obraId,
    required this.hitoId,
    required this.predecesorIds,
  });

  @override
  List<Object?> get props => [obraId, hitoId, predecesorIds];
}

/// CU-26: avanza un hito a su siguiente fase operativa
/// (Pendiente → En Ejecución → Certificado). El destino se calcula
/// internamente: la UI solo ofrece avanzar cuando es válido.
class AdvanceMilestoneStatus extends MilestonesEvent {
  final String hitoId;

  const AdvanceMilestoneStatus({required this.hitoId});

  @override
  List<Object?> get props => [hitoId];
}

/// CU-27: elimina un hito sin progreso ni dependencias (previa confirmación
/// en la UI, paso 1).
class DeleteMilestoneRequested extends MilestonesEvent {
  final String hitoId;

  const DeleteMilestoneRequested({required this.hitoId});

  @override
  List<Object?> get props => [hitoId];
}
