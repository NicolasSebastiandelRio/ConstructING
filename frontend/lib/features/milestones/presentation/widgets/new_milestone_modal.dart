import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/milestone.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// CU-23 pasos 1-3: formulario "Añadir Hito" (nombre, descripción, duración).
/// Valida con CU-16 (paso 2) y confirma solo tras persistir en local.
class NewMilestoneModal extends StatefulWidget {
  final String obraId;

  const NewMilestoneModal({super.key, required this.obraId});

  @override
  State<NewMilestoneModal> createState() => _NewMilestoneModalState();
}

class _NewMilestoneModalState extends State<NewMilestoneModal> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _duracionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _duracionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // CU-23 paso 2 + Alt. CU-16: resalta faltantes y detiene el envío.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    context.read<MilestonesBloc>().add(
          CreateMilestoneRequested(
            obraId: widget.obraId,
            nombre: _nombreController.text.trim(),
            descripcion: _descripcionController.text.trim().isEmpty
                ? null
                : _descripcionController.text.trim(),
            duracionDias: int.parse(_duracionController.text.trim()),
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
            const SnackBar(
              content: Text('Hito registrado en la Hoja de Ruta.'),
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
                  'AÑADIR HITO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nombreController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Hito',
                    hintText: 'Ej: Cimientos',
                    prefixIcon:
                        Icon(Icons.flag_outlined, color: AppTheme.accentGold),
                  ),
                  validator: Milestone.validateNombre,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descripcionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (Opcional)',
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
                      : const Text('Guardar'),
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
