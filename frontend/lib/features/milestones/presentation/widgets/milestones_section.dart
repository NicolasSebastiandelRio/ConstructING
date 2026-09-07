import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/estimated_end_writer.dart';
import '../../data/datasources/milestone_local_data_source.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/notify/milestone_owner_notifier.dart';
import '../../domain/schedule/milestone_schedule.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';
import 'dependencies_dialog.dart';
import 'delete_milestone_dialog.dart';
import 'edit_milestone_modal.dart';
import 'new_milestone_modal.dart';
import 'advance_status_dialog.dart';

/// Hoja de Ruta de la obra como roadmap / línea de tiempo secuencial.
///
/// La fecha de inicio de la ruta es la fecha de inicio definida al crear el
/// proyecto ([obraFechaInicio]). Los hitos se ordenan cronológicamente por
/// inicio temprano (con desempate estable por creación) y se dibujan uno
/// conectado con el siguiente (riel vertical con nodos), de modo que se
/// entiende rápidamente la secuencia y el progreso.
///
/// Cada hito muestra: nombre, descripción (si existe), duración en días,
/// rango de fechas y fecha de finalización estimada en formato DD/MM/AAAA.
/// La duración restante baja con el paso del tiempo
/// ([MilestoneScheduleView.remainingDays]) y al modificar un hito el bloc
/// recalcula las fechas dependientes (CU-29) y notifica al propietario.
class MilestonesSection extends StatelessWidget {
  final String obraId;
  final bool isProfesional;

  /// DAO inyectable (tests); en producción se crea sobre la BD local real.
  final MilestoneLocalDataSource? dataSource;

  /// CU-30: escribe la fecha estimada en la obra (opcional; la ficha real
  /// lo provee, en tests se omite o se usa un fake).
  final EstimatedEndWriter? scheduleWriter;

  /// Inicio de la obra (yyyy-MM-dd) para anclar el roadmap a fechas
  /// concretas. Si se omite, se muestran días relativos.
  final String? obraFechaInicio;

  /// Datos del propietario para el aviso "uno de sus hitos fue modificado".
  /// La ficha técnica los provee desde la obra; en tests se omiten.
  final String? propietarioEmail;
  final String? propietarioNombre;

  /// Notificador inyectable (tests); por defecto traza de consola.
  final MilestoneOwnerNotifier? ownerNotifier;

  const MilestonesSection({
    super.key,
    required this.obraId,
    required this.isProfesional,
    this.dataSource,
    this.scheduleWriter,
    this.obraFechaInicio,
    this.propietarioEmail,
    this.propietarioNombre,
    this.ownerNotifier,
  });

