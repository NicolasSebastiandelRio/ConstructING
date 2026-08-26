import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/works_remote_data_source.dart';
import 'works_event.dart';
import 'works_state.dart';

class WorksBloc extends Bloc<WorksEvent, WorksState> {
  final WorksRemoteDataSource worksRemoteDataSource;

  WorksBloc({required this.worksRemoteDataSource}) : super(WorksInitial()) {
    on<FetchWorksEvent>((event, emit) async {
      emit(WorksLoading());
      try {
        final works = await worksRemoteDataSource.getWorks();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    on<CreateWorkEvent>((event, emit) async {
      try {
        await worksRemoteDataSource.createWork(event.workData);
        // Volvemos a consultar el listado actualizado tras crear la obra (CU-18)
        final works = await worksRemoteDataSource.getWorks();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });
  }
}