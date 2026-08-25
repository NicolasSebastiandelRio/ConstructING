import 'package:equatable/equatable.dart';

abstract class WorksEvent extends Equatable {
  const WorksEvent();
  @override
  List<Object?> get props => [];
}

class FetchWorksEvent extends WorksEvent {}

class CreateWorkEvent extends WorksEvent {
  final String nombre;
  final String direccion;
  final String? descripcion;
  final String fechaInicio;
  final String? propietarioEmail;

  const CreateWorkEvent({
    required this.nombre,
    required this.direccion,
    this.descripcion,
    required this.fechaInicio,
    this.propietarioEmail,
  });

  @override
  List<Object?> get props => [nombre, direccion, descripcion, fechaInicio, propietarioEmail];
}