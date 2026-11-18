import 'package:video_player/video_player.dart';

import 'video_controller_platform.dart';

/// Lector de la duración real del video (CU-38 paso 2: duración del
/// metadato). Inyectable en tests; la implementación de producción abre
/// el archivo con `video_player` solo para leer el metadato y lo libera.
///
/// Devuelve null si la duración no es legible (CU-38: "duración
/// desconocida": el validador la trata como cumplimiento, ya que la
/// grabación nativa nace acotada por debajo del límite).
typedef VideoDurationReader = Future<double?> Function(String path);

Future<double?> readVideoDuration(String path) async {
  VideoPlayerController? controller;
  try {
    controller = localVideoControllerOf(path);
    await controller.initialize();
    return controller.value.duration.inMilliseconds / 1000.0;
  } catch (_) {
    // Sin metadato legible (buffer no procesable o plataforma sin soporte):
    // el validador trata null como cumplimiento (CU-38).
    return null;
  } finally {
    try {
      await controller?.dispose();
    } catch (_) {
      // La liberación puede fallar si el player no llegó a inicializarse;
      // solo se pretendía leer metadata (buffer del video intacto).
    }
  }
}
