import 'package:equatable/equatable.dart';

import '../../../evidence/domain/entities/evidence.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../domain/entities/signature_stroke.dart';
import '../../domain/stroke_metadata.dart';

abstract class CertificationState extends Equatable {
  const CertificationState();

  /// CU-52/CU-57: ¿habilita este estado el lienzo de firma manuscrita?
  ///
  /// Solo los estados que representan una conformidad PENDIENTE de firma lo
  /// habilitan. Un estado bloqueado (el rol ya firmó, falta la conformidad
  /// técnica previa o el hito ya está sellado) lo deshabilita: es el guard
  /// único que consumen el bloc (trazo, limpieza y confirmación) y la
  /// pantalla del CU-51 (render del lienzo).
  bool get signaturePadEnabled => false;

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

  /// CU-52 paso 4: el lienzo está habilitado — hay una conformidad pendiente
  /// de capturar (lienzo limpio tras un rechazo incluido, CU-53).
  @override
  bool get signaturePadEnabled => true;

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

  /// CU-57: este rol ya firmó — el lienzo queda BLOQUEADO (no firma dos
  /// veces, ni siquiera repinta sobre el estado de espera).
  @override
  bool get signaturePadEnabled => false;

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

  /// CU-57/CU-59: el acta quedó sellada y el hito congelado — no admite
  /// nuevas firmas (el lienzo no vuelve a habilitarse).
  @override
  bool get signaturePadEnabled => false;

  @override
  List<Object?> get props =>
      [...super.props, conformidadAt, metadatos, actaPath, hashSha256];
}

/// CU-57 (precondición colegiada): el hito todavía NO tiene la conformidad
/// técnica del profesional responsable, así que no existe borrador de
/// conformidad que refrendar. El Propietario no puede forzar el cierre: el
/// lienzo queda inhabilitado y se le indica que espere la certificación del
/// profesional.
class CertificationFirstSignatureRequired extends CertificationSummaryReady {
  final String message;

  const CertificationFirstSignatureRequired({
    required this.message,
    required super.hito,
    required super.evidencias,
  }) : super(strokes: const []);

  /// CU-57: sin la primera firma del profesional no hay nada que firmar.
  @override
  bool get signaturePadEnabled => false;

  @override
  List<Object?> get props => [...super.props, message];
}

/// CU-57/CU-59: el hito ya tiene su acta sellada (ambas firmas capturadas) y
/// sus registros congelados. Reabrir el resumen no habilita una nueva firma:
/// los datos certificados quedaron grabados en piedra.
class CertificationAlreadySealed extends CertificationSummaryReady {
  final String message;

  const CertificationAlreadySealed({
    required this.message,
    required super.hito,
    required super.evidencias,
  }) : super(strokes: const []);

  @override
  bool get signaturePadEnabled => false;

  @override
  List<Object?> get props => [...super.props, message];
}

class CertificationError extends CertificationState {
  final String message;

  const CertificationError({required this.message});

  @override
  List<Object?> get props => [message];
}
