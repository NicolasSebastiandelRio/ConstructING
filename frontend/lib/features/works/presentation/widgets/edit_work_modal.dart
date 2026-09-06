import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/work_entity.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_event.dart';
import '../blocs/works_state.dart';
import '../validators/coordinates.dart';

/// CU-17: edita los datos administrativos de una obra en curso.
/// Los campos se precargan con los datos actuales (paso 2); al guardar se
/// validan (CU-16) y se persiste vía PATCH /works/:id (pasos 3-4).
class EditWorkModal extends StatefulWidget {
  final WorkEntity work;

  const EditWorkModal({super.key, required this.work});

  @override
  State<EditWorkModal> createState() => _EditWorkModalState();
}

class _EditWorkModalState extends State<EditWorkModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _direccionController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _propietarioEmailController;
  late final TextEditingController _latitudController;
  late final TextEditingController _longitudController;

  late DateTime _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // CU-17 paso 2: campos editables precargados con los datos actuales.
    _nombreController = TextEditingController(text: widget.work.nombre);
    _direccionController = TextEditingController(text: widget.work.direccion);
    _descripcionController =
        TextEditingController(text: widget.work.descripcion ?? '');
    // Vacío = conservar el propietario actual (CU-14: sólo se re-vincula si
    // se informa un correo).
    _propietarioEmailController = TextEditingController();
    // Vacío = conservar el ancla actual (CU-15).
    _latitudController = TextEditingController();
    _longitudController = TextEditingController();
    _selectedDate =
        DateTime.tryParse(widget.work.fechaInicio) ?? DateTime.now();
  }

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

  Future<void> _submitEdit() async {
    // CU-16: resalta los campos inválidos y detiene el envío.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final workData = {
        'nombre': _nombreController.text.trim(),
        'direccion': _direccionController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'fechaInicio': DateFormat('yyyy-MM-dd').format(_selectedDate),
        // CU-14: sólo se re-vincula si se informa un correo nuevo.
        if (_propietarioEmailController.text.trim().isNotEmpty)
          'propietarioEmail':
              _propietarioEmailController.text.trim().toLowerCase(),
        // CU-15: sólo se actualiza el ancla si se informan coordenadas.
        if (Coordinates.parseOrNull(_latitudController.text) != null)
          'latitud': Coordinates.parseOrNull(_latitudController.text),
        if (Coordinates.parseOrNull(_longitudController.text) != null)
          'longitud': Coordinates.parseOrNull(_longitudController.text),
      };

      if (!mounted) return;
      // El resultado lo informa el BlocListener (CU-17 paso 4).
      context
          .read<WorksBloc>()
          .add(UpdateWorkEvent(id: widget.work.id, workData: workData));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar la obra: ${e.toString()}'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayDate = DateFormat('dd/MM/yyyy').format(_selectedDate);

    return BlocListener<WorksBloc, WorksState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is WorksLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Obra actualizada exitosamente.'),
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
                  'EDITAR OBRA',
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
                    prefixIcon: Icon(Icons.business_outlined,
                        color: AppTheme.accentGold),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'El nombre es obligatorio'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _direccionController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    prefixIcon: Icon(Icons.location_on_outlined,
                        color: AppTheme.accentGold),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'La dirección es obligatoria'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descripcionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    prefixIcon: Icon(Icons.description_outlined,
                        color: AppTheme.accentGold),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _propietarioEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo correo del propietario (opcional)',
                    hintText: 'Vacío = conservar el actual',
                    prefixIcon:
                        Icon(Icons.person_outline, color: AppTheme.accentGold),
                  ),
                  validator: (value) {
                    if (value != null &&
                        value.trim().isNotEmpty &&
                        !value.contains('@')) {
                      return 'Ingrese un correo de propietario válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitudController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Latitud (opcional)',
                          prefixIcon: Icon(Icons.my_location_outlined,
                              color: AppTheme.accentGold),
                        ),
                        validator: Coordinates.validateLatitude,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _longitudController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Longitud (opcional)',
                          prefixIcon: Icon(Icons.my_location_outlined,
                              color: AppTheme.accentGold),
                        ),
                        validator: Coordinates.validateLongitude,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => _selectDate(context),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de Inicio',
                      prefixIcon: Icon(Icons.calendar_today_outlined,
                          color: AppTheme.accentGold),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          displayDate,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            color: AppTheme.accentGold),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitEdit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Guardar Cambios'),
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
