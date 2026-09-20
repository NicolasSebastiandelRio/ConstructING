import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// CU-36 (Estampar Marca de agua Inalterable, RF_03/RNF_S_04).
///
/// Renderiza una capa de texto de alto contraste (DataStamp) sobre el
/// archivo visual: coordenadas, fecha y hora de la captura (pasos 2-4:
/// sobrescribe el buffer en memoria con el archivo unificado y lo retorna).
///
/// RNF_E_01: el renderizado debe demorar menos de 300 ms.
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

  /// Renderiza [lines] sobre [sourceBytes] y retorna el PNG unificado
  /// (pasos 2-4: sobrescribe el buffer en memoria con el archivo unificado).
  ///
  /// Para video (CU-33 paso 4, primer frame) el códec de video no es
  /// editable en memoria con dart:ui; la marca se persiste como atributo
  /// ([composeText]) y se presenta como overlay en la reproducción.
  static Future<Uint8List> renderOverImage({
    required Uint8List sourceBytes,
    required List<String> lines,
  }) async {
    final stopwatch = Stopwatch()..start();

    final source = await ui.instantiateImageCodec(sourceBytes);
    final frame = await source.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());

    // Banda de alto contraste en la base (paso 2).
    final fontSize =
        math.min(26.0, math.max(11.0, image.width * 0.028)).toDouble();
    final textHeight = lines.length * fontSize * 1.35;
    final bandHeight = textHeight + 24.0;
    final bandTop = math.max(0.0, image.height - bandHeight);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, bandTop, image.width.toDouble(), bandHeight),
        const ui.Radius.circular(0),
      ),
      ui.Paint()..color = const ui.Color(0xB3000000),
    );

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: lines.join('\n'),
      style: TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        height: 1.25,
        shadows: const [
          ui.Shadow(color: ui.Color(0xFF000000), blurRadius: 2),
        ],
      ),
    );
    textPainter.layout(maxWidth: image.width - 32.0);
    textPainter.paint(
      canvas,
      ui.Offset(16, image.height - textHeight - 12),
    );

    final picture = recorder.endRecording();
    final unified = await picture.toImage(image.width, image.height);
    final data = await unified.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    unified.dispose();

    // RNF_E_01 (medición del presupuesto de renderizado).
    final elapsed = stopwatch.elapsed;
    debugAssertWithinBudget(elapsed);

    return data!.buffer.asUint8List();
  }

  static void debugAssertWithinBudget(Duration elapsed) {
    assert(() {
      if (elapsed > renderBudget) {
        // ignore: avoid_print
        print('DataStamp RNF_E_01: render tardó ${elapsed.inMilliseconds} ms (> 300 ms)');
      }
      return true;
    }());
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
