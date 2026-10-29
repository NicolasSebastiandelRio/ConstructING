import 'package:equatable/equatable.dart';

import '../../domain/entities/app_notification.dart';

abstract class NotificationsState extends Equatable {
  const NotificationsState();

  @override
  List<Object?> get props => [];
}

class NotificationsInitial extends NotificationsState {}

class NotificationsLoading extends NotificationsState {}

/// CU-70 paso 4: bandeja renderizada (descendente) + badge de no leídas
/// (CU-72) + preferencias vigentes (CU-71).
class NotificationsLoaded extends NotificationsState {
  final List<AppNotification> inbox;

  /// CU-72 paso 4: alimenta el indicador de "mensaje nuevo" de la campana.
  final int noLeidas;

  final NotificationPreferences preferences;

  /// CU-71 paso 4: mensaje exacto de confirmación a mostrar
  /// ("Preferencias actualizadas"). Null cuando no hay nada que informar.
  final String? message;

  const NotificationsLoaded({
    required this.inbox,
    required this.noLeidas,
    required this.preferences,
    this.message,
  });

  NotificationsLoaded copyWith({
    List<AppNotification>? inbox,
    int? noLeidas,
    NotificationPreferences? preferences,
    String? message,
  }) =>
      NotificationsLoaded(
        inbox: inbox ?? this.inbox,
        noLeidas: noLeidas ?? this.noLeidas,
        preferences: preferences ?? this.preferences,
        message: message,
      );

  /// Vista sin el mensaje efímero (tras mostrarlo una vez).
  NotificationsLoaded clearMessage() => NotificationsLoaded(
        inbox: inbox,
        noLeidas: noLeidas,
        preferences: preferences,
      );

  @override
  List<Object?> get props => [inbox, noLeidas, preferences, message];
}

class NotificationsError extends NotificationsState {
  final String message;

  const NotificationsError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// CU-72 paso 4 / CU-69: estado liviano solo para el badge de la campana y el
/// resultado del chequeo de retrasos (no carga la bandeja completa).
class NotificationsBadgeLoaded extends NotificationsState {
  final int noLeidas;

  /// Cuántas alertas nuevas generó el último chequeo de retrasos (CU-69).
  final int? retrasosGenerados;

  const NotificationsBadgeLoaded({required this.noLeidas, this.retrasosGenerados});

  @override
  List<Object?> get props => [noLeidas, retrasosGenerados];
}
