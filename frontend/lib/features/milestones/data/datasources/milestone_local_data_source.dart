import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/local_database.dart';
import '../../domain/entities/milestone.dart';

/// Acceso tipado a hitos y dependencias en la BD local (CU-23/CU-42).
///
/// Toda escritura corre en transacción (RNF_C_02) y nace con
/// `es_sincronizado=false` para la futura sincronización (CU-44, Sprint 4).
class MilestoneLocalDataSource {
  MilestoneLocalDataSource({required LocalDatabase localDatabase, Uuid? uuid})
      : _localDatabase = localDatabase,
        _uuid = uuid ?? const Uuid();

  final LocalDatabase _localDatabase;
  final Uuid _uuid;

  Future<Database> get _db => _localDatabase.database;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// CU-23 paso 4: persiste el hito en estado Pendiente (poscondición CU-23).
  Future<Milestone> create({
    required String obraId,
    required String nombre,
    String? descripcion,
    required int duracionDias,
  }) async {
    if (nombre.trim().isEmpty) {
      throw const CacheStorageException('El nombre del hito es obligatorio.');
    }
    if (duracionDias < 0) {
      throw const CacheStorageException(
          'La duración debe ser un número mayor o igual a 0.');
    }
    final db = await _db;
    final milestone = Milestone(
      id: _uuid.v4(),
      obraId: obraId,
      nombre: nombre.trim(),
      descripcion: descripcion?.trim().isEmpty == true ? null : descripcion?.trim(),
      duracionDias: duracionDias,
    );
    try {
      await db.transaction((txn) async {
        await txn.insert('milestones', milestone.toLocalDb(nowIso: _nowIso()));
      });
    } catch (e) {
      throw const CacheStorageException(
        'No se pudo guardar localmente. Verifique el espacio disponible en el dispositivo.',
      );
    }
    return milestone;
  }

  /// Hoja de Ruta de la obra, en orden de creación.
  Future<List<Milestone>> listByObra(String obraId) async {    final db = await _db;
    final rows = await db.query(
      'milestones',
      where: 'obra_id = ?',
      whereArgs: [obraId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Milestone.fromLocalDb).toList();
  }

  /// Recupera un hito por ID (null si no existe).
  Future<Milestone?> getById(String id) async {
    final db = await _db;
    final rows = await db.query('milestones', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Milestone.fromLocalDb(rows.first);
  }

  /// CU-25: actualiza descripción/duración/estado de un hito existente.
  Future<Milestone> update(Milestone milestone) async {
    final db = await _db;
    try {
      await db.transaction((txn) async {
        await txn.update(
          'milestones',
          {
            'nombre': milestone.nombre,
            'descripcion': milestone.descripcion,
            'duracion_dias': milestone.duracionDias,
            'estado': milestone.estado.label,
            'es_critico': milestone.esCritico ? 1 : 0,
            'es_sincronizado': milestone.esSincronizado ? 1 : 0,
            'updated_at': _nowIso(),
          },
          where: 'id = ?',
          whereArgs: [milestone.id],
        );
      });
    } catch (e) {
      throw const CacheStorageException(
        'No se pudo guardar localmente. Verifique el espacio disponible en el dispositivo.',
      );
    }
    return milestone;
  }

  /// CU-27: elimina el hito y sus aristas (las precondiciones las valida el
  /// servicio/bloc: sin progreso, sin evidencias, sin dependencias activas).
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('milestone_dependencies',
          where: 'hito_id = ? OR predecesor_id = ?', whereArgs: [id, id]);
      await txn.delete('milestones', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// CU-24: registra que [hitoId] depende de [predecesorId].
  Future<void> addDependency({
    required String hitoId,
    required String predecesorId,
  }) async {
    if (hitoId == predecesorId) {
      throw const CacheStorageException('Un hito no puede depender de sí mismo.');
    }
    final db = await _db;
    await db.insert(
      'milestone_dependencies',
      {'hito_id': hitoId, 'predecesor_id': predecesorId},
    );
  }

  Future<void> removeDependency({
    required String hitoId,
    required String predecesorId,
  }) async {
    final db = await _db;
    await db.delete(
      'milestone_dependencies',
      where: 'hito_id = ? AND predecesor_id = ?',
      whereArgs: [hitoId, predecesorId],
    );
  }

  /// IDs de los predecesores directos de un hito (CU-24/CU-28/CU-29).
  Future<List<String>> predecessorIds(String hitoId) async {
    final db = await _db;
    final rows = await db.query(
      'milestone_dependencies',
      columns: ['predecesor_id'],
      where: 'hito_id = ?',
      whereArgs: [hitoId],
    );
    return rows.map((r) => r['predecesor_id'] as String).toList();
  }

  /// CU-29 paso 4: marca con holgura cero como críticos (1) y limpia el
  /// resto (0), en una sola transacción por obra.
  Future<void> setCritical({
    required String obraId,
    required Set<String> criticalIds,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'milestones',
        {'es_critico': 0, 'updated_at': _nowIso()},
        where: 'obra_id = ?',
        whereArgs: [obraId],
      );
      if (criticalIds.isEmpty) return;
      final placeholders = List.filled(criticalIds.length, '?').join(',');
      await txn.update(
        'milestones',
        {'es_critico': 1, 'updated_at': _nowIso()},
        where: 'obra_id = ? AND id IN ($placeholders)',
        whereArgs: [obraId, ...criticalIds],
      );
    });
  }

  /// IDs de los hitos que dependen de [predecesorId] (sucesores directos).
  Future<List<String>> successorIds(String predecesorId) async {
    final db = await _db;
    final rows = await db.query(
      'milestone_dependencies',
      columns: ['hito_id'],
      where: 'predecesor_id = ?',
      whereArgs: [predecesorId],
    );
    return rows.map((r) => r['hito_id'] as String).toList();
  }

  /// Mapa hito → predecesores de toda la obra (CU-24 paso 2 en memoria y
  /// base del cálculo de ruta crítica CU-29).
  Future<Map<String, Set<String>>> dependencyMap(String obraId) async {    final db = await _db;
    final milestones = await db.query(
      'milestones',
      columns: ['id'],
      where: 'obra_id = ?',
      whereArgs: [obraId],
    );
    final ids = milestones.map((r) => r['id'] as String).toSet();
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final edges = await db.query(
      'milestone_dependencies',
      where: 'hito_id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    final map = <String, Set<String>>{for (final id in ids) id: {}};
    for (final edge in edges) {
      map[edge['hito_id'] as String]?.add(edge['predecesor_id'] as String);
    }
    return map;
  }
}
