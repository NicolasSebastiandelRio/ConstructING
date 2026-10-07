import 'package:equatable/equatable.dart';

import '../../milestones/domain/entities/milestone.dart';
import '../../evidence/domain/entities/evidence.dart';
import 'entities/signature_stroke.dart';
import 'stroke_metadata.dart';

/// CU-56 paso 1 (RF_05): payload completo para el motor de renderizado del
/// acta — datos maestros del proyecto, registros visuales del hito y las
/// firmas capturadas con sus metadatos biométricos (CU-55).
class ActaPayload extends Equatable {
  /// Identificador único del acta (se estampa en el documento; base del
  /// registro de certificaciones con hash, CU-59).
  final String actaId;

  final Milestone hito;

  /// Datos maestros del proyecto (null si no está disponible en el flujo).
  final String? obraNombre;

  /// Nombre del Propietario vinculado a la obra (null si no viaja en el
  /// flujo: se suma con el módulo de notificaciones, CU-68).
  final String? propietarioNombre;

  final List<Evidence> evidencias;

  /// Trazos de la firma manuscrita capturada (CU-52).
  final List<SignatureStroke> trazosFirma;

  /// Metadatos biométricos del trazo (CU-55).
  final StrokeMetadata metadatos;

  /// Rol del firmante: "Profesional" (primera firma, conformidad técnica)
  /// o "Propietario" (conformidad del cliente).
  final String firmante;

  final DateTime fechaConformidad;

  /// --- Conformidad colegiada (CU-57, doble firma) ---
  ///
  /// Cuando el acta se emite con doble firma, la segunda parte firma
  /// después de la primera: su trazo, metadatos biométricos, rol y fecha
  /// quedan consolidados en el mismo documento antes del sellado (CU-59).
  /// Null / vacío = acta de firma simple (flujo legacy de una parte).
  final String? segundoFirmante;
  final List<SignatureStroke> trazosSegundaFirma;
  final StrokeMetadata? metadatosSegundaFirma;
  final DateTime? fechaSegundaConformidad;

  /// La conformidad es colegiada cuando las dos partes firmaron.
  bool get conDobleFirma => segundoFirmante != null;

  const ActaPayload({
    required this.actaId,
    required this.hito,
    this.obraNombre,
    this.propietarioNombre,
    required this.evidencias,
    required this.trazosFirma,
    required this.metadatos,
    required this.firmante,
    required this.fechaConformidad,
    this.segundoFirmante,
    this.trazosSegundaFirma = const [],
    this.metadatosSegundaFirma,
    this.fechaSegundaConformidad,
  });

  @override
  List<Object?> get props => [
        actaId,
        hito,
        obraNombre,
        propietarioNombre,
        evidencias,
        trazosFirma,
        metadatos,
        firmante,
        fechaConformidad,
        segundoFirmante,
        trazosSegundaFirma,
        metadatosSegundaFirma,
        fechaSegundaConformidad,
      ];
}
