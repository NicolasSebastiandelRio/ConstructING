import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/acta_hash.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

import 'milestones_test_helpers.dart';

/// Trazo sintético de firma: línea recta de [length] px con 3 puntos.
List<SignaturePoint> _trazo({
  double length = 200,
  int t0 = 1000,
  int dt = 150,
}) => [
      SignaturePoint(x: 0, y: 0, t: t0),
      SignaturePoint(x: length / 2, y: 0, t: t0 + dt),
      SignaturePoint(x: length, y: 0, t: t0 + 2 * dt),
    ];

void main() {
  group('ActaHash - CU-59 paso 2 (motor criptográfico)', () {
    test('SHA-256 determinista sobre la totalidad del documento', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = ActaHash.sha256OfBytes(bytes);
      expect(hash, ActaHash.sha256OfBytes(bytes));
    });

    test('formato: cadena alfanumérica hex de 64 en mayúsculas', () {
      final hash = ActaHash.sha256OfBytes(Uint8List(64));
      expect(hash, hasLength(64));
      expect(hash, matches(RegExp(r'^[0-9A-F]{64}$')));
    });

    test('poscondición: alterar un solo byte cambia radicalmente el sello',
        () {
      final original = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]);
      final alterado = Uint8List.fromList(original)..[7] = 0x53;
      final hashOriginal = ActaHash.sha256OfBytes(original);
      final hashAlterado = ActaHash.sha256OfBytes(alterado);
      expect(hashAlterado, isNot(hashOriginal));
      expect(hashAlterado, hasLength(64));
    });
  });

  group('CertificationLocalDataSource - CU-59 paso 4 (tabla de la BD)', () {
    Future<({LocalDatabase db, CertificationLocalDataSource dao})> _dao(
      String prefix,
    ) async {
      sqfliteFfiInit();
      final localDb = LocalDatabase();
      final path =
          '${Directory.systemTemp.path}/cu59_${prefix}_${DateTime.now().microsecondsSinceEpoch}.db';
      await localDb.openLocalDatabase(
        factoryOverride: databaseFactoryFfiNoIsolate,
        nameOverride: path,
      );
      addTearDown(() async {
        await localDb.close();
        final file = File(path);
        if (await file.exists()) await file.delete();
      });
      return (
        db: localDb,
        dao: CertificationLocalDataSource(localDatabase: localDb),
      );
    }

    test('inserta y recupera el sello del hito', () async {
      final ctx = await _dao('a');

      expect(await ctx.dao.findByHito('h1'), isNull);

      await ctx.dao.insert(CertificationRecord(
        actaId: 'acta-1',
        hitoId: 'h1',
        obraId: 'w1',
        hashSha256: 'AABBCC',
        firmante: 'Profesional',
        createdAt: DateTime(2026, 10, 4),
      ));

      final fila = await ctx.dao.findByHito('h1');
      expect(fila?.hashSha256, 'AABBCC');
      expect(fila?.firmante, 'Profesional');
    });

    test('sellado inmutable: repetir el acta es idempotente (no re-firma)',
        () async {
      final ctx = await _dao('b');

      await ctx.dao.insert(CertificationRecord(
        actaId: 'acta-2',
        hitoId: 'h2',
        obraId: 'w1',
        hashSha256: 'ORIGINAL',
        createdAt: DateTime(2026, 10, 4),
      ));
      final segunda = await ctx.dao.insert(CertificationRecord(
        actaId: 'acta-2',
        hitoId: 'h2',
        obraId: 'w1',
        hashSha256: 'CAMBIADO',
        createdAt: DateTime(2026, 10, 5),
      ));

      // El sello original prevalece (no se modifica post-firma).
      expect(segunda.hashSha256, 'ORIGINAL');
      expect((await ctx.dao.findByHito('h2'))?.hashSha256, 'ORIGINAL');
    });
  });

  group('CertificationBloc - CU-59 sellado en el pipeline de certificación',
      () {
    test('Confirmar emite el sello SHA-256 y lo registra en la tabla',
        () async {
      final daos = await openSharedTestDaos('cu59c');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Cimientos', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final daoCert =
          CertificationLocalDataSource(localDatabase: daos.db);
      final bloc = CertificationBloc(
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        certificationDao: daoCert,
        actaGenerator: (payload) async =>
            Uint8List.fromList([37, 80, 68, 70, 45, 49]),
        persistActa: ({required Uint8List bytes, required String fileName}) async =>
            '/caché/$fileName',
      );
      addTearDown(bloc.close);

      final loaded = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationLoading>(),
          isA<CertificationSummaryReady>(),
        ]),
      );
      bloc.add(LoadCertificationSummary(hitoId: hito.id));
      await loaded;

      final flow = expectLater(
        bloc.stream,
        emitsInOrder([
          isA<CertificationSummaryReady>(),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      final captured = bloc.state as CertificationSignatureCaptured;
      // El sello corresponde al hash SHA-256 real de los bytes del acta.
      expect(
        captured.hashSha256,
        ActaHash.sha256OfBytes(Uint8List.fromList([37, 80, 68, 70, 45, 49])),
      );
      final fila = await daoCert.findByHito(hito.id);
      expect(fila?.hashSha256, captured.hashSha256);
    });
  });
}
