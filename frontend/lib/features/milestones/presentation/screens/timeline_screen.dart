import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../data/datasources/milestone_local_data_source.dart';
import '../../domain/cpm/critical_path.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/schedule/milestone_schedule.dart';
import '../blocs/timeline_bloc.dart';
import '../blocs/timeline_event.dart';
import '../blocs/timeline_state.dart';
import '../widgets/milestones_section.dart';
import 'milestone_detail_screen.dart';

/// Línea de Tiempo de la obra (CU-64, RF_02).
///
/// CU-64 paso 4: grafica el avance del proyecto como una **línea de tiempo
/// vertical** — riel con nodos numerados y tarjeta por hito — con nombre,
/// estado, rango de fechas (DD/MM/AAAA) y días restantes. El orden es
/// cronológico por inicio temprano (paso 2, resuelto por [TimelineBloc]).
/// Alto contraste sobre [AppTheme.darkBackground] (RNF_U_03).
///
/// CU-64 Alt. 2.1/2.2: sin hitos registrados la pantalla muestra el mensaje
/// [emptyStateMessage] en lugar de un riel vacío.
///
/// CU-65 paso 1: cada nodo es tocable y abre el Detalle Técnico del hito
/// ([MilestoneDetailScreen]) con su metadata, notas y evidencias.
class TimelineScreen extends StatelessWidget {
  final String obraId;
  final String obraNombre;

  /// Inicio de la obra ('yyyy-MM-dd' o 'DD/MM/AAAA') que ancla la línea de
  /// tiempo a fechas concretas. Null ⇒ se muestran solo duraciones relativas.
  final String? obraFechaInicio;

  /// DAO inyectable (tests); en producción se crea sobre la BD local real.
  final MilestoneLocalDataSource? dataSource;

  /// DAO de evidencias para el Detalle Técnico (CU-65). Se propaga al abrir
  /// el hito; null ⇒ el detalle usa la BD local real (producción).
  final EvidenceLocalDataSource? evidenceDao;

  /// Rol del usuario en sesión (profesional / propietario). Se conserva para
  /// que el wiring de navegación lo propague; la Línea de Tiempo (CU-64) es
  /// de solo lectura para ambos roles.
  final String? userRole;

  /// CU-64: `true` cuando la pantalla se embebe como pestaña "Avance" dentro
  /// del panel de la obra (sin `AppBar` propia, la provee el detalle).
  final bool embedded;

  const TimelineScreen({
    super.key,
    required this.obraId,
    required this.obraNombre,
    this.obraFechaInicio,
    this.dataSource,
    this.evidenceDao,
    this.userRole,
    this.embedded = false,
  });

