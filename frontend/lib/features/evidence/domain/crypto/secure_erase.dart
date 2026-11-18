/// CU-59/PT-07 (RNF_C_05): módulo de BORRADO SEGURO del binario local de
/// evidencia.
///
/// Tras confirmarse la sincronización (CU-44), el binario liberado del
/// caché local (des-referencia del registro ya volcado) se destruye con
/// RE-ESCRITURA CON PATRÓN antes de la eliminación del archivo: un simple
/// restore-file no puede recuperar el contenido.
///
/// Resolución por plataforma (mismo patrón del acta, CU-54):
/// - IO (móvil/desktop): sobreescritura multi-pase + eliminación.
/// - Web: el navegador controla el almacenamiento; el componente queda
///   como des-referencia (la liberación real la realiza el navegador).
export 'secure_erase_io.dart' if (dart.library.html) 'secure_erase_web.dart';
