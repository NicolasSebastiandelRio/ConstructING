import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../domain/entities/evidence.dart';
import '../checksum/evidence_checksum.dart';

/// Resultado de la verificación de integridad de una evidencia (CU-58,
/// RF_08/RNF_S_03): comparación del checksum asociado al registro (BD)
/// contra el hash SHA-256 recalculado sobre los bytes reales del archivo.
class IntegrityCheck extends Equatable {
  /// El archivo en disco conservó su huella: no hubo manipulación externa.
  final bool ok;

  /// Checksum almacenado en el registro (BD).
  final String esperado;

  /// Hash recalculado sobre el binario en disco.
  final String actual;

  const IntegrityCheck({
    required this.ok,
    required this.esperado,
    required this.actual,
  });

  @override
  List<Object?> get props => [ok, esperado, actual];
}

/// CU-58 (pasos de verificación, RF_08/RNF_S_03): verificación de
/// integridad de la evidencia al reabrir o antes de sincronizar.
///
/// Invocado por el motor de sincronización (ref. CU-45) antes de transmitir
/// y por los flujos de consulta: recalcula la firma matemática del binario
/// en disco y la compara con el identificador inmutable guardado en la BD.
/// Un solo píxel alterado produce divergencia (el archivo fue manipulado
/// fuera del sistema o se corrompió).
class EvidenceIntegrityVerifier {
  const EvidenceIntegrityVerifier({required this.fileReader});

  /// Lector de bytes del archivo local (gateway de captura en producción).
  final Future<List<int>> Function(String archivo) fileReader;

  /// SHA-256 en memoria de una lista de bytes (insumo compartido).
  static String sha256OfBytes(List<int> bytes) =>
      EvidenceChecksum.sha256OfBytes(Uint8List.fromList(bytes));

  /// Verifica una evidencia: recalcula el hash del archivo en disco y lo
  /// compara contra el checksum del registro. Lanza si el archivo no está
  /// disponible (el punto de integración decide la política: reintentar,
  /// re-recapturar o cuarentena).
  Future<IntegrityCheck> verify(Evidence evidence) async {
    final bytes = await fileReader(evidence.archivo);
    final actual = sha256OfBytes(bytes);
    final esperado = evidence.checksum;
    return IntegrityCheck(
      ok: actual == esperado,
      esperado: esperado,
      actual: actual,
    );
  }

  /// Verifica un lote (hitos de auditoría, CU-63/CU-50). Retorna las
  /// flags de divergencia por evidencia: `ok == false` en el resultado.
  Future<Map<String, IntegrityCheck>> verifyAll(
    List<Evidence> evidencias,
  ) async {
    final results = <String, IntegrityCheck>{};
    for (final evidence in evidencias) {
      try {
        results[evidence.id] = await verify(evidence);
      } catch (e) {
        // Archivo no disponible: divergencia reportable (no silencia).
        results[evidence.id] =
            IntegrityCheck(ok: false, esperado: evidence.checksum, actual: '');
      }
    }
    return results;
  }
}