  /// Ancla de la ruta: acepta ISO (yyyy-MM-dd[THH:mm...]) y el formato
  /// legible DD/MM/AAAA por robustez. Null si no hay inicio válido.
  static DateTime? parseObraStart(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        try {
          return DateTime(y, m, d);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MilestonesBloc>(
      create: (_) => MilestonesBloc(
        dataSource: dataSource ??
            MilestoneLocalDataSource(localDatabase: LocalDatabase()),
        scheduleWriter: scheduleWriter,
        ownerNotifier: ownerNotifier,
      )..add(LoadMilestones(obraId: obraId)),
      child: Builder(
        builder: (sectionContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'HOJA DE RUTA',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isProfesional)
                  TextButton.icon(
                    onPressed: () => _openNewModal(sectionContext),
                    icon: const Icon(Icons.add,
                        color: AppTheme.accentGold, size: 18),
                    label: const Text('Añadir Hito',
                        style: TextStyle(
                            color: AppTheme.accentGold, fontSize: 13)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            BlocBuilder<MilestonesBloc, MilestonesState>(
              builder: (context, state) {
                if (state is MilestonesLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: AppTheme.accentGold),
                    ),
                  );
                } else if (state is MilestonesError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(
                                color: AppTheme.primaryRed),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => context
                              .read<MilestonesBloc>()
                              .add(LoadMilestones(obraId: obraId)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentGold,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (state is MilestonesLoaded) {
                  if (state.milestones.isEmpty) {                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay hitos registrados en este proyecto todavía.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    );
                  }
                  // Roadmap cronológico: ordenados por inicio temprano (con
                  // desempate estable por creación); sin cronograma, orden
                  // de creación.
                  final obraStart = parseObraStart(obraFechaInicio);
                  final indexed =
                      state.milestones.asMap().entries.toList();
                  indexed.sort((a, b) {
                    final sa = state.schedules[a.value.id]?.earlyStart;
                    final sb = state.schedules[b.value.id]?.earlyStart;
                    if (sa == null && sb == null) {
                      return a.key.compareTo(b.key);
                    }
                    if (sa == null) return 1;
                    if (sb == null) return -1;
                    final byStart = sa.compareTo(sb);
                    return byStart != 0 ? byStart : a.key.compareTo(b.key);
                  });
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RoadmapHeader(
                        obraStart: obraStart,
                        state: state,
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < indexed.length; i++)
                        _RoadmapStep(
                          position: i + 1,
                          total: indexed.length,
                          isFirst: i == 0,
                          isLast: i == indexed.length - 1,
                          child: _MilestoneTile(
                            milestone: indexed[i].value,
                            allMilestones: state.milestones,
                            allEdges: state.edges,
                            isProfesional: isProfesional,
                            sequenceLabel:
                                'HITO ${i + 1} DE ${indexed.length}',
                            scheduleView: _scheduleViewOf(
                              state,
                              indexed[i].value,
                              obraStart,
                            ),
                            onEdit: () => _openEditModal(
                                context, indexed[i].value),
                            onAdvance: indexed[i].value.estado.next == null
                                ? null
                                : () => _openAdvanceDialog(
                                    context, indexed[i].value),
                            onDelete: indexed[i].value.estado ==
                                    MilestoneStatus.pendiente
                                ? () => _openDeleteDialog(
                                    context, indexed[i].value)
                                : null,
                            onDependencies: () => _openDependenciesDialog(
                              context,
                              milestone: indexed[i].value,
                              allMilestones: state.milestones,
                              allEdges: state.edges,
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Resuelve la vista de cronograma de un hito (fechas + restantes), o
  /// null si no hay ancla de inicio o aún no hay cálculo.
  MilestoneScheduleView? _scheduleViewOf(
    MilestonesLoaded state,
    Milestone milestone,
    DateTime? obraStart,
  ) {
    final schedule = state.schedules[milestone.id];
    if (obraStart == null || schedule == null) return null;
    return MilestoneScheduleView.resolve(
      obraStart: obraStart,
      earlyStart: schedule.earlyStart,
      earlyFinish: schedule.earlyFinish,
      durationDays: milestone.duracionDias,
      isCritical: schedule.isCritical,
    );
  }

  void _openNewModal(BuildContext context) {    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<MilestonesBloc>(context),
        child: NewMilestoneModal(obraId: obraId),
      ),
    );
  }

  /// CU-26 paso 1: confirma el avance a la siguiente fase operativa.
  void _openAdvanceDialog(BuildContext context, Milestone milestone) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<MilestonesBloc>(context),
        child: AdvanceStatusDialog(hito: milestone),
      ),
    );
  }

  /// CU-27 paso 1: cuadro de advertencia antes de eliminar.
  void _openDeleteDialog(BuildContext context, Milestone milestone) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<MilestonesBloc>(context),
        child: DeleteMilestoneDialog(hito: milestone),
      ),
    );
  }

  /// CU-25 paso 1: abre la edición con los datos actuales precargados.
  /// Lleva los datos del propietario para notificarle la modificación.
  void _openEditModal(BuildContext context, Milestone milestone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<MilestonesBloc>(context),
        child: EditMilestoneModal(
          milestone: milestone,
          propietarioEmail: propietarioEmail,
          propietarioNombre: propietarioNombre,
        ),
      ),
    );
  }

