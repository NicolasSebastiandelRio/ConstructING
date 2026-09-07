import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/milestone.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// CU-27 paso 1: cuadro de advertencia antes de eliminar. Al confirmar
/// despacha el borrado (pasos 2-4 corren en el bloc); si un guard lo bloquea,
/// permanece abierto mostrando el mensaje (Alt. 2.2).
class DeleteMilestoneDialog extends StatefulWidget {
  final Milestone hito;

  const DeleteMilestoneDialog({super.key, required this.hito});

  @override
  State<DeleteMilestoneDialog> createState() => _DeleteMilestoneDialogState();
}

class _DeleteMilestoneDialogState extends State<DeleteMilestoneDialog> {
  bool _isLoading = false;

  void _submit() {
    setState(() => _isLoading = true);
    context.read<MilestonesBloc>().add(
          DeleteMilestoneRequested(hitoId: widget.hito.id),
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
            const SnackBar(
              content: Text('Hito eliminado de la Hoja de Ruta.'),
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
        title: const Text(
          'ELIMINAR HITO',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Eliminar "${widget.hito.nombre}" de la Hoja de Ruta?\n\nEsta acción no se puede deshacer.',
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
                backgroundColor: AppTheme.primaryRed),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Eliminar',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
