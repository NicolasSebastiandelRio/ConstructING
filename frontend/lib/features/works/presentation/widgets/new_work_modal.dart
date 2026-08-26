import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/theme/app_theme.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_event.dart';

class NewWorkModal extends StatefulWidget {
  const NewWorkModal({super.key});

  @override
  State<NewWorkModal> createState() => _NewWorkModalState();
}

class _NewWorkModalState extends State<NewWorkModal> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _direccionController = TextEditingController();
  final _descripcionController = TextEditingController(); // Opcional según UI
  final _fechaInicioController = TextEditingController();

  bool _isLoading = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void dispose() {
    _nombreController.dispose();
    _direccionController.dispose();
    _descripcionController.dispose();
    _fechaInicioController.dispose();
    super.dispose();
  }

  Future<void> _submitWork() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Recuperamos el ID del usuario autenticado actual desde el almacenamiento seguro (CU-05)
      // O asignamos un propietario por defecto para pruebas del MVP
      final propietarioId = await _secureStorage.read(key: 'user_id') ?? 'd3b07384-d113-4ec6-a563-95d80d07e60d';

      final workData = {
        'nombre': _nombreController.text.trim(),
        'direccion': _direccionController.text.trim(),
        if (_descripcionController.text.isNotEmpty) 'descripcion': _descripcionController.text.trim(),
        'fechaInicio': _fechaInicioController.text.trim().isEmpty 
            ? DateTime.now().toIso8601String().split('T')[0] 
            : _fechaInicioController.text.trim(),
        'propietarioId': propietarioId,
      };

      // Despachamos el evento de creación al BLoC (CU-13)
      if (!mounted) return;
      context.read<WorksBloc>().add(CreateWorkEvent(workData: workData));

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obra registrada exitosamente en el sistema.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar la obra: ${e.toString()}'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                'NUEVO PROYECTO',
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
                  labelText: 'Nombre del Proyecto',
                  hintText: 'Ej: Edificio Residencial Central',
                  prefixIcon: Icon(Icons.business_outlined, color: AppTheme.accentGold),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _direccionController,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  hintText: 'Ej: Av. Libertador 1234, CABA',
                  prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.accentGold),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'La dirección es obligatoria' : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _descripcionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción (Opcional)',
                  hintText: 'Detalles generales de la obra...',
                  prefixIcon: Icon(Icons.description_outlined, color: AppTheme.accentGold),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _fechaInicioController,
                decoration: const InputDecoration(
                  labelText: 'Fecha de Inicio (YYYY-MM-DD)',
                  hintText: '2026-03-01',
                  prefixIcon: Icon(Icons.calendar_today_outlined, color: AppTheme.accentGold),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _submitWork,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear Proyecto'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}