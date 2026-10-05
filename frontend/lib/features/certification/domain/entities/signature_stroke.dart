import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Punto del trazo táctil (CU-52 paso 1). Guarda coordenadas, presión y
/// marca de tiempo del contacto: son los parámetros biométricos que
/// enriquecen el acta (CU-55, RF_05).
class SignaturePoint extends Equatable {
  final double x;
  final double y;

  /// Milisegundos desde epoch (marca de tiempo del evento de contacto).
  final int t;

  /// Presión del contacto (0..1); 1.0 si el dispositivo no la informa.
  final double pressure;

  const SignaturePoint({
    required this.x,
    required this.y,
    required this.t,
    this.pressure = 1.0,
  });

  /// Distancia Euclídea a otro punto (en píxeles lógicos).
  double distanceTo(SignaturePoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  @override
  List<Object?> get props => [x, y, t, pressure];
}

/// Trazo continuo de la firma (CU-52): los puntos capturados entre el
/// contacto inicial y su levantada sobre el lienzo.
class SignatureStroke extends Equatable {
  final List<SignaturePoint> points;

  const SignatureStroke(this.points);

  /// Longitud recorrida por el trazo, en píxeles lógicos (CU-52 Alt. 2.1).
  double get lengthPx {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += points[i].distanceTo(points[i - 1]);
    }
    return total;
  }

  @override
  List<Object?> get props => [points];
}
