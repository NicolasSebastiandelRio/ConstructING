import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/notifications_bloc.dart';
import '../bloc/notifications_event.dart';
import '../bloc/notifications_state.dart';

/// CU-70 paso 1 / CU-72 paso 4: campana de la cabecera con el indicador de
/// "mensaje nuevo".
///
/// Consulta el número de alertas NO leídas del usuario y pinta el punto/​badge
/// sobre el ícono; al tocarla abre la bandeja de entrada (CU-70).
class NotificationBell extends StatefulWidget {
  final String usuarioId;

  /// Navegación a la bandeja (CU-70). Si es null, sólo refresca el badge.
  final VoidCallback? onPressed;

  const NotificationBell({
    super.key,
    required this.usuarioId,
    this.onPressed,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    // CU-72 paso 4: el badge se calcula al montar la cabecera.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<NotificationsBloc>()
          .add(RefreshUnreadBadge(usuarioId: widget.usuarioId));
    });
  }

  int _noLeidas(NotificationsState state) {
    if (state is NotificationsLoaded) return state.noLeidas;
    if (state is NotificationsBadgeLoaded) return state.noLeidas;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        final noLeidas = _noLeidas(state);
        return IconButton(
          key: const Key('notification_bell'),
          tooltip: 'Notificaciones',
          onPressed: () {
            if (widget.onPressed != null) {
              widget.onPressed!.call();
            } else {
              context
                  .read<NotificationsBloc>()
                  .add(LoadNotifications(usuarioId: widget.usuarioId));
            }
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined,
                  color: AppTheme.accentGold),
              // CU-72 paso 4: indicador de "mensaje nuevo".
              if (noLeidas > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    key: const Key('notification_badge'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    child: Text(
                      noLeidas > 99 ? '99+' : '$noLeidas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
