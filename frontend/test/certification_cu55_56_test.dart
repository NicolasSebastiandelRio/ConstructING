import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import 'package:constructing_mobile/features/certification/data/acta_pdf_generator.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/domain/stroke_metadata.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_bloc.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_event.dart';
import 'package:constructing_mobile/features/certification/presentation/bloc/certification_state.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

import 'milestones_test_helpers.dart';

/// Trazo sintético de firma: línea recta de [length] px con 3 puntos.
List<SignaturePoint> _trazo({
  double length = 200,
  int t0 = 1000,
  int dt = 150,
  double pressure = 0.8,
}) => [
      SignaturePoint(x: 0, y: 0, t: t0, pressure: pressure),
      SignaturePoint(x: length / 2, y: 0, t: t0 + dt, pressure: pressure),
      SignaturePoint(x: length, y: 0, t: t0 + 2 * dt, pressure: pressure),
    ];

Milestone _hito() => const Milestone(
      id: 'h1',
      obraId: 'w1',
      nombre: 'Cimientos',
      descripcion: 'Excavación y platea',
      duracionDias: 5,
      estado: MilestoneStatus.enEjecucion,
      esCritico: true,
    );

/// PNG mínimo (8x8) con el paquete image, para incrustar en el acta.
Uint8List _pngFixture() {
  final image = im.Image(width: 8, height: 8, numChannels: 3);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixel(x, y, im.ColorRgb8(200, 60, 30));
    }
  }
  return im.encodePng(image);
}

Evidence _foto({required String archivo, bool sincronizada = false}) =>
    Evidence(
      id: archivo.hashCode.toString(),
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: archivo,
      nota: 'Fisura menor en V3',
      latitud: -34.6,
      longitud: -58.4,
      precisionMetros: 5,
      fechaCaptura: DateTime(2026, 9, 1, 10, 30),
      tamanoBytes: 1024,
      checksum: 'abc',
      marcaTexto: 'ConstructING',
      fueraDeObra: true,
      esSincronizado: sincronizada,
    );

