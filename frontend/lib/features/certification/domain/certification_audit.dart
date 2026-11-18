import 'package:flutter/foundation.dart';

import '../../milestones/domain/entities/milestone.dart';
import 'entities/signature_stroke.dart';

/// Traza de auditoría transitoria del flujo de certificación (Sprint 5).
///
/// El Audit Log persistente e inalterable es CU-60: hasta entonces cada
/// hito del proceso deja una línea estructurada en consola con el mismo
/// contenido que persistirá (RF_08, RNF_S_03).
class CertificationAudit {
  /// CU-51 paso 2: el resumen a certificar fue consultado y desplegado.
  static void logSummaryAccessed({required Milestone hito}) {
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] resumen de certificación consultado '
      'hito=${hito.id} obra=${hito.obraId} estado=${hito.estado.label}',
    );
  }

  /// CU-52 Alt. 2.1/2.2: firma rechazada por longitud mínima insuficiente
  /// y lienzo limpiado (CU-53) para el reintento.
  static void logSignatureRejected({required Milestone hito}) {
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] firma rechazada por trazo inválido '
      'hito=${hito.id} obra=${hito.obraId}',
    );
  }
  /// CU-52 paso 2: firma manuscrita capturada y validada (conformidad).
  static void logSignatureCaptured({
    required Milestone hito,
    required List<SignatureStroke> strokes,
  }) {
    final total =
        strokes.fold<double>(0.0, (s, stroke) => s + stroke.lengthPx);
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] firma manuscrita capturada '
      'hito=${hito.id} obra=${hito.obraId} '
      'trazos=${strokes.length} longitudPx=${total.toStringAsFixed(1)}',
    );
  }

  /// CU-54 paso 4: acta guardada como copia offline del certificado.
  static void logActaDownloaded({
    required Milestone hito,
    required String ubicacion,
  }) {
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] acta descargada '
      'hito=${hito.id} obra=${hito.obraId} ubicacion=$ubicacion',
    );
  }

  /// CU-57 paso 2/4 (RNF_C_05): hito y evidencias congelados tras la firma
  /// — grabados en piedra, con Update/Delete inactivos en la BD.
  static void logRecordsFrozen({required Milestone hito}) {
    debugPrint(
      '[AUDIT-CU60-PENDIENTE] registros congelados (CU-57) '
      'hito=${hito.id} obra=${hito.obraId} estado=${hito.estado.label}',
    );
  }
}
