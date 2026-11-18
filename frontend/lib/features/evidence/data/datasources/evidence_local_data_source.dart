import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/local_database.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../domain/entities/evidence.dart';

/// Acceso tipado a la evidencia pericial en la BD local (CU-42, RF_03).
///
/// Toda escritura corre en transacción (RNF_C_02) y nace con
/// `es_sincronizado=false` para el motor de sincronización (CU-44).
class EvidenceLocalDataSource {
  EvidenceLocalDataSource({required LocalDatabase localDatabase, Uuid? uuid})
      : _localDatabase = localDatabase,
        _uuid = uuid ?? const Uuid();

  final LocalDatabase _localDatabase;
  final Uuid _uuid;

  Future<Database> get _db => _localDatabase.database;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// CU-57 (RF_08, RNF_C_05): los registros hijos (fotos/videos) de un
  /// hito certificado quedan congelados — Update/Delete inactivos en la
  /// BD. Sin fila de hito (o sin estado "Certificado") el registro queda
  /// editable (no bloquea flujos de sincronización ni legacy).
  Future<void> _assertHitoEditable(
    DatabaseExecutor db,
    String hitoId,
  ) async {
    final rows = await db.query(
      'milestones',
      columns: ['estado'],
      where: 'id = ?',
      whereArgs: [hitoId],
      limit: 1,
    );
    final estado = rows.isEmpty ? null : rows.first['estado'] as String?;
    if (estado == MilestoneStatus.certificado.label) {
      throw const CacheStorageException(
        'El hito está certificado: su evidencia quedó congelada por la firma (CU-57).',
      );
    }
  }

  /// CU-32 paso 6 / CU-33 paso 4 (vía CU-42): persiste la evidencia con el
  /// flag `es_sincronizado=false` — queda encolada para el CU-44. El flag
  /// `fueraDeObra` (CU-35 soft-fail) viaja con la fila para que la galería
  /// estampe la etiqueta roja de no coincidencia.
  Future<Evidence> create({
    required String hitoId,
    required String obraId,
    required EvidenceType tipo,
    required String archivo,
    String? nota,
    required double latitud,
    required double longitud,
    required double precisionMetros,
    required DateTime fechaCaptura,
    double? duracionSeg,
    required int tamanoBytes,
    required String checksum,
    required String marcaTexto,
    bool fueraDeObra = false,
  }) async {
    if (hitoId.trim().isEmpty || obraId.trim().isEmpty) {
      throw const CacheStorageException(
          'La evidencia debe vincularse a un hito de la obra.');
    }
    if (checksum.trim().isEmpty) {
      throw const CacheStorageException(
          'La evidencia requiere su checksum de integridad (CU-45).');
    }
    final evidence = Evidence(
      id: _uuid.v4(),
      hitoId: hitoId,
      obraId: obraId,
      tipo: tipo,
      archivo: archivo,
      nota: nota?.trim().isEmpty == true ? null : nota?.trim(),
      latitud: latitud,
      longitud: longitud,
      precisionMetros: precisionMetros,
      fechaCaptura: fechaCaptura,
      duracionSeg: duracionSeg,
      tamanoBytes: tamanoBytes,
      checksum: checksum.trim(),
      marcaTexto: marcaTexto,
      fueraDeObra: fueraDeObra,
    );
    try {
      final db = await _db;
      await db.transaction((txn) async {
        // CU-57: la evidencia de un hito certificado no admite nuevas cargas.
        await _assertHitoEditable(txn, hitoId);
        await txn.insert('evidences', evidence.toLocalDb(nowIso: _nowIso()));
      });
    } catch (e) {
      if (e is CacheStorageException) rethrow;
      throw const CacheStorageException(
        'No se pudo guardar localmente. Verifique el espacio disponible en el dispositivo.',
      );
    }
    return evidence;
  }

  /// Galería de evidencias del hito (CU-40 paso 2: fuente del mapa).
  Future<List<Evidence>> listByHito(String hitoId) async {
    final db = await _db;
    final rows = await db.query(
      'evidences',
      where: 'hito_id = ?',
      whereArgs: [hitoId],
      orderBy: 'fecha_captura ASC',
    );
    return rows.map(Evidence.fromLocalDb).toList();
  }

  /// CU-50 paso 2: cantidad de evidencias multimedia cargadas para el hito.
  /// Cuenta registros (sincronizados o no): el cierre formal exige al menos
  /// una (1) evidencia aunque el caché del archivo ya se haya liberado.
  Future<int> countByHito(String hitoId) async {
    final db = await _db;
    final rows = await db.query(
      'evidences',
      columns: ['id'],
      where: 'hito_id = ?',
      whereArgs: [hitoId],
    );
    return rows.length;
  }

  /// Todas las evidencias de la obra (CU-40 a nivel de obra, si se requiere).
  Future<List<Evidence>> listByObra(String obraId) async {
    final db = await _db;
    final rows = await db.query(
      'evidences',
      where: 'obra_id = ?',
      whereArgs: [obraId],
      orderBy: 'fecha_captura ASC',
    );
    return rows.map(Evidence.fromLocalDb).toList();
  }

  /// Cola de sincronización (CU-44 paso 1): registros con
  /// `es_sincronizado=false` de toda la BD.
  Future<List<Evidence>> listPendingSync() async {
    final db = await _db;
    final rows = await db.query(
      'evidences',
      where: 'es_sincronizado = ?',
      whereArgs: [0],
      orderBy: 'fecha_captura ASC',
    );
    return rows.map(Evidence.fromLocalDb).toList();
  }

  /// CU-44 paso 4: marca el registro como sincronizado y libera el espacio
  /// de caché temporal (el campo `archivo` queda vacío; el binario ya está
  /// respaldado en la nube y validado por CU-45).
  Future<void> markSynced(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'evidences',
        {'es_sincronizado': 1, 'archivo': '', 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// CU-46/CU-45 retransmisión: tras un intento fallido el registro sigue
  /// pendiente; actualiza la ruta del archivo si la re-captura cambió.
  /// CU-57: inactivo sobre la evidencia de un hito certificado.
  Future<void> updateArchivo(String id, String archivo) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'evidences',
        columns: ['hito_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final hitoId = rows.isEmpty ? null : rows.first['hito_id'] as String?;
      if (hitoId != null) {
        await _assertHitoEditable(txn, hitoId);
      }
      await txn.update(
        'evidences',
        {'archivo': archivo, 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Reparación legacy (Sprint 4): re-ancla el checksum CU-45 al archivo
  /// real del caché (ver SyncEngine._uploadWithIntegrity). CU-57: inactivo
  /// sobre la evidencia de un hito certificado.
  Future<void> updateChecksum(String id, String checksum) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'evidences',
        columns: ['hito_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final hitoId = rows.isEmpty ? null : rows.first['hito_id'] as String?;
      if (hitoId != null) {
        await _assertHitoEditable(txn, hitoId);
      }
      await txn.update(
        'evidences',
        {'checksum': checksum, 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// CU-41 (poscondición): borra el registro descartado antes de ser
  /// confirmado (memoria liberada, sin archivos basura). CU-57: inactivo
  /// sobre la evidencia de un hito certificado.
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'evidences',
        columns: ['hito_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final hitoId = rows.isEmpty ? null : rows.first['hito_id'] as String?;
      if (hitoId != null) {
        await _assertHitoEditable(txn, hitoId);
      }
      await txn.delete('evidences', where: 'id = ?', whereArgs: [id]);
    });
  }
}
