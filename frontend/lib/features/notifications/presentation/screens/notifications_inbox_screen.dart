import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/notification_local_data_source.dart';
import '../../data/datasources/notification_remote_data_source.dart';
import '../../data/delay_alert_scheduler.dart';
import '../../domain/entities/app_notification.dart';
import '../bloc/notifications_bloc.dart';
import '../bloc/notifications_event.dart';
import '../bloc/notifications_state.dart';
import 'notification_preferences_screen.dart';

/// CU-70 (RF_10): bandeja de entrada de notificaciones.
///
/// Paso 2: consulta en BD todas las alertas del usuario, ordenadas de forma
/// descendente. Paso 4: renderiza la bandeja. CU-72: tocar una notificación
/// la marca como leída, muestra su contenido y apaga el badge de la campana.
class NotificationsInboxScreen extends StatefulWidget {
  final String usuarioId;

  /// DAO inyectables (tests); en producción se crean sobre la BD local real.
  final NotificationLocalDataSource? notificationDao;
  final NotificationRemoteDataSource? remote;
  final DelayAlertScheduler? delayScheduler;

  const NotificationsInboxScreen({
    super.key,
    required this.usuarioId,
    this.notificationDao,
    this.remote,
    this.delayScheduler,
  });

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  late final NotificationsBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = NotificationsBloc(
      dao: widget.notificationDao ??
          NotificationLocalDataSource(localDatabase: LocalDatabase()),
      remote: widget.remote,
      delayScheduler: widget.delayScheduler,
    )..add(LoadNotifications(usuarioId: widget.usuarioId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  /// CU-72 pasos 1-3: marca leída y despliega el contenido de la alerta.
  Future<void> _openNotification(AppNotification notification) async {
    _bloc.add(MarkNotificationAsRead(
      id: notification.id,
      usuarioId: widget.usuarioId,
    ));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationDetailSheet(notification: notification),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationsBloc>.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text(
            'NOTIFICACIONES',
            style: TextStyle(
                fontFamily: 'Cinzel',
                color: AppTheme.accentGold,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          iconTheme: const IconThemeData(color: AppTheme.accentGold),
          actions: [
            // CU-71 paso 1: acceso a la configuración de alertas del perfil.
            IconButton(
              key: const Key('notification_settings_button'),
              tooltip: 'Configuración de alertas',
              icon: const Icon(Icons.tune, color: AppTheme.accentGold),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NotificationPreferencesScreen(
                    usuarioId: widget.usuarioId,
                    notificationDao: widget.notificationDao,
                    remote: widget.remote,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: BlocConsumer<NotificationsBloc, NotificationsState>(
          listenWhen: (_, current) =>
              current is NotificationsLoaded && current.message != null,
          listener: (context, state) {
            if (state is NotificationsLoaded && state.message != null) {
              // CU-71 paso 4: confirmación exacta de la especificación.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message!),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is NotificationsLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentGold),
              );
            }
            if (state is NotificationsError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.primaryRed)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => context.read<NotificationsBloc>().add(
                            LoadNotifications(usuarioId: widget.usuarioId),
                          ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGold,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }
            if (state is NotificationsLoaded) {
              if (state.inbox.isEmpty) return const _InboxEmptyState();
              return RefreshIndicator(
                color: AppTheme.accentGold,
                onRefresh: () async => context
                    .read<NotificationsBloc>()
                    .add(LoadNotifications(usuarioId: widget.usuarioId)),
                child: ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: state.inbox.length,
                  itemBuilder: (context, index) {
                    final alerta = state.inbox[index];
                    return _NotificationTile(
                      notification: alerta,
                      onTap: () => _openNotification(alerta),
                    );
                  },
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Bandeja sin alertas.
class _InboxEmptyState extends StatelessWidget {
  const _InboxEmptyState();

  static const String message = 'No tiene notificaciones registradas';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none,
                color: AppTheme.accentGold.withValues(alpha: 0.6), size: 42),
            const SizedBox(height: 12),
            const Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de la bandeja (CU-70 paso 4).
class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  IconData get _icon {
    switch (notification.tipo) {
      case NotificationTipo.firma:
        return Icons.draw_outlined;
      case NotificationTipo.retraso:
        return Icons.warning_amber_outlined;
      case NotificationTipo.avance:
        return Icons.trending_up;
    }
  }

  String get _fecha {
    final f = notification.createdAt.toLocal();
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/${f.year} '
        '${f.hour.toString().padLeft(2, '0')}:'
        '${f.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final alta = notification.prioridad == NotificationPrioridad.alta;
    // Material propio: el ListTile pinta su fondo/splash sobre el Material
    // más cercano (un DecoratedBox intermedio los ocultaría y Flutter lo
    // reporta como assertion en debug).
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: notification.leida
            ? AppTheme.darkSurface
            : AppTheme.accentGold.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: (alta ? AppTheme.primaryRed : AppTheme.accentGold)
                .withValues(alpha: notification.leida ? 0.25 : 0.7),
          ),
        ),
        child: ListTile(
        onTap: onTap,
        leading: Icon(
          _icon,
          color: alta ? AppTheme.primaryRed : AppTheme.accentGold,
        ),
        title: Text(
          notification.titulo,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight:
                notification.leida ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.mensaje,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              '${notification.tipo.label} · $_fecha',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
        // CU-72 paso 4: el punto de "mensaje nuevo" de la fila.
        trailing: notification.leida
            ? null
            : Container(
                key: Key('notification_unread_${notification.id}'),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryRed,
                  shape: BoxShape.circle,
                ),
              ),
        ),
      ),
    );
  }
}

/// CU-72 paso 3: contenido de la alerta seleccionada.
class _NotificationDetailSheet extends StatelessWidget {
  final AppNotification notification;

  const _NotificationDetailSheet({required this.notification});

  @override
  Widget build(BuildContext context) {
    final f = notification.createdAt.toLocal();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.titulo,
            style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            notification.mensaje,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            '${notification.tipo.label} · '
            '${f.day.toString().padLeft(2, '0')}/'
            '${f.month.toString().padLeft(2, '0')}/${f.year} '
            '${f.hour.toString().padLeft(2, '0')}:'
            '${f.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (notification.obraId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Obra: ${notification.obraId}',
              style: const TextStyle(color: AppTheme.lightBlue, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
