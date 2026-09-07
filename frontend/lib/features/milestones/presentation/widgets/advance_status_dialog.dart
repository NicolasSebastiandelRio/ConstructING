import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/milestone.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// CU-26 paso 1: confirma el avance a la siguiente fase operativa.
/// Al confirmar despacha el avance (pasos 2-4 corren en el bloc); ante error
/// (p. ej. CU-28 denegando) permanece abierto mostrando el mensaje.
class AdvanceStatusDialog extends StatefulWidget {
  final Milestone hito;

  const AdvanceStatusDialog({super.key, required this.hito});

  @override
  State<AdvanceStatusDialog> createState() => _AdvanceStatusDialogState();
}

class _AdvanceStatusDialogState extends State<AdvanceStatusDialog> {
  bool _isLoading = false;

  MilestoneStatus get _target => widget.hito.estado.next!;

  String get _successMessage => _target == MilestoneStatus.enEjecucion
      ? 'Hito en ejecución.'
      : 'Hito certificado.';

  String get _verb => _target == MilestoneStatus.enEjecucion ? 'Iniciar' : 'Certificar';

  void _submit() {
    setState(() => _isLoading = true);
    context.read<MilestonesBloc>().add(
          AdvanceMilestoneStatus(hitoId: widget.hito.id),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MilestonesBloc, MilestonesState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is MilestonesLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text(_successMessage),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is MilestonesError) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(listenerContext).showSnackBar(
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
          '${_verb.toUpperCase()} HITO',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Avanzar "${widget.hito.nombre}" de "${widget.hito.estado.label}" a "${_target.label}"?',
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
