import '../../domain/entities/work_entity.dart';

class WorkModel extends WorkEntity {
  const WorkModel({
    required super.id,
    required super.nombre,
    required super.direccion,
    super.descripcion,
    required super.latitud,
    required super.longitud,
    required super.fechaInicio,
    required super.estado,
    required super.progreso,
    required super.profesionalId,
    super.propietarioId,
    super.propietarioNombre,
    super.propietarioEmail,
  });

  static double? _parseCoord(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  factory WorkModel.fromJson(Map<String, dynamic> json) {
    final owner = json['propietario'];
    final Map<String, dynamic>? ownerMap =
        owner is Map<String, dynamic> ? owner : null;
    return WorkModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      direccion: json['direccion'] ?? '',
      descripcion: json['descripcion'],
      // Sin ancla en BD se preserva null (no se inventan coordenadas).
      latitud: _parseCoord(json['latitud']),
      longitud: _parseCoord(json['longitud']),
      fechaInicio: json['fecha_inicio'] ?? json['fechaInicio'] ?? '',
      estado: json['estado'] ?? 'En progreso',
      progreso: (json['progreso'] != null)
          ? double.tryParse(json['progreso'].toString()) ?? 0.0
          : 0.0,
      profesionalId: json['profesional_id'] ?? json['profesionalId'] ?? '',
      propietarioId:
          json['propietario_id'] ?? json['propietarioId'] ?? ownerMap?['id'],
      propietarioNombre: ownerMap?['nombre'],
      propietarioEmail: ownerMap?['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'direccion': direccion,
      'descripcion': descripcion,
      'fechaInicio': fechaInicio,
      'latitud': latitud,
      'longitud': longitud,
    };
  }
}
