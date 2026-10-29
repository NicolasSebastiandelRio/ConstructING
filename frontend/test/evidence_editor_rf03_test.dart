import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/audit/data/audit_log_writer.dart';
import 'package:constructing_mobile/features/audit/data/datasources/audit_log_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/editing/evidence_edit_ops.dart';
import 'package:constructing_mobile/features/evidence/domain/datastamp/stamp_layout.dart';
import 'package:constructing_mobile/features/evidence/domain/validation/evidence_file_validator.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/gateway/capture_gateway.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';
import 'package:constructing_mobile/features/evidence/presentation/bloc/capture_flow_bloc.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

/// Imagen JPEG sintética de [w]×[h] píxeles (formato admitido por RF_03).
Uint8List _imagen({int w = 40, int h = 20}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 100, 50));
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// Imagen PNG: NO admitida por RF_03 (debe rechazarse con mensaje claro).
Uint8List _png({int w = 40, int h = 20}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(20, 200, 120));
  return Uint8List.fromList(img.encodePng(im));
}

int _ancho(Uint8List bytes) => img.decodeImage(bytes)!.width;
int _alto(Uint8List bytes) => img.decodeImage(bytes)!.height;

class _FakeCaptureGateway implements CaptureGateway {
  _FakeCaptureGateway({Uint8List? bytes}) : bytes = bytes ?? _imagen();

  final Uint8List bytes;
  final List<EvidenceType> capturas = [];

  @override
  Future<String> capture({required EvidenceType tipo}) async {
    capturas.add(tipo);
    return 'blob://captura';
  }

  @override
  Future<List<int>> readBytes(String path) async => bytes;

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async =>
      'blob://final';

  @override
  Future<void> releaseTempFile(String path) async {}
}

class _FakeLocationGateway implements LocationGateway {
  @override
  Future<DevicePosition> getCurrentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      const DevicePosition(
        latitud: -34.6037,
        longitud: -58.3816,
        precisionMetros: 5,
      );
}

class _Ctx {
  final EvidenceLocalDataSource evidences;
  final AuditLogLocalDataSource auditDao;
  final AuditLogWriter auditWriter;

  const _Ctx({
    required this.evidences,
    required this.auditDao,
    required this.auditWriter,
  });
}

Future<_Ctx> _contexto(String nombre) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/ed_${nombre}_'
      '${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  final auditDao = AuditLogLocalDataSource(localDatabase: localDb);
  return _Ctx(
    evidences: EvidenceLocalDataSource(localDatabase: localDb),
    auditDao: auditDao,
    auditWriter: AuditLogWriter(
      dataSource: auditDao,
      userIdReader: () async => 'test-user',
    ),
  );
}