  /// CU-24 paso 1: abre el diálogo de predecesores del hito.
  void _openDependenciesDialog(
    BuildContext context, {
    required Milestone milestone,
    required List<Milestone> allMilestones,
    required Map<String, Set<String>> allEdges,
  }) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<MilestonesBloc>(context),
        child: DependenciesDialog(
          obraId: obraId,
          hito: milestone,
          milestones: allMilestones,
          allEdges: allEdges,
        ),
      ),
    );
  }
}

/// Cabecera del roadmap: ancla la ruta a la fecha de inicio del proyecto y
/// resume el fin estimado + el progreso (X de N certificados).
class _RoadmapHeader extends StatelessWidget {
  final DateTime? obraStart;
  final MilestonesLoaded state;

  const _RoadmapHeader({required this.obraStart, required this.state});

  @override
  Widget build(BuildContext context) {
    final total = state.milestones.length;
    final done = state.milestones
        .where((m) => m.estado == MilestoneStatus.certificado)
        .length;
    String? endText;
    final startAnchor = obraStart;
    if (startAnchor != null && state.schedules.isNotEmpty) {
      var duration = 0;
      for (final s in state.schedules.values) {
        if (s.earlyFinish > duration) duration = s.earlyFinish;
      }
      final end = DateTime(startAnchor.year, startAnchor.month, startAnchor.day)
          .add(Duration(days: duration));
      endText = MilestoneScheduleView.format(end);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined,
                  color: AppTheme.accentGold, size: 16),
              const SizedBox(width: 6),
              Text(
                obraStart != null
                    ? 'Inicio de ruta: ${MilestoneScheduleView.format(obraStart!)}'
                    : 'Inicio de ruta: sin fecha de proyecto',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            endText != null
                ? 'Fin estimado: $endText · $done de $total certificados'
                : '$done de $total certificados',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Paso del roadmap: riel vertical con nodo numerado + línea que lo conecta
/// con el anterior y el siguiente, y la tarjeta del hito a la derecha.
class _RoadmapStep extends StatelessWidget {
  final int position;
  final int total;
  final bool isFirst;
  final bool isLast;
  final Widget child;

  const _RoadmapStep({
    required this.position,
    required this.total,
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                // Conector superior (el primero no tiene: inicia la ruta).
                Container(
                  width: 2,
                  height: isFirst ? 12 : 14,
                  color: isFirst
                      ? Colors.transparent
                      : AppTheme.accentGold.withValues(alpha: 0.5),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.darkSurface,
                    border: Border.all(
                      color: AppTheme.accentGold.withValues(alpha: 0.8),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Conector inferior (el último no continúa: cierra la ruta).
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : AppTheme.accentGold.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : 8,
                top: 2,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un hito en la Hoja de Ruta, con acciones según rol y estado.
class _MilestoneTile extends StatelessWidget {
  final Milestone milestone;
  final List<Milestone> allMilestones;
  final Map<String, Set<String>> allEdges;
  final bool isProfesional;
  final VoidCallback onEdit;
  final VoidCallback? onAdvance;
  final VoidCallback? onDelete;
  final VoidCallback onDependencies;

  /// Etiqueta de secuencia del roadmap ("HITO 1 DE 3").
  final String? sequenceLabel;

  /// Vista de cronograma del roadmap (fechas + restantes); null si no hay
  /// ancla o cálculo todavía (se muestra duración relativa).
  final MilestoneScheduleView? scheduleView;

  const _MilestoneTile({
    required this.milestone,
    required this.allMilestones,
    required this.allEdges,
    required this.isProfesional,
    required this.onEdit,
    required this.onAdvance,
    required this.onDelete,
    required this.onDependencies,
    required this.scheduleView,
    this.sequenceLabel,
  });

  Color _statusColor(MilestoneStatus estado) {
    switch (estado) {
      case MilestoneStatus.certificado:
        return Colors.greenAccent;
      case MilestoneStatus.enEjecucion:
        return AppTheme.lightBlue;
      case MilestoneStatus.pendiente:
        return Colors.white54;
    }
  }

  IconData _statusIcon(MilestoneStatus estado) {
    switch (estado) {
      case MilestoneStatus.certificado:
        return Icons.check_circle;
      case MilestoneStatus.enEjecucion:
        return Icons.play_circle_fill;
      case MilestoneStatus.pendiente:
        return Icons.flag_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final m in allMilestones) m.id: m.nombre};
    final predecessorNames = (allEdges[milestone.id] ?? {})
        .map((id) => names[id] ?? '¿?')
        .toList();
    // CU-24 precondición: se necesitan al menos dos hitos para vincular.
    final canLink =
        isProfesional && allMilestones.length >= 2 && milestone.estado != MilestoneStatus.certificado;
    final canEdit =
        isProfesional && milestone.estado == MilestoneStatus.pendiente;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Icon(_statusIcon(milestone.estado),
            color: _statusColor(milestone.estado)),
        title: Row(
          children: [
            Expanded(
              child: Text(milestone.nombre,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            // CU-29 poscondición: los hitos críticos quedan resaltados.
            if (milestone.esCritico)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CRÍTICA',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sequenceLabel != null)
              Text(
                sequenceLabel!,
                style: const TextStyle(
                    color: AppTheme.accentGold, fontSize: 10),
              ),
            if (milestone.descripcion != null &&
                milestone.descripcion!.trim().isNotEmpty)
              Text(
                milestone.descripcion!,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            Text(
              '${milestone.duracionDias} días · ${milestone.estado.label}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            // Roadmap: rango de fechas y días restantes (CU-29 display).
            // La fecha de fin estimada = inicio del hito + duración, en
            // formato legible DD/MM/AAAA. Los restantes bajan con el tiempo.
            if (scheduleView != null) ...[
              Text(
                '${MilestoneScheduleView.format(scheduleView!.startDate)} → ${MilestoneScheduleView.format(scheduleView!.endDate)}',
                style: const TextStyle(
                    color: AppTheme.lightBlue, fontSize: 12),
              ),
              Text(
                'Fin estimado: ${MilestoneScheduleView.format(scheduleView!.endDate)}',
                style: const TextStyle(
                    color: AppTheme.lightBlue, fontSize: 12),
              ),
              Text(
                'Quedan ${scheduleView!.remainingDays} días',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11),
              ),
            ],
            if (predecessorNames.isNotEmpty)
              Text(
                'Depende de: ${predecessorNames.join(', ')}',
                style: const TextStyle(
                    color: AppTheme.lightBlue, fontSize: 11),
              ),
          ],
        ),
        trailing: (canLink || canEdit || (isProfesional && onAdvance != null))
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canLink)
                    IconButton(
                      tooltip: 'Agregar predecesor',
                      icon: const Icon(Icons.link_outlined,
                          color: AppTheme.lightBlue),
                      onPressed: onDependencies,
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Editar hito',
                      icon: const Icon(Icons.edit_outlined,
                          color: AppTheme.accentGold),
                      onPressed: onEdit,
                    ),
                  // CU-26 paso 1: avanza a la siguiente fase (solo Profesional
                  // y solo si hay fase siguiente; los certificados no avanzan).
                  if (isProfesional && onAdvance != null)
                    IconButton(
                      tooltip: milestone.estado == MilestoneStatus.pendiente
                          ? 'Iniciar hito'
                          : 'Certificar hito',
                      icon: Icon(
                        milestone.estado == MilestoneStatus.pendiente
                            ? Icons.play_arrow_outlined
                            : Icons.check_circle_outline,
                        color: Colors.greenAccent,
                      ),
                      onPressed: onAdvance,
                    ),
                  // CU-27 paso 1: solo hitos Pendiente (sin progreso).
                  if (isProfesional && onDelete != null)
                    IconButton(
                      tooltip: 'Eliminar hito',
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.primaryRed),
                      onPressed: onDelete,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
