import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/audit_log_local_data_source.dart';
import '../../data/datasources/audit_log_remote_data_source.dart';
import 'audit_report_state.dart';

/// BLoC del Reporte de Auditoría (CU-63, RF_08/RNF_U_03).
///
/// Paso 2: consulta en BD todos los registros inmutables del `audit_log`
/// vinculados al `ID de obra`, **ordenados cronológicamente** (ascendente).
/// Paso 4: expone la tabla con quién, cuándo y desde dónde.
///
/// Los registros son inmutables (RNF_S_03): este BLoC solo lee, nunca
/// modifica ni elimina.
class AuditReportBloc extends Bloc<AuditReportEvent, AuditReportState> {
  final AuditLogLocalDataSource local;

  /// Fuente remota opcional: consolida los registros que el servidor ya
  /// recibió (CU-60 paso 2) con el timestamp exacto del servidor.
  final AuditLogRemoteDataSource? remote;

  /// CU-63 "quién": resolutor de nombre del actor. Opcional — si se omite o
  /// falla, la vista muestra el `usuarioId`.
  final Future<String?> Function(String usuarioId)? usuarioNombre;

  AuditReportBloc({
    required this.local,
    this.remote,
    this.usuarioNombre,
  }) : super(AuditReportLoading()) {
    on<LoadAuditReport>(_onLoad);
  }

  /// CU-63 pasos 1-4: consulta, ordena cronológicamente y resuelve actores.
  Future<void> _onLoad(
    LoadAuditReport event,
    Emitter<AuditReportState> emit,
  ) async {
    emit(AuditReportLoading());
    try {
      final locales = await local.listByObra(event.obraId);
      final registros = [...locales]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(AuditReportLoaded(
        registros: registros,
        actores: await _resolverActores(registros),
      ));
    } catch (e) {
      emit(AuditReportError(message: _message(e)));
    }
  }

  /// CU-63 paso 4 ("quién"): un nombre legible por cada actor distinto.
  Future<Map<String, String>> _resolverActores(
    List<AuditLogRecord> registros,
  ) async {
    final resolver = usuarioNombre;
    if (resolver == null) return const {};
    final actores = <String, String>{};
    for (final id in {for (final r in registros) r.usuarioId}) {
      try {
        final nombre = await resolver(id);
        if (nombre != null && nombre.trim().isNotEmpty) {
          actores[id] = nombre.trim();
        }
      } catch (_) {
        // Best-effort: la fila cae al identificador del usuario.
      }
    }
    return actores;
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}
