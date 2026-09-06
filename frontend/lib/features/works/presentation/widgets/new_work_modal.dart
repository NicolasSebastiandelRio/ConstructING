import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart'; // Asegúrate de tener intl en pubspec.yaml
import '../../../../core/theme/app_theme.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_event.dart';
import '../blocs/works_state.dart';
import '../validators/coordinates.dart';

class NewWorkModal extends StatefulWidget {
  const NewWorkModal({super.key});

  @override
  State<NewWorkModal> createState() => _NewWorkModalState();
}

class _NewWorkModalState extends State<NewWorkModal> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _direccionController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _propietarioEmailController = TextEditingController();
  final _latitudController = TextEditingController();
  final _longitudController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _direccionController.dispose();
    _descripcionController.dispose();
    _propietarioEmailController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    super.dispose();
  }

  /// UX: Selector de fecha nativo adaptado al formato argentino (DD/MM/YYYY)
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accentGold,
              onPrimary: Colors.black,
              surface: AppTheme.darkSurface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitWork() async {
    // CU-16 paso 1-2: la validación del formulario resalta los campos
    // obligatorios faltantes y detiene el envío (flujo alterno 2.1/2.2).
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Formato para base de datos (YYYY-MM-DD) requerido por NestJS/PostgreSQL
      final String formattedDateForApi = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final workData = {
        'nombre': _nombreController.text.trim(),
        'direccion': _direccionController.text.trim(),
        if (_descripcionController.text.isNotEmpty) 'descripcion': _descripcionController.text.trim(),
        'fechaInicio': formattedDateForApi,
        'propietarioEmail': _propietarioEmailController.text.trim().toLowerCase(),
        // CU-15 (flujo alterno 2.2): ancla geográfica manual opcional.
        if (Coordinates.parseOrNull(_latitudController.text) != null)
          'latitud': Coordinates.parseOrNull(_latitudController.text),
        if (Coordinates.parseOrNull(_longitudController.text) != null)
          'longitud': Coordinates.parseOrNull(_longitudController.text),
      };

      if (!mounted) return;
      // El resultado (éxito o error de validación del backend) lo informa el
      // BlocListener: no se confirma nada hasta que la BD responde (CU-13.5).
      context.read<WorksBloc>().add(CreateWorkEvent(workData: workData));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar la obra: ${e.toString()}'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Formato visual para el usuario (DD/MM/YYYY - Estándar Argentino)
    final String displayDate = DateFormat('dd/MM/yyyy').format(_selectedDate);

    // CU-16 (flujo alterno 2.2) + CU-13 paso 5: el éxito sólo se informa
    // cuando la BD confirma la persistencia; ante un error del backend el
    // modal permanece abierto mostrando el mensaje.
    return BlocListener<WorksBloc, WorksState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is WorksLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Obra registrada exitosamente en el sistema.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is WorksError) {
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

              // Campo obligatorio exigido por CU-14 (Vincular Propietario por Correo)
              TextFormField(
                controller: _propietarioEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico del Propietario',
                  hintText: 'propietario@ejemplo.com',
                  prefixIcon: Icon(Icons.person_outline, color: AppTheme.accentGold),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty || !value.contains('@')) {
                    return 'Ingrese un correo de propietario válido';
                  }
                  return null;
                },
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

              // CU-15 (flujo alterno 2.2): coordenadas manuales opcionales
              // cuando no hay geocodificación automática disponible.
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitudController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Latitud (Opcional)',
                        hintText: 'Ej: -34.6037',
                        prefixIcon: Icon(Icons.my_location_outlined, color: AppTheme.accentGold),
                      ),
                      validator: Coordinates.validateLatitude,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _longitudController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Longitud (Opcional)',
                        hintText: 'Ej: -58.3816',
                        prefixIcon: Icon(Icons.my_location_outlined, color: AppTheme.accentGold),
                      ),
                      validator: Coordinates.validateLongitude,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // UX Mejorada: Selector de Fecha táctil (Evita tipeo manual de guiones)
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha de Inicio',
                    prefixIcon: Icon(Icons.calendar_today_outlined, color: AppTheme.accentGold),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        displayDate,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const Icon(Icons.arrow_drop_down, color: AppTheme.accentGold),
                    ],
                  ),
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
    ));
  }
}