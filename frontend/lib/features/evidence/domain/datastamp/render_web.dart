import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'stamp_layout.dart';

/// CU-36 (impl. WEB): render de la marca con dart:ui (en el navegador no
/// hay Isolate.run; el canvas del navegador no genera ANR como Android).
///
/// La tipografía y la banda se escalan con el **tamaño real de la imagen**:
/// antes la fuente estaba fija en 24 px, así que al recortar una foto
/// (imagen chica) el texto la tapaba por completo. Además se limita la banda
/// a una fracción del alto para que la marca nunca oculte la evidencia.
Future<Uint8List> renderStamp(Uint8List sourceBytes, List<String> lines) async {
  final source = await ui.instantiateImageCodec(sourceBytes);
  final frame = await source.getNextFrame();
  final image = frame.image;

  final ancho = image.width.toDouble();
  final alto = image.height.toDouble();

  // Escala tipográfica relativa al lado menor (ver StampLayout).
  var fontSize = StampLayout.fontSizeFor(image.width, image.height);
  final pad = StampLayout.paddingFor(image.width, image.height);

  final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
  void layoutText() {
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
    textPainter.layout(maxWidth: math.max(1.0, ancho - pad * 2));
  }

  layoutText();
  // La banda no puede ocupar más de la fracción permitida del alto: si el
  // texto no entra, se reduce la fuente hasta el mínimo legible.
  final maxBand = StampLayout.maxBandHeight(image.height);
  var guardas = 0;
  while (textPainter.height + pad * 2 > maxBand &&
      fontSize > StampLayout.minFontSize &&
      guardas < 12) {
    fontSize *= 0.88;
    layoutText();
    guardas++;
  }

  final bandHeight =
      math.min(textPainter.height + pad * 2, alto).clamp(0.0, alto);
  final bandTop = math.max(0.0, alto - bandHeight);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(image, ui.Offset.zero, ui.Paint());

  // Banda de alto contraste en la base (paso 2).
  canvas.drawRect(
    ui.Rect.fromLTWH(0, bandTop, ancho, bandHeight),
    ui.Paint()..color = const ui.Color(0xB3000000),
  );
  textPainter.paint(
    canvas,
    ui.Offset(pad, bandTop + (bandHeight - textPainter.height) / 2),
  );

  final picture = recorder.endRecording();
  final unified = await picture.toImage(image.width, image.height);
  final data = await unified.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  unified.dispose();
  return data!.buffer.asUint8List();
}
