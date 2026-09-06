import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../../../core/network/dio_client.dart';
import '../validators/password_policy.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  final String initialRole;

  const RegisterScreen({super.key, required this.initialRole});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _docNumberController = TextEditingController();
  final _matriculaController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  String _docType = 'DNI';
  bool _isLoading = false;
  String _errorMessage = '';

  bool get _isProfesional => widget.initialRole == 'Profesional';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _docNumberController.dispose();
    _matriculaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final dataSource = AuthRemoteDataSourceImpl(dioClient: DioClient());
      await dataSource.register(
        nombre: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        rol: widget.initialRole,
        matricula: _isProfesional ? _matriculaController.text.trim() : null,
        // CU-22: reclamo opcional de la invitación (une al nuevo usuario a su obra).
        invitationCode: _invitationCodeController.text.trim().isEmpty
            ? null
            : _invitationCodeController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cuenta creada con éxito. Inicie sesión para continuar.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(initialRole: widget.initialRole),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.accentGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isProfesional ? 'REGISTRO DE PROFESIONAL' : 'REGISTRO DE PROPIETARIO',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isProfesional
                        ? 'Gestiona tus propiedades en desarrollo'
                        : 'Accede al progreso de tus construcciones',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 28),

                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryRed),
                      ),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                      prefixIcon: Icon(Icons.person_outline, color: AppTheme.accentGold),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Ingrese su nombre completo' : null,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico',
                      prefixIcon: Icon(Icons.email_outlined, color: AppTheme.accentGold),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty || !value.contains('@')) {
                        return 'Ingrese un correo electrónico válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                          value: _docType,
                          dropdownColor: AppTheme.darkSurface,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(value: 'DNI', child: Text('DNI')),
                            DropdownMenuItem(value: 'PAS', child: Text('PAS')),
                            DropdownMenuItem(value: 'CI', child: Text('CI')),
                          ],
                          onChanged: (val) => setState(() => _docType = val ?? 'DNI'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _docNumberController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Número de Documento',
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? 'Campo obligatorio' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (_isProfesional) ...[
                    TextFormField(
                      controller: _matriculaController,
                      decoration: const InputDecoration(
                        labelText: 'Matrícula Profesional',
                        hintText: 'Ej: ING-12345 / MMO-67890 / ARQ-54321',
                        prefixIcon: Icon(Icons.badge_outlined, color: AppTheme.accentGold),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'La matrícula es obligatoria' : null,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Campo obligatorio para Ingeniero / MMO / Arquitecto',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock_outline, color: AppTheme.accentGold),
                    ),
                    validator: (value) {
                      // CU-06 Flujo Alterno 3.2 (RNF_S_01): política estricta de
                      // complejidad de contraseña desde el frontend.
                      if (value == null || !PasswordPolicy.isValid(value)) {
                        return PasswordPolicy.errorMessage;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar Contraseña',
                      prefixIcon: Icon(Icons.lock_reset_outlined, color: AppTheme.accentGold),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // CU-22: código de invitación opcional para unirse a una obra.
                  TextFormField(
                    controller: _invitationCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código de Invitación (Opcional)',
                      hintText: 'Ej: CNG-7K2P9Q',
                      prefixIcon: Icon(Icons.mail_outline, color: AppTheme.accentGold),
                    ),
                    validator: (value) {
                      if (value != null &&
                          value.trim().isNotEmpty &&
                          !RegExp(r'^CNG-[A-Z0-9]{6}$', caseSensitive: false)
                              .hasMatch(value.trim())) {
                        return 'Formato de código inválido (Ej: CNG-7K2P9Q)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Registrarse'),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginScreen(initialRole: widget.initialRole),
                        ),
                      );
                    },
                    child: const Text(
                      '¿Ya tienes una cuenta? INICIA SESIÓN',
                      style: TextStyle(color: AppTheme.lightBlue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}