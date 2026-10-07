import 'package:equatable/equatable.dart';

/// Resultado del borrado seguro (CU-59) en plataforma web.
///
/// El navegador es dueño del almacenamiento: no permite la re-escritura
/// con patrón del espacio físico. La destrucción se degrada a
/// DES-REFERENCIA: al liberar el binario del caché (CU-44) la memoria de
/// respuesta del componente mantiene la firma del módulo; la liberación
/// física la realiza el navegador.
class SecureEraseResult extends Equatable {
  /// El binario no tiene copia físico en la plataforma web.
  final bool archivoInexistente;

  /// Pasadas reales de re-escritura (0 en web: no aplica).
  final int pasadas;

  /// Tamaño en bytes del binario esperado (0 si no existía).
  final int bytes;

  const SecureEraseResult({
    required this.archivoInexistente,
    required this.pasadas,
    required this.bytes,
  });

  @override
  List<Object?> get props => [archivoInexistente, pasadas, bytes];
}

/// CU-59 (web): des-referencia del binario (la liberación física la
/// realiza el navegador; RNF_C_05 degradado por plataforma).
class SecureEraseService {
  const SecureEraseService();

  /// Firma del módulo (web): no opera ningún archivo físico.
  Future<SecureEraseResult> eraseFile(
    String path, {
    List<int>? patrones,
  }) async {
    return const SecureEraseResult(
      archivoInexistente: true,
      pasadas: 0,
      bytes: 0,
    );
  }
}
