import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// CU-59 (RF_08, RNF_C_05): motor criptográfico del acta de conformidad.
///
/// Procesa la totalidad del documento binario con el algoritmo
/// unidireccional SHA-256 y retorna la cadena alfanumérica única (hash)
/// lista para asociarse al registro en la tabla de certificaciones de la
/// BD. El sello cambia radicalmente si se altera un solo byte del original:
/// sellado lógico contra modificaciones post-firma.
class ActaHash {
  /// SHA-256 en hexadecimal (mayúsculas) del contenido binario.
  static String sha256OfBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString().toUpperCase();
  }
}
