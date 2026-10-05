import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/certification_bloc.dart';
import '../bloc/certification_event.dart';
import '../bloc/certification_state.dart';
import '../../domain/entities/signature_stroke.dart';

/// Lienzo de firma manuscrita (CU-52, RF_05 + RNF_U_05).
///
/// Captura el trazo táctil en vivo (coordenadas + presión + marca de
/// tiempo por punto) y lo acumula en el bloc al levantar el contacto.
/// El botón "Confirmar" queda bloqueado sin trazos; "Limpiar Pantalla"
/// ejecuta el CU-53 (borra el buffer y repinta al instante).
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  /// Trazo en curso (antes de levantar el contacto): se dibuja en vivo y
  /// no pertenece aún al estado del bloc.
  List<SignaturePoint> _current = const [];

  /// Contacto activo; los punteros extra se ignoran (una firma, un trazo).
  int? _activePointer;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    setState(() {
      _current = [
        SignaturePoint(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
          t: event.timeStamp.inMilliseconds,
          pressure: _pressureOf(event.pressure),
        ),
      ];
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _current = [
        ..._current,
        SignaturePoint(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
          t: event.timeStamp.inMilliseconds,
          pressure: _pressureOf(event.pressure),
        ),
      ];
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _commit();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _commit();
  }

  void _commit() {
    _activePointer = null;
    final stroke = _current;
    setState(() => _current = const []);
    if (stroke.isNotEmpty) {
      context
          .read<CertificationBloc>()
          .add(SignatureStrokeCommitted(points: stroke));
    }
  }

  double _pressureOf(double raw) => raw <= 0 ? 1.0 : raw.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CertificationBloc, CertificationState>(
      buildWhen: (previous, current) =>
          previous.runtimeType != current.runtimeType ||
          (previous is CertificationSummaryReady &&
              current is CertificationSummaryReady &&
              previous.strokes != current.strokes),
      builder: (context, state) {
        final strokes =
            state is CertificationSummaryReady ? state.strokes : const <SignatureStroke>[];
        final canClear = strokes.isNotEmpty || _current.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: Container(
                key: const Key('signature_pad_canvas'),
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.accentGold.withValues(alpha: 0.6)),
                ),
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: strokes,
                    current: _current,
                  ),
                  child: strokes.isEmpty && _current.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Realice aquí el trazo de su firma',
                            style: TextStyle(color: Colors.black38, fontSize: 12),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canClear
                        ? () => context
                            .read<CertificationBloc>()
                            .add(const ClearSignaturePad())
                        : null,
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                    label: const Text('Limpiar Pantalla'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: strokes.isNotEmpty
                        ? () => context
                            .read<CertificationBloc>()
                            .add(const SignatureConfirmationRequested())
                        : null,
                    icon: const Icon(Icons.fingerprint, size: 18),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGold,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Pintor del lienzo: repasa los trazos comprometidos y el trazo en curso.
class _SignaturePainter extends CustomPainter {
  final List<SignatureStroke> strokes;
  final List<SignaturePoint> current;

  const _SignaturePainter({required this.strokes, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, paint);
    }
    _drawStroke(canvas, current, paint);
  }

  void _drawStroke(Canvas canvas, List<SignaturePoint> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.x, points.first.y),
        paint.strokeWidth / 2,
        Paint()..color = paint.color,
      );
      return;
    }
    final path = Path()
      ..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) =>
      old.strokes != strokes || old.current != current;
}
