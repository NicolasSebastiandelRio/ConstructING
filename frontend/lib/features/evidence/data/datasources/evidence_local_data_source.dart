import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/local_database.dart';
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

  /// CU-32 paso 6 / CU-33 paso 4 (vía CU-42): persiste la evidencia con el
  /// flag `es_sincronizado=false` — queda encolada para el CU-44.
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
    );
    try {
      final db = await _db;
      await db.transaction((txn) async {
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
  Future<void> updateArchivo(String id, String archivo) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'evidences',
        {'archivo': archivo, 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// CU-41 (positcondición): borra el registro descartado antes de ser
  /// confirmado (memoria liberada, sin archivos basura).
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('evidences', where: 'id = ?', whereArgs: [id]);
    });
  }
}
