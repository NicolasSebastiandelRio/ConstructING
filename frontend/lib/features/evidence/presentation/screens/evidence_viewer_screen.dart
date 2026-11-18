import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/evidence.dart';
import '../widgets/evidence_mismatch_banner.dart';
import '../../gateway/video_controller_platform.dart';

/// Creador del controlador de video según plataforma (inyectable en tests).
///
/// Web: el path del picker es una `blob:` URL → se reproduce como red.
/// Móvil/desktop: path de archivo real → `VideoPlayerController.file`.
/// (La resolución se resuelve en `gateway/video_controller_platform.dart`
/// con exports condicionales para no importar `dart:io` en web.)
typedef VideoControllerFactory = VideoPlayerController Function(
  String source,
  {
  required bool isLocalFile,
});

/// Visor de evidencia guardada (CU-40 paso 3, Sprint 4): previsualización
/// de la foto/video al tocar su tarjeta en la galería.
///
/// Orden de fuente del binario:
/// 1. Caché local ([Evidence.archivo]) mientras no se liberó (CU-44).
/// 2. Nube vía `GET /evidences/:id/file` cuando ya se liberó el caché.
///
/// Si ninguna fuente está disponible (p. ej. la evidencia nunca llegó a
/// sincronizarse y el caché se liberó) se informa sin romper la vista.
/// Si la captura no coincidió con el ancla (CU-35 soft-fail), la etiqueta
/// roja de no coincidencia se estampa sobre la imagen.
class EvidenceViewerScreen extends StatefulWidget {
  final Evidence evidence;

  /// Lector de bytes del archivo local (inyectable en tests).
  final Future<List<int>> Function(String path)? localBytesReader;

  /// Descarga del binario desde la nube (inyectable en tests).
  final Future<List<int>> Function(String id)? remoteBytesLoader;

  /// Fábrica del controlador de video (inyectable en tests).
  final VideoControllerFactory? videoControllerFactory;

  const EvidenceViewerScreen({
    super.key,
    required this.evidence,
    this.localBytesReader,
    this.remoteBytesLoader,
    this.videoControllerFactory,
  });

  @override
  State<EvidenceViewerScreen> createState() => _EvidenceViewerScreenState();
}

enum _ViewerSource { local, nube }

class _EvidenceViewerScreenState extends State<EvidenceViewerScreen> {
  Uint8List? _bytes;
  VideoPlayerController? _videoController;
  String? _error;
  _ViewerSource? _source;
  bool _loading = true;

  bool get _isVideo => widget.evidence.esVideo;

  VideoPlayerController _buildVideoController(
    String source, {
    required bool isLocalFile,
  }) =>
      (widget.videoControllerFactory ?? _defaultVideoController)(
        source,
        isLocalFile: isLocalFile,
      );

  static VideoPlayerController _defaultVideoController(
    String source, {
    required bool isLocalFile,
  }) {
    if (isLocalFile) {
      return localVideoControllerOf(source);
    }
    return VideoPlayerController.networkUrl(Uri.parse(source));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final evidence = widget.evidence;
    Uint8List? bytes;
    _ViewerSource? source;

    // 1) Caché local: el archivo temporal del picker aún existe.
    if (evidence.archivo.trim().isNotEmpty) {
      try {
        final reader = widget.localBytesReader ??
            (String path) => XFile(path).readAsBytes();
        bytes = Uint8List.fromList(await reader(evidence.archivo));
        source = _ViewerSource.local;
      } catch (_) {
        // El archivo local ya no existe (caché liberado o blob expirado):
        // se intenta la nube antes de rendirse.
        source = null;
      }
    }

    // 2) Nube: binario respaldado por el CU-44/CU-45.
    bytes ??= await _loadFromCloud();

    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _error = 'No se pudo previsualizar la evidencia. '
            'Su archivo local ya se liberó y aún no está '
            'sincronizada en la nube (CU-44).';
        _loading = false;
      });
      return;
    }
    if (_isVideo) {
      final ok = await _initVideo(bytes);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error =
              'No se pudo reproducir el video de la evidencia.';
          _loading = false;
        });
        return;
      }
    }
    setState(() {
      _bytes = bytes;
      _source = source ?? _ViewerSource.nube;
      _loading = false;
    });
  }

  /// Descarga del binario desde la nube (null si falla: el error se
  /// informa sin romper la vista).
  Future<Uint8List?> _loadFromCloud() async {
    try {
      final loader = widget.remoteBytesLoader ?? _defaultRemoteLoader;
      final bytes = await loader(widget.evidence.id);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _defaultRemoteLoader(String id) async {
    final dio = DioClient().dio;
    final response = await dio.get<List<int>>(
      '/evidences/$id/file',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<bool> _initVideo(Uint8List bytes) async {
    VideoPlayerController? controller;
    try {
      if (widget.evidence.archivo.trim().isNotEmpty &&
          _source == _ViewerSource.local) {
        controller = _buildVideoController(
          widget.evidence.archivo,
          isLocalFile: true,
        );
      } else {
        // Sin archivo local: streaming directo desde el servidor.
        controller = _buildVideoController(
          '${DioClient.baseUrl}/evidences/${widget.evidence.id}/file',
          isLocalFile: false,
        );
      }
      await controller.initialize();
    } catch (_) {
      await controller?.dispose();
      return false;
    }
    _videoController = controller;
    return true;
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final evidence = widget.evidence;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          '${evidence.tipo.label.toUpperCase()} · ${_fechaText()}',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
        iconTheme: const IconThemeData(color: AppTheme.accentGold),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentGold))
          : _error != null
              ? _errorView()
              : _mediaView(),
    );
  }

  String _fechaText() {
    final f = widget.evidence.fechaCaptura;
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/${f.year}';
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: AppTheme.primaryRed, size: 56),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaView() {
    final evidence = widget.evidence;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isVideo ? _videoView() : _photoView(),
              ),
              // CU-35 soft-fail: etiqueta roja permanente sobre la imagen.
              if (evidence.fueraDeObra)
                const EvidenceLocationMismatchBanner(),
            ],
          ),
          const SizedBox(height: 12),
          // Origen del binario mostrado (transparencia del visor).
          Text(
            _source == _ViewerSource.local
                ? 'Fuente: caché local del dispositivo'
                : 'Fuente: nube (binario sincronizado CU-44/CU-45)',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Text(
            evidence.marcaTexto,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _photoView() => InteractiveViewer(
        maxScale: 4,
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
        ),
      );

  Widget _videoView() {
    final controller = _videoController!;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio == 0
          ? 16 / 9
          : controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(controller),
          // CU-36 (video): la marca pericial se presenta como overlay de
          // reproducción (el códec no es editable en memoria), igual que
          // en la preview de captura.
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                widget.evidence.marcaTexto,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
          _VideoControls(controller: controller),
        ],
      ),
    );
  }
}

/// Controles mínimos del video (play/pausa + posición).
class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoControls({required this.controller});

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
            },
          ),
          Expanded(
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: AppTheme.accentGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
