import 'entities/app_notification.dart';

/// Mensajes canónicos del motor de alertas (CU-67/CU-68/CU-69, RF_10).
///
/// Centraliza la redacción para que el disparador (bloc/servicio) no
/// construya textos sueltos y las pruebas puedan aseverar el contenido
/// exacto de cada alerta.
abstract final class NotificationCatalog {
  /// CU-67: actualización de obra disparada al cerrar un hito o al subir una
  /// evidencia. El destinatario es el Propietario.
  static AppNotification avanceDeObra({
    required String id,
    required String propietarioId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    required String causa,
    String? hitoId,
    DateTime? ahora,
  }) =>
      AppNotification(
        id: id,
        usuarioId: propietarioId,
        tipo: NotificationTipo.avance,
        titulo: 'Avance en "$obraNombre"',
        mensaje: 'El profesional responsable registró un avance en el hito '
            '"$hitoNombre" ($causa). Abra la obra para revisar la evidencia.',
        obraId: obraId,
        hitoId: hitoId,
        prioridad: NotificationPrioridad.normal,
        createdAt: ahora ?? DateTime.now(),
      );

  /// CU-68: acta lista para firmar. Alta prioridad (paso 2).
  static AppNotification solicitudDeFirma({
    required String id,
    required String propietarioId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    String? hitoId,
    DateTime? ahora,
  }) =>
      AppNotification(
        id: id,
        usuarioId: propietarioId,
        tipo: NotificationTipo.firma,
        titulo: 'Acta lista para firmar',
        mensaje: 'El hito "$hitoNombre" de la obra "$obraNombre" tiene la '
            'conformidad del profesional y espera su firma para sellar el '
            'acta.',
        obraId: obraId,
        hitoId: hitoId,
        prioridad: NotificationPrioridad.alta,
        createdAt: ahora ?? DateTime.now(),
      );

  /// El Propietario firmó el acta: el Profesional responsable recibe la
  /// confirmación (contraparte de [solicitudDeFirma]). Sin esta alerta el
  /// profesional no tenía NINGUNA notificación en la campana.
  static AppNotification conformidadDelPropietario({
    required String id,
    required String profesionalId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    String? hitoId,
    DateTime? ahora,
  }) =>
      AppNotification(
        id: id,
        usuarioId: profesionalId,
        tipo: NotificationTipo.firma,
        titulo: 'El propietario firmó el acta',
        mensaje: 'La conformidad del hito "$hitoNombre" de la obra '
            '"$obraNombre" ya tiene la firma del propietario. El acta quedó '
            'sellada y la etapa se considera certificada.',
        obraId: obraId,
        hitoId: hitoId,
        prioridad: NotificationPrioridad.alta,
        createdAt: ahora ?? DateTime.now(),
      );

  /// CU-69: desvío temporal de un hito de ruta crítica vencido.
  static AppNotification retrasoDeHitoCritico({
    required String id,
    required String profesionalId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    required String fechaFinEstimada,
    required int diasDeDesvio,
    String? hitoId,
    DateTime? ahora,
  }) =>
      AppNotification(
        id: id,
        usuarioId: profesionalId,
        tipo: NotificationTipo.retraso,
        titulo: 'Alerta de retraso',
        mensaje: 'El hito de ruta crítica "$hitoNombre" de la obra '
            '"$obraNombre" superó su fecha de fin estimada '
            '($fechaFinEstimada) por $diasDeDesvio día(s) sin certificarse.',
        obraId: obraId,
        hitoId: hitoId,
        prioridad: NotificationPrioridad.alta,
        createdAt: ahora ?? DateTime.now(),
      );
}
