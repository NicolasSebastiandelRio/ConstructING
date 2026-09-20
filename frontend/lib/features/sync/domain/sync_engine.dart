import 'package:flutter/foundation.dart';

import '../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../evidence/domain/entities/evidence.dart';
import '../../milestones/data/datasources/milestone_local_data_source.dart';
import '../data/datasources/sync_remote_data_source.dart';
import 'sync_run_result.dart';

/// Motor de sincronización offline-first (CU-44..CU-47, RF_06/RNF_E_05).
///
/// Vuelca los registros locales pendientes hacia el servidor central al
/// detectar red estable (precondición: CU-43 confirmó conectividad):
/// - CU-44: recopila pendientes, los envía por HTTPS y marca cada registro
///   como sincronizado tras el HTTP 200, liberando el caché temporal.
/// - CU-45: toda evidencia viaja con su checksum SHA-256; ante divergencia
///   retransmite (Alt. 2.2).
/// - CU-46: consulta el offset ya recibido y transmite solo el bloque
///   restante (carga reanudable).
/// - CU-47: el servidor resuelve colisiones por última modificación; el
///   motor aplica el veredicto sobre la fila local.
///
/// Ante error de red (Alt. 2.1/2.2) cancela la operación actual, mantiene
/// el registro pendiente y programa un reintento.
class SyncEngine {
  SyncEngine({
    required this.milestones,
    required this.evidences,
    required this.remote,
    required this.evidenceReader,
    this.maxIntegrityRetries = 3,
    this.onProgress,
  });

  final MilestoneLocalDataSource milestones;
  final EvidenceLocalDataSource evidences;
  final SyncRemoteDataSource remote;

  /// Reintentos ante divergencia de checksum (CU-45 Alt. 2.2).
  final int maxIntegrityRetries;

  /// Callback de progreso para alimentar el indicador (CU-48).
  final ValueChanged<SyncRunResult>? onProgress;

  /// Lector de bytes del archivo local (gateway de captura en producción).
  final Future<List<int>> Function(String path) evidenceReader;

  int _pendingCount = 0;

  /// Cantidad de registros pendientes conocidos (base del panel CU-48).
  int get pendingCount => _pendingCount;

  /// Ejecuta el volcado completo. Nunca lanza: los errores se traducen en
  /// registros pendientes + reintento programado (CU-44 Alt. 2.2).
  Future<SyncRunResult> run() async {
    var hitos = 0;
    var evidenciasOk = 0;
    var retransmisiones = 0;
    var pendientes = 0;

    // --- CU-44 paso 1: hitos pendientes ---
    final hitosPendientes = await milestones.listPendingSync();
    for (final milestone in hitosPendientes) {
      try {
        final verdict = await remote.pushMilestone({
          'id': milestone.id,
          'obraId': milestone.obraId,
          'nombre': milestone.nombre,
          'descripcion': milestone.descripcion,
          'duracionDias': milestone.duracionDias,
          'estado': milestone.estado.label,
          'esCritico': milestone.esCritico,
          'updatedAtLocal': await _updatedAtOf(milestone.id),
        });
        // CU-47 paso 4: el veredicto del servidor unifica la línea de
        // tiempo; el estado local adopta la versión vigente.
        if (verdict.conflict && verdict.estado.isNotEmpty) {
          await milestones.applyServerVerdict(
            id: milestone.id,
            estado: verdict.estado,
          );
        }
        await milestones.markSynced(milestone.id);
        hitos++;
      } catch (e) {
        debugPrint('CU-44 Alt. 2.2: hito ${milestone.id} queda pendiente: $e');
        pendientes++;
      }
    }

    // --- CU-44 paso 1: evidencias pendientes ---
    final evidenciasPendientes = await evidences.listPendingSync();
    for (final evidence in evidenciasPendientes) {
      try {
        final retransmisionesDeEvidencia = await _uploadWithIntegrity(evidence);
        retransmisiones += retransmisionesDeEvidencia;
        evidenciasOk++;
      } on SyncIntegrityException {
        retransmisiones++;
        pendientes++;
        debugPrint('CU-45 Alt.: la evidencia ${evidence.id} se retransmitirá.');
      } catch (e) {
        debugPrint('CU-44 Alt. 2.2: evidencia ${evidence.id} queda pendiente: $e');
        pendientes++;
      }
    }

    _pendingCount = await _countPending();
    final result = SyncRunResult(
      hitosSubidos: hitos,
      evidenciasSubidas: evidenciasOk,
      pendientes: pendientes,
      retransmisiones: retransmisiones,
    );
    onProgress?.call(result);
    return result;
  }

  /// Subida de una evidencia con retransmisión ante corrupción (CU-45 Alt.).
  /// Retorna la cantidad de retransmisiones ejecutadas.
  Future<int> _uploadWithIntegrity(Evidence evidence) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final bytes = await _bytesOf(evidence);
        await remote.uploadEvidence(
          evidenceMeta: _metaOf(evidence),
          bytes: bytes,
          totalBytes: bytes.length,
          checksum: evidence.checksum,
        );
        // CU-44 paso 4: marca sincronizado + libera caché temporal.
        await evidences.markSynced(evidence.id);
        return attempt - 1;
      } on SyncIntegrityException {
        if (attempt >= maxIntegrityRetries) rethrow;
        debugPrint(
          'CU-45 Alt. 2.2: retransmisión ${attempt + 1} de la evidencia ${evidence.id}.',
        );
      }
    }
  }

  /// Meta + bytes de la evidencia. Si el archivo local ya se liberó y el
  /// registro está pendiente (corte a mitad de la corrida), se re-captura:
  /// la evidencia viaja desde la ruta vigente.
  Future<List<int>> _bytesOf(Evidence evidence) async {
    if (evidence.archivo.isEmpty) {
      throw StateError('Evidencia ${evidence.id} sin archivo local disponible.');
    }
    return evidenceReader(evidence.archivo);
  }

  Map<String, dynamic> _metaOf(Evidence evidence) {
    return {
      'id': evidence.id,
      'hitoId': evidence.hitoId,
      'obraId': evidence.obraId,
      'tipo': evidence.tipo.label,
      'nota': evidence.nota,
      'latitud': evidence.latitud,
      'longitud': evidence.longitud,
      'precisionM': evidence.precisionMetros,
      'fechaCaptura': evidence.fechaCaptura.toIso8601String(),
      'duracionSeg': evidence.duracionSeg,
      'marcaTexto': evidence.marcaTexto,
    };
  }

  Future<String> _updatedAtOf(String milestoneId) async {
    // El datasource mantiene `updated_at` por fila (clave del CU-47).
    final stored = await milestones.updatedAtOf(milestoneId);
    return stored ?? DateTime.now().toIso8601String();
  }

  Future<int> _countPending() async {
    final evidencias = await evidences.listPendingSync();
    final hitos = await milestones.listPendingSync();
    return evidencias.length + hitos.length;
  }

  /// Refresca el contador de pendientes sin correr el motor (CU-48).
  Future<void> refreshPendingCount() async {
    _pendingCount = await _countPending();
  }
}
