import 'package:equatable/equatable.dart';

import '../../../evidence/domain/entities/evidence.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../domain/entities/signature_stroke.dart';
import '../../domain/stroke_metadata.dart';

abstract class CertificationState extends Equatable {
  const CertificationState();

  @override
  List<Object?> get props => [];
}

class CertificationInitial extends CertificationState {}

class CertificationLoading extends CertificationState {}

/// CU-51 paso 2/4: resumen consolidado del hito (fechas, multimedia y
/// notas) con el lienzo habilitado para ejecutar el CU-52 (Registrar
/// Firma). Los trazos en curso se reflejan para el repintado del lienzo.
class CertificationSummaryReady extends CertificationState {
  final Milestone hito;
  final List<Evidence> evidencias;
  final List<SignatureStroke> strokes;

  const CertificationSummaryReady({
    required this.hito,
    this.evidencias = const [],
    this.strokes = const [],
  });

  CertificationSummaryReady copyWith({List<SignatureStroke>? strokes}) =>
      CertificationSummaryReady(
        hito: hito,
        evidencias: evidencias,
        strokes: strokes ?? this.strokes,
      );

  @override
  List<Object?> get props => [hito, evidencias, strokes];
}

/// CU-57 (doble firma): la PRIMERA firma ya fue registrada (persistida) y
/// este rol no puede firmar dos veces — el acta espera la conformidad de la
/// OTRA parte. El lienzo queda bloqueado (sin doble firma del mismo rol).
class CertificationAwaitingOtherParty extends CertificationSummaryReady {
  final String message;

  const CertificationAwaitingOtherParty({
    required this.message,
    required super.hito,
    required super.evidencias,
  }) : super(strokes: const []);

  @override
  List<Object?> get props => [...super.props, message];
}

/// CU-52 Alt. 2.1/2.2: trazo inferior a la longitud mínima permitida. El
/// lienzo queda limpio (CU-53 ejecutado), la confirmación bloqueada y se
/// pide reintentar. Extiende SummaryReady para conservar el resumen.
class CertificationSignatureRejected extends CertificationSummaryReady {
  final String message;

  const CertificationSignatureRejected({
    required this.message,
    required super.hito,
    required super.evidencias,
  }) : super(strokes: const []);

  @override
  List<Object?> get props => [...super.props, message];
}

/// CU-52 paso 2 / CU-57 (doble firma): la primera firma fue validada y
/// capturada; el lienzo se limpió de nuevo (CU-53) para que la otra parte
/// otorgue su conformidad. Al confirmar el segundo trazo, el acta se
/// compila colegiada (CU-56), se sella (CU-59) y se congelan los registros.
class CertificationSecondSignaturePending extends CertificationSummaryReady {
  /// Rol que firmó primero ("Profesional" o "Propietario").
  final String primerFirmante;

  final List<SignatureStroke> trazosPrimeraFirma;
  final StrokeMetadata metadatosPrimeraFirma;
  final DateTime fechaPrimeraConformidad;

  /// Mensaje de advertencia para la UI (p. ej. rechazo del trazo de la
  /// segunda parte por longitud mínima, Alt. CU-52 2.1/2.2).
  final String? message;

  const CertificationSecondSignaturePending({
    required this.primerFirmante,
    required this.trazosPrimeraFirma,
    required this.metadatosPrimeraFirma,
    required this.fechaPrimeraConformidad,
    required super.hito,
    required super.evidencias,
    this.message,
    List<SignatureStroke>? strokes,
  }) : super(strokes: strokes ?? const []);

  /// Conserva la identidad de la etapa pendiente al acumular trazos del
  /// lienzo (el buffer de la segunda parte convive con la primera firma).
  @override
  CertificationSecondSignaturePending copyWith({
    List<SignatureStroke>? strokes,
  }) =>
      CertificationSecondSignaturePending(
        primerFirmante: primerFirmante,
        trazosPrimeraFirma: trazosPrimeraFirma,
        metadatosPrimeraFirma: metadatosPrimeraFirma,
        fechaPrimeraConformidad: fechaPrimeraConformidad,
        hito: hito,
        evidencias: evidencias,
        message: message,
        strokes: strokes ?? this.strokes,
      );

  @override
  List<Object?> get props => [
        ...super.props,
        primerFirmante,
        trazosPrimeraFirma,
        metadatosPrimeraFirma,
        fechaPrimeraConformidad,
        message,
      ];
}

/// CU-52 paso 2: trazo validado y conformidad técnica capturada; el acta
/// quedó generada (CU-55 Metadatos + CU-56 PDF) en el [actaPath] del caché
/// local (accesible por el CU-54) y sellada criptográficamente (CU-59:
/// hash SHA-256 inmutable en la tabla de certificaciones). Extiende
/// SummaryReady para conservar el resumen y la firma.
class CertificationSignatureCaptured extends CertificationSummaryReady {
  final DateTime conformidadAt;
  final StrokeMetadata metadatos;
  final String? actaPath;

  /// Sello SHA-256 (hex, 64) del documento binario consolidado (CU-59).
  final String hashSha256;

  const CertificationSignatureCaptured({
    required this.conformidadAt,
    required this.metadatos,
    required super.hito,
    required super.evidencias,
    required super.strokes,
    required this.hashSha256,
    this.actaPath,
  });

  @override
  List<Object?> get props =>
      [...super.props, conformidadAt, metadatos, actaPath, hashSha256];
}

class CertificationError extends CertificationState {
  final String message;

  const CertificationError({required this.message});

  @override
  List<Object?> get props => [message];
}
