import 'package:equatable/equatable.dart';

abstract class WorksEvent extends Equatable {
  const WorksEvent();

  @override
  List<Object?> get props => [];
}

class FetchWorksEvent extends WorksEvent {
  /// CU-18: con `propietarioId` consulta "Mis Obras"; sin él, el listado
  /// general (rol Profesional). Con `archivedOnly` trae el historial de
  /// archivadas en lugar del listado activo (CU-21 paso 4).
  final String? propietarioId;
  final bool archivedOnly;

  const FetchWorksEvent({this.propietarioId, this.archivedOnly = false});

  @override
  List<Object?> get props => [propietarioId, archivedOnly];
}

/// CU-19: recupera los datos maestros de una obra desde la BD.
class FetchWorkDetailEvent extends WorksEvent {
  final String id;

  const FetchWorkDetailEvent({required this.id});

  @override
  List<Object?> get props => [id];
}

class CreateWorkEvent extends WorksEvent {
  final Map<String, dynamic> workData;

  const CreateWorkEvent({required this.workData});

  @override
  List<Object?> get props => [workData];
}

/// CU-17: edita los datos administrativos de una obra existente.
class UpdateWorkEvent extends WorksEvent {
  final String id;
  final Map<String, dynamic> workData;

  const UpdateWorkEvent({required this.id, required this.workData});

  @override
  List<Object?> get props => [id, workData];
}

/// CU-20: cambia la fase global de la obra.
class UpdateWorkStatusEvent extends WorksEvent {
  final String id;
  final String estado;

  const UpdateWorkStatusEvent({required this.id, required this.estado});

  @override
  List<Object?> get props => [id, estado];
}

/// CU-21: archiva una obra completada (previa confirmación en la UI).
class ArchiveWorkEvent extends WorksEvent {
  final String id;

  const ArchiveWorkEvent({required this.id});

  @override
  List<Object?> get props => [id];
}
