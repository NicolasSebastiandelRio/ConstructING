import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/geo/closeness_validator.dart';

/// Etiqueta roja permanente sobre la imagen/video de una evidencia cuya
/// ubicación no coincide con el ancla de la obra (CU-35 soft-fail, Sprint 4).
///
/// Se muestra en la previsualización de la captura y en las tarjetas de la
/// galería; el texto es exactamente el definido en
/// [ClosenessValidator.mismatchLabel].
class EvidenceLocationMismatchBanner extends StatelessWidget {
  const EvidenceLocationMismatchBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: AppTheme.primaryRed.withValues(alpha: 0.92),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: const Row(
          children: [
            Icon(Icons.location_off_outlined,
                color: Colors.white, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                ClosenessValidator.mismatchLabel,
                maxLines: 2,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
