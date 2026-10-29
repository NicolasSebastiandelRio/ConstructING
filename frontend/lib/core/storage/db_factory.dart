// Selector de factory de BD local por plataforma (import condicional).
//
// - IO (móvil/desktop): `package:sqflite` (SQLite nativo del plugin).
// - Web: `sqflite_common_ffi_web` (SQLite sobre IndexedDB, misma API).
export 'db_factory_io.dart' if (dart.library.html) 'db_factory_web.dart';
