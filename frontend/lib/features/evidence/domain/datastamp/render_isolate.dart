import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

import 'datastamp_font.dart';

/// CU-36 (impl. IO — móviles/desktop): renderizado de la marca de agua en un
/// ISOLATE de fondo.
///
/// RNF_E_01: el renderizado debe ser < 300 ms y NUNCA bloquear el UI
/// isolate: decodificar y re-encodear una foto de cámara (varias MP) en el
/// hilo principal congelaba la app → ANR "isn't responding" en Android.
/// Todo el trabajo pesado (decode → banda → texto → encode) corre en
/// `Isolate.run`; el UI isolate solo consume el resultado.
Future<Uint8List> renderStamp(Uint8List sourceBytes, List<String> lines) {
  return Isolate.run(() => _render(sourceBytes, lines));
}

Uint8List _render(Uint8List sourceBytes, List<String> lines) {
  final image = im.findDecoderForData(sourceBytes)?.decode(sourceBytes);
  if (image == null) {
    throw StateError('Formato no procesable para estampar la marca (CU-36).');
  }

  // Banda de alto contraste en la base (paso 2).
  final font = image.width < 640 ? arial14 : arial24;
  final lineHeightPx = (font.lineHeight * 1.25).round();
  final textHeight = lines.length * lineHeightPx;
  final bandHeight = (textHeight + 24).clamp(0, image.height);
  final bandTop = (image.height - bandHeight).clamp(0, image.height);
  im.fillRect(
    image,
    x1: 0,
    y1: bandTop,
    x2: image.width - 1,
    y2: image.height - 1,
    color: im.ColorUint8.rgba(0, 0, 0, 0xB3),
  );

  // Líneas de texto blanco con sombra simulada (pasos 3-4).
  var y = bandTop + 12;
  const marginX = 16;
  for (final line in lines) {
    im.drawString(
      image,
      line,
      font: font,
      x: marginX + 1,
      y: y + 1,
      color: im.ColorUint8.rgb(0, 0, 0),
    );
    im.drawString(
      image,
      line,
      font: font,
      x: marginX,
      y: y,
      color: im.ColorUint8.rgb(255, 255, 255),
    );
    y += lineHeightPx;
  }

  // Re-encode JPEG del buffer estampado (mismo umbral de calidad del
  // picker, CU-36/CU-45: el checksum se calcula sobre ESTOS bytes).
  return im.encodeJpg(image, quality: 88);
}
