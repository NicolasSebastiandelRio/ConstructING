import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';

/// Abre la BD del esquema CU-42 en memoria (ffi) para cada test.
Future<Database> _openMemoryDb() {
  sqfliteFfiInit();
  return LocalDatabase().openLocalDatabase(
    factoryOverride: databaseFactoryFfi,
    nameOverride: inMemoryDatabasePath,
  );
}

void main() {
  group('LocalDatabase - CU-42 (Almacenar Datos en Caché Local)', () {
    test('crea las tablas milestones y milestone_dependencies', () async {
      final db = await _openMemoryDb();
      addTearDown(db.close);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('milestones','milestone_dependencies') ORDER BY name",
      );

      expect(tables.map((r) => r['name']), ['milestone_dependencies', 'milestones']);
    });

    test('paso 4: el hito persiste con es_sincronizado = false y estado Pendiente', () async {
      final db = await _openMemoryDb();
      addTearDown(db.close);

      await db.insert('milestones', {
        'id': 'h1',
        'obra_id': 'w1',
        'nombre': 'Cimientos',
        'duracion_dias': 10,
        'created_at': '2026-09-06T00:00:00.000Z',
        'updated_at': '2026-09-06T00:00:00.000Z',
      });

      final rows = await db.query('milestones', where: 'id = ?', whereArgs: ['h1']);
      expect(rows, hasLength(1));
      expect(rows.first['estado'], 'Pendiente');
      expect(rows.first['es_critico'], 0);
      expect(rows.first['es_sincronizado'], 0);
    });

    test('persiste la arista de dependencia hito -> predecesor (CU-24)', () async {
      final db = await _openMemoryDb();
      addTearDown(db.close);

      for (final id in ['h1', 'h2']) {
        await db.insert('milestones', {
          'id': id,
          'obra_id': 'w1',
          'nombre': 'Hito $id',
          'duracion_dias': 5,
          'created_at': '2026-09-06T00:00:00.000Z',
          'updated_at': '2026-09-06T00:00:00.000Z',
        });
      }
      await db.insert('milestone_dependencies', {'hito_id': 'h2', 'predecesor_id': 'h1'});

      final edges = await db.query('milestone_dependencies');
      expect(edges, hasLength(1));
      expect(edges.first, containsPair('hito_id', 'h2'));
      expect(edges.first, containsPair('predecesor_id', 'h1'));
    });

    test('RNF_C_02: la escritura es transaccional (rollback ante fallo)', () async {
      final db = await _openMemoryDb();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) async {
          await txn.insert('milestones', {
            'id': 'h-tx',
            'obra_id': 'w1',
            'nombre': 'Hito Tx',
            'duracion_dias': 3,
            'created_at': '2026-09-06T00:00:00.000Z',
            'updated_at': '2026-09-06T00:00:00.000Z',
          });
          throw Exception('fallo simulado a mitad de la transacción');
        }),
        throwsException,
      );

      final rows = await db.query('milestones', where: 'id = ?', whereArgs: ['h-tx']);
      expect(rows, isEmpty);
    });

    test('RNF_C_02: un fallo de apertura se convierte en alerta inmediata', () async {
      final db = LocalDatabase();

      await expectLater(
        db.openLocalDatabase(
          factoryOverride: databaseFactoryFfi,
          // Un directorio NO es una BD válida: fuerza el error de apertura.
          nameOverride: Directory.systemTemp.path,
        ),
        throwsA(
          isA<CacheStorageException>().having(
            (e) => e.message,
            'message',
            contains('espacio disponible'),
          ),
        ),
      );
    });
  });
}