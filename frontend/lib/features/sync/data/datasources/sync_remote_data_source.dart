import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';

/// Veredicto del servidor ante una subida de evidencia.
enum EvidenceUploadOutcome { synced, corrupted }

/// Resultado del CU-47 informado por el servidor ante una colisión.
class MilestoneSyncVerdict {
  final bool synced;
  final bool conflict;
  final String id;
  final String estado;
  final String? updatedAtLocal;

  const MilestoneSyncVerdict({
    required this.synced,
    required this.conflict,
    required this.id,
    required this.estado,
    this.updatedAtLocal,
  });

  factory MilestoneSyncVerdict.fromJson(Map<String, dynamic> json) {
    final state = (json['finalState'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MilestoneSyncVerdict(
      synced: json['synced'] == true,
      conflict: json['conflict'] == true,
      id: state['id'] as String? ?? '',
      estado: state['estado'] as String? ?? '',
      updatedAtLocal: state['updatedAtLocal'] as String?,
    );
  }
}

/// Error de integridad (CU-45 Alt.): el checksum recibido no coincide y el
/// CU-44 debe retransmitir (el servidor ya borró el archivo corrupto).
class SyncIntegrityException implements Exception {
  final String message;

  const SyncIntegrityException(this.message);

  @override
  String toString() => message;
}

/// Error de red/servidor (CU-44 Alt. 2.1): mantener pendiente y reintentar.
class SyncTemporaryException implements Exception {
  final String message;

  const SyncTemporaryException(this.message);

  @override
  String toString() => message;
}

/// Fuente remota del motor de sincronización (CU-44..CU-46).
abstract class SyncRemoteDataSource {
  /// CU-44: volcado de un hito pendiente (HTTPS). Retorna el veredicto
  /// del servidor (CU-47: política de última modificación).
  Future<MilestoneSyncVerdict> pushMilestone(Map<String, dynamic> payload);

  /// CU-44 paso 1-2 + CU-45 + CU-46: sube la evidencia validando integridad.
  /// Consulta primero el offset ya recibido (CU-46 paso 2) y transmite
  /// únicamente el bloque restante (paso 3).
  Future<void> uploadEvidence({
    required Map<String, dynamic> evidenceMeta,
    required List<int> bytes,
    required int totalBytes,
    required String checksum,
  });
}

class HttpSyncRemoteDataSource implements SyncRemoteDataSource {
  HttpSyncRemoteDataSource({required this.dioClient});

  final DioClient dioClient;

  /// Tamaño de bloque para la carga reanudable (CU-46 paso 3).
  static const int chunkSize = 512 * 1024;

  /// El JWT viaja por el interceptor global del `DioClient` (CU-05).
  Dio get _dio => dioClient.dio;

  @override
  Future<MilestoneSyncVerdict> pushMilestone(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post(
        '/sync/milestones',
        data: payload,
      );
      return MilestoneSyncVerdict.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw SyncTemporaryException(
        'El servidor no confirmó el paquete (${e.response?.statusCode ?? 'sin red'}).',
      );
    }
  }

  @override
  Future<void> uploadEvidence({
    required Map<String, dynamic> evidenceMeta,
    required List<int> bytes,
    required int totalBytes,
    required String checksum,
  }) async {
    // CU-46 paso 1-2: consulta el punto exacto de interrupción previo.
    var offset = 0;
    try {
      final offsetResponse = await _dio.get(
        '/evidences/${evidenceMeta['id']}/offset',
      );
      offset = (offsetResponse.data['bytes'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw SyncTemporaryException(
        'No se pudo consultar el punto de interrupción (${e.response?.statusCode ?? 'sin red'}).',
      );
    }

    if (offset >= totalBytes) {
      // El archivo ya está completo en la nube: falta la confirmación del
      // bloque final (reensamblado + CU-45).
      final outcome = await _sendChunk(
        evidenceMeta: evidenceMeta,
        offset: totalBytes,
        chunk: const [],
        totalBytes: totalBytes,
        checksum: checksum,
      );
      _assertValid(outcome);
      return;
    }

    // CU-46 paso 3: transmite únicamente el bloque restante.
    while (offset < totalBytes) {
      final end = (offset + chunkSize) > totalBytes
          ? totalBytes
          : offset + chunkSize;
      final slice = bytes.sublist(offset, end);
      final outcome = await _sendChunk(
        evidenceMeta: evidenceMeta,
        offset: offset,
        chunk: slice,
        totalBytes: totalBytes,
        checksum: checksum,
      );
      _assertValid(outcome);
      offset = end;
    }
  }

  Future<String> _sendChunk({
    required Map<String, dynamic> evidenceMeta,
    required int offset,
    required List<int> chunk,
    required int totalBytes,
    required String checksum,
  }) async {
    final response = await _dio.patch(
      '/evidences/${evidenceMeta['id']}/chunk',
      data: {
        'offset': offset,
        'bytesB64': chunk.isEmpty ? '' : base64Encode(chunk),
        'meta': {
          ...evidenceMeta,
          'tamanoBytes': totalBytes,
          'checksum': checksum,
        },
      },
    );
    return ((response.data as Map)['result'] as String?) ?? 'synced';
  }

  void _assertValid(String outcome) {
    if (outcome == 'corrupted') {
      // CU-45 Alt. 2.2: integridad fallida → CU-44 retransmite.
      throw const SyncIntegrityException('Archivo corrupto en el transporte');
    }
  }
}