void main() {
  group('StrokeMetadataExtractor - CU-55', () {
    test('extrae presión, velocidad y coordenadas del trazo', () {
      final metadata = StrokeMetadataExtractor.extract(
        trazos: [SignatureStroke(_trazo(length: 200, pressure: 0.6))],
      );

      expect(metadata.trazosCount, 1);
      expect(metadata.puntosCount, 3);
      expect(metadata.longitudTotalPx, 200.0);
      expect(metadata.duracionMs, 300.0);
      // 200 px en 300 ms = 666.67 px/s.
      expect(metadata.velocidadMediaPxS, closeTo(666.67, 0.01));
      expect(metadata.presionMedia, 0.6);
      expect(metadata.presionMaxima, 0.6);
      expect(metadata.minX, 0);
      expect(metadata.maxX, 200);
      expect(metadata.minY, 0);
      expect(metadata.maxY, 0);
    });

    test('varios trazos: longitud y presión agregadas', () {
      final metadata = StrokeMetadataExtractor.extract(trazos: [
        SignatureStroke(_trazo(length: 100, pressure: 0.4)),
        SignatureStroke(_trazo(length: 150, t0: 2000, pressure: 0.9)),
      ]);

      expect(metadata.trazosCount, 2);
      expect(metadata.longitudTotalPx, 250.0);
      expect(metadata.duracionMs, 1300.0); // 1000 → 2300.
      expect(metadata.presionMaxima, 0.9);
      expect(
        metadata.presionMedia,
        closeTo((0.4 * 3 + 0.9 * 3) / 6, 0.001),
      );
    });

    test('sin trazos → metadatos en cero', () {
      final metadata = StrokeMetadataExtractor.extract(trazos: const []);
      expect(metadata.puntosCount, 0);
      expect(metadata.velocidadMediaPxS, 0);
    });

    test('paso 4: retorna objeto de datos (JSON) acoplable al acta', () {
      final trazos = [SignatureStroke(_trazo(length: 200, pressure: 0.5))];
      final metadata = StrokeMetadataExtractor.extract(trazos: trazos);

      final json = metadata.toJson(trazos: trazos);

      expect(json['trazos_count'], 1);
      expect(json['puntos_count'], 3);
      expect(json['longitud_total_px'], 200.0);
      expect(json['duracion_ms'], 300.0);
      expect(json['velocidad_media_px_s'], 666.67);
      expect(json['presion_media'], 0.5);
      expect((json['area_px'] as Map)['min_x'], 0.0);
      expect((json['area_px'] as Map)['max_x'], 200.0);
      final trazosJson = json['trazos'] as List;
      expect(trazosJson, hasLength(1));
      final puntosJson = (trazosJson.first as Map)['puntos'] as List;
      expect(puntosJson, hasLength(3));
      final primerPunto = puntosJson.first as Map;
      expect(primerPunto['x'], 0.0);
      expect(primerPunto['y'], 0.0);
      expect(primerPunto['t'], 1000);
      expect(primerPunto['presion'], 0.5);
    });
  });

  group('DefaultActaPdfGenerator - CU-56', () {
    test('retorna PDF binario con datos maestros, evidencias y firma',
        () async {
      final dir =
          '${Directory.systemTemp.path}/acta56_${DateTime.now().microsecondsSinceEpoch}';
      final png = _pngFixture();
      final archivoFoto = File(await saveActaFixture(dir, 'foto1.png'));
      await archivoFoto.writeAsBytes(png);
      addTearDown(() async {
        final d = Directory(dir);
        if (await d.exists()) await d.delete(recursive: true);
      });

      final payload = ActaPayload(
        actaId: 'acta-test-1',
        hito: _hito(),
        obraNombre: 'Torre Norte',
        propietarioNombre: 'Juan Pérez',
        evidencias: [
          _foto(archivo: archivoFoto.path),
          _foto(archivo: '', sincronizada: true),
          Evidence(
            id: 'v1',
            hitoId: 'h1',
            obraId: 'w1',
            tipo: EvidenceType.video,
            archivo: '',
            latitud: -34.6,
            longitud: -58.4,
            precisionMetros: 5,
            fechaCaptura: DateTime(2026, 9, 2, 11, 0),
            duracionSeg: 12.5,
            tamanoBytes: 2048,
            checksum: 'def',
            marcaTexto: 'ConstructING',
          ),
        ],
        trazosFirma: [SignatureStroke(_trazo(length: 250))],
        metadatos: StrokeMetadataExtractor.extract(
            trazos: [SignatureStroke(_trazo(length: 250))]),
        firmante: 'Profesional',
        fechaConformidad: DateTime(2026, 10, 4, 9, 45),
      );

      final bytes = await DefaultActaPdfGenerator(
        readImageBytes: (archivo) => File(archivo).readAsBytes(),
      ).generate(payload);

      expect(bytes, isNotEmpty);
      expect(
        String.fromCharCodes(bytes.sublist(0, 8)),
        startsWith('%PDF-'),
      );
      // Cola del documento con marcador de cierre.
      expect(
        String.fromCharCodes(bytes.sublist(bytes.length - 32)),
        contains('%%EOF'),
      );
    });

    test('sin reader o con archivo inexistente: el acta no se bloquea',
        () async {
      final payload = ActaPayload(
        actaId: 'acta-test-2',
        hito: _hito(),
        evidencias: [
          _foto(archivo: '/cache/inexistente.png'),
          _foto(archivo: '', sincronizada: true),
        ],
        trazosFirma: [SignatureStroke(_trazo(length: 250))],
        metadatos: StrokeMetadataExtractor.extract(
            trazos: [SignatureStroke(_trazo(length: 250))]),
        firmante: 'Propietario',
        fechaConformidad: DateTime(2026, 10, 4),
      );

      final bytes = await DefaultActaPdfGenerator().generate(payload);
      expect(
        String.fromCharCodes(bytes.sublist(0, 5)),
        '%PDF-',
      );
    });
  });

  group('CertificationBloc - pipeline CU-52 → CU-55 → CU-56', () {
    test('Confirmar genera metadatos + acta y la persiste en caché', () async {
      final daos = await openSharedTestDaos('cu5556a');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      // CU-57: el pipeline de certificación congela desde "En Ejecución".
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      ActaPayload? generatorPayload;
      Uint8List? persistedBytes;
      String? persistedName;
      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au55'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        firmante: 'Profesional',
        actaGenerator: (payload) async {
          generatorPayload = payload;
          return Uint8List.fromList([37, 80, 68, 70, 45]);
        },
        persistActa: ({required Uint8List bytes, required String fileName}) async {
          persistedBytes = bytes;
          persistedName = fileName;
          return '/caché/$fileName';
        },
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
      // CU-55: firma enriquecida con metadatos biométricos.
      expect(captured.metadatos.puntosCount, 3);
      expect(captured.metadatos.longitudTotalPx, 250.0);
      // CU-56: acta persistida en el caché local (la localiza el CU-54).
      expect(captured.actaPath, '/caché/acta_${hito.id}.pdf');
      expect(persistedBytes, isNotEmpty);
      expect(persistedName, 'acta_${hito.id}.pdf');
      // El payload llegó al motor con hito y firmante.
      expect(generatorPayload?.hito.id, hito.id);
      expect(generatorPayload?.firmante, 'Profesional');
      expect(generatorPayload?.metadatos.puntosCount, 3);
    });

    test('fallo del motor de PDF → CertificationError (sin acta)', () async {
      final daos = await openSharedTestDaos('cu5556b');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au55'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        actaGenerator: (payload) async => throw Exception('Motor caído'),
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
          isA<CertificationError>(),
        ]),
      );
      bloc.add(SignatureStrokeCommitted(points: _trazo(length: 250)));
      bloc.add(const SignatureConfirmationRequested());
      await flow;

      expect((bloc.state as CertificationError).message, contains('Motor'));
    });

    test('deja traza de auditoría con metadatos del trazo (CU-60 transitorio)',
        () async {
      final daos = await openSharedTestDaos('cu5556c');
      final hito = await daos.milestones
          .create(obraId: 'w1', nombre: 'Hito', duracionDias: 3);
      // CU-57: el pipeline de certificación congela desde "En Ejecución".
      await daos.milestones
          .update(hito.copyWith(estado: MilestoneStatus.enEjecucion));

      final bloc = CertificationBloc(
      auditLog: await openTestAuditLogWriter('au55'),
        milestoneDao: daos.milestones,
        evidenceDao: daos.evidences,
        actaGenerator: (payload) async =>
            Uint8List.fromList([37, 80, 68, 70]),
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

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

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

      expect(
        lines.any((l) =>
            l.contains('[AUDIT-CU60-PENDIENTE]') &&
            l.contains('firma manuscrita capturada') &&
            l.contains('hito=${hito.id}') &&
            l.contains('trazos=1')),
        isTrue,
      );
    });
  });
}

/// Escribe un archivo fixture en [dir] y devuelve su ruta.
Future<String> saveActaFixture(String dir, String name) async {
  final d = Directory(dir);
  if (!await d.exists()) await d.create(recursive: true);
  return '$dir/$name';
}
