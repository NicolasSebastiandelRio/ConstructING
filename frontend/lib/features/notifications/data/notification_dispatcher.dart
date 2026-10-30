import 'package:uuid/uuid.dart';

import '../domain/entities/app_notification.dart';
import '../domain/notification_catalog.dart';
import 'datasources/notification_local_data_source.dart';
import 'datasources/notification_remote_data_source.dart';

/// CU-67/CU-68 (RF_10): punto ÚNICO de disparo del motor de alertas.
///
/// Los módulos de negocio (hitos, evidencia, certificación) no redactan ni
/// persisten notificaciones: emiten la señal a este despachador, que aplica
/// las preferencias del receptor (CU-71), guarda la alerta en la bandeja
/// local (CU-70) y la envía al servidor de forma best-effort.
class NotificationDispatcher {
  NotificationDispatcher({
    required NotificationLocalDataSource local,
    NotificationRemoteDataSource? remote,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _local = local,
        _remote = remote,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? (() => DateTime.now());

  final NotificationLocalDataSource _local;
  final NotificationRemoteDataSource? _remote;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// CU-67: actualización de obra al Propietario (cierre de hito o subida de
  /// evidencia).
  Future<AppNotification> notifyAvanceDeObra({
    required String propietarioId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    required String causa,
    String? hitoId,
  }) =>
      _dispatch(NotificationCatalog.avanceDeObra(
        id: _uuid.v4(),
        propietarioId: propietarioId,
        obraId: obraId,
        obraNombre: obraNombre,
        hitoNombre: hitoNombre,
        causa: causa,
        hitoId: hitoId,
        ahora: _clock(),
      ));

  /// CU-68: acta lista para firmar (alta prioridad).
  Future<AppNotification> notifySolicitudDeFirma({
    required String propietarioId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    String? hitoId,
  }) =>
      _dispatch(NotificationCatalog.solicitudDeFirma(
        id: _uuid.v4(),
        propietarioId: propietarioId,
        obraId: obraId,
        obraNombre: obraNombre,
        hitoNombre: hitoNombre,
        hitoId: hitoId,
        ahora: _clock(),
      ));

  /// Notifica al Profesional responsable que el Propietario firmó el acta
  /// (contraparte de [notifySolicitudDeFirma]).
  Future<AppNotification> notifyConformidadDelPropietario({
    required String profesionalId,
    required String obraId,
    required String obraNombre,
    required String hitoNombre,
    String? hitoId,
  }) =>
      _dispatch(NotificationCatalog.conformidadDelPropietario(
        id: _uuid.v4(),
        profesionalId: profesionalId,
        obraId: obraId,
        obraNombre: obraNombre,
        hitoNombre: hitoNombre,
        hitoId: hitoId,
        ahora: _clock(),
      ));

  /// Persiste la alerta en la bandeja local y, si hay red, la despacha al
  /// servidor (CU-67 paso 4). El canal de correo lo decide el servidor según
  /// la preferencia del usuario (CU-71 paso 4).
  ///
  /// Público para que el Cron Job del CU-69 publique una alerta ya redactada.
  Future<AppNotification> publish(AppNotification notification) async {
    await _local.save(notification);
    // Best-effort: la bandeja local ya tiene la alerta.
    await _remote?.send(notification);
    return notification;
  }

  Future<AppNotification> _dispatch(AppNotification notification) =>
      publish(notification);
}
