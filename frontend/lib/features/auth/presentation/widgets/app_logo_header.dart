import 'package:flutter/material.dart';

class AppLogoHeader extends StatelessWidget {
  final double logoHeight;

  // Aumentamos el tamaño base de 85.0 a 140.0
  const AppLogoHeader({
    super.key,
    this.logoHeight = 140.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: logoHeight,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        Text(
          'ConstructING',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 34,
                letterSpacing: 2.0,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'REGISTRANDO IMPERIOS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
            letterSpacing: 3.5,
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}