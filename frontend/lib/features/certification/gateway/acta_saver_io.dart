import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'acta_paths.dart';

/// Nombre interno del subdirectorio de caché (fallback sin descargas
/// públicas, p. ej. Android/iOS hasta incorporar el plugin correspondiente).
const String actaCacheDirName = 'constructing_actas';

/// CU-54 paso 4: resuelve el directorio destino del PDF.
///
/// Con [directoryOverride] se apunta a un directorio exacto (tests, o el
/// directorio público cuando se sume path_provider). Sin override se usa el
/// directorio de descargas del usuario cuando el SO lo expone sin
/// dependencias (Windows/macOS/Linux); en móvil queda el caché de la app.
String actaDirectory({String? directoryOverride}) {
  if (directoryOverride != null) return directoryOverride;
  final public = _publicDownloadsDirectory();
  return public ?? '${Directory.systemTemp.path}/$actaCacheDirName';
}

String? _publicDownloadsDirectory() {
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE'];
    return profile == null ? null : '$profile\\Downloads';
  }
  if (Platform.isMacOS || Platform.isLinux) {
    final home = Platform.environment['HOME'];
    return home == null ? null : '$home/Downloads';
  }
  return null;
}

Directory _dirOf(String? directoryOverride) =>
    Directory(actaDirectory(directoryOverride: directoryOverride));

/// CU-54 paso 4: guarda el PDF del acta en el directorio de descargas del
/// dispositivo y devuelve la ruta de la copia offline física.
Future<String> saveActaFile({
  required Uint8List bytes,
  required String fileName,
  String? directoryOverride,
}) async {
  final dir = _dirOf(directoryOverride);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// CU-54 paso 2 (caché local): localiza el PDF del acta del hito. Null si
/// el hito no tiene acta guardada localmente todavía.
Future<Uint8List?> readLocalActa({
  required String hitoId,
  String? directoryOverride,
}) async {
  final dir = _dirOf(directoryOverride);
  final file = File(p.join(dir.path, actaFileName(hitoId)));
  if (!await file.exists()) return null;
  return await file.readAsBytes();
}
