import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/estimated_end_writer.dart';
import '../../data/datasources/milestone_local_data_source.dart';
import '../../domain/audit/milestone_audit.dart';
import '../../domain/cpm/critical_path.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/graph/milestone_graph.dart';
import '../../domain/notify/milestone_owner_notifier.dart';
import '../../domain/validation/progression_guard.dart';
import 'milestones_event.dart';
import 'milestones_state.dart';

/// Bloc de la Hoja de Ruta (CU-23..CU-27, RF_02). Todo persiste en la BD
/// local (offline-first); la nube se sincroniza en el Sprint 4 (CU-44).
class MilestonesBloc extends Bloc<MilestonesEvent, MilestonesState> {
  final MilestoneLocalDataSource dataSource;

  /// CU-30: escribe la fecha estimada en la obra (opcional; en tests se
  /// omite o se usa un fake).
  final EstimatedEndWriter? scheduleWriter;

  /// Aviso al propietario tras editar un hito ("uno de sus hitos fue
  /// modificado"). Opcional; si se omite se usa la traza de consola para no
  /// perder el aviso en offline-first.
  final MilestoneOwnerNotifier ownerNotifier;

  MilestonesBloc({
    required this.dataSource,
    this.scheduleWriter,
    MilestoneOwnerNotifier? ownerNotifier,
  })  : ownerNotifier =
            ownerNotifier ?? const ConsoleMilestoneOwnerNotifier(),
        super(MilestonesInitial()) {
    on<LoadMilestones>((event, emit) async {
      emit(MilestonesLoading());
      try {
        emit(await _loaded(event.obraId));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });

    // CU-23 pasos 3-4: persiste en local y refresca la Hoja de Ruta.
    // El recálculo de ruta crítica (CU-29) se enchufa en este handler en su
    // turno: tras persistir, computará holguras y marcará críticos.
    on<CreateMilestoneRequested>((event, emit) async {
      emit(MilestonesLoading());
      try {
        if (Milestone.validateNombre(event.nombre) != null) {
          throw Exception(Milestone.validateNombre(event.nombre));
        }
        await dataSource.create(
          obraId: event.obraId,
          nombre: event.nombre,
          descripcion: event.descripcion,
          duracionDias: event.duracionDias,
        );
        final cpm = await _recalculateCriticalPath(event.obraId);
        emit(await _loaded(event.obraId, cpm.schedules));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });

    // CU-25 pasos 3-4: valida, actualiza en local y refresca.
    // Precondición: solo hitos Pendiente (sin iniciar). CU-29 se enchufa aquí
    // en su turno, igual que en el alta: al cambiar duración/descripción se
    // recalculan las fechas de los hitos posteriores que dependen de él.
    // Paso 5 (roadmap): se notifica al propietario que un hito fue modificado.
    on<UpdateMilestoneRequested>((event, emit) async {
      emit(MilestonesLoading());
      try {
        final current = await dataSource.getById(event.id);
        if (current == null) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        if (current.estado != MilestoneStatus.pendiente) {
          throw Exception(
            'Solo se puede editar un hito en estado Pendiente.',
          );
        }
        if (event.duracionDias < 0) {
          throw Exception('La duración debe ser un número mayor o igual a 0.');
        }
        final updated = current.copyWith(
          descripcion: event.descripcion,
          duracionDias: event.duracionDias,
        );
        await dataSource.update(updated);
        final cpm = await _recalculateCriticalPath(current.obraId);
        // Notificación best-effort: lo local ya persistió y las fechas ya se
        // recalcularon; si el aviso falla no se revierte la edición.
        try {
          await this.ownerNotifier.notifyEdited(
            milestone: updated,
            propietarioEmail: event.propietarioEmail,
            propietarioNombre: event.propietarioNombre,
          );
        } catch (e) {
          debugPrint('Aviso al propietario pendiente (obra ${current.obraId}): $e');
        }
        emit(await _loaded(current.obraId, cpm.schedules));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });

    // CU-24 pasos 3-4: reemplaza los predecesores, persiste y refresca.
    // La verificación de ciclos (paso 2) corre en memoria ANTES de tocar la
    // BD (Alt. 2.2). CU-29 se enchufa aquí en su turno, igual que en el alta.
    on<SetDependenciesRequested>((event, emit) async {
      emit(MilestonesLoading());
      try {
        final milestones = await dataSource.listByObra(event.obraId);
        final ids = milestones.map((m) => m.id).toSet();
        if (!ids.contains(event.hitoId)) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        final unknown = event.predecesorIds.where((id) => !ids.contains(id));
        if (unknown.isNotEmpty) {
          throw Exception('Uno o más hitos seleccionados no pertenecen a la obra.');
        }
        final edges = await dataSource.dependencyMap(event.obraId);
        final next = Set<String>.of(event.predecesorIds);
        if (MilestoneGraph.wouldCreateCycle(
          existing: edges,
          hitoId: event.hitoId,
          newPredecessors: next,
        )) {
          throw Exception('Referencia circular detectada');
        }
        final current = Set<String>.of(edges[event.hitoId] ?? {});
        for (final add in next.difference(current)) {
          await dataSource.addDependency(hitoId: event.hitoId, predecesorId: add);
        }
        for (final remove in current.difference(next)) {
          await dataSource.removeDependency(
              hitoId: event.hitoId, predecesorId: remove);
        }
        final cpm = await _recalculateCriticalPath(event.obraId);
        emit(await _loaded(event.obraId, cpm.schedules));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });

    // CU-26: avanza a la siguiente fase (Pendiente → En Ejecución →
    // Certificado). Al iniciar se ejecuta CU-28 (paso 2); el cambio se
    // audita (paso 4, CU-60 transitorio) y se refresca la pantalla.
    // Roadmap secuencial: al finalizar (certificar) un hito se recalcula la
    // ruta para que el siguiente comience en secuencia y el fin estimado de
    // la obra quede ajustado (CU-29/CU-30, igual que en el alta).
    on<AdvanceMilestoneStatus>((event, emit) async {
      emit(MilestonesLoading());
      try {
        final current = await dataSource.getById(event.hitoId);
        if (current == null) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        final next = current.estado.next;
        if (next == null) {
          throw Exception('El hito ya está certificado.');
        }
        // CU-28: solo se puede INICIAR si los predecesores están certificados.
        if (next == MilestoneStatus.enEjecucion) {
          final milestones = await dataSource.listByObra(current.obraId);
          final byId = {for (final m in milestones) m.id: m};
          final edges = await dataSource.dependencyMap(current.obraId);
          final check = ProgressionGuard.canAdvance(
            hitoId: current.id,
            byId: byId,
            edges: edges,
          );
          if (!check.allowed) {
            throw Exception(ProgressionGuard.denialMessage(check));
          }
        }
        MilestoneAudit.logStatusChange(before: current, after: next);
        await dataSource.update(current.copyWith(estado: next));
        final cpm = await _recalculateCriticalPath(current.obraId);
        emit(await _loaded(current.obraId, cpm.schedules));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });

    // CU-27 pasos 2+4: verifica guards en BD, borra y refresca la lista.
    // CU-29 se enchufa aquí en su turno, igual que en el alta.
    on<DeleteMilestoneRequested>((event, emit) async {
      emit(MilestonesLoading());
      try {
        final current = await dataSource.getById(event.hitoId);
        if (current == null) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        // Alt. 2.1/2.2: con progreso (En Ejecución/Certificado) o
        // dependencias activas (entrantes o salientes) se bloquea.
        if (current.estado != MilestoneStatus.pendiente) {
          throw Exception(
            'No se puede eliminar un hito con progreso o dependencias activas',
          );
        }
        final predecessors =
            await dataSource.predecessorIds(current.id);
        final successors = await dataSource.successorIds(current.id);
        if (predecessors.isNotEmpty || successors.isNotEmpty) {
          throw Exception(
            'No se puede eliminar un hito con progreso o dependencias activas',
          );
        }
        // Evidencias asociadas: el módulo de evidencia (CU-32+, Sprint 4/5)
        // aún no existe; al llegar se suma aquí su chequeo antes del borrado.
        await dataSource.delete(current.id);
        final cpm = await _recalculateCriticalPath(current.obraId);
        emit(await _loaded(current.obraId, cpm.schedules));
      } catch (e) {
        emit(MilestonesError(message: _message(e)));
      }
    });
  }

  /// Hoja de Ruta fresca: lista + mapa de aristas (CU-24/CU-29) +
  /// cronograma para el roadmap. Si no se provee el cálculo (carga
  /// inicial), se computa acá tolerando grafos circulares.
  Future<MilestonesLoaded> _loaded(
    String obraId, [
    Map<String, CpmNodeSchedule>? schedules,
  ]) async {
    final milestones = await dataSource.listByObra(obraId);
    final edges = await dataSource.dependencyMap(obraId);
    return MilestonesLoaded(
      milestones: milestones,
      edges: edges,
      schedules: schedules ?? _safeSchedules(milestones, edges),
    );
  }

  /// Cronograma defensivo para lectura: ante grafo circular devuelve vacío
  /// (la mutación que lo produjo ya informó el error por su lado).
  Map<String, CpmNodeSchedule> _safeSchedules(
    List<Milestone> milestones,
    Map<String, Set<String>> edges,
  ) {
    try {
      return CriticalPath.calculate(
        durations: {for (final m in milestones) m.id: m.duracionDias},
        predecessors: edges,
      ).schedules;
    } catch (_) {
      return const {};
    }
  }

  /// CU-29 (invocado tras crear/modificar/eliminar hitos y dependencias):
  /// recalcula holguras, persiste los críticos y dispara CU-30. Retorna el
  /// cálculo para reutilizarlo en el estado. Lanza [CriticalPathException]
  /// si el grafo quedó circular (no debería ocurrir: CU-24 lo impide).
  Future<CriticalPathResult> _recalculateCriticalPath(String obraId) async {
    final milestones = await dataSource.listByObra(obraId);
    final edges = await dataSource.dependencyMap(obraId);
    final result = CriticalPath.calculate(
      durations: {for (final m in milestones) m.id: m.duracionDias},
      predecessors: edges,
    );
    await dataSource.setCritical(obraId: obraId, criticalIds: result.criticalIds);
    // CU-30: fecha estimada best-effort (offline-first: lo local ya
    // persistió; ante fallo se reintentará en el próximo recálculo/CU-44).
    final writer = scheduleWriter;
    if (writer != null) {
      try {
        await writer.write(
          obraId: obraId,
          projectDurationDays: result.projectDuration,
        );
      } catch (e) {
        debugPrint('CU-30 pendiente (obra $obraId): $e');
      }
    }
    return result;
  }

  String _message(Object e) =>
      e.toString().replaceAll('Exception: ', '').replaceAll(
          'CacheStorageException: ', '');
}
