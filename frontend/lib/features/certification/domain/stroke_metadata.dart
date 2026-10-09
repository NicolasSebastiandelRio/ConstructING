import 'package:equatable/equatable.dart';

import 'entities/signature_stroke.dart';

/// CU-55 (RF_05): metadatos biométricos de la firma manuscrita —
/// velocidad, presión y coordenadas del trazo, para sumar validez
/// probatoria al acta (firma enriquecida con datos invisibles).
class StrokeMetadata extends Equatable {
  final int trazosCount;
  final int puntosCount;
  final double longitudTotalPx;
  final double duracionMs;
  final double presionMedia;
  final double presionMaxima;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const StrokeMetadata({
    required this.trazosCount,
    required this.puntosCount,
    required this.longitudTotalPx,
    required this.duracionMs,
    required this.presionMedia,
    required this.presionMaxima,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// Velocidad media del trazo, en píxeles por segundo.
  double get velocidadMediaPxS =>
      duracionMs <= 0 ? 0 : longitudTotalPx / duracionMs * 1000;

  /// CU-55 paso 4: objeto de datos (JSON) con los metadatos recopilados
  /// (agregados + matriz de puntos x,y) para acoplar al acta. Los dobles
  /// se redondean para salida estable (base del hash futuro, CU-59).
  Map<String, dynamic> toJson({required List<SignatureStroke> trazos}) {
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    double r3(double v) => double.parse(v.toStringAsFixed(3));
    return {
      'trazos_count': trazosCount,
      'puntos_count': puntosCount,
      'longitud_total_px': r2(longitudTotalPx),
      'duracion_ms': r2(duracionMs),
      'velocidad_media_px_s': r2(velocidadMediaPxS),
      'presion_media': r3(presionMedia),
      'presion_maxima': r3(presionMaxima),
      'area_px': {
        'min_x': r2(minX),
        'min_y': r2(minY),
        'max_x': r2(maxX),
        'max_y': r2(maxY),
      },
      'trazos': [
        for (final trazo in trazos)
          {
            'longitud_px': r2(trazo.lengthPx),
            'puntos': [
              for (final p in trazo.points)
                {
                  'x': r2(p.x),
                  'y': r2(p.y),
                  't': p.t,
                  'presion': r3(p.pressure),
                },
            ],
          },
      ],
    };
  }

  @override
  List<Object?> get props => [
        trazosCount,
        puntosCount,
        longitudTotalPx,
        duracionMs,
        presionMedia,
        presionMaxima,
        minX,
        minY,
        maxX,
        maxY,
      ];

  /// Reconstruye los metadatos desde su JSON persistido (conformidad
  /// pendiente, CU-57): usa los AGREGADOS — la matriz de trazos viaja
  /// separada en el borrador.
  static StrokeMetadata fromStoredJson(Map<String, dynamic> json) {
    double r2(Object? v) => (v is num ? v : 0).toDouble();
    double r3(Object? v) => (v is num ? v : 0).toDouble();
    final area =
        (json['area_px'] as Map?)?.cast<String, dynamic>() ?? const {};
    return StrokeMetadata(
      trazosCount: (json['trazos_count'] as num?)?.toInt() ?? 0,
      puntosCount: (json['puntos_count'] as num?)?.toInt() ?? 0,
      longitudTotalPx: r2(json['longitud_total_px']),
      duracionMs: r2(json['duracion_ms']),
      presionMedia: r3(json['presion_media']),
      presionMaxima: r3(json['presion_maxima']),
      minX: r2(area['min_x']),
      minY: r2(area['min_y']),
      maxX: r2(area['max_x']),
      maxY: r2(area['max_y']),
    );
  }
}

/// CU-55: extractor de parámetros biométricos. Consulta los eventos de
/// bajo nivel capturados durante el contacto (invocado internamente por el
/// CU-52 en su paso 2) y los conforma en un [StrokeMetadata].
class StrokeMetadataExtractor {
  static StrokeMetadata extract({required List<SignatureStroke> trazos}) {
    final puntos = [for (final trazo in trazos) ...trazo.points];
    if (puntos.isEmpty) {
      return const StrokeMetadata(
        trazosCount: 0,
        puntosCount: 0,
        longitudTotalPx: 0,
        duracionMs: 0,
        presionMedia: 0,
        presionMaxima: 0,
        minX: 0,
        minY: 0,
        maxX: 0,
        maxY: 0,
      );
    }
    var longitud = 0.0;
    var presionAcumulada = 0.0;
    var presionMaxima = puntos.first.pressure;
    var minX = puntos.first.x;
    var minY = puntos.first.y;
    var maxX = puntos.first.x;
    var maxY = puntos.first.y;
    for (final punto in puntos) {
      presionAcumulada += punto.pressure;
      if (punto.pressure > presionMaxima) presionMaxima = punto.pressure;
      if (punto.x < minX) minX = punto.x;
      if (punto.x > maxX) maxX = punto.x;
      if (punto.y < minY) minY = punto.y;
      if (punto.y > maxY) maxY = punto.y;
    }
    for (final trazo in trazos) {
      longitud += trazo.lengthPx;
    }
    final duracion = puntos.last.t - puntos.first.t;
    return StrokeMetadata(
      trazosCount: trazos.length,
      puntosCount: puntos.length,
      longitudTotalPx: longitud,
      duracionMs: duracion < 0 ? 0 : duracion.toDouble(),
      presionMedia: presionAcumulada / puntos.length,
      presionMaxima: presionMaxima,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
    );
  }
}
