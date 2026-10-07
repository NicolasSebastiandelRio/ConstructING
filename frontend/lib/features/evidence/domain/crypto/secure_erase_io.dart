import 'dart:io';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Resultado del borrado seguro (CU-59): qué pasó con el binario local.
class SecureEraseResult extends Equatable {
  /// El archivo ya no existía: poscondición satisfecha igualmente.
  final bool archivoInexistente;

  /// Cantidad de pasadas de re-escritura con patrón ejecutadas.
  final int pasadas;

  /// Tamaño en bytes del binario destruido.
  final int bytes;

  const SecureEraseResult({
    required this.archivoInexistente,
    required this.pasadas,
    required this.bytes,
  });

  @override
  List<Object?> get props => [archivoInexistente, pasadas, bytes];
}

/// CU-59 (RNF_C_05): motor de borrado seguro sobre el sistema de archivos.
///
/// Flujo principal:
/// 1. Localiza el binario local (des-referencia pendiente del registro
///    ya sincronizado, CU-44).
/// 2. Re-escribe TODOS los bytes con patrones deterministas en múltiples
///    pasadas (0x00 → 0xFF → 0x00) y cierra con una pasada pseudoaleatoria:
///    la huella original desaparece del disco y un simple restore no puede
///    recuperar el contenido.
/// 3. Elimina la entrada del sistema de archivos (des-referencia final).
/// 4. Verifica su ausencia y retorna el resultado del bloqueo.
///
/// Alt.: archivo ya inexistente → resultado con flag y poscondición
/// satisfecha.
class SecureEraseService {
  const SecureEraseService();

  /// Patrones deterministas por defecto (orden por pasada).
  static const List<int> patronesPorDefecto = [0x00, 0xFF, 0x00];

  /// Borrado seguro del archivo en [path]: re-escritura con patrón
  /// multi-pase + eliminación + verificación de ausencia.
  Future<SecureEraseResult> eraseFile(
    String path, {
    List<int>? patrones,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return const SecureEraseResult(
        archivoInexistente: true,
        pasadas: 0,
        bytes: 0,
      );
    }
    final patronesActivos = patrones ?? patronesPorDefecto;
    final length = await file.length();
    final rng = math.Random();

    final raf = await file.open(mode: FileMode.write);
    try {
      for (final byte in patronesActivos) {
        final chunk = List<int>.filled(length, byte);
        await raf.setPosition(0);
        await raf.writeFrom(chunk);
        await raf.flush();
      }
      // Cierre con patrón pseudoaleatorio: el estado del espacio justo
      // antes de la eliminación no delata el patrón de las pasadas previas.
      final cierre = List<int>.generate(length, (_) => rng.nextInt(256));
      await raf.setPosition(0);
      await raf.writeFrom(cierre);
      await raf.flush();
    } finally {
      await raf.close();
    }

    // Des-referencia definitiva del binario.
    await file.delete();
    if (await file.exists()) {
      throw StateError('CU-59: el archivo $path resistió la eliminación.');
    }

    return SecureEraseResult(
      archivoInexistente: false,
      pasadas: patronesActivos.length + 1,
      bytes: length,
    );
  }
}
