import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../domain/entities/evidence.dart';
import 'persist_final.dart';

/// Excepción de captura (CU-31 Alt. 2.2): permiso de cámara denegado.
class CameraPermissionException implements Exception {
  final String message;

  const CameraPermissionException(this.message);

  @override
  String toString() => message;
}

/// Gateway de captura pericial (CU-31: RF_03).
///
/// Encapsula el entorno de cámara **aislado** (CU-37): únicamente permite
/// captura en vivo del lente — jamás expone el File Picker de la galería —
/// garantizando que el usuario solo pueda registrar lo que tiene frente a
/// la cámara.
abstract class CaptureGateway {
  /// CU-31 paso 1-2: solicita apertura de cámara y activa el lente.
  ///
  /// Devuelve el archivo capturado en vivo o lanza
  /// [CameraPermissionException] si el permiso del OS fue denegado
  /// (Alt. 2.1/2.2).
  Future<String> capture({required EvidenceType tipo});

  /// Lee los bytes del archivo temporal producido por la captura (buffer de
  /// memoria del CU-36/CU-41).
  Future<List<int>> readBytes(String path);

  /// Sprint 4 (CU-45): persiste los bytes definitivos de la evidencia (con
  /// la marca ya estampada) como archivo del caché local y devuelve la ruta
  /// vigente. Obligatorio porque el checksum declarado se calcula sobre
  /// estos bytes: si se sincronizara el archivo temporal del picker (sin
  /// estampar) el servidor detectaría divergencia CU-45 y la evidencia
  /// quedaría pendiente para siempre.
  ///
  /// Web: regenera una `blob:` URL nueva (los blobs del picker viven solo
  /// durante la sesión). Móvil/desktop: escribe un archivo hermano del
  /// temporal del picker (mismo directorio de caché de la app).
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  });

  /// CU-44 paso 4: libera el archivo temporal una vez sincronizado.
  Future<void> releaseTempFile(String path);
}

/// Implementación de producción.
///
/// Usa el selector nativo del OS **exclusivamente con origen cámara**:
/// `ImageSource.camera` abre la vista en tiempo real del lente; en web
/// delega a getUserMedia. Nunca se invoca `ImageSource.gallery`
/// (CU-37: galería bloqueada por diseño).
class LiveCaptureGateway implements CaptureGateway {
  const LiveCaptureGateway();

  @override
  Future<String> capture({required EvidenceType tipo}) async {
    final picker = ImagePicker();
    final XFile? file;
    try {
      if (tipo == EvidenceType.video) {
        // CU-33/RNF_E_06 + CU-38: la grabación nativa nace acotada por
        // debajo del límite de 30 s — 25 s de margen de seguridad porque el
        // OS redondea hacia arriba y el validador CU-38 rechaza >= 30.0 s
        // precisos (edge case que rechazaría videos al límite).
        file = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 25),
        );
      } else {
        // CU-32: fotograma del avance en el lugar de la obra.
        file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          imageQuality: 88,
        );
      }
    } on Exception {
      throw const CameraPermissionException(
        'Debe otorgar permisos de cámara para continuar',
      );
    }
    if (file == null) {
      // El usuario canceló la captura nativa: se propaga como cancelación
      // (CU-41: sin archivos basura generados).
      throw const CameraPermissionException('Captura cancelada');
    }
    return file.path;
  }

  @override
  Future<List<int>> readBytes(String path) async {
    final file = XFile(path);
    return file.readAsBytes();
  }

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async {
    if (kIsWeb) {
      // Web: regenera una blob: URL con los bytes estampados (dart:ui no
      // puede escribir al disco del navegador).
      return createBlobUrlFromBytes(Uint8List.fromList(bytes));
    }
    // Móvil/desktop: archivo hermano del temporal del picker (el directorio
    // es el caché privado de la app, siempre escribible).
    return writeSiblingFile(Uint8List.fromList(bytes), originalPath);
  }

  @override
  Future<void> releaseTempFile(String path) async {
    // Los archivos temporales del picker se gestionan por el OS; la
    // liberación del registro de caché la hace la BD (CU-44 paso 4).
  }
}
