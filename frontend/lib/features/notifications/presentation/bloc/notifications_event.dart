import 'package:equatable/equatable.dart';

import '../../domain/entities/app_notification.dart';

abstract class NotificationsEvent extends Equatable {
  const NotificationsEvent();

  @override
  List<Object?> get props => [];
}

/// CU-70 paso 1/2: el usuario abre la bandeja (campana); se consultan todas
/// las alertas dirigidas a su `ID de usuario`.
class LoadNotifications extends NotificationsEvent {
  final String usuarioId;

  const LoadNotifications({required this.usuarioId});

  @override
  List<Object?> get props => [usuarioId];
}

/// CU-72 paso 1: el usuario toca una notificación de la lista para verla.
class MarkNotificationAsRead extends NotificationsEvent {
  final String id;
  final String usuarioId;

  const MarkNotificationAsRead({required this.id, required this.usuarioId});

  @override
  List<Object?> get props => [id, usuarioId];
}

/// CU-71 paso 1: el usuario ingresa a la configuración de su perfil.
class LoadNotificationPreferences extends NotificationsEvent {
  final String usuarioId;

  const LoadNotificationPreferences({required this.usuarioId});

  @override
  List<Object?> get props => [usuarioId];
}

/// CU-71 paso 1/2: el usuario activa o desactiva "Recibir por correo".
class UpdateNotificationPreference extends NotificationsEvent {
  final String usuarioId;
  final bool recibirPorCorreo;

  const UpdateNotificationPreference({
    required this.usuarioId,
    required this.recibirPorCorreo,
  });

  @override
  List<Object?> get props => [usuarioId, recibirPorCorreo];
}

/// CU-69: disparo manual del chequeo diario de retrasos (QA y botón
/// "Revisar retrasos" del Dashboard).
class RunDelayCheck extends NotificationsEvent {
  final String usuarioId;
  final List<({String obraId, String obraNombre, String profesionalId})> obras;

  const RunDelayCheck({required this.usuarioId, required this.obras});

  @override
  List<Object?> get props => [usuarioId, obras];
}

/// Estado del badge de la campana sin abrir la bandeja (CU-72 paso 4).
class RefreshUnreadBadge extends NotificationsEvent {
  final String usuarioId;

  const RefreshUnreadBadge({required this.usuarioId});

  @override
  List<Object?> get props => [usuarioId];
}

/// Tipo de alerta usado por `AppNotification` (reexportado por comodidad de
/// los consumidores del bloc).
typedef NotificationKind = NotificationTipo;
