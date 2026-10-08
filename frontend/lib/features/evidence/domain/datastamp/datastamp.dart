import 'dart:typed_data';

import 'render_isolate.dart'
    if (dart.library.js_interop) 'render_web.dart';

/// CU-36 (Estampar Marca de agua Inalterable, RF_03/RNF_S_04).
///
/// Renderiza una capa de texto de alto contraste (DataStamp) sobre el
/// archivo visual: coordenadas, fecha y hora de la captura (pasos 2-4:
/// sobrescribe el buffer en memoria con el archivo unificado y lo retorna).
///
/// RNF_E_01: el renderizado debe demorar menos de 300 ms y NUNCA bloquear
/// el UI isolate (impl. IO corre en background isolate — sin ANR Android).
class DataStamp {
  /// Límite de rendimiento de la poscondición de la spec.
  static const Duration renderBudget = Duration(milliseconds: 300);

  /// Construye las líneas del DataStamp (paso 2: capa de alto contraste).
  ///
  /// Formato pericial: app + fecha/hora, coordenadas con precisión y nota
  /// técnica si la hay (CU-39). Unificado en un texto compacto.
  static List<String> buildLines({
    required DateTime fechaCaptura,
    required double latitud,
    required double longitud,
    required double precisionMetros,
    String? nota,
    String hitoNombre = '',
    String obraNombre = '',
  }) {
    final fecha =
        '${_pad(fechaCaptura.day)}/${_pad(fechaCaptura.month)}/${fechaCaptura.year}';
    final hora = '${_pad(fechaCaptura.hour)}:${_pad(fechaCaptura.minute)}';
    return [
      'ConstructING · $fecha $hora',
      'Lat: ${latitud.toStringAsFixed(6)}  Lon: ${longitud.toStringAsFixed(6)} '
          '(±${precisionMetros.round()} m)',
      if (hitoNombre.trim().isNotEmpty) 'Hito: ${hitoNombre.trim()}',
      if (nota != null && nota.trim().isNotEmpty) 'Nota: ${nota.trim()}',
    ];
  }

  /// Une las líneas en el texto de marca que se persiste como atributo.
  static String composeText(List<String> lines) => lines.join(' | ');

  /// Renderiza [lines] sobre [sourceBytes] y retorna el archivo unificado
  /// (pasos 2-4: sobrescribe el buffer en memoria con el archivo unificado).
  ///
  /// Impl. por plataforma: IO (móvil/desktop) en `Isolate.run` con el
  /// paquete `image` (JPEG out, RNF_E_01, sin ANR); web con dart:ui (PNG).
  static Future<Uint8List> renderOverImage({
    required Uint8List sourceBytes,
    required List<String> lines,
  }) {
    final stopwatch = Stopwatch()..start();
    return renderStamp(sourceBytes, lines).then((result) {
      debugAssertWithinBudget(stopwatch.elapsed);
      return result;
    });
  }

  static void debugAssertWithinBudget(Duration elapsed) {
    assert(() {
      if (elapsed > renderBudget) {
        // ignore: avoid_print
        print(
            'DataStamp RNF_E_01: render tardó ${elapsed.inMilliseconds} ms '
            '(> 300 ms)');
      }
      return true;
    }());
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
