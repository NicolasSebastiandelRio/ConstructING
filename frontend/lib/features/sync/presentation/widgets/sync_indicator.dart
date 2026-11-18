import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/sync_status_cubit.dart';

/// CU-48: indicador global de sincronización en la barra superior.
///
/// - Nube tildada: todo sincronizado (en reposo).
/// - Nube con flecha: sincronizando (paso 2).
/// - Nube con alerta: registros pendientes a la espera de red.
///
/// Al tocarlo despliega el panel con el detalle exacto (paso 4: p. ej.
/// "3 evidencias pendientes de subida") y el botón "Sincronizar Ahora"
/// (CU-49) para forzar la subida manual.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  /// Cubit global si existe; null en entornos sin el proveedor (tests).
  static SyncStatusCubit? maybeOf(BuildContext context) {
    try {
      return context.read<SyncStatusCubit>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = maybeOf(context);
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<SyncStatusCubit, SyncStatusState>(
      builder: (context, state) {
        final IconData icon;
        final Color color;
        if (state.syncing) {
          icon = Icons.cloud_upload_outlined; // nube con flecha
          color = AppTheme.lightBlue;
        } else if (state.pendientes > 0) {
          icon = Icons.cloud_upload_outlined;
          color = Colors.orangeAccent;
        } else {
          icon = Icons.cloud_done_outlined;
          color = Colors.greenAccent;
        }
        return IconButton(
          tooltip: state.detalle,
          icon: Icon(icon, color: color),
          onPressed: () => _openPanel(context),
        );
      },
    );
  }

  /// CU-48 pasos 3-4: panel de detalle de la cola de sincronización.
  void _openPanel(BuildContext context) {
    final cubit = context.read<SyncStatusCubit>();
    cubit.refresh();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BlocProvider<SyncStatusCubit>.value(
        value: cubit,
        child: const _SyncPanel(),
      ),
    );
  }
}

class _SyncPanel extends StatelessWidget {
  const _SyncPanel();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SyncStatusCubit, SyncStatusState>(
      listener: (context, state) {
        final message = state.ultimoMensaje;
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor:
                  state.syncing ? AppTheme.lightBlue : Colors.green.shade800,
            ),
          );
        }
      },
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ESTADO DE SINCRONIZACIÓN',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.syncing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      state.pendientes > 0
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_done_outlined,
                      color: state.pendientes > 0
                          ? Colors.orangeAccent
                          : Colors.greenAccent,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.detalle,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.ultimoMensaje != null)
                Text(
                  state.ultimoMensaje!,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              const SizedBox(height: 20),
              // CU-49: control manual sobre la subida de evidencia.
              ElevatedButton.icon(
                onPressed: state.syncing
                    ? null
                    : () => context.read<SyncStatusCubit>().syncNow(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGold),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar Ahora',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
