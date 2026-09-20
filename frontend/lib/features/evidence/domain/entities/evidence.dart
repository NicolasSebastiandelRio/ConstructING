import 'package:equatable/equatable.dart';

/// Tipos de evidencia pericial (CU-32: foto, CU-33: video).
enum EvidenceType {
  foto('Foto'),
  video('Video');

  const EvidenceType(this.label);

  final String label;

  static EvidenceType fromLabel(String? label) => EvidenceType.values.firstWhere(
        (t) => t.label == label,
        orElse: () => EvidenceType.foto,
      );
}

/// Evidencia pericial georreferenciada (RF_03, RF_04).
///
/// Persistencia local-first (CU-42): `esSincronizado=false` hasta que el
/// motor de sincronización (CU-44) la suba a la nube y libere el archivo
/// temporal. El [checksum] SHA-256 respalda la validación de integridad
/// bit a bit del CU-45 (RNF_C_03).
class Evidence extends Equatable {
  final String id;
  final String hitoId;
  final String obraId;

  /// Foto (CU-32) o Video (CU-33).
  final EvidenceType tipo;

  /// Ruta/URI local del archivo multimedia (vacío si ya se liberó el caché
  /// tras sincronizar, CU-44 paso 4: "libera el espacio de caché temporal").
  final String archivo;

  /// Observación técnica acoplada (CU-39, punto de extensión de CU-32/33).
  final String? nota;

  /// Coordenadas GPS obtenidas por CU-34 en el instante de la captura.
  final double latitud;
  final double longitud;
  final double precisionMetros;

  /// Fecha/hora de la captura (DataStamp CU-36, RNF_S_04).
  final DateTime fechaCaptura;

  /// Duración en segundos (solo video; CU-38 exige < 30 s).
  final double? duracionSeg;

  /// Peso del archivo en bytes (CU-38 exige < 15 MB).
  final int tamanoBytes;

  /// SHA-256 del archivo original (CU-45, RNF_C_03).
  final String checksum;

  /// Marca pericial estampada (texto compuesto por CU-36).
  final String marcaTexto;

  final bool esSincronizado;

  const Evidence({
    required this.id,
    required this.hitoId,
    required this.obraId,
    required this.tipo,
    required this.archivo,
    this.nota,
    required this.latitud,
    required this.longitud,
    required this.precisionMetros,
    required this.fechaCaptura,
    this.duracionSeg,
    required this.tamanoBytes,
    required this.checksum,
    required this.marcaTexto,
    this.esSincronizado = false,
  });

  bool get esVideo => tipo == EvidenceType.video;

  Map<String, dynamic> toLocalDb({required String nowIso}) {
    return {
      'id': id,
      'hito_id': hitoId,
      'obra_id': obraId,
      'tipo': tipo.label,
      'archivo': archivo,
      'nota': nota,
      'latitud': latitud,
      'longitud': longitud,
      'precision_m': precisionMetros,
      'fecha_captura': fechaCaptura.toIso8601String(),
      'duracion_seg': duracionSeg,
      'tamano_bytes': tamanoBytes,
      'checksum': checksum,
      'marca_texto': marcaTexto,
      'es_sincronizado': esSincronizado ? 1 : 0,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
  }

  factory Evidence.fromLocalDb(Map<String, dynamic> row) {
    return Evidence(
      id: row['id'] as String,
      hitoId: row['hito_id'] as String,
      obraId: row['obra_id'] as String,
      tipo: EvidenceType.fromLabel(row['tipo'] as String?),
      archivo: (row['archivo'] as String?) ?? '',
      nota: row['nota'] as String?,
      latitud: (row['latitud'] as num).toDouble(),
      longitud: (row['longitud'] as num).toDouble(),
      precisionMetros: (row['precision_m'] as num? ?? 0).toDouble(),
      fechaCaptura:
          DateTime.tryParse(row['fecha_captura'] as String? ?? '') ??
              DateTime.now(),
      duracionSeg: (row['duracion_seg'] as num?)?.toDouble(),
      tamanoBytes: (row['tamano_bytes'] as num? ?? 0).toInt(),
      checksum: (row['checksum'] as String?) ?? '',
      marcaTexto: (row['marca_texto'] as String?) ?? '',
      esSincronizado: (row['es_sincronizado'] as num? ?? 0) == 1,
    );
  }

  Evidence copyWith({
    String? archivo,
    String? nota,
    bool? esSincronizado,
  }) {
    return Evidence(
      id: id,
      hitoId: hitoId,
      obraId: obraId,
      tipo: tipo,
      archivo: archivo ?? this.archivo,
      nota: nota ?? this.nota,
      latitud: latitud,
      longitud: longitud,
      precisionMetros: precisionMetros,
      fechaCaptura: fechaCaptura,
      duracionSeg: duracionSeg,
      tamanoBytes: tamanoBytes,
      checksum: checksum,
      marcaTexto: marcaTexto,
      esSincronizado: esSincronizado ?? this.esSincronizado,
    );
  }

  @override
  List<Object?> get props => [
        id,
        hitoId,
        obraId,
        tipo,
        archivo,
        nota,
        latitud,
        longitud,
        precisionMetros,
        fechaCaptura,
        duracionSeg,
        tamanoBytes,
        checksum,
        marcaTexto,
        esSincronizado,
      ];
}
