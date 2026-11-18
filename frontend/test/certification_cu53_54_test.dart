import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/certification/data/datasources/acta_remote_data_source.dart';
import 'package:constructing_mobile/features/certification/gateway/acta_saver.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/acta_download_cubit.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/acta_download_state.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

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

/// Adaptador HTTP falso para probar la fuente remota sin servidor.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function() handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler();

  @override
  void close({bool force = false}) {}
}

class _FakeDioClient extends DioClient {
  _FakeDioClient(this.dioOverride);

  final Dio dioOverride;

  @override
  Dio get dio => dioOverride;
}

void main() {
  group('CertificationBloc CU-53 - Limpiar / Reintentar Trazo de Firma', () {
    test('ciclo completo: trazo → Limpiar Pantalla → nuevo trazo → Confirmar',
        () async {
      final daos = await openSharedTestDaos('cu53a');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      // CU-57: el pipeline de certificación congela desde "En Ejecución".
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au53'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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

      // Paso 1: trazo con error.
      final flow = expectLater(
        bloc.stream,
        emitsInOrder([
          // Paso 2: el lienzo queda en blanco (respuesta instantánea).
          predicate<CertificationSummaryReady>(
              (s) => s.strokes.isNotEmpty, 'trazo previo'),
          predicate<CertificationSummaryReady>(
              (s) => s.strokes.isEmpty, 'limpiado'),
          // Pasos 3/4: nuevo trazo correcto y Confirmar habilitado.
          predicate<CertificationSummaryReady>(
              (s) => s.strokes.isNotEmpty, 'nuevo trazo'),
          isA<CertificationSignatureCaptured>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 80)));
      bloc.add(const ClearSignaturePad());
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250, t0: 9000)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      expect(bloc.state, isA<CertificationSignatureCaptured>());
    });

    test('Limpiar Pantalla sin trazos es inocuo (precondición respetada)',
        () async {
      final daos = await openSharedTestDaos('cu53b');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au53'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
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

      // Con el lienzo en blanco no hay nada que limpiar: el estado no
      // cambia (ni emisión ni píxeles tocados).
      final emitted = <CertificationState>[];
      final sub = bloc.stream.listen(emitted.add);
      bloc.add(const ClearSignaturePad());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emitted, isEmpty);
      expect((bloc.state as CertificationSummaryReady).strokes, isEmpty);
    });
  });

  group('CertificationBloc CU-54 - Descargar Acta de Conformidad', () {
    test('Flujo Normal: localiza el acta en el caché local y guarda la copia',
        () async {
      final daos = await openSharedTestDaos('cu54a');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.certificado));

      final dir =
          '${Directory.systemTemp.path}/acta_cu54a_${DateTime.now().microsecondsSinceEpoch}';
      final expectedFile = File(await saveActaFile(
          bytes: Uint8List.fromList([37, 80, 68, 70]),
          fileName: actaFileName(hito.id),
          directoryOverride: dir));
      addTearDown(() async {
        if (await expectedFile.exists()) await expectedFile.delete();
        final d = Directory(dir);
        if (await d.exists()) await d.delete();
      });

      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (hitoId) =>
            readLocalActa(hitoId: hitoId, directoryOverride: dir),
        saveActa: ({required Uint8List bytes, required String fileName}) =>
            saveActaFile(
                bytes: bytes,
                fileName: fileName,
                directoryOverride: dir),
      );
      addTearDown(cubit.close);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloaded>(),
        ]),
      );
      await cubit.download(hitoId: hito.id);
      await flow;

      final downloaded = cubit.state as ActaDownloaded;
      expect(downloaded.fileName, actaFileName(hito.id));
      expect(downloaded.ubicacion, expectedFile.path);
      expect(downloaded.origen, 'caché local');
      expect(await expectedFile.exists(), isTrue);
    });

    test('paso 2 (servidor central): sin caché local descarga del servidor',
        () async {
      final daos = await openSharedTestDaos('cu54b');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.certificado));

      var savedBytes = Uint8List(0);
      var savedName = '';
      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (_) async => null,
        saveActa: ({required Uint8List bytes, required String fileName}) async {
          savedBytes = bytes;
          savedName = fileName;
          return '/descargas/$fileName';
        },
        remoteActa: ({required String hitoId}) async =>
            Uint8List.fromList([37, 80, 68, 70]),
      );
      addTearDown(cubit.close);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloaded>(),
        ]),
      );
      await cubit.download(hitoId: hito.id);
      await flow;

      final downloaded = cubit.state as ActaDownloaded;
      expect(downloaded.origen, 'servidor central');
      expect(downloaded.fileName, actaFileName(hito.id));
      expect(downloaded.ubicacion, '/descargas/${actaFileName(hito.id)}');
      expect(savedBytes, isNotEmpty);
      expect(savedName, actaFileName(hito.id));
    });

    test('acta inexistente en ambos orígenes → mensaje de no disponible',
        () async {
      final daos = await openSharedTestDaos('cu54c');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.certificado));

      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (_) async => null,
        saveActa: ({required Uint8List bytes, required String fileName}) async =>
            'x',
        remoteActa: ({required String hitoId}) async => null,
      );
      addTearDown(cubit.close);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloadError>(),
        ]),
      );
      await cubit.download(hitoId: hito.id);
      await flow;

      expect(
        (cubit.state as ActaDownloadError).message,
        'El acta de conformidad aún no está disponible para este hito.',
      );
    });

    test('Precondición: hito sin estado Certificado rechaza la descarga',
        () async {
      final daos = await openSharedTestDaos('cu54d');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);

      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (_) async => null,
        saveActa: ({required Uint8List bytes, required String fileName}) async =>
            'x',
      );
      addTearDown(cubit.close);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloadError>(),
        ]),
      );
      await cubit.download(hitoId: hito.id);
      await flow;

      expect(
        (cubit.state as ActaDownloadError).message,
        contains('"Certificado"'),
      );
    });

    test('hito inexistente → error', () async {
      final daos = await openSharedTestDaos('cu54e');
      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (_) async => null,
        saveActa: ({required Uint8List bytes, required String fileName}) async =>
            'x',
      );
      addTearDown(cubit.close);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloadError>(),
        ]),
      );
      await cubit.download(hitoId: 'fantasma');
      await flow;

      expect(
        (cubit.state as ActaDownloadError).message,
        contains('ya no existe'),
      );
    });

    test('deja traza de auditoría de la descarga (CU-60 transitorio)',
        () async {
      final daos = await openSharedTestDaos('cu54f');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.certificado));

      final cubit = ActaDownloadCubit(
        milestoneDao: daos.milestones,
        readCachedActa: (_) async => Uint8List.fromList([1, 2, 3]),
        saveActa: ({required Uint8List bytes, required String fileName}) async =>
            '/tmp/acta.pdf',
      );
      addTearDown(cubit.close);

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      final flow = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<ActaDownloading>(),
          isA<ActaDownloaded>(),
        ]),
      );
      await cubit.download(hitoId: hito.id);
      await flow;

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('acta descargada') &&
            l.contains('hito=${hito.id}') &&
            l.contains('/tmp/acta.pdf')),
        isTrue,
      );
    });
  });

  group('Gateway de actas (IO) - CU-54', () {
    test('paso 4: sin override apunta al directorio público de descargas',
        () {
      final dir = actaDirectory();
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        expect(dir, contains('Downloads'));
      } else {
        expect(dir, endsWith(actaCacheDirName));
      }
    });

    test('guarda y localiza el PDF por convención de nombre', () async {
      final dir =
          '${Directory.systemTemp.path}/acta_io_${DateTime.now().microsecondsSinceEpoch}';
      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 50, 51]);
      final path = await saveActaFile(
        bytes: bytes,
        fileName: actaFileName('h-io'),
        directoryOverride: dir,
      );
      addTearDown(() async {
        final d = Directory(dir);
        if (await d.exists()) await d.delete(recursive: true);
      });

      expect(File(path).readAsBytesSync(), bytes);
      final local = await readLocalActa(
          hitoId: 'h-io', directoryOverride: dir);
      expect(local, isNotNull);
      expect(local, bytes);
    });

    test('localización: hito sin acta devuelve null', () async {
      final dir =
          '${Directory.systemTemp.path}/acta_io_${DateTime.now().microsecondsSinceEpoch}';
      final local = await readLocalActa(
          hitoId: 'sin-acta', directoryOverride: dir);
      expect(local, isNull);
    });
  });

  group('ActaRemoteDataSource - CU-54 paso 2 (servidor central)', () {
    // Mismo patrón que works_remote_data_source_cu13_test: Dio directo con
    // adaptador falso (evita el interceptor real de DioClient).
    Dio _fakeDio(Future<ResponseBody> Function() responder) {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpAdapter(responder);
      return dio;
    }

    test('HTTP 200 con PDF devuelve los bytes', () async {
      final source = ActaRemoteDataSource(
        dioClient: _FakeDioClient(
          _fakeDio(() async => ResponseBody.fromString(
                'pdf-fake-bytes',
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/pdf'],
                },
              )),
        ),
      );

      final bytes = await source.fetchActaPdf(hitoId: 'h1');
      expect(bytes, Uint8List.fromList('pdf-fake-bytes'.codeUnits));
    });

    test('HTTP 404 → null (el servidor aún no tiene el acta)', () async {
      final source = ActaRemoteDataSource(
        dioClient: _FakeDioClient(
          _fakeDio(() async => ResponseBody.fromString('not found', 404)),
        ),
      );

      expect(await source.fetchActaPdf(hitoId: 'h1'), isNull);
    });

    test('fallo de red → ActaRemoteException con mensaje apto', () async {
      final source = ActaRemoteDataSource(
        dioClient: _FakeDioClient(
          _fakeDio(() async => throw DioException.connectionError(
                requestOptions: RequestOptions(path: '/x'),
                reason: 'connection refused',
              )),
        ),
      );

      await expectLater(
        source.fetchActaPdf(hitoId: 'h1'),
        throwsA(isA<ActaRemoteException>()),
      );
    });
  });

  group('MilestonesSection - CU-54 paso 1 (widget)', () {
    testWidgets('el hito Certificado ofrece Descargar Acta PDF (Cualquiera)',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Cimientos',
          duracionDias: 5,
          estado: MilestoneStatus.certificado,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonesSection(
              obraId: 'w1',
              isProfesional: false,
              dataSource: dao,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Descargar Acta PDF'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('hitos no certificados no ofrecen la descarga del acta',
        (tester) async {
      final dao = FakeMilestoneDao();
      dao.seed([
        const Milestone(
            id: 'h1', obraId: 'w1', nombre: 'Cimientos', duracionDias: 5),
        const Milestone(
          id: 'h2',
          obraId: 'w1',
          nombre: 'Estructura',
          duracionDias: 5,
          estado: MilestoneStatus.enEjecucion,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MilestonesSection(
              obraId: 'w1',
              isProfesional: true,
              dataSource: dao,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Descargar Acta PDF'), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    });
  });
}
