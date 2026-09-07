import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/notify/milestone_owner_notifier.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// CU-25 pasos 1-3: formulario "Editar Hito" con los datos actuales
/// precargados (paso 2). Según la spec solo se editan descripción y
/// duración; el nombre se muestra de solo lectura.
/// Al guardar se recalculan las fechas dependientes (bloc/CU-29) y se
/// notifica al propietario que uno de sus hitos fue modificado.
class EditMilestoneModal extends StatefulWidget {
  final Milestone milestone;

  /// Datos del propietario para el aviso posterior (no se persisten).
  final String? propietarioEmail;
  final String? propietarioNombre;

  const EditMilestoneModal({
    super.key,
    required this.milestone,
    this.propietarioEmail,
    this.propietarioNombre,
  });

  @override
  State<EditMilestoneModal> createState() => _EditMilestoneModalState();
}

class _EditMilestoneModalState extends State<EditMilestoneModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descripcionController;
  late final TextEditingController _duracionController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descripcionController =
        TextEditingController(text: widget.milestone.descripcion ?? '');
    _duracionController =
        TextEditingController(text: widget.milestone.duracionDias.toString());
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _duracionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    context.read<MilestonesBloc>().add(
          UpdateMilestoneRequested(
            id: widget.milestone.id,
            descripcion: _descripcionController.text.trim(),
            duracionDias: int.parse(_duracionController.text.trim()),
            propietarioEmail: widget.propietarioEmail,
            propietarioNombre: widget.propietarioNombre,
          ),
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
              content: Text(
                MilestoneOwnerNotice.editedMessage(
                  propietarioEmail: widget.propietarioEmail,
                  propietarioNombre: widget.propietarioNombre,
                ),
              ),
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
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'EDITAR HITO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.milestone.nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descripcionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción Técnica',
                    hintText: 'Detalle técnico de la etapa...',
                    prefixIcon: Icon(Icons.description_outlined,
                        color: AppTheme.accentGold),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _duracionController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duración Estimada (días)',
                    hintText: 'Ej: 10',
                    prefixIcon: Icon(Icons.timer_outlined,
                        color: AppTheme.accentGold),
                  ),
                  validator: Milestone.validateDuracion,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Actualizar'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
