import 'package:equatable/equatable.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/storage/local_database.dart';

/// Registro de auditoría (CU-60, RF_08/RNF_S_03): huella permanente e
/// imborrable de una transacción crítica.
class AuditLogRecord extends Equatable {
  final String id;
  final String usuarioId;

  /// Tipo de acción crítica (p. ej. "hito_creado", "evidencia_cargada",
  /// "acta_sellada").
  final String accion;
  final String? detalle;

  /// Contexto de obra (opcional; para el Reporte de Auditoría, CU-63).
  final String? obraId;

  /// Coordenadas actuales informadas por el módulo de origen (opcional).
  final String? coordenadas;

  /// Timestamp exacto del evento.
  final DateTime createdAt;

  const AuditLogRecord({
    required this.id,
    required this.usuarioId,
    required this.accion,
    this.detalle,
    this.obraId,
    this.coordenadas,
    required this.createdAt,
  });

  Map<String, dynamic> toLocalDb() => {
        'id': id,
        'usuario_id': usuarioId,
        'accion': accion,
        'detalle': detalle,
        'obra_id': obraId,
        'coordenadas': coordenadas,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory AuditLogRecord.fromLocalDb(Map<String, dynamic> row) =>
      AuditLogRecord(
        id: row['id'] as String,
        usuarioId: row['usuario_id'] as String,
        accion: row['accion'] as String,
        detalle: row['detalle'] as String?,
        obraId: row['obra_id'] as String?,
        coordenadas: row['coordenadas'] as String?,
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toRemoteJson() => {
        'usuarioId': usuarioId,
        'accion': accion,
        'detalle': detalle,
        'obraId': obraId,
        'coordenadas': coordenadas,
      };

  @override
  List<Object?> get props =>
      [id, usuarioId, accion, detalle, obraId, coordenadas, createdAt];
}

/// Acceso a la tabla de auditoría en la BD local (CU-60, RNF_S_03).
///
/// SOLO lectura e inserción: no existen métodos de UPDATE ni DELETE — la
/// prohibición de modificar filas es estructura del código (la huella es
/// imborrable). Escrituras en transacción (RNF_C_02).
class AuditLogLocalDataSource {
  AuditLogLocalDataSource({required LocalDatabase localDatabase})
      : _localDatabase = localDatabase;

  final LocalDatabase _localDatabase;

  Future<Database> get _db => _localDatabase.database;

  /// CU-60 paso 4: inserta el registro inmutable en la tabla de auditoría.
  Future<AuditLogRecord> insert(AuditLogRecord record) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('audit_log', record.toLocalDb());
    });
    return record;
  }

  /// Consulta cronológica de la obra (descendente; insumo del CU-63).
  Future<List<AuditLogRecord>> listByObra(String obraId) async {
    final db = await _db;
    final rows = await db.query(
      'audit_log',
      where: 'obra_id = ?',
      whereArgs: [obraId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AuditLogRecord.fromLocalDb).toList();
  }

  /// Historial completo local (descendente).
  Future<List<AuditLogRecord>> listAll() async {
    final db = await _db;
    final rows = await db.query(
      'audit_log',
      orderBy: 'created_at DESC',
    );
    return rows.map(AuditLogRecord.fromLocalDb).toList();
  }
}
