import 'package:video_player/video_player.dart';

/// Versión web: el path del picker es una `blob:` URL y el controlador de
/// video la reproduce como fuente de red (no existe `dart:io` en web).
VideoPlayerController localVideoControllerOf(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
