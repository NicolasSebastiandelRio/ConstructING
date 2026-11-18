import 'package:equatable/equatable.dart';

import '../../data/datasources/audit_log_local_data_source.dart';

abstract class AuditReportEvent extends Equatable {
  const AuditReportEvent();

  @override
  List<Object?> get props => [];
}

/// CU-63 paso 1/2: el actor accede a "Reporte de Auditoría" dentro del panel
/// de la obra; el sistema consulta todos los registros inmutables vinculados
/// a ese `ID de obra`, ordenados cronológicamente.
class LoadAuditReport extends AuditReportEvent {
  final String obraId;

  const LoadAuditReport({required this.obraId});

  @override
  List<Object?> get props => [obraId];
}

abstract class AuditReportState extends Equatable {
  const AuditReportState();

  @override
  List<Object?> get props => [];
}

class AuditReportLoading extends AuditReportState {}

/// CU-63 paso 4: hoja de ruta forense renderizada.
class AuditReportLoaded extends AuditReportState {
  /// Registros del `audit_log` de la obra en orden CRONOLÓGICO (el más
  /// antiguo primero: la línea de tiempo del proyecto).
  final List<AuditLogRecord> registros;

  /// CU-63 paso 4 ("quién"): nombre del actor por `usuarioId`. Si no pudo
  /// resolverse, la vista cae al identificador.
  final Map<String, String> actores;

  const AuditReportLoaded({required this.registros, this.actores = const {}});

  /// Nombre a mostrar del actor de un registro.
  String actorDe(AuditLogRecord registro) =>
      actores[registro.usuarioId] ?? registro.usuarioId;

  @override
  List<Object?> get props => [registros, actores];
}

class AuditReportError extends AuditReportState {
  final String message;

  const AuditReportError({required this.message});

  @override
  List<Object?> get props => [message];
}
