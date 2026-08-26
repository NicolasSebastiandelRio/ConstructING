import 'package:equatable/equatable.dart';

abstract class WorksEvent extends Equatable {
  const WorksEvent();

  @override
  List<Object?> get props => [];
}

class FetchWorksEvent extends WorksEvent {}

class CreateWorkEvent extends WorksEvent {
  final Map<String, dynamic> workData;

  const CreateWorkEvent({required this.workData});

  @override
  List<Object?> get props => [workData];
}