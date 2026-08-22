import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo Institucional Coliseo Transparente
                Image.asset(
                  'assets/images/logo.png',
                  height: 300,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                const Text(
                  'ConstructING',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'REGISTRANDO IMPERIOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 3.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 48),

                // Sección Propietario (Mockup 1)
                _buildRoleSection(
                  context,
                  title: '¿ERES UN PROPIETARIO?',
                  subtitle: 'Accede al progreso de tus construcciones',
                  onLoginPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(initialRole: 'Propietario'),
                      ),
                    );
                  },
                  onRegisterPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(initialRole: 'Propietario'),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
                const Divider(color: Colors.white24, thickness: 1),
                const SizedBox(height: 24),

                // Sección Profesional (Mockup 1)
                _buildRoleSection(
                  context,
                  title: '¿ERES UN PROFESIONAL RESPONSABLE?',
                  subtitle: 'Accede a la gestión de tus propiedades en desarrollo',
                  onLoginPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(initialRole: 'Profesional'),
                      ),
                    );
                  },
                  onRegisterPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(initialRole: 'Profesional'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onLoginPressed,
    required VoidCallback onRegisterPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Cinzel',
            color: AppTheme.accentGold,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Cinzel',
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onLoginPressed,
          child: const Text('Iniciar Sesión'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onRegisterPressed,
          child: const Text(
            '¿No tienes una cuenta? REGÍSTRATE',
            style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.lightBlue,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}