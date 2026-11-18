import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'milestones_test_helpers.dart';

/// CU-42 (Almacenar Datos en Caché Local) aplicado a la evidencia pericial.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('EvidenceLocalDataSource - CU-42 (BD local, RNF_C_02)', () {
    test('la tabla evidences se crea en el esquema v2', () async {
      final dao = await openEvidenceDao('ev42');
      final evidences = await dao.listByHito('h1');
      expect(evidences, isEmpty);
    });

    test('paso 4: la evidencia persiste con es_sincronizado = false', () async {
      final dao = await openEvidenceDao('ev42');
      final evidence = await dao.create(
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: 'blob://local/abc',
        latitud: -34.6037,
        longitud: -58.3816,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 9, 19, 10, 0),
        tamanoBytes: 1024,
        checksum: 'ABC123',
        marcaTexto: 'ConstructING · 19/09/2026 10:00',
      );
      expect(evidence.esSincronizado, isFalse);

      final loaded = await dao.listByHito('h1');
      expect(loaded.single.id, evidence.id);
      expect(loaded.single.tipo, EvidenceType.foto);
      expect(loaded.single.esSincronizado, isFalse);
    });

    test('la migración v1 → v2 crea la tabla sin perder hitos', () async {
      // BD creada en v1 (solo hitos), luego reabierta con v2.
      sqfliteFfiInit();
      final path =
          '${Directory.systemTemp.path}/ev42_migrate_${DateTime.now().microsecondsSinceEpoch}.db';
      final factory = databaseFactoryFfiNoIsolate;
      final db = await factory.openDatabase(path, options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(LocalDatabase.createMilestones);
          await db.execute(LocalDatabase.createMilestoneDependencies);
        },
      ));
      await db.insert('milestones', {
        'id': 'h1',
        'obra_id': 'w1',
        'nombre': 'Cimientos',
        'duracion_dias': 10,
        'estado': 'Pendiente',
        'es_critico': 0,
        'es_sincronizado': 0,
        'created_at': '2026-09-19T10:00:00Z',
        'updated_at': '2026-09-19T10:00:00Z',
      });
      await db.close();

      final localDb = LocalDatabase();
      await localDb.openLocalDatabase(
        factoryOverride: factory,
        nameOverride: path,
      );
      final milestoneDao =
          MilestoneDaoProbe(localDatabase: localDb);
      final milestones = await milestoneDao.listByObra('w1');
      expect(milestones.single.nombre, 'Cimientos');
      final evidences = await EvidenceLocalDataSource(localDatabase: localDb)
          .listByHito('h1');
      expect(evidences, isEmpty);
    });

    test('RNF_C_02: ante fallo de espacio alerta inmediatamente', () async {
      final dao = await openEvidenceDao('ev42');
      expect(
        () => dao.create(
          hitoId: '',
          obraId: '',
          tipo: EvidenceType.foto,
          archivo: 'x',
          latitud: 0,
          longitud: 0,
          precisionMetros: 0,
          fechaCaptura: DateTime.now(),
          tamanoBytes: 0,
          checksum: 'X',
          marcaTexto: '',
        ),
        throwsA(isA<CacheStorageException>()),
      );
    });

    test('CU-44 paso 4: markSynced marca el flag y libera el caché', () async {
      final dao = await openEvidenceDao('ev42');
      final evidence = await dao.create(
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.video,
        archivo: 'blob://local/video',
        latitud: -34.6,
        longitud: -58.38,
        precisionMetros: 3,
        fechaCaptura: DateTime(2026, 9, 19, 10, 0),
        duracionSeg: 15,
        tamanoBytes: 1024,
        checksum: 'ABC123',
        marcaTexto: 'marca',
      );
      await dao.markSynced(evidence.id);

      final pending = await dao.listPendingSync();
      expect(pending, isEmpty);
      final all = await dao.listByHito('h1');
      expect(all.single.esSincronizado, isTrue);
      // El espacio de caché temporal queda liberado (ruta vacía).
      expect(all.single.archivo, isEmpty);
    });
  });
}

/// Sonda para leer hitos desde un test de evidencias (evita import circular).
class MilestoneDaoProbe extends MilestoneLocalDataSource {
  MilestoneDaoProbe({required super.localDatabase});
}
