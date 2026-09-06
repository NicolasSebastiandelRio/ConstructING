import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

/// Factory nativa del plugin sqflite (Android/iOS/macOS/desktop).
DatabaseFactory get platformDatabaseFactory => sqflite.databaseFactory;

/// Resuelve el path del archivo de BD en el directorio de databases.
Future<String> resolveDatabasePath(String name) async {
  final dir = await sqflite.getDatabasesPath();
  return p.join(dir, name);
}
