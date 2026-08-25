import 'package:equatable/equatable.dart';
import '../../domain/entities/work_entity.dart';

abstract class WorksState extends Equatable {
  const WorksState();
  @override
  List<Object?> get props => [];
}

class WorksInitial extends WorksState {}

class WorksLoading extends WorksState {}

class WorksLoaded extends WorksState {
  final List<WorkEntity> works;
  const WorksLoaded({required this.works});
  @override
  List<Object?> get props => [works];
}

class WorksError extends WorksState {
  final String message;
  const WorksError({required this.message});
  @override
  List<Object?> get props => [message];
}

class WorkCreatedSuccess extends WorksState {
  final WorkEntity work;
  const WorkCreatedSuccess({required this.work});
  @override
  List<Object?> get props => [work];
}