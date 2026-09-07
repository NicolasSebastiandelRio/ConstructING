import 'package:equatable/equatable.dart';

/// Estados del hito (etiquetas exactas de la especificación).
enum MilestoneStatus {
  pendiente('Pendiente'),
  enEjecucion('En Ejecución'),
  certificado('Certificado');

  const MilestoneStatus(this.label);

  final String label;

  static MilestoneStatus fromLabel(String? label) {
    return MilestoneStatus.values.firstWhere(
      (s) => s.label == label,
      orElse: () => MilestoneStatus.pendiente,
    );
  }
}

extension MilestoneStatusX on MilestoneStatus {
  /// Siguiente fase operativa (CU-26: Pendiente → En Ejecución →
  /// Certificado), o null si ya está en la final. Fuente única usada por el
  /// bloc y la UI para ofrecer solo avances válidos.
  MilestoneStatus? get next {
    switch (this) {
      case MilestoneStatus.pendiente:
        return MilestoneStatus.enEjecucion;
      case MilestoneStatus.enEjecucion:
        return MilestoneStatus.certificado;
      case MilestoneStatus.certificado:
        return null;
    }
  }
}

/// Hito de obra: etapa técnica del cronograma (CU-23, RF_02).
///
/// Persistencia local-first (CU-42): `esSincronizado=false` hasta que el
/// motor de sincronización del Sprint 4 (CU-44) lo suba a la nube.
class Milestone extends Equatable {
  final String id;
  final String obraId;
  final String nombre;
  final String? descripcion;
  final int duracionDias;
  final MilestoneStatus estado;
  final bool esCritico;
  final bool esSincronizado;

  const Milestone({
    required this.id,
    required this.obraId,
    required this.nombre,
    this.descripcion,
    required this.duracionDias,
    this.estado = MilestoneStatus.pendiente,
    this.esCritico = false,
    this.esSincronizado = false,
  });

  /// CU-16 (paso 2 de CU-23): sin nulos ni duraciones negativas.
  static String? validateNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre del hito es obligatorio.';
    }
    return null;
  }

  /// La duración debe informarse como entero mayor o igual a cero días.
  static String? validateDuracion(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La duración estimada es obligatoria.';
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      return 'La duración debe ser un número mayor o igual a 0.';
    }
    return null;
  }

  Map<String, dynamic> toLocalDb({required String nowIso}) {
    return {
      'id': id,
      'obra_id': obraId,
      'nombre': nombre,
      'descripcion': descripcion,
      'duracion_dias': duracionDias,
      'estado': estado.label,
      'es_critico': esCritico ? 1 : 0,
      'es_sincronizado': esSincronizado ? 1 : 0,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
  }

  factory Milestone.fromLocalDb(Map<String, dynamic> row) {
    return Milestone(
      id: row['id'] as String,
      obraId: row['obra_id'] as String,
      nombre: row['nombre'] as String,
      descripcion: row['descripcion'] as String?,
      duracionDias: (row['duracion_dias'] as num).toInt(),
      estado: MilestoneStatus.fromLabel(row['estado'] as String?),
      esCritico: (row['es_critico'] as num? ?? 0) == 1,
      esSincronizado: (row['es_sincronizado'] as num? ?? 0) == 1,
    );
  }

  Milestone copyWith({
    String? nombre,
    String? descripcion,
    int? duracionDias,
    MilestoneStatus? estado,
    bool? esCritico,
    bool? esSincronizado,
  }) {
    return Milestone(
      id: id,
      obraId: obraId,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      duracionDias: duracionDias ?? this.duracionDias,
      estado: estado ?? this.estado,
      esCritico: esCritico ?? this.esCritico,
      esSincronizado: esSincronizado ?? this.esSincronizado,
    );
  }

  @override
  List<Object?> get props => [
        id,
        obraId,
        nombre,
        descripcion,
        duracionDias,
        estado,
        esCritico,
        esSincronizado,
      ];
}
