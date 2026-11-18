import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/editing/evidence_edit_ops.dart';

/// Editor de la evidencia fotográfica (RF_03): permite **girar** y
/// **recortar** la imagen antes de estampar la marca pericial.
///
/// El área de trabajo está centrada y acotada (nunca ocupa toda la pantalla):
/// el usuario hace zoom/arrastra la foto dentro del marco y lo que queda
/// visible en el marco es lo que se conserva al aplicar. El giro se ofrece en
/// pasos de 90°.
///
/// Devuelve por `Navigator.pop` los bytes editados (`Uint8List`) o `null` si
/// el usuario cancela.
class EvidenceEditorScreen extends StatefulWidget {
  /// Bytes originales de la captura (sin editar, sin marca).
  final Uint8List bytes;

  const EvidenceEditorScreen({super.key, required this.bytes});

  @override
  State<EvidenceEditorScreen> createState() => _EvidenceEditorScreenState();
}

class _EvidenceEditorScreenState extends State<EvidenceEditorScreen> {
  late final Uint8List _original = widget.bytes;

  /// Giro acumulado en cuartos de vuelta (0..3, sentido horario).
  int _turns = 0;

  /// Imagen de trabajo: el original ya girado (lo que se ve y se recorta).
  EditedImage? _working;

  bool _busy = true;
  final TransformationController _transform = TransformationController();

  /// Tamaño del marco de recorte (se fija en el build y se usa al aplicar).
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    // La primera vista de trabajo es el original decodificado (giro 0).
    final inicial = EvidenceEditOps.rotate(_original, 0);
    _working = inicial;
    _busy = inicial == null;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Gira 90° (sentido horario si [delta] > 0) partiendo SIEMPRE del original
  /// para no acumular pérdida por recompresión.
  Future<void> _rotate(int delta) async {
    if (_busy) return;
    final turns = (_turns + delta) % 4;
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    final siguiente = EvidenceEditOps.rotate(_original, turns);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (siguiente != null) {
        _turns = turns;
        _working = siguiente;
        _transform.value = Matrix4.identity();
      }
    });
  }

  /// Rectángulo a conservar, en píxeles de la imagen de trabajo.
  ///
  /// Lo visible del marco se invierte con la transformación del
  /// `InteractiveViewer` y se convierte a coordenadas de imagen descontando
  /// el letterboxing del `BoxFit.contain`.
  Rect _cropRect(EditedImage working) {
    final vw = _viewport.width;
    final vh = _viewport.height;
    if (vw <= 0 || vh <= 0) {
      return Rect.fromLTWH(
          0, 0, working.width.toDouble(), working.height.toDouble());
    }
    // Letterboxing: el marco y la imagen comparten proporción, pero se
    // calcula explícitamente para no depender del redondeo.
    final escala = math.min(vw / working.width, vh / working.height);
    final dw = working.width * escala;
    final dh = working.height * escala;
    final dx = (vw - dw) / 2;
    final dy = (vh - dh) / 2;

    final inversa = Matrix4.inverted(_transform.value);
    final esquinas = <Offset>[
      Offset.zero,
      Offset(vw, 0),
      Offset(0, vh),
      Offset(vw, vh),
    ].map((p) => MatrixUtils.transformPoint(inversa, p)).toList();

    final izq = esquinas.map((c) => c.dx).reduce(math.min);
    final der = esquinas.map((c) => c.dx).reduce(math.max);
    final arr = esquinas.map((c) => c.dy).reduce(math.min);
    final aba = esquinas.map((c) => c.dy).reduce(math.max);

    final x = ((izq - dx) / escala).clamp(0.0, working.width - 1.0);
    final y = ((arr - dy) / escala).clamp(0.0, working.height - 1.0);
    final ancho = ((der - dx) / escala - x)
        .clamp(1.0, working.width.toDouble() - x);
    final alto = ((aba - dy) / escala - y)
        .clamp(1.0, working.height.toDouble() - y);

    return Rect.fromLTWH(x, y, ancho, alto);
  }

  Future<void> _apply() async {
    final working = _working;
    if (working == null || _busy) return;
    final rect = _cropRect(working);
    // Un recorte por debajo de 16 px no es una fotografía usable.
    if (rect.width < 16 || rect.height < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El recorte es demasiado pequeño: amplíe la imagen.'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    final editada = EvidenceEditOps.rotateAndCrop(
      original: _original,
      quarterTurns: _turns,
      x: rect.left.round(),
      y: rect.top.round(),
      width: rect.width.round(),
      height: rect.height.round(),
    );
    if (!mounted) return;
    if (editada == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo procesar la imagen.'),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
      return;
    }
    Navigator.of(context).pop(editada.bytes);
  }

  @override
  Widget build(BuildContext context) {
    final working = _working;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'RECORTAR Y GIRAR',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: AppTheme.accentGold),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(null),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: working == null
          ? const Center(
              child: Text('No se pudo abrir la imagen.',
                  style: TextStyle(color: AppTheme.primaryRed)),
            )
          : SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Arrastre y haga zoom para encuadrar. Lo que queda dentro '
                    'del marco es lo que se conserva.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  // Área de trabajo CENTRADA y ACOTADA (no ocupa toda la
                  // pantalla): mantiene la proporción de la imagen y se
                  // limita a un cuadrado máximo de 420 lógicos.
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final limite = math.min(
                            math.min(constraints.maxWidth, constraints.maxHeight) -
                                24,
                            420.0,
                          );
                          final aspecto = working.width / working.height;
                          final vw = aspecto >= 1 ? limite : limite * aspecto;
                          final vh = aspecto >= 1 ? limite / aspecto : limite;
                          _viewport = Size(vw, vh);
                          return SizedBox(
                            width: vw,
                            height: vh,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: InteractiveViewer(
                                    transformationController: _transform,
                                    minScale: 1,
                                    maxScale: 6,
                                    child: SizedBox(
                                      width: vw,
                                      height: vh,
                                      child: Image.memory(
                                        working.bytes,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  ),
                                ),
                                // Marco de recorte (lo visible se conserva).
                                IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: AppTheme.accentGold,
                                          width: 2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(
                          color: AppTheme.accentGold, strokeWidth: 2),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          key: const Key('editor_rotate_left'),
                          tooltip: 'Girar 90° a la izquierda',
                          onPressed: _busy ? null : () => _rotate(-1),
                          icon: const Icon(Icons.rotate_left,
                              color: AppTheme.accentGold),
                        ),
                        IconButton(
                          key: const Key('editor_rotate_right'),
                          tooltip: 'Girar 90° a la derecha',
                          onPressed: _busy ? null : () => _rotate(1),
                          icon: const Icon(Icons.rotate_right,
                              color: AppTheme.accentGold),
                        ),
                        IconButton(
                          key: const Key('editor_reset'),
                          tooltip: 'Restablecer encuadre',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _transform.value = Matrix4.identity();
                                  }),
                          icon: const Icon(Icons.crop_free,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('editor_apply'),
                        onPressed: _busy ? null : _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Aplicar recorte'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
