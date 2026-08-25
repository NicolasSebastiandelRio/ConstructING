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
  });

  factory WorkModel.fromJson(Map<String, dynamic> json) {
    return WorkModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      direccion: json['direccion'] ?? '',
      descripcion: json['descripcion'],
      latitud: (json['latitud'] != null)
          ? double.tryParse(json['latitud'].toString()) ?? -34.6037
          : -34.6037,
      longitud: (json['longitud'] != null)
          ? double.tryParse(json['longitud'].toString()) ?? -58.3816
          : -58.3816,
      fechaInicio: json['fecha_inicio'] ?? json['fechaInicio'] ?? '',
      estado: json['estado'] ?? 'En progreso',
      progreso: (json['progreso'] != null)
          ? double.tryParse(json['progreso'].toString()) ?? 0.0
          : 0.0,
      profesionalId: json['profesional_id'] ?? json['profesionalId'] ?? '',
      propietarioId: json['propietario_id'] ?? json['propietarioId'],
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