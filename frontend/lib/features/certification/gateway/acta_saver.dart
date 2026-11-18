/// Utilidades del acta de conformidad + guardado por plataforma (CU-54).
///
/// La resolución de plataforma sigue el patrón del feature de evidencia:
/// web (descarga del navegador) o IO (archivo en el dispositivo).
export 'acta_paths.dart';
export 'acta_saver_io.dart' if (dart.library.html) 'acta_saver_web.dart';
