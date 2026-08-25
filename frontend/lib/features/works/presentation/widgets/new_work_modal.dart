import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/works_bloc.dart';
import '../bloc/works_event.dart';

class NewWorkModal extends StatefulWidget {
  const NewWorkModal({super.key});

  @override
  State<NewWorkModal> createState() => _NewWorkModalState();
}

class _NewWorkModalState extends State<NewWorkModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _descController = TextEditingController();
  final _dateController = TextEditingController(text: '2026-08-24');
  final _propEmailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descController.dispose();
    _dateController.dispose();
    _propEmailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    context.read<WorksBloc>().add(
          CreateWorkEvent(
            nombre: _nameController.text.trim(),
            direccion: _addressController.text.trim(),
            descripcion: _descController.text.trim(),
            fechaInicio: _dateController.text.trim(),
            propietarioEmail: _propEmailController.text.trim().isNotEmpty
                ? _propEmailController.text.trim()
                : null,
          ),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'NUEVO PROYECTO',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      color: AppTheme.accentGold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre del Proyecto *'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Dirección *'),
                validator: (val) =>
                    val == null || val.isEmpty ? 'La dirección es obligatoria' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _propEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email del Propietario (Opcional)',
                  hintText: 'ejemplo@correo.com',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción del Proyecto'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: 'Fecha de Inicio (YYYY-MM-DD) *',
                  prefixIcon: Icon(Icons.calendar_today, color: AppTheme.accentGold),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'La fecha es obligatoria' : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Crear Proyecto'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}