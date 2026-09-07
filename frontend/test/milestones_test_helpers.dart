import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

int _dbCounter = 0;

/// DAO sobre BD temporal aislada (ffi) para tests planos.
///
/// NOTA: cada test usa un archivo temporal único (se borra al fin) porque los
/// opens `:memory:` comparten instancia (caché singleInstance) y contaminan
/// entre tests. Se usa `databaseFactoryFfiNoIsolate`: el factory con isolate
/// worker deja recursos que cuelgan la finalización del test.
Future<MilestoneLocalDataSource> openTestDao(String prefix) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path =
      '${Directory.systemTemp.path}/${prefix}_${_dbCounter++}_${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  return MilestoneLocalDataSource(localDatabase: localDb);
}

/// DAO fake en memoria para widget tests (sin FFI: abrir BD real dentro de
/// testWidgets cuelga la finalización en este entorno).
class FakeMilestoneDao implements MilestoneLocalDataSource {
  final Map<String, Milestone> _store = {};
  final Map<String, Set<String>> _deps = {};
  int createCalls = 0;
  int updateCalls = 0;

  void seed(List<Milestone> milestones) {
    for (final milestone in milestones) {
      _store[milestone.id] = milestone;
    }
  }

  void seedEdges(Map<String, Set<String>> edges) {
    for (final entry in edges.entries) {
      _deps[entry.key] = Set.of(entry.value);
    }
  }

  @override
  Future<Milestone> create({
    required String obraId,
    required String nombre,
    String? descripcion,
    required int duracionDias,
  }) async {
    createCalls++;
    if (nombre.trim().isEmpty) {
      throw const CacheStorageException('El nombre del hito es obligatorio.');
    }
    if (duracionDias < 0) {
      throw const CacheStorageException(
          'La duración debe ser un número mayor o igual a 0.');
    }
    final milestone = Milestone(
      id: 'fake-${_store.length + 1}',
      obraId: obraId,
      nombre: nombre.trim(),
      descripcion: descripcion,
      duracionDias: duracionDias,
    );
    _store[milestone.id] = milestone;
    return milestone;
  }

  @override
  Future<List<Milestone>> listByObra(String obraId) async =>
      _store.values.where((m) => m.obraId == obraId).toList();

  @override
  Future<Milestone?> getById(String id) async => _store[id];

  @override
  Future<Milestone> update(Milestone milestone) async {
    updateCalls++;
    _store[milestone.id] = milestone;
    return milestone;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
    _deps.remove(id);
    for (final entry in _deps.values) {
      entry.remove(id);
    }
  }

  @override
  Future<void> addDependency({
    required String hitoId,
    required String predecesorId,
  }) async {
    if (hitoId == predecesorId) {
      throw const CacheStorageException('Un hito no puede depender de sí mismo.');
    }
    _deps.putIfAbsent(hitoId, () => <String>{}).add(predecesorId);
  }

  @override
  Future<void> removeDependency({
    required String hitoId,
    required String predecesorId,
  }) async {
    _deps[hitoId]?.remove(predecesorId);
  }

  @override
  Future<List<String>> predecessorIds(String hitoId) async =>
      _deps[hitoId]?.toList() ?? [];

  @override
  Future<List<String>> successorIds(String predecesorId) async => _deps.entries
      .where((entry) => entry.value.contains(predecesorId))
      .map((entry) => entry.key)
      .toList();

  @override
  Future<void> setCritical({
    required String obraId,
    required Set<String> criticalIds,
  }) async {
    for (final milestone in _store.values.where((m) => m.obraId == obraId)) {
      _store[milestone.id] =
          milestone.copyWith(esCritico: criticalIds.contains(milestone.id));
    }
  }

  @override
  Future<Map<String, Set<String>>> dependencyMap(String obraId) async {
    final ids = _store.values.where((m) => m.obraId == obraId).map((m) => m.id).toSet();
    return {for (final id in ids) id: Set.of(_deps[id] ?? {})};
  }
}
