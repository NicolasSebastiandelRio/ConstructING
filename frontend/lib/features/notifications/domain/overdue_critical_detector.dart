import 'package:equatable/equatable.dart';

import '../../milestones/domain/cpm/critical_path.dart';
import '../../milestones/domain/entities/milestone.dart';
import '../../milestones/domain/schedule/milestone_schedule.dart';

/// CU-69 (RF_10, RF_02): hito de ruta crítica vencido.
class OverdueCriticalMilestone extends Equatable {
  final Milestone hito;

  /// Fecha de fin estimada del hito (inicio temprano + duración, CU-29).
  final DateTime fechaFinEstimada;

  /// Días completos transcurridos desde la fecha de fin estimada.
  final int diasDeDesvio;

  const OverdueCriticalMilestone({
    required this.hito,
    required this.fechaFinEstimada,
    required this.diasDeDesvio,
  });

  @override
  List<Object?> get props => [hito, fechaFinEstimada, diasDeDesvio];
}

/// CU-69 paso 1 (RF_10, RF_02): detección diaria de desvíos temporales.
///
/// Regla de la especificación: un hito marcado como **Ruta Crítica** que ya
/// superó su **fecha de fin estimada** y NO está completado/certificado.
///
/// Es una función pura sobre el cronograma (CU-29) para poder probarse sin
/// reloj ni base de datos: recibe `today` explícito.
abstract final class OverdueCriticalDetector {
  static List<OverdueCriticalMilestone> detect({
    required List<Milestone> hitos,
    required Map<String, CpmNodeSchedule> schedules,
    required DateTime obraStart,
    required DateTime today,
  }) {
    final hoy = DateTime(today.year, today.month, today.day);
    final vencidos = <OverdueCriticalMilestone>[];
    for (final hito in hitos) {
      // Solo hitos de ruta crítica y todavía abiertos.
      if (!hito.esCritico) continue;
      if (hito.estado == MilestoneStatus.certificado) continue;

      final schedule = schedules[hito.id];
      if (schedule == null) continue;

      final view = MilestoneScheduleView.resolve(
        obraStart: obraStart,
        earlyStart: schedule.earlyStart,
        earlyFinish: schedule.earlyFinish,
        durationDays: hito.duracionDias,
        isCritical: schedule.isCritical,
      );
      final fin = DateTime(
        view.endDate.year,
        view.endDate.month,
        view.endDate.day,
      );
      if (!hoy.isAfter(fin)) continue;

      vencidos.add(OverdueCriticalMilestone(
        hito: hito,
        fechaFinEstimada: fin,
        diasDeDesvio: hoy.difference(fin).inDays,
      ));
    }
    return vencidos;
  }
}