Milestone _hito() => const Milestone(
      id: 'h1',
      obraId: 'w1',
      nombre: 'Estructura',
      duracionDias: 10,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RF_03 - EvidenceEditOps (recorte y giro)', () {
    test('girar 90° intercambia ancho y alto', () {
      final original = _imagen(w: 40, h: 20);
      final girada = EvidenceEditOps.rotate(original, 1)!;
      expect(girada.width, 20);
      expect(girada.height, 40);
    });

    test('cuatro giros vuelven a la orientación original', () {
      final original = _imagen(w: 40, h: 20);
      final girada = EvidenceEditOps.rotate(original, 4)!;
      expect(girada.width, 40);
      expect(girada.height, 20);
    });

    test('el recorte devuelve exactamente el área pedida', () {
      final original = _imagen(w: 40, h: 20);
      final recortada = EvidenceEditOps.rotateAndCrop(
        original: original,
        quarterTurns: 0,
        x: 5,
        y: 4,
        width: 12,
        height: 8,
      )!;
      expect(recortada.width, 12);
      expect(recortada.height, 8);
      expect(_ancho(recortada.bytes), 12);
      expect(_alto(recortada.bytes), 8);
    });

    test('giro + recorte en una pasada sobre la imagen ya girada', () {
      final original = _imagen(w: 40, h: 20);
      // Tras girar 90°, la imagen mide 20×40: el recorte se aplica ahí.
      final recortada = EvidenceEditOps.rotateAndCrop(
        original: original,
        quarterTurns: 1,
        x: 0,
        y: 0,
        width: 10,
        height: 30,
      )!;
      expect(recortada.width, 10);
      expect(recortada.height, 30);
    });

    test('el recorte fuera de límites se acota en vez de romper', () {
      final original = _imagen(w: 40, h: 20);
      final recortada = EvidenceEditOps.rotateAndCrop(
        original: original,
        quarterTurns: 0,
        x: 35,
        y: 15,
        width: 100,
        height: 100,
      )!;
      expect(recortada.width, lessThanOrEqualTo(5));
      expect(recortada.height, lessThanOrEqualTo(5));
      expect(recortada.width, greaterThan(0));
      expect(recortada.height, greaterThan(0));
    });

    test('bytes no decodificables devuelven null (no lanzan)', () {
      final basura = Uint8List.fromList([1, 2, 3, 4]);
      expect(EvidenceEditOps.rotate(basura, 1), isNull);
      expect(
        EvidenceEditOps.rotateAndCrop(
          original: basura,
          quarterTurns: 0,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
        ),
        isNull,
      );
    });
  });

  group('CU-36 - StampLayout (marca proporcional a la imagen)', () {
    test('una imagen recortada chica NO recibe la fuente fija de 24 px', () {
      final tamano = StampLayout.fontSizeFor(300, 300);
      expect(tamano, lessThan(24));
      expect(tamano, greaterThanOrEqualTo(StampLayout.minFontSize));
      expect(tamano, closeTo(12.6, 0.5));
    });

    test('una foto grande se acota al máximo legible', () {
      expect(StampLayout.fontSizeFor(4000, 3000), StampLayout.maxFontSize);
    });

    test('usa el LADO MENOR: un recorte ancho y bajo no agranda la marca', () {
      // Misma anchura, distinta altura: manda el lado menor (600 < 3000).
      expect(
        StampLayout.fontSizeFor(4000, 600),
        lessThan(StampLayout.fontSizeFor(4000, 3000)),
      );
      expect(StampLayout.fontSizeFor(4000, 600), closeTo(25.2, 0.5));
    });

    test('la banda nunca supera el 45% del alto', () {
      expect(StampLayout.maxBandHeight(1000), 450);
      expect(StampLayout.fits(textHeight: 400, height: 1000), isTrue);
      expect(StampLayout.fits(textHeight: 500, height: 1000), isFalse);
    });
  });

  group('RF_03 - EvidenceFileValidator (solo JPG/JPEG)', () {
    test('acepta JPEG y rechaza PNG por CONTENIDO', () {
      expect(EvidenceFileValidator.esJpeg(_imagen()), isTrue);
      expect(EvidenceFileValidator.rechazo(_imagen()), isNull);
      expect(EvidenceFileValidator.esJpeg(_png()), isFalse);
      expect(EvidenceFileValidator.rechazo(_png()),
          EvidenceFileValidator.notJpegMessage);
    });

    test('un PNG renombrado a .jpg se rechaza igual', () {
      expect(
        EvidenceFileValidator.rechazo(_png(), path: '/tmp/foto.jpg'),
        EvidenceFileValidator.notJpegMessage,
      );
    });

    test('archivo vacío tiene su propio mensaje', () {
      expect(EvidenceFileValidator.rechazo(const []),
          EvidenceFileValidator.emptyMessage);
    });
  });

  group('RF_03 - CaptureFlowBloc con galería y edición', () {
    test('PickPhotoFromGallery usa el selector y NO abre la cámara', () async {
      final ctx = await _contexto('galeria');
      final gateway = _FakeCaptureGateway();
      var selecciones = 0;
      final bloc = CaptureFlowBloc(
        captureGateway: gateway,
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        pickFromGallery: () async {
          selecciones++;
          return 'blob://galeria';
        },
        editImage: (bytes) async => bytes, // sin cambios
      );
      addTearDown(bloc.close);

      final espera =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowPreview>()));
      bloc.add(PickPhotoFromGalleryRequested());
      await espera;

      expect(selecciones, 1);
      expect(gateway.capturas, isEmpty);
    });

    test('cancelar la edición vuelve al entorno sin crear borrador', () async {
      final ctx = await _contexto('cancelar');
      List<int>? recibidos;
      final bloc = CaptureFlowBloc(
        captureGateway: _FakeCaptureGateway(),
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        editImage: (bytes) async {
          recibidos = bytes;
          return null; // el usuario cancela
        },
      );
      addTearDown(bloc.close);

      final espera =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowReady>()));
      bloc.add(CapturePhotoRequested());
      await espera;

      expect(recibidos, isNotNull);
      expect(await ctx.evidences.listByHito('h1'), isEmpty);
    });

    test('la edición se aplica ANTES de la marca y del checksum', () async {
      final ctx = await _contexto('editado');
      final recortada = EvidenceEditOps.rotateAndCrop(
        original: _imagen(w: 40, h: 20),
        quarterTurns: 0,
        x: 0,
        y: 0,
        width: 24,
        height: 12,
      )!;
      var editado = false;
      final bloc = CaptureFlowBloc(
        captureGateway: _FakeCaptureGateway(),
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        editImage: (bytes) async {
          editado = true;
          return recortada.bytes;
        },
      );
      addTearDown(bloc.close);

      final espera =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowPreview>()));
      bloc.add(CapturePhotoRequested());
      await espera;

      expect(editado, isTrue);
      final draft = (bloc.state as CaptureFlowPreview).draft;
      // La marca (CU-36) se estampa sobre la imagen YA recortada: el ancho
      // resultante no puede superar el del recorte (24 px).
      expect(_ancho(Uint8List.fromList(draft.bytes)), lessThanOrEqualTo(24));
    });

    test('el origen de la imagen queda en la huella de auditoría (CU-60)',
        () async {
      final ctx = await _contexto('origen');
      final bloc = CaptureFlowBloc(
        captureGateway: _FakeCaptureGateway(),
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        pickFromGallery: () async => 'blob://galeria',
        editImage: (bytes) async => bytes,
      );
      addTearDown(bloc.close);

      final previewEsperado =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowPreview>()));
      bloc.add(PickPhotoFromGalleryRequested());
      await previewEsperado;

      final guardado =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowSaved>()));
      bloc.add(EvidenceSaveRequested());
      await guardado;

      final huellas = await ctx.auditDao.listByObra('w1');
      final carga =
          huellas.firstWhere((h) => h.accion == 'evidencia_cargada');
      expect(carga.detalle, contains('origen=galeria'));
    });

    test('una PNG se RECHAZA con mensaje y no crea evidencia ni abre el editor',
        () async {
      final ctx = await _contexto('png');
      var editorAbierto = false;
      final bloc = CaptureFlowBloc(
        captureGateway: _FakeCaptureGateway(bytes: _png()),
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        editImage: (bytes) async {
          editorAbierto = true;
          return bytes;
        },
      );
      addTearDown(bloc.close);

      final espera =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowFailure>()));
      bloc.add(CapturePhotoRequested());
      await espera;

      expect((bloc.state as CaptureFlowFailure).message,
          EvidenceFileValidator.notJpegMessage);
      expect(editorAbierto, isFalse);
      expect(await ctx.evidences.listByHito('h1'), isEmpty);
    });

    test('si el procesamiento de la imagen falla, se informa (no crashea)',
        () async {
      final ctx = await _contexto('fallaEditor');
      final bloc = CaptureFlowBloc(
        captureGateway: _FakeCaptureGateway(),
        locationGateway: _FakeLocationGateway(),
        evidences: ctx.evidences,
        hito: _hito(),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        auditLog: ctx.auditWriter,
        videoDurationReader: (_) async => null,
        editImage: (bytes) async => throw StateError('boom'),
      );
      addTearDown(bloc.close);

      final espera =
          expectLater(bloc.stream, emitsThrough(isA<CaptureFlowFailure>()));
      bloc.add(CapturePhotoRequested());
      await espera;

      expect((bloc.state as CaptureFlowFailure).message,
          contains('No se pudo procesar la imagen'));
      expect(await ctx.evidences.listByHito('h1'), isEmpty);
    });
  });
}
