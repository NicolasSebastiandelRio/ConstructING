import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/works_remote_data_source.dart';
import '../../data/models/work_model.dart';
import 'works_event.dart';
import 'works_state.dart';

class WorksBloc extends Bloc<WorksEvent, WorksState> {
  final WorksRemoteDataSource worksRemoteDataSource;

  /// CU-18/CU-21: último filtro de listado consultado. Las mutaciones
  /// (crear/editar/estado/archivar) refrescan con este mismo filtro para no
  /// romper el alcance ("Mis Obras" vs general, activas vs historial).
  String? _lastPropietarioId;
  bool _lastArchivedOnly = false;

  WorksBloc({required this.worksRemoteDataSource}) : super(WorksInitial()) {
    // CU-18: Consultar Obras Asignadas (+ CU-21 Historial)
    on<FetchWorksEvent>((event, emit) async {
      _lastPropietarioId = event.propietarioId;
      _lastArchivedOnly = event.archivedOnly;
      emit(WorksLoading());
      try {
        final works = await worksRemoteDataSource.getWorks(
          propietarioId: event.propietarioId,
          archivedOnly: event.archivedOnly,
        );
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    // CU-19: Visualizar Ficha Técnica (datos maestros desde la BD)
    on<FetchWorkDetailEvent>((event, emit) async {
      emit(WorkDetailLoading());
      try {
        final work = await worksRemoteDataSource.getWorkById(event.id);
        emit(WorkDetailLoaded(work: work));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    // CU-13: Crear Nueva Obra y refrescar vista
    on<CreateWorkEvent>((event, emit) async {
      emit(WorksLoading());
      try {
        await worksRemoteDataSource.createWork(event.workData);
        // Recargamos el listado con el filtro vigente para mantener la UI
        final works = await _refreshList();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    // CU-17: Modificar Información de Obra y refrescar vista (paso 4)
    on<UpdateWorkEvent>((event, emit) async {
      emit(WorksLoading());
      try {
        await worksRemoteDataSource.updateWork(event.id, event.workData);
        final works = await _refreshList();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    // CU-20: Actualizar Estado del Proyecto y refrescar vista (poscondición)
    on<UpdateWorkStatusEvent>((event, emit) async {
      emit(WorksLoading());
      try {
        await worksRemoteDataSource.updateWorkStatus(event.id, event.estado);
        final works = await _refreshList();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });

    // CU-21: Archivar Obra y refrescar vista (paso 4: sale del listado activo)
    on<ArchiveWorkEvent>((event, emit) async {
      emit(WorksLoading());
      try {
        await worksRemoteDataSource.archiveWork(event.id);
        final works = await _refreshList();
        emit(WorksLoaded(works: works));
      } catch (e) {
        emit(WorksError(message: e.toString().replaceAll('Exception: ', '')));
      }
    });
  }

  Future<List<WorkModel>> _refreshList() {
    return worksRemoteDataSource.getWorks(
      propietarioId: _lastPropietarioId,
      archivedOnly: _lastArchivedOnly,
    );
  }
}
