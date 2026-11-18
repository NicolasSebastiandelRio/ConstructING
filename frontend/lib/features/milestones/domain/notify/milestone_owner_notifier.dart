import 'package:flutter/foundation.dart';

import '../entities/milestone.dart';

/// Notificación al propietario ante la edición de un hito.
///
/// La Hoja de Ruta es local-first (offline): no hay push al otro dispositivo
/// todavía. Hasta que el centro de notificaciones (Mockup 6, otro sprint)
/// exista, la notificación es una traza estructurada + mensaje visible en la
/// UI que confirma al editor que el propietario fue avisado. El contenido es
/// el mismo que persistirá cuando el módulo real llegue, igual que
/// [MilestoneAudit] hace con CU-60.
abstract class MilestoneOwnerNotifier {
  /// Avisa que [milestone] fue modificado. No debe lanzar: el guardado local
  /// ya ocurrió y la notificación es best-effort (offline-first).
  Future<void> notifyEdited({
    required Milestone milestone,
    String? propietarioEmail,
    String? propietarioNombre,
  });
}

/// Implementación por defecto: traza en consola (transitoria hasta el módulo
/// de notificaciones). Nunca lanza.
class ConsoleMilestoneOwnerNotifier implements MilestoneOwnerNotifier {
  const ConsoleMilestoneOwnerNotifier();

  @override
  Future<void> notifyEdited({
    required Milestone milestone,
    String? propietarioEmail,
    String? propietarioNombre,
  }) async {
    final owner = _ownerLabel(propietarioEmail, propietarioNombre);
    debugPrint(
      '[NOTIFY-OWNER] obra=${milestone.obraId} hito=${milestone.id} '
      '"${milestone.nombre}" modificado. Se notifica al propietario: $owner. '
      'Uno de sus hitos fue modificado.',
    );
  }

  static String _ownerLabel(String? email, String? nombre) {
    final e = email?.trim() ?? '';
    final n = nombre?.trim() ?? '';
    if (e.isNotEmpty && n.isNotEmpty) return '$n <$e>';
    if (e.isNotEmpty) return e;
    if (n.isNotEmpty) return n;
    return 'sin propietario vinculado';
  }
}

/// Mensaje visible para el editor tras guardar (reutilizado por el modal).
class MilestoneOwnerNotice {
  /// Texto de confirmación: si hay propietario vinculado se aclara que fue
  /// notificado; si no, el mensaje clásico (compat CU-25).
  static String editedMessage({String? propietarioEmail, String? propietarioNombre}) {
    final hasOwner = (propietarioEmail?.trim().isNotEmpty == true) ||
        (propietarioNombre?.trim().isNotEmpty == true);
    if (hasOwner) {
      return 'Hito actualizado. Se notificó al propietario.';
    }
    return 'Hito actualizado.';
  }
}
