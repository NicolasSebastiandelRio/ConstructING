import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/storage/local_database.dart';
import '../../domain/entities/app_notification.dart';

/// Acceso a la bandeja de notificaciones y las preferencias de alerta en la
/// BD local (CU-67..CU-72, RF_10).
///
/// Escrituras en transacción (RNF_C_02). La consulta de bandeja es
/// descendente por fecha (CU-70 paso 2: más recientes primero).
class NotificationLocalDataSource {
  NotificationLocalDataSource({required LocalDatabase localDatabase})
      : _localDatabase = localDatabase;

  final LocalDatabase _localDatabase;

  Future<Database> get _db => _localDatabase.database;

  /// Persiste una alerta. Idempotente por `id` (reintentos de sincronización
  /// no duplican la bandeja).
  Future<AppNotification> save(AppNotification notification) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'notifications',
        notification.toLocalDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return notification;
  }

  /// CU-70 paso 2: todas las alertas dirigidas al usuario, más recientes
  /// primero (descendente).
  Future<List<AppNotification>> listByUsuario(String usuarioId) async {
    final db = await _db;
    final rows = await db.query(
      'notifications',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AppNotification.fromLocalDb).toList();
  }

  /// CU-72 paso 4: insumo del badge de la campana (alertas no leídas).
  Future<int> countUnread(String usuarioId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM notifications '
      'WHERE usuario_id = ? AND leida = 0',
      [usuarioId],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  /// CU-72 paso 2: marca la alerta como leída. Devuelve la fila actualizada o
  /// null si el id no existe en la bandeja local.
  Future<AppNotification?> markAsRead(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'notifications',
        {'leida': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    final rows = await db.query(
      'notifications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppNotification.fromLocalDb(rows.first);
  }

  /// CU-69 (idempotencia del cron diario): ¿ya existe una alerta de retraso
  /// para esta obra creada a partir de [desde]?
  Future<bool> existsRetrasoSince(String obraId, DateTime desde) async {
    final db = await _db;
    final rows = await db.query(
      'notifications',
      columns: ['id'],
      where: 'obra_id = ? AND tipo = ? AND created_at >= ?',
      whereArgs: [obraId, NotificationTipo.retraso.code,
        desde.toUtc().toIso8601String()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// CU-71: preferencias del usuario. Si no hay fila devuelve el default
  /// (recibir por correo activo) sin escribir.
  Future<NotificationPreferences> getPreferences(String usuarioId) async {
    final db = await _db;
    final rows = await db.query(
      'notification_preferences',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return NotificationPreferences(usuarioId: usuarioId);
    }
    return NotificationPreferences.fromLocalDb(rows.first);
  }

  /// CU-71 paso 2: actualiza el valor booleano "Recibir por correo".
  Future<NotificationPreferences> savePreferences(
    NotificationPreferences preferences,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'notification_preferences',
        preferences.toLocalDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return preferences;
  }
}
