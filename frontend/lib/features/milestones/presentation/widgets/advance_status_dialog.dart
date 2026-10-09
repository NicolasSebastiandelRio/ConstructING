import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../certification/presentation/screens/certification_summary_screen.dart';
import '../../domain/entities/milestone.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// Confirmación del paso 1 del avance/cierre:
/// - CU-26: hito Pendiente → "Iniciar" (en Ejecución).
/// - CU-50 (RF_05): hito En Ejecución → "Certificar Etapa": solicita el
///   cierre formal; el bloc valida la evidencia (paso 2) y emite
///   MilestoneCertificationReady para conectar con CU-51 (doble firma).
/// Ante error de certificación se retorna al detalle del hito (Alt. 2.2);
/// ante error de inicio el diálogo permanece abierto con el mensaje.
class AdvanceStatusDialog extends StatefulWidget {
  final Milestone hito;

  /// Datos maestros y rol del firmante para el acta (CU-51/CU-56).
  final String? obraNombre;
  final String? propietarioNombre;
  final String? firmante;

  /// CU-57: se invoca cuando el flujo de certificación abierto desde este
  /// diálogo se cierra (para recargar la Hoja de Ruta con el estado
  /// colegiado vigente).
  final VoidCallback? onFlowFinished;

  const AdvanceStatusDialog({
    super.key,
    required this.hito,
    this.obraNombre,
    this.propietarioNombre,
    this.firmante,
    this.onFlowFinished,
  });

  @override
  State<AdvanceStatusDialog> createState() => _AdvanceStatusDialogState();
}

class _AdvanceStatusDialogState extends State<AdvanceStatusDialog> {
  bool _isLoading = false;

  MilestoneStatus get _target => widget.hito.estado.next!;

  bool get _isCertification => _target == MilestoneStatus.certificado;

  String get _verb => _isCertification ? 'Certificar Etapa' : 'Iniciar';

  String get _prompt => _isCertification
      ? '¿Solicitar el cierre formal de la etapa "${widget.hito.nombre}"? '
          'El sistema validará que el hito tenga evidencia visual cargada.'
      : '¿Avanzar "${widget.hito.nombre}" de "${widget.hito.estado.label}" a "${_target.label}"?';

  void _submit() {
    setState(() => _isLoading = true);
    context.read<MilestonesBloc>().add(
          _isCertification
              ? RequestMilestoneCertification(hitoId: widget.hito.id)
              : AdvanceMilestoneStatus(hitoId: widget.hito.id),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MilestonesBloc, MilestonesState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is MilestoneCertificationReady) {
          // CU-50 paso 4: ejecuta el CU-51 (Visualizar Resumen) para
          // iniciar el proceso de doble firma (RF_05).
          setState(() => _isLoading = false);
          Navigator.pop(listenerContext);
          Navigator.of(listenerContext)
              .push(
                MaterialPageRoute(
                  builder: (_) => CertificationSummaryScreen(
                    hitoId: state.hitoId,
                    obraNombre: widget.obraNombre,
                    propietarioNombre: widget.propietarioNombre,
                    firmante: widget.firmante,
                  ),
                ),
              )
              // CU-57: al volver del flujo colegiado se recarga la Hoja de
              // Ruta (primera firma registrada → "esperando al propietario").
              .then((_) => widget.onFlowFinished?.call());
        } else if (state is MilestoneCertificationBlocked) {
          // Alt. 2.2 (CU-50): bloqueado → retorna al detalle del hito.
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.primaryRed,
            ),
          );
        } else if (state is MilestonesLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Hito en ejecución.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is MilestonesError) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          // Fallo real (p. ej. BD) en la solicitud de certificación:
          // retorna al detalle del hito (Alt. 2.2).
          if (_isCertification) Navigator.pop(listenerContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.primaryRed,
            ),
          );
        }
      },
      child: AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Text(
          _isCertification ? 'CERTIFICAR ETAPA' : 'INICIAR HITO',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          _prompt,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : Text(_verb,
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
