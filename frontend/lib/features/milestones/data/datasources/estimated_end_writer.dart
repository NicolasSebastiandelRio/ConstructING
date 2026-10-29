import '../../../works/data/datasources/works_remote_data_source.dart';

/// Escribe la fecha estimada de fin de la obra (CU-30 pasos 1-3).
///
/// El llamador (CU-29) decide la política ante fallos: offline-first implica
/// best-effort (lo local ya persistió; CU-44 reintentará la nube).
abstract class EstimatedEndWriter {
  /// Persiste `fechaInicio + projectDurationDays` como `fecha_fin_estimada`.
  /// Retorna la fecha ISO escrita. Puede lanzar (red, formato inválido).
  Future<String> write({
    required String obraId,
    required int projectDurationDays,
  });
}

/// Implementación contra la API de obras (PATCH /works/:id).
class WorksApiEstimatedEndWriter implements EstimatedEndWriter {
  final WorksRemoteDataSource works;

  WorksApiEstimatedEndWriter({required this.works});

  @override
  Future<String> write({
    required String obraId,
    required int projectDurationDays,
  }) async {
    final obra = await works.getWorkById(obraId);
    final start = DateTime.tryParse(obra.fechaInicio);
    if (start == null) {
      throw Exception('La obra no tiene fecha de inicio válida.');
    }
    final end = start.add(Duration(days: projectDurationDays));
    final iso = '${end.year.toString().padLeft(4, '0')}-'
        '${end.month.toString().padLeft(2, '0')}-'
        '${end.day.toString().padLeft(2, '0')}';
    await works.updateWork(obraId, {'fechaFinEstimada': iso});
    return iso;
  }
}
