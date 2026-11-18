import '../entities/milestone.dart';

/// Resultado de la validación de progresión (CU-28).
class ProgressionCheck {
  /// `true` si el avance está autorizado (paso 4: confirmación True).
  final bool allowed;

  /// Nombres (o IDs) de los predecesores que bloquean el avance.
  final List<String> blocking;

  const ProgressionCheck({required this.allowed, this.blocking = const []});
}

/// Guard interno de coherencia del cronograma (CU-28, RF_02).
///
/// Invocado por CU-26 antes de avanzar el estado de un hito: autoriza solo
/// si todos sus predecesores están "Certificados" (paso 2). Sin
/// predecesores, siempre autoriza. Ante dato corrupto (arista a un hito
/// inexistente) falla cerrado para preservar la coherencia (poscondición).
class ProgressionGuard {
  /// Evalúa si [hitoId] puede avanzar dado el mapa de hitos y aristas.
  static ProgressionCheck canAdvance({
    required String hitoId,
    required Map<String, Milestone> byId,
    required Map<String, Set<String>> edges,
  }) {
    final blocking = <String>[];
    for (final predecessorId in edges[hitoId] ?? const <String>{}) {
      final predecessor = byId[predecessorId];
      if (predecessor == null) {
        blocking.add(predecessorId);
      } else if (predecessor.estado != MilestoneStatus.certificado) {
        blocking.add(predecessor.nombre);
      }
    }
    return ProgressionCheck(allowed: blocking.isEmpty, blocking: blocking);
  }

  /// Mensaje para informar al usuario la denegatoria (Alt. 2.2).
  static String denialMessage(ProgressionCheck check) =>
      'El hito está bloqueado hasta que se certifiquen: ${check.blocking.join(', ')}.';
}
