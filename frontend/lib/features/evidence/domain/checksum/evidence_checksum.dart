import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// CU-45 (Validar Integridad de Archivos Sincronizados, RF_06/RNF_C_03).
///
/// Calcula el checksum (hash) del archivo original localmente (paso 1) para
/// que el servidor lo compare con el archivo recibido y garantice integridad
/// bit a bit. Ante divergencia, el CU-44 retransmite (Alt. 2.2).
class EvidenceChecksum {
  /// SHA-256 en hexadecimal (mayúsculas) del contenido binario.
  static String sha256OfBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString().toUpperCase();
  }
}
