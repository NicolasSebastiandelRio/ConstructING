import 'package:flutter/foundation.dart';

import '../entities/milestone.dart';

/// Traza de auditoría transitoria (CU-26 paso 4).
///
/// El Audit Log persistente e inalterable es CU-60 (Sprint 5, PT-07). Hasta
/// entonces, cada cambio de estado deja una línea estructurada en consola,
/// con el mismo contenido que persistirá (hito, obra, anterior → nuevo).
class MilestoneAudit {
  static void logStatusChange({
    required Milestone before,
    required MilestoneStatus after,
  }) {
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] hito=${before.id} obra=${before.obraId} '
      'estado: ${before.estado.label} → ${after.label}',
    );
  }
}
