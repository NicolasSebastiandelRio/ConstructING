import '../entities/milestone.dart';

/// Resultado de la validación de acceso al flujo de certificación (CU-50).
class CertificationCheck {
  /// `true` si el hito está autorizado a entrar en flujo de certificación.
  final bool allowed;

  /// Mensaje de bloqueo (Alt. 2.2 / precondición) cuando [allowed] es false.
  final String? reason;

  const CertificationCheck.allowed() : allowed = true, reason = null;

  const CertificationCheck.denied(this.reason) : allowed = false;
}

/// Guard de cierre formal de etapa (CU-50, RF_05: Certificación con Firma
/// Digital).
///
/// Evaluado por CU-50 "Solicitar Certificación de Hito": exige hito "En
/// Ejecución" (precondición) y al menos una (1) evidencia multimedia
/// cargada (paso 2). Falla cerrado: sin datos o sin evidencia no autoriza.
class CertificationGuard {
  /// Mensaje exacto de la especificación para el Alt. 2.1/2.2.
  static const String sinEvidenciaMessage =
      'No se puede certificar: debe cargar evidencia visual del avance';

  static CertificationCheck evaluate({
    required Milestone hito,
    required int evidenciasCount,
  }) {
    if (hito.estado != MilestoneStatus.enEjecucion) {
      return const CertificationCheck.denied(
          'Solo se puede certificar un hito en estado "En Ejecución".');
    }
    if (evidenciasCount <= 0) {
      return const CertificationCheck.denied(sinEvidenciaMessage);
    }
    return const CertificationCheck.allowed();
  }
}
