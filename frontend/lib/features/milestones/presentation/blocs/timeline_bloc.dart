import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/milestone_local_data_source.dart';
import '../../domain/cpm/critical_path.dart';
import '../../domain/entities/milestone.dart';
import 'timeline_event.dart';
import 'timeline_state.dart';

/// Bloc de la Línea de Tiempo (CU-64, RF_02).
///
/// CU-64 paso 2: recupera de la BD local la Hoja de Ruta completa de la obra
/// (hitos + dependencias) y la deja **ordenada cronológicamente** por inicio
/// temprano, con desempate estable por orden de creación (mismo criterio que
/// la Hoja de Ruta del CU-29). El cronograma se computa con
/// [CriticalPath.calculate] dentro de un `try`/`catch`: ante un grafo
/// circular (Alt. 2.1/2.2) la Línea de Tiempo se muestra igual, sin
/// cronograma, en vez de romper la pantalla.
class TimelineBloc extends Bloc<TimelineEvent, TimelineState> {
  /// CU-64 paso 2: fuente local de hitos y dependencias (CU-42). Inyectable
  /// para que los tests compartan su propia BD o un DAO fake en memoria.
  final MilestoneLocalDataSource dataSource;

  TimelineBloc({required this.dataSource}) : super(const TimelineInitial()) {
    on<LoadTimeline>((event, emit) async {
      emit(const TimelineLoading());
      try {
        // Paso 2: Hoja de Ruta de la obra + aristas de dependencia (CU-24).
        final hitos = await dataSource.listByObra(event.obraId);
        final edges = await dataSource.dependencyMap(event.obraId);
        // CU-29: cronograma por hito para fechar la línea de tiempo.
        final schedules = _safeSchedules(hitos, edges);
        emit(TimelineLoaded(
          hitos: _sortedByEarlyStart(hitos, schedules),
          schedules: schedules,
          edges: edges,
        ));
      } catch (e) {
        emit(TimelineError(message: _message(e)));
      }
    });
  }

  /// CU-64 paso 2: orden cronológico por inicio temprano (ascendente) con
  /// desempate estable por orden de creación (el que trae la BD).
  ///
  /// Sin cronograma (grafo circular) se conserva el orden de creación de la
  /// Hoja de Ruta, igual que en [MilestonesSection].
  List<Milestone> _sortedByEarlyStart(
    List<Milestone> hitos,
    Map<String, CpmNodeSchedule> schedules,
  ) {
    final indexed = hitos.asMap().entries.toList();
    indexed.sort((a, b) {
      final sa = schedules[a.value.id]?.earlyStart;
      final sb = schedules[b.value.id]?.earlyStart;
      if (sa == null && sb == null) {
        return a.key.compareTo(b.key);
      }
      if (sa == null) return 1;
      if (sb == null) return -1;
      final byStart = sa.compareTo(sb);
      return byStart != 0 ? byStart : a.key.compareTo(b.key);
    });
    return [for (final entry in indexed) entry.value];
  }

  /// Cronograma defensivo: ante grafo circular devuelve vacío y la Línea de
  /// Tiempo sigue mostrándose (CU-64 Alt. 2.1/2.2), sin romper la pantalla.
  Map<String, CpmNodeSchedule> _safeSchedules(
    List<Milestone> hitos,
    Map<String, Set<String>> edges,
  ) {
    try {
      return CriticalPath.calculate(
        durations: {for (final h in hitos) h.id: h.duracionDias},
        predecessors: edges,
      ).schedules;
    } catch (_) {
      return const {};
    }
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}
