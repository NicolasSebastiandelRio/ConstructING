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
/// Esquema v5: `milestones` (hitos con flag `es_sincronizado` para el motor
/// de sincronización, CU-44), `milestone_dependencies` (aristas predecesor →
/// hito para CU-24 y la ruta crítica CU-29), `evidences` (evidencias
/// periciales georreferenciadas de CU-32/33, con checksum CU-45 y flag
/// `fuera_obra` del CU-35 soft-fail, Sprint 4), `certifications` (sello
/// SHA-256 del acta de conformidad, CU-59, PT-07) y `audit_log` (huella
/// imborrable de las transacciones críticas, CU-60, RNF_S_03).
class LocalDatabase {
  static const String fileName = 'constructing.db';
  static const int schemaVersion = 9;

  static const String createMilestones = '''
CREATE TABLE IF NOT EXISTS milestones(
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
CREATE TABLE IF NOT EXISTS milestone_dependencies(
  hito_id TEXT NOT NULL,
  predecesor_id TEXT NOT NULL,
  PRIMARY KEY (hito_id, predecesor_id)
)''';

  /// Tabla de evidencias periciales (CU-32/CU-33 vía CU-42, RF_03/RF_04).
  /// Nace `es_sincronizado=0`; el CU-44 lo marca al confirmar HTTP 200 y
  /// liberar el caché temporal. `fuera_obra` registra el CU-35 soft-fail
  /// (captura fuera del radio perimetral, Sprint 4).
  static const String createEvidences = '''
CREATE TABLE IF NOT EXISTS evidences(
  id TEXT PRIMARY KEY,
  hito_id TEXT NOT NULL,
  obra_id TEXT NOT NULL,
  tipo TEXT NOT NULL,
  archivo TEXT NOT NULL,
  nota TEXT,
  latitud REAL NOT NULL,
  longitud REAL NOT NULL,
  precision_m REAL NOT NULL,
  fecha_captura TEXT NOT NULL,
  duracion_seg REAL,
  tamano_bytes INTEGER NOT NULL,
  checksum TEXT NOT NULL,
  marca_texto TEXT NOT NULL,
  fuera_obra INTEGER NOT NULL DEFAULT 0,
  es_sincronizado INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''';

  /// Tabla de certificaciones (CU-59, RF_08/RNF_C_05, PT-07): el sello
  /// SHA-256 inmutable del acta PDF consolidada — el documento legal queda
  /// sellado lógicamente contra modificaciones post-firma. Con la doble
  /// firma (CU-57) `firmante2` registra el segundo actor de la conformidad
  /// colegiada (esquema v6).
  static const String createCertifications = '''
CREATE TABLE IF NOT EXISTS certifications(
  acta_id TEXT PRIMARY KEY,
  hito_id TEXT NOT NULL,
  obra_id TEXT NOT NULL,
  hash_sha256 TEXT NOT NULL,
  firmante TEXT,
  firmante2 TEXT,
  created_at TEXT NOT NULL
)''';

  /// Conformidades pendientes de segunda firma (CU-57, doble firma): la
  /// primera firma queda PERSISTIDA en la BD local (borrador de
  /// conformidad) hasta que la otra parte complete la conformidad
  /// colegiada (sellado CU-59) o la descarte. Es la memoria que permite al
  /// Propietario — en otra sesión o rol — encontrar el hito "esperando su
  /// firma" y cerrarlo (el borrador vive solo en el caché local).
  static const String createPendingConformidades = '''
CREATE TABLE IF NOT EXISTS conformidades_pendientes(
  hito_id TEXT PRIMARY KEY,
  obra_id TEXT NOT NULL,
  primer_firmante TEXT NOT NULL,
  primer_firmante_nombre TEXT,
  primer_trazos TEXT NOT NULL,
  primer_metadatos TEXT NOT NULL,
  primer_fecha TEXT NOT NULL,
  created_at TEXT NOT NULL
)''';

  /// Tabla de auditoría (CU-60, RF_08/RNF_S_03): huella permanente e
  /// imborrable de las transacciones críticas (qué actor hizo qué acción,
  /// a qué hora y dónde). Solo INSERT/SELECT: Update/Delete quedan
  /// prohibidos por diseño (RNF_S_03).
  static const String createAuditLog = '''
CREATE TABLE IF NOT EXISTS audit_log(
  id TEXT PRIMARY KEY,
  usuario_id TEXT NOT NULL,
  accion TEXT NOT NULL,
  detalle TEXT,
  obra_id TEXT,
  coordenadas TEXT,
  created_at TEXT NOT NULL
)''';

