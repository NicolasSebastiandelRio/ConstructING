import 'package:sqflite_common/sqlite_api.dart';

import 'db_factory.dart';

/// Error de almacenamiento local con mensaje apto para la UI.
///
/// RNF_C_02 (Integridad Local): si el guardado falla (p. ej. falta de
/// espacio), se alerta inmediatamente en lugar de perder el dato en silencio.
class CacheStorageException implements Exception {
  final String message;

  const CacheStorageException(this.message);

  @override
  String toString() => 'CacheStorageException: $message';
}

/// Base de datos local del dispositivo (CU-42: Caché Local, RF_06).
///
/// La factory se resuelve por plataforma (`db_factory.dart`): SQLite nativo
/// en móvil, IndexedDB en web (misma API). En tests se inyecta
/// `sqflite_common_ffi` en memoria.
///
/// Esquema v1: `milestones` (hitos con flag `es_sincronizado` para el motor
/// de sincronización del Sprint 4, CU-44) y `milestone_dependencies`
/// (aristas predecesor → hito para CU-24 y la ruta crítica CU-29).
class LocalDatabase {
  static const String fileName = 'constructing.db';
  static const int schemaVersion = 1;

  static const String createMilestones = '''
CREATE TABLE milestones(
  id TEXT PRIMARY KEY,
  obra_id TEXT NOT NULL,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  duracion_dias INTEGER NOT NULL DEFAULT 1,
  estado TEXT NOT NULL DEFAULT 'Pendiente',
  es_critico INTEGER NOT NULL DEFAULT 0,
  es_sincronizado INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''';

  static const String createMilestoneDependencies = '''
CREATE TABLE milestone_dependencies(
  hito_id TEXT NOT NULL,
  predecesor_id TEXT NOT NULL,
  PRIMARY KEY (hito_id, predecesor_id)
)''';

  Database? _db;

  /// Instancia lazy compartida por la app.
  Future<Database> get database async => _db ??= await openLocalDatabase();

  /// Abre (y crea/migra si hace falta) la BD. Acepta overrides para tests.
  Future<Database> openLocalDatabase({
    DatabaseFactory? factoryOverride,
    String? nameOverride,
  }) async {
    final factory = factoryOverride ?? platformDatabaseFactory;
    final name = nameOverride ?? fileName;
    final fullPath = name == inMemoryDatabasePath
        ? name
        : factoryOverride != null
            ? name
            : await resolveDatabasePath(name);
    try {
      final db = await factory.openDatabase(
        fullPath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: (db, version) async {
            await db.execute(createMilestones);
            await db.execute(createMilestoneDependencies);
            await db.execute(
                'CREATE INDEX idx_milestones_obra ON milestones(obra_id)');
            await db.execute(
                'CREATE INDEX idx_dependencies_hito ON milestone_dependencies(hito_id)');
          },
        ),
      );
      _db = db;
      return db;
    } catch (e) {
      // RNF_C_02: alertar de inmediato (la UI muestra este mensaje).
      throw CacheStorageException(
        'No se pudo guardar localmente. Verifique el espacio disponible en el dispositivo.',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
