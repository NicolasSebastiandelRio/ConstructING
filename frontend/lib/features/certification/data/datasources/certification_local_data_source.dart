import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/storage/local_database.dart';

/// Registro de certificación sellada (CU-59, RF_08/RNF_C_05).
class CertificationRecord extends Equatable {
  final String actaId;
  final String hitoId;
  final String obraId;
  final String hashSha256;
  final String? firmante;

  /// Segundo actor de la conformidad colegiada (CU-57): si el acta lleva
  /// doble firma, aquí queda el rol de la otra parte ("Propietario" o
  /// "Profesional", según quién firmó primero).
  final String? firmante2;
  final DateTime createdAt;

  const CertificationRecord({
    required this.actaId,
    required this.hitoId,
    required this.obraId,
    required this.hashSha256,
    this.firmante,
    this.firmante2,
    required this.createdAt,
  });

  Map<String, dynamic> toLocalDb() => {
        'acta_id': actaId,
        'hito_id': hitoId,
        'obra_id': obraId,
        'hash_sha256': hashSha256,
        'firmante': firmante,
        'firmante2': firmante2,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory CertificationRecord.fromLocalDb(Map<String, dynamic> row) =>
      CertificationRecord(
        actaId: row['acta_id'] as String,
        hitoId: row['hito_id'] as String,
        obraId: row['obra_id'] as String,
        hashSha256: (row['hash_sha256'] as String?) ?? '',
        firmante: row['firmante'] as String?,
        firmante2: row['firmante2'] as String?,
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
      );

  @override
  List<Object?> get props =>
      [actaId, hitoId, obraId, hashSha256, firmante, firmante2, createdAt];
}

/// Acceso tipado a la tabla de certificaciones en la BD local (CU-59).
///
/// El sello SHA-256 del acta queda grabado en piedra: la tabla no admite
/// UPDATE/DELETE (sellado lógico post-firma, RNF_C_05) — solo inserciones
/// y consultas. Escrituras en transacción (RNF_C_02).
class CertificationLocalDataSource {
  CertificationLocalDataSource({required LocalDatabase localDatabase})
      : _localDatabase = localDatabase;

  final LocalDatabase _localDatabase;

  Future<Database> get _db => _localDatabase.database;

  /// CU-59 paso 4: almacena el hash calculado en la tabla de
  /// certificaciones. Un [actaId] repetido es idempotente: devuelve el
  /// registro existente (el sello no se re-firma).
  Future<CertificationRecord> insert(CertificationRecord record) async {
    final db = await _db;
    final existentes = await db.query(
      'certifications',
      where: 'acta_id = ?',
      whereArgs: [record.actaId],
      limit: 1,
    );
    if (existentes.isNotEmpty) {
      return CertificationRecord.fromLocalDb(existentes.first);
    }
    await db.transaction((txn) async {
      await txn.insert('certifications', record.toLocalDb());
    });
    return record;
  }

  /// La certificación sellada del hito (null si aún no tiene acta).
  Future<CertificationRecord?> findByHito(String hitoId) async {
    final db = await _db;
    final rows = await db.query(
      'certifications',
      where: 'hito_id = ?',
      whereArgs: [hitoId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CertificationRecord.fromLocalDb(rows.first);
  }
}

/// Borrador de conformidad esperando la segunda firma (CU-57): primera
/// firma persistida (rol, trazos, metadatos y fecha) hasta que la otra
/// parte complete la conformidad colegiada o se la descarte.
class PendingConformidad extends Equatable {
  final String hitoId;
  final String obraId;

  /// Rol que firmó primero ("Profesional" o "Propietario").
  final String primerFirmante;

  /// Trazos (JSON) y metadatos (JSON) de la primera firma.
  final List<Map<String, dynamic>> primerTrazos;
  final Map<String, dynamic> primerMetadatos;
  final DateTime primerFecha;
  final DateTime createdAt;

  const PendingConformidad({
    required this.hitoId,
    required this.obraId,
    required this.primerFirmante,
    required this.primerTrazos,
    required this.primerMetadatos,
    required this.primerFecha,
    required this.createdAt,
  });

  Map<String, dynamic> toLocalDb() => {
        'hito_id': hitoId,
        'obra_id': obraId,
        'primer_firmante': primerFirmante,
        'primer_trazos': jsonEncode(primerTrazos),
        'primer_metadatos': jsonEncode(primerMetadatos),
        'primer_fecha': primerFecha.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory PendingConformidad.fromLocalDb(Map<String, dynamic> row) =>
      PendingConformidad(
        hitoId: row['hito_id'] as String,
        obraId: row['obra_id'] as String,
        primerFirmante: row['primer_firmante'] as String,
        primerTrazos: [
          for (final item
              in (jsonDecode(row['primer_trazos'] as String) as List))
            (item as Map).cast<String, dynamic>(),
        ],
        primerMetadatos:
            (jsonDecode(row['primer_metadatos'] as String) as Map)
                .cast<String, dynamic>(),
        primerFecha: DateTime.parse(row['primer_fecha'] as String),
        createdAt:
            DateTime.tryParse(row['created_at'] as String) ?? DateTime.now(),
      );

  @override
  List<Object?> get props =>
      [hitoId, obraId, primerFirmante, primerFecha];
}

/// Acceso a los borradores de conformidad pendientes (CU-57, doble firma).
class PendingConformidadDataSource {
  PendingConformidadDataSource({required LocalDatabase localDatabase})
      : _localDatabase = localDatabase;

  final LocalDatabase _localDatabase;

  Future<Database> get _db => _localDatabase.database;

  /// Persiste la primera firma (borrador) del acta a sellar.
  Future<PendingConformidad> save(PendingConformidad conformidad) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'conformidades_pendientes',
        conformidad.toLocalDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return conformidad;
  }

  /// Borrador pendiente del hito (null si aún no hay primera firma).
  Future<PendingConformidad?> findPending(String hitoId) async {
    final db = await _db;
    final rows = await db.query(
      'conformidades_pendientes',
      where: 'hito_id = ?',
      whereArgs: [hitoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingConformidad.fromLocalDb(rows.first);
  }

  /// Todos los borradores pendientes de la obra (insumo del badge de la
  /// Hoja de Ruta del Propietario: "falta su firma").
  Future<List<PendingConformidad>> listByObra(String obraId) async {
    final db = await _db;
    final rows = await db.query(
      'conformidades_pendientes',
      where: 'obra_id = ?',
      whereArgs: [obraId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingConformidad.fromLocalDb).toList();
  }

  /// La conformidad colegiada se completó: el borrador se descarta.
  Future<void> delete(String hitoId) async {
    final db = await _db;
    await db.delete(
      'conformidades_pendientes',
      where: 'hito_id = ?',
      whereArgs: [hitoId],
    );
  }
}
