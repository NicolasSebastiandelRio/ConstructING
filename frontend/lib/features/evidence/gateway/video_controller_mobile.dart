import 'dart:io';

import 'package:video_player/video_player.dart';

/// Versión móvil/desktop: el path del picker es un archivo real en disco.
VideoPlayerController localVideoControllerOf(String path) =>
    VideoPlayerController.file(File(path));
