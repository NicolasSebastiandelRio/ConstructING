import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/notification_local_data_source.dart';
import '../../data/datasources/notification_remote_data_source.dart';
import '../bloc/notifications_bloc.dart';
import '../bloc/notifications_event.dart';
import '../bloc/notifications_state.dart';

/// CU-71 (RF_10): configuración de la preferencia de alerta del usuario.
///
/// Paso 1: el usuario ingresa a la configuración de su perfil y activa o
/// desactiva "Recibir por correo". Paso 2: se actualiza el valor booleano en
/// la tabla de preferencias. Paso 4: se muestra el mensaje exacto
/// "Preferencias actualizadas" y la regla se aplica a los futuros mensajes.
class NotificationPreferencesScreen extends StatefulWidget {
  final String usuarioId;

  /// DAO inyectables (tests); en producción se crean sobre la BD local real.
  final NotificationLocalDataSource? notificationDao;
  final NotificationRemoteDataSource? remote;

  const NotificationPreferencesScreen({
    super.key,
    required this.usuarioId,
    this.notificationDao,
    this.remote,
  });

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  late final NotificationsBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = NotificationsBloc(
      dao: widget.notificationDao ??
          NotificationLocalDataSource(localDatabase: LocalDatabase()),
      remote: widget.remote,
    )..add(LoadNotificationPreferences(usuarioId: widget.usuarioId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
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
            'CONFIGURACIÓN DE ALERTAS',
            style: TextStyle(
                fontFamily: 'Cinzel',
                color: AppTheme.accentGold,
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
          iconTheme: const IconThemeData(color: AppTheme.accentGold),
        ),
        body: BlocConsumer<NotificationsBloc, NotificationsState>(
          listenWhen: (_, current) =>
              current is NotificationsLoaded && current.message != null,
          listener: (context, state) {
            if (state is NotificationsLoaded && state.message != null) {
              // CU-71 paso 4: mensaje exacto de la especificación.
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
                child: Text(state.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.primaryRed)),
              );
            }
            if (state is! NotificationsLoaded) {
              return const SizedBox.shrink();
            }
            final prefs = state.preferences;
            return ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Material propio: SwitchListTile pinta su fondo/splash sobre
                // el Material más cercano (un DecoratedBox intermedio los
                // ocultaría y Flutter lo reporta como assertion en debug).
                Material(
                  color: AppTheme.darkSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: AppTheme.accentGold.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CANAL DE ALERTAS',
                          style: TextStyle(
                              fontFamily: 'Cinzel',
                              color: AppTheme.accentGold,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Las alertas siempre quedan en su bandeja. Esta '
                          'preferencia decide además el envío por correo.',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          key: const Key('preference_recibir_por_correo'),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppTheme.accentGold,
                          title: const Text(
                            'Recibir por correo',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            prefs.recibirPorCorreo ? 'Activado' : 'Desactivado',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                          value: prefs.recibirPorCorreo,
                          onChanged: (valor) =>
                              context.read<NotificationsBloc>().add(
                                    UpdateNotificationPreference(
                                      usuarioId: widget.usuarioId,
                                      recibirPorCorreo: valor,
                                    ),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
