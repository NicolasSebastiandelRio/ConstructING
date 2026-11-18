import 'dart:typed_data';

import '../checksum/evidence_checksum.dart';

/// CU-58 (Calcular Hash SHA-256, RF_08/RNF_S_03): Motor Criptográfico del
/// Módulo de Evidencia.
///
/// Invocado internamente durante el almacenamiento de nueva evidencia
/// (CU-32, CU-33): firma matemática del archivo binario (foto o video) en
/// memoria y retorna la cadena alfanumérica única (hash) lista para
/// asociarse al registro en la base de datos (poscondición: identificador
/// inmutable que cambiaría radicalmente si se altera un solo píxel).
class EvidenceHashService {
  const EvidenceHashService();

  /// SHA-256 en hexadecimal (mayúsculas) del contenido binario en memoria.
  Future<String> hashBytes(Uint8List bytes) async {
    return EvidenceChecksum.sha256OfBytes(bytes);
  }
}
