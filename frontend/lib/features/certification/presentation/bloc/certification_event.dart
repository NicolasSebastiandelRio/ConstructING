import 'package:equatable/equatable.dart';

import '../../domain/entities/signature_stroke.dart';

abstract class CertificationEvent extends Equatable {
  const CertificationEvent();

  @override
  List<Object?> get props => [];
}

/// CU-51 paso 1: el usuario accede a la pantalla de pre-certificación; el
/// bloc consulta en BD los registros asociados al hito (paso 2).
class LoadCertificationSummary extends CertificationEvent {
  final String hitoId;

  const LoadCertificationSummary({required this.hitoId});

  @override
  List<Object?> get props => [hitoId];
}

/// CU-52 paso 1: el usuario finalizó un trazo sobre el lienzo; se acumula
/// para la validación de la confirmación.
class SignatureStrokeCommitted extends CertificationEvent {
  final List<SignaturePoint> points;

  const SignatureStrokeCommitted({required this.points});

  @override
  List<Object?> get props => [points];
}

/// CU-53 paso 1: el usuario presiona "Limpiar Pantalla" (o el sistema lo
/// exige ante un trazo inválido) y borra el buffer del lienzo.
class ClearSignaturePad extends CertificationEvent {
  const ClearSignaturePad();
}

/// CU-52 paso 1: el usuario presiona "Confirmar"; el sistema valida el
/// trazo (paso 2) y captura la conformidad o pide reintentar (Alt. 2.2).
class SignatureConfirmationRequested extends CertificationEvent {
  const SignatureConfirmationRequested();
}
