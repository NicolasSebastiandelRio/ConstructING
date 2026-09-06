import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Factory SQLite sobre IndexedDB (navegador). Misma API que en móvil.
DatabaseFactory get platformDatabaseFactory => databaseFactoryFfiWeb;

/// En web (IndexedDB) el nombre basta, sin paths de archivo.
Future<String> resolveDatabasePath(String name) async => name;