  /// CU-64 Alt. 2.1/2.2: mensaje exacto de la especificación cuando la obra
  /// todavía no tiene hitos registrados.
  static const String emptyStateMessage =
      'Aún no se han registrado avances en este proyecto';

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TimelineBloc>(
      create: (_) => TimelineBloc(
        dataSource: dataSource ??
            MilestoneLocalDataSource(localDatabase: LocalDatabase()),
      )..add(LoadTimeline(obraId: obraId)),
      child: Scaffold(
        backgroundColor: AppTheme.darkBackground,
        appBar: embedded
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                title: Text(
                  'LÍNEA DE TIEMPO · $obraNombre',
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                iconTheme: const IconThemeData(color: AppTheme.accentGold),
              ),
        body: BlocBuilder<TimelineBloc, TimelineState>(
          builder: (context, state) {
            if (state is TimelineLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentGold),
              );
            }
            if (state is TimelineError) {
              return _errorView(context, state.message);
            }
            if (state is TimelineLoaded) {
              if (state.hitos.isEmpty) {
                return _emptyView();
              }
              return _timelineView(context, state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// CU-64 Alt. 2.1/2.2: sin hitos no hay línea de tiempo que graficar.
  Widget _emptyView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_outlined, color: Colors.white24, size: 68),
            SizedBox(height: 12),
            Text(
              emptyStateMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.primaryRed),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => context
                  .read<TimelineBloc>()
                  .add(LoadTimeline(obraId: obraId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CU-64 paso 4: riel vertical con los nodos del proyecto ya ordenados.
  Widget _timelineView(BuildContext context, TimelineLoaded state) {
    final obraStart = MilestonesSection.parseObraStart(obraFechaInicio);
    final total = state.hitos.length;
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _TimelineHeader(state: state, obraStart: obraStart),
        const SizedBox(height: 12),
        for (var i = 0; i < total; i++)
          _TimelineStep(
            position: i + 1,
            isFirst: i == 0,
            isLast: i == total - 1,
            child: _TimelineNode(
              milestone: state.hitos[i],
              sequenceLabel: 'HITO ${i + 1} DE $total',
              scheduleView: _scheduleViewOf(
                state.hitos[i],
                state.schedules,
                obraStart,
              ),
              // CU-65 paso 1: el nodo abre el Detalle Técnico del hito.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MilestoneDetailScreen(
                    hito: state.hitos[i],
                    evidenceDao: evidenceDao,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Resuelve la vista de cronograma (fechas + días restantes) del hito, o
  /// null si la obra no tiene ancla de inicio o el grafo quedó circular.
  MilestoneScheduleView? _scheduleViewOf(
    Milestone hito,
    Map<String, CpmNodeSchedule> schedules,
    DateTime? obraStart,
  ) {
    final schedule = schedules[hito.id];
    if (obraStart == null || schedule == null) return null;
    return MilestoneScheduleView.resolve(
      obraStart: obraStart,
      earlyStart: schedule.earlyStart,
      earlyFinish: schedule.earlyFinish,
      durationDays: hito.duracionDias,
      isCritical: schedule.isCritical,
    );
  }
}

/// Cabecera de la Línea de Tiempo: ancla las fechas y resume el progreso
/// (X de N certificados) para leer el avance de un vistazo (CU-64 paso 4).
class _TimelineHeader extends StatelessWidget {
  final TimelineLoaded state;
  final DateTime? obraStart;

  const _TimelineHeader({required this.state, required this.obraStart});

  @override
  Widget build(BuildContext context) {
    final total = state.hitos.length;
    final done = state.hitos
        .where((h) => h.estado == MilestoneStatus.certificado)
        .length;
    var endText = 'Fin estimado: sin cronograma';
    final anchor = obraStart;
    if (anchor != null && state.schedules.isNotEmpty) {
      var duration = 0;
      for (final schedule in state.schedules.values) {
        if (schedule.earlyFinish > duration) duration = schedule.earlyFinish;
      }
      final end = DateTime(anchor.year, anchor.month, anchor.day)
          .add(Duration(days: duration));
      endText = 'Fin estimado: ${MilestoneScheduleView.format(end)}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: AppTheme.accentGold, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  anchor != null
                      ? 'Inicio: ${MilestoneScheduleView.format(anchor)}'
                      : 'Inicio: sin fecha de proyecto',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Barra de progreso: hitos certificados sobre el total (RNF_U_03).
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$endText · $done de $total certificados',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Paso del riel vertical: nodo numerado con conectores superior e inferior
/// (mismo patrón visual que la Hoja de Ruta) y el hito a la derecha.
class _TimelineStep extends StatelessWidget {
  final int position;
  final bool isFirst;
  final bool isLast;
  final Widget child;

  const _TimelineStep({
    required this.position,
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
                // Conector superior (el primero inicia la línea de tiempo).
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
                // Conector inferior (el último cierra la línea de tiempo).
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
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8, top: 2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nodo de la Línea de Tiempo (CU-64 paso 4): tarjeta tocable del hito con
/// nombre, estado, rango de fechas y días restantes.
class _TimelineNode extends StatelessWidget {
  final Milestone milestone;

  /// Etiqueta de secuencia ("HITO 1 DE 3").
  final String sequenceLabel;

  /// Fechas y días restantes (CU-29 display); null si no hay ancla o cálculo.
  final MilestoneScheduleView? scheduleView;

  /// CU-65 paso 1: abre el Detalle Técnico del hito.
  final VoidCallback onTap;

  const _TimelineNode({
    required this.milestone,
    required this.sequenceLabel,
    required this.scheduleView,
    required this.onTap,
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
    final schedule = scheduleView;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: milestone.esCritico
              ? AppTheme.primaryRed.withValues(alpha: 0.7)
              : AppTheme.accentGold.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(milestone.estado),
                      color: _statusColor(milestone.estado)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      milestone.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // CU-29 poscondición: los hitos críticos quedan resaltados.
                  if (milestone.esCritico)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'CRÍTICA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sequenceLabel,
                style: const TextStyle(
                    color: AppTheme.accentGold, fontSize: 10),
              ),
              if (milestone.descripcion != null &&
                  milestone.descripcion!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    milestone.descripcion!,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${milestone.duracionDias} días · ${milestone.estado.label}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              if (schedule != null) ...[
                Text(
                  '${MilestoneScheduleView.format(schedule.startDate)} → '
                  '${MilestoneScheduleView.format(schedule.endDate)}',
                  style:
                      const TextStyle(color: AppTheme.lightBlue, fontSize: 12),
                ),
                Text(
                  'Quedan ${schedule.remainingDays} días',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
              const SizedBox(height: 4),
              // CU-65 paso 1: señal visual de que el nodo es tocable.
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Ver detalle técnico',
                    style: TextStyle(color: AppTheme.accentGold, fontSize: 11),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.accentGold),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
