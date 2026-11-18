import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/notification_local_data_source.dart';
import '../../data/datasources/notification_remote_data_source.dart';
import '../../data/delay_alert_scheduler.dart';
import '../../domain/entities/app_notification.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// Mensajes exactos de la especificación del Sprint 6.
abstract final class NotificationsMessages {
  /// CU-71 paso 4.
  static const String preferenciasActualizadas = 'Preferencias actualizadas';
}

/// BLoC de la bandeja de notificaciones (CU-70/CU-71/CU-72) y del disparo
/// manual del cron de retrasos (CU-69).
class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final NotificationLocalDataSource dao;
  final NotificationRemoteDataSource? remote;

  /// CU-69: chequeo diario de desvíos temporales. Opcional (tests que sólo
  /// ejercitan la bandeja).
  final DelayAlertScheduler? delayScheduler;

  NotificationsBloc({
    required this.dao,
    this.remote,
    this.delayScheduler,
  }) : super(NotificationsInitial()) {
    on<LoadNotifications>(_onLoad);
    on<LoadNotificationPreferences>(_onLoadPreferences);
    on<MarkNotificationAsRead>(_onMarkAsRead);
    on<UpdateNotificationPreference>(_onUpdatePreference);
    on<RunDelayCheck>(_onRunDelayCheck);
    on<RefreshUnreadBadge>(_onRefreshBadge);
  }

  /// CU-70 pasos 2-4: consulta la bandeja del usuario (descendente) y la
  /// despliega junto con el badge de no leídas y sus preferencias.
  Future<void> _onLoad(
    LoadNotifications event,
    Emitter<NotificationsState> emit,
  ) async {
    emit(NotificationsLoading());
    try {
      final inbox = await _reloadInbox(event.usuarioId);
      emit(NotificationsLoaded(
        inbox: inbox,
        noLeidas: await dao.countUnread(event.usuarioId),
        preferences: await dao.getPreferences(event.usuarioId),
      ));
    } catch (e) {
      emit(NotificationsError(message: _message(e)));
    }
  }

  /// CU-71 paso 1: preferencias vigentes al entrar a la configuración.
  Future<void> _onLoadPreferences(
    LoadNotificationPreferences event,
    Emitter<NotificationsState> emit,
  ) async {
    emit(NotificationsLoading());
    try {
      emit(NotificationsLoaded(
        inbox: await dao.listByUsuario(event.usuarioId),
        noLeidas: await dao.countUnread(event.usuarioId),
        preferences: await dao.getPreferences(event.usuarioId),
      ));
    } catch (e) {
      emit(NotificationsError(message: _message(e)));
    }
  }

  /// CU-72 pasos 2-4: cambia el estado a "leída", desaparece el indicador de
  /// mensaje nuevo y se mantiene el orden del panel.
  Future<void> _onMarkAsRead(
    MarkNotificationAsRead event,
    Emitter<NotificationsState> emit,
  ) async {
    try {
      await dao.markAsRead(event.id);
      // Best-effort: el servidor consolida el estado de lectura.
      await remote?.markAsRead(event.id);
      emit(NotificationsLoaded(
        inbox: await dao.listByUsuario(event.usuarioId),
        noLeidas: await dao.countUnread(event.usuarioId),
        preferences: await dao.getPreferences(event.usuarioId),
      ));
    } catch (e) {
      emit(NotificationsError(message: _message(e)));
    }
  }

  /// CU-71 pasos 2-4: actualiza el booleano "Recibir por correo" y confirma
  /// con el mensaje exacto de la especificación.
  Future<void> _onUpdatePreference(
    UpdateNotificationPreference event,
    Emitter<NotificationsState> emit,
  ) async {
    try {
      final guardada = await dao.savePreferences(NotificationPreferences(
        usuarioId: event.usuarioId,
        recibirPorCorreo: event.recibirPorCorreo,
      ));
      await remote?.savePreferences(guardada);
      emit(NotificationsLoaded(
        inbox: await dao.listByUsuario(event.usuarioId),
        noLeidas: await dao.countUnread(event.usuarioId),
        preferences: guardada,
        message: NotificationsMessages.preferenciasActualizadas,
      ));
    } catch (e) {
      emit(NotificationsError(message: _message(e)));
    }
  }

  /// CU-69: disparo manual del chequeo diario de retrasos.
  Future<void> _onRunDelayCheck(
    RunDelayCheck event,
    Emitter<NotificationsState> emit,
  ) async {
    final scheduler = delayScheduler;
    if (scheduler == null) return;
    var generadas = 0;
    for (final obra in event.obras) {
      generadas += await scheduler.runForObra(
        obraId: obra.obraId,
        obraNombre: obra.obraNombre,
        profesionalId: obra.profesionalId,
      );
    }
    emit(NotificationsLoaded(
      inbox: await dao.listByUsuario(event.usuarioId),
      noLeidas: await dao.countUnread(event.usuarioId),
      preferences: await dao.getPreferences(event.usuarioId),
      message: generadas == 0
          ? 'Sin desvíos temporales nuevos'
          : 'Se generaron $generadas alerta(s) de retraso',
    ));
  }

  /// CU-72 paso 4: sólo el número del badge (campana de la cabecera).
  Future<void> _onRefreshBadge(
    RefreshUnreadBadge event,
    Emitter<NotificationsState> emit,
  ) async {
    try {
      emit(NotificationsBadgeLoaded(
        noLeidas: await dao.countUnread(event.usuarioId),
      ));
    } catch (e) {
      emit(NotificationsError(message: _message(e)));
    }
  }

  /// Bandeja local enriquecida, best-effort, con lo que el servidor ya
  /// conoce (CU-70 paso 2). Las filas locales mandan: nunca se pisa el estado
  /// de lectura ya resuelto en el dispositivo.
  Future<List<AppNotification>> _reloadInbox(String usuarioId) async {
    final locales = await dao.listByUsuario(usuarioId);
    final fuente = remote;
    if (fuente == null) return locales;
    final remotos = await fuente.fetchByUsuario(usuarioId);
    if (remotos == null || remotos.isEmpty) return locales;
    final idsLocales = {for (final n in locales) n.id};
    var agregado = false;
    for (final remoto in remotos) {
      if (idsLocales.contains(remoto.id)) continue;
      await dao.save(remoto);
      agregado = true;
    }
    return agregado ? await dao.listByUsuario(usuarioId) : locales;
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}
