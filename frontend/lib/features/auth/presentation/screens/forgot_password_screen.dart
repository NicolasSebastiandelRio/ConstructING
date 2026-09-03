import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/dio_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  
  bool _codeSent = false;
  bool _isLoading = false;
  final DioClient _dioClient = DioClient();

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  /// CU-03 Paso 1: Solicitar código de recuperación al backend
  Future<void> _requestRecoveryCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _dioClient.dio.post('/auth/forgot-password', data: {
        'email': _emailController.text.trim().toLowerCase(),
      });

      setState(() {
        _codeSent = true;
        _isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se ha enviado un código temporal a su correo electrónico.'),
          backgroundColor: Colors.green,
        ),
      );
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      final message = e.response?.data['message'] ?? 'Error de conexión con el servidor.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.primaryRed),
      );
    }
  }

  /// CU-03 Paso 2: Enviar código temporal y nueva contraseña para blanqueo
  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _dioClient.dio.post('/auth/reset-password', data: {
        'email': _emailController.text.trim().toLowerCase(),
        'code': _codeController.text.trim(),
        'newPassword': _newPasswordController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada con éxito. Inicie sesión.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      final message = e.response?.data['message'] ?? 'Código inválido o expirado.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.primaryRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RECUPERAR ACCESO',
          style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.accentGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SISTEMA DE RECUPERACIÓN DE CLAVE',
                  style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _codeSent
                      ? 'Ingrese el código de 6 dígitos recibido por correo y su nueva contraseña.'
                      : 'Ingrese el correo electrónico vinculado a su cuenta para recibir un código de validación temporal.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Campo de Correo Electrónico
                TextFormField(
                  controller: _emailController,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    hintText: 'correo@ejemplo.com',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.accentGold),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty || !value.contains('@')) {
                      return 'Ingrese un correo electrónico válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Campos dinámicos si el código ya fue enviado
                if (_codeSent) ...[
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Código Temporal (6 dígitos)',
                      hintText: '123456',
                      prefixIcon: Icon(Icons.lock_clock_outlined, color: AppTheme.accentGold),
                    ),
                    validator: (value) => value == null || !RegExp(r'^\d{6}4').hasMatch(value.trim())
                      ? 'Ingrese el código completo'
                      : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nueva Contraseña',
                      hintText: 'Mínimo 8 caracteres',
                      prefixIcon: Icon(Icons.lock_outline, color: AppTheme.accentGold),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'La contraseña debe tener al menos 8 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Restablecer Contraseña'),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _requestRecoveryCode,
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Enviar Código de Recuperación'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}