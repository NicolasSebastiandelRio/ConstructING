import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart'; // <--- Importación de la pantalla de recuperación (CU-03)
import '../../../works/presentation/screens/works_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  final String initialRole;

  const LoginScreen({super.key, required this.initialRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    // Despacha el evento de login hacia el AuthBloc (CU-01)[cite: 3]
    context.read<AuthBloc>().add(
          LoginButtonPressed(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            role: widget.initialRole,
          ),
        );
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
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthAuthenticated) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '¡Bienvenido, ${state.user.nombre}!',
                        style: const TextStyle(fontFamily: 'Cinzel'),
                      ),
                      backgroundColor: Colors.green.shade800,
                    ),
                  );

                  // Navegación real hacia el Dashboard de Obras (Mockup 5 / 11) según RBAC[cite: 4, 7]
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WorksDashboardScreen(
                        userRole: state.user.rol,
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                final errorMessage = state is AuthError ? state.message : '';

                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'INICIAR SESIÓN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          color: AppTheme.accentGold,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.initialRole,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cinzel',
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (errorMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryRed.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryRed),
                          ),
                          child: Text(
                            errorMessage,
                            style: const TextStyle(
                              fontFamily: 'Cinzel',
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo Electrónico',
                          prefixIcon: Icon(Icons.email_outlined, color: AppTheme.accentGold),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty || !value.contains('@')) {
                            return 'Por favor ingrese un correo válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: Icon(Icons.lock_outline, color: AppTheme.accentGold),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'La contraseña debe tener al menos 6 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: isLoading ? null : _handleLogin,
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Iniciar Sesión'),
                      ),
                      const SizedBox(height: 12),

                      // Botón para invocar el flujo de Recuperación de Contraseña (CU-03)[cite: 3]
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            color: AppTheme.accentGold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RegisterScreen(initialRole: widget.initialRole),
                            ),
                          );
                        },
                        child: const Text(
                          '¿No tienes una cuenta? REGÍSTRATE',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            color: AppTheme.lightBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}