  /// Bandeja de notificaciones in-app (CU-67..CU-70, RF_10): alertas
  /// dirigidas a un usuario, con su estado de lectura (CU-72) para el badge
  /// de la campana. Esquema v8.
  static const String createNotifications = '''
CREATE TABLE IF NOT EXISTS notifications(
  id TEXT PRIMARY KEY,
  usuario_id TEXT NOT NULL,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  mensaje TEXT NOT NULL,
  obra_id TEXT,
  hito_id TEXT,
  prioridad TEXT NOT NULL DEFAULT 'normal',
  leida INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''';

  /// Preferencias de canal de alerta del usuario (CU-71, RF_10): el booleano
  /// "Recibir por correo" que decide el canal del despacho (CU-67 paso 2).
  static const String createNotificationPreferences = '''
CREATE TABLE IF NOT EXISTS notification_preferences(
  usuario_id TEXT PRIMARY KEY,
  recibir_por_correo INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
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
      // En web la apertura carga el worker + sqlite3.wasm: si eso se cuelga
      // se corta con error visible en vez de un spinner eterno.
      final db = await factory
          .openDatabase(
            fullPath,
            options: OpenDatabaseOptions(
              version: schemaVersion,
              onCreate: (db, version) async {
                await db.execute(createMilestones);
                await db.execute(createMilestoneDependencies);
                await db.execute(createEvidences);
                await db.execute(createCertifications);
                await db.execute(createAuditLog);
                await db.execute(createPendingConformidades);
                await db.execute(createNotifications);
                await db.execute(createNotificationPreferences);
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_milestones_obra ON milestones(obra_id)');
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_dependencies_hito ON milestone_dependencies(hito_id)');
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_evidences_hito ON evidences(hito_id)');
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_certifications_hito ON certifications(hito_id)');
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_audit_log_obra ON audit_log(obra_id)');
                await db.execute(
                    'CREATE INDEX IF NOT EXISTS idx_notifications_usuario ON notifications(usuario_id)');
              },
              onUpgrade: (db, oldVersion, newVersion) async {
                // Migraciones por RANGO de versión (nunca por igualdad): una
                // BD que salta varias versiones a la vez —p. ej. la de un
                // navegador que quedó en v5 y abre el esquema v9— debe recibir
                // TODAS las estructuras intermedias. Con comparaciones `==` el
                // salto omitía la creación de tablas y rompía el flujo (CU-57
                // fallaba con "no such table: conformidades_pendientes").
                // Las creaciones son idempotentes (IF NOT EXISTS) y las
                // columnas se agregan de forma tolerante, así re-ejecutar la
                // migración sobre una BD ya migrada no rompe.
                if (oldVersion < 2) {
                  await db.execute(createEvidences);
                  await db.execute(
                      'CREATE INDEX IF NOT EXISTS idx_evidences_hito ON evidences(hito_id)');
                }
                if (oldVersion < 4) {
                  await db.execute(createCertifications);
                  await db.execute(
                      'CREATE INDEX IF NOT EXISTS idx_certifications_hito ON certifications(hito_id)');
                }
                if (oldVersion < 5) {
                  await db.execute(createAuditLog);
                  await db.execute(
                      'CREATE INDEX IF NOT EXISTS idx_audit_log_obra ON audit_log(obra_id)');
                }
                // v6 → v7 (CU-57): borradores de conformidad colegiada.
                if (oldVersion < 7) {
                  await db.execute(createPendingConformidades);
                }
                // v7 → v8 (CU-67..CU-72): bandeja y preferencias de alerta.
                if (oldVersion < 8) {
                  await db.execute(createNotifications);
                  await db.execute(createNotificationPreferences);
                  await db.execute(
                      'CREATE INDEX IF NOT EXISTS idx_notifications_usuario ON notifications(usuario_id)');
                }
                // Columnas agregadas después de la creación de cada tabla:
                // tolerantes a que ya existan (idempotentes entre saltos).
                await _agregarColumnaSiFalta(
                    db, 'evidences', 'fuera_obra', 'INTEGER NOT NULL DEFAULT 0');
                await _agregarColumnaSiFalta(
                    db, 'certifications', 'firmante2', 'TEXT');
                await _agregarColumnaSiFalta(db, 'conformidades_pendientes',
                    'primer_firmante_nombre', 'TEXT');
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
      _db = db;
      return db;
    } catch (e) {
      // RNF_C_02: alertar de inmediato (la UI muestra este mensaje).
      throw const CacheStorageException(
        'No se pudo guardar localmente. Verifique el espacio disponible en el dispositivo.',
      );
    }
  }

  /// Agrega una columna de forma TOLERANTE: si ya existe (porque la tabla se
  /// acaba de crear con el esquema nuevo) el error se ignora. Es lo que hace
  /// idempotente la migración cuando una BD salta varias versiones.
  static Future<void> _agregarColumnaSiFalta(
    Database db,
    String tabla,
    String columna,
    String tipo,
  ) async {
    try {
      await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $tipo');
    } catch (_) {
      // La columna ya está presente en esta BD: nada que hacer.
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
