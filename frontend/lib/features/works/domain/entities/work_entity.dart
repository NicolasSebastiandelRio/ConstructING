import 'package:equatable/equatable.dart';

class WorkEntity extends Equatable {
  final String id;
  final String nombre;
  final String direccion;
  final String? descripcion;
  final double latitud;
  final double longitud;
  final String fechaInicio;
  final String estado;
  final double progreso;
  final String profesionalId;
  final String? propietarioId;

  const WorkEntity({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.descripcion,
    required this.latitud,
    required this.longitud,
    required this.fechaInicio,
    required this.estado,
    required this.progreso,
    required this.profesionalId,
    this.propietarioId,
  });

  @override
  List<Object?> get props => [
        id,
        nombre,
        direccion,
        descripcion,
        latitud,
        longitud,
        fechaInicio,
        estado,
        progreso,
        profesionalId,
        propietarioId,
      ];
}