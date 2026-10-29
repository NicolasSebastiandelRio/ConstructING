import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// CU-36 (impl. WEB): render de la marca con dart:ui (en el navegador no
/// hay Isolate.run; el canvas del navegador no genera ANR como Android).
Future<Uint8List> renderStamp(Uint8List sourceBytes, List<String> lines) async {
  final source = await ui.instantiateImageCodec(sourceBytes);
  final frame = await source.getNextFrame();
  final image = frame.image;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(image, ui.Offset.zero, ui.Paint());

  // Banda de alto contraste en la base (paso 2).
  final fontSize =
      (24.0).clamp(11.0, 26.0).toDouble();
  final textHeight = lines.length * fontSize * 1.35;
  final bandHeight = textHeight + 24.0;
  final bandTop = (image.height - bandHeight).clamp(0.0, image.height.toDouble());
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
  textPainter.layout(
    maxWidth: (image.width - 32.0).clamp(0.0, double.infinity).toDouble(),
  );
  textPainter.paint(canvas, ui.Offset(16, image.height - textHeight - 12));

  final picture = recorder.endRecording();
  final unified = await picture.toImage(image.width, image.height);
  final data = await unified.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  unified.dispose();
  return data!.buffer.asUint8List();
}
