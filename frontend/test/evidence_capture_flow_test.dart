import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/gateway/capture_gateway.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';
import 'package:constructing_mobile/features/evidence/presentation/bloc/capture_flow_bloc.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'milestones_test_helpers.dart';

/// PNG 1x1 válido: permite que el estampado CU-36 tenga éxito en tests y
/// que se ejecute el persistFinal (CU-45 Sprint 4).
const pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Fakes de hardware para el flujo de captura (cámara aislada CU-37 y
/// GPS CU-34).
class FakeCaptureGateway implements CaptureGateway {
  FakeCaptureGateway({this.onCapture, Uint8List? bytes})
      : _bytes = bytes;

  final Future<String> Function(EvidenceType tipo)? onCapture;
  final Uint8List? _bytes;

  @override
  Future<String> capture({required EvidenceType tipo}) async {
    final path = await onCapture?.call(tipo);
    return path ?? 'blob://local/fake';
  }

  @override
  Future<List<int>> readBytes(String path) async =>
      _bytes ?? Uint8List.fromList(base64Decode(pngBase64));

  final List<String> persistedPaths = [];

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async {
    // Simula el persist de los bytes estampados: la "ruta" nueva describe
    // los bytes recibidos (verificación de coherencia CU-45).
    final fake = 'blob://local/persisted/${persistedPaths.length}';
    persistedPaths.add(fake);
    return fake;
  }

  @override
  Future<void> releaseTempFile(String path) async {}
}

class DeniedCaptureGateway implements CaptureGateway {
  const DeniedCaptureGateway();

  @override
  Future<String> capture({required EvidenceType tipo}) async {
    throw const CameraPermissionException(
      'Debe otorgar permisos de cámara para continuar',
    );
  }

  @override
  Future<List<int>> readBytes(String path) async => [];

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async =>
      originalPath;

  @override
  Future<void> releaseTempFile(String path) async {}
}

class FakeLocationGateway implements LocationGateway {
  const FakeLocationGateway({this.position, this.error});

  final DevicePosition? position;
  final Exception? error;

  @override
  Future<DevicePosition> getCurrentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return position!;
  }
}

/// CU-31..CU-42: flujo completo de captura de evidencia (RF_03/RF_04).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hito = Milestone(
    id: 'h1',
    obraId: 'w1',
    nombre: 'Estructura',
    duracionDias: 10,
  );
  const anclaLat = -34.6037;
  const anclaLon = -58.3816;

  Future<(CaptureFlowBloc, EvidenceLocalDataSource)> buildBloc({
    CaptureGateway? captureGateway,
    LocationGateway? locationGateway,
    double Function()? videoDuration,
  }) async {
    final dao = await openEvidenceDao('capture');
    final bloc = CaptureFlowBloc(
      captureGateway: captureGateway ?? FakeCaptureGateway(),
      locationGateway: locationGateway ??
          FakeLocationGateway(
            position: const DevicePosition(
              latitud: anclaLat,
              longitud: anclaLon,
              precisionMetros: 5,
            ),
          ),
      evidences: dao,
      hito: hito,
      obraId: 'w1',
      obraLatitud: anclaLat,
      obraLongitud: anclaLon,
      videoDurationReader: videoDuration != null
          ? (_) async => videoDuration()
          : (_) async => null,
    );
    addTearDown(bloc.close);
    return (bloc, dao);
  }

  test(
      'CU-36/CU-45 (Sprint 4): la foto guardada es el archivo ESTAMPADO, no el '
      'temporal del picker (evita divergencia de checksum en la sync)',
      () async {
    final (bloc, dao) = await buildBloc();
    bloc.add(CapturePhotoRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowPreview>()]),
    );

    bloc.add(EvidenceSaveRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
    );

    final evidences = await dao.listByHito('h1');
    // El archivo persistido describe los bytes estampados sobre los que se
    // calculó el checksum (sin esto, CU-45 da "corrupted" en bucle).
    expect(evidences.single.archivo, startsWith('blob://local/persisted'));
    expect(evidences.single.archivo, isNot('blob://local/fake'));
  });

  test('CU-31 Alt. 2.1/2.2: permiso de cámara denegado → alerta exacta',
      () async {
    final (bloc, _) = await buildBloc(
      captureGateway: const DeniedCaptureGateway(),
    );
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowFailure>().having(
          (s) => s.message,
          'message',
          'Debe otorgar permisos de cámara para continuar',
        ),
      ]),
    );
    bloc.add(CapturePhotoRequested());
    await expectation;
  });

  test('CU-32/CU-34 Alt. 4.2: sin señal GPS aborta la captura', () async {
    final (bloc, _) = await buildBloc(
      locationGateway: const FakeLocationGateway(
        error: const GeolocationException(
          'No se pudo obtener la ubicación del dispositivo.',
        ),
      ),
    );
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowFailure>().having(
          (s) => s.message,
          'message',
          'No se pudo obtener la ubicación del dispositivo.',
        ),
      ]),
    );
    bloc.add(CapturePhotoRequested());
    await expectation;
  });

  test(
      'CU-35 soft-fail (Sprint 4): fuera de los límites NO aborta; el borrador '
      'queda marcado fueraDeObra y se guarda con el flag', () async {
    final (bloc, dao) = await buildBloc(
      locationGateway: FakeLocationGateway(
        position: DevicePosition(
          latitud: -35.0,
          longitud: -59.0,
          precisionMetros: 5,
        ),
      ),
    );
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowPreview>().having(
          (s) => s.draft.fueraDeObra,
          'fueraDeObra',
          isTrue,
        ),
      ]),
    );
    bloc.add(CapturePhotoRequested());
    await expectation;

    // El guardado continúa pese a la no coincidencia de ubicación.
    final saved = expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
    );
    bloc.add(EvidenceSaveRequested());
    await saved;

    final evidences = await dao.listByHito('h1');
    expect(evidences.single.fueraDeObra, isTrue);
  });

  test(
      'CU-35 flujo normal: captura dentro del radio queda sin flag '
      'fueraDeObra', () async {
    final (bloc, dao) = await buildBloc();
    bloc.add(CapturePhotoRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowPreview>().having(
          (s) => s.draft.fueraDeObra,
          'fueraDeObra',
          isFalse,
        ),
      ]),
    );

    bloc.add(EvidenceSaveRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
    );

    final evidences = await dao.listByHito('h1');
    expect(evidences.single.fueraDeObra, isFalse);
  });

  test(
      'CU-35 soft-fail sin ancla de obra (CU-15 sin coordenadas): también '
      'queda etiquetada y se guarda', () async {
    final dao = await openEvidenceDao('capture_no_anchor');
    final bloc = CaptureFlowBloc(
      captureGateway: FakeCaptureGateway(),
      locationGateway: FakeLocationGateway(
        position: const DevicePosition(
          latitud: anclaLat,
          longitud: anclaLon,
          precisionMetros: 5,
        ),
      ),
      evidences: dao,
      hito: hito,
      obraId: 'w1',
      obraLatitud: null, // obra sin ancla geográfica
      obraLongitud: null,
    );
    addTearDown(bloc.close);

    bloc.add(CapturePhotoRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowPreview>().having(
          (s) => s.draft.fueraDeObra,
          'fueraDeObra',
          isTrue,
        ),
      ]),
    );

    bloc.add(EvidenceSaveRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
    );

    final evidences = await dao.listByHito('h1');
    expect(evidences.single.fueraDeObra, isTrue);
  });

  test(
      'CU-32 flujo completo: captura → CU-34 → CU-35 → CU-36 → guardar (CU-42)',
      () async {
    final (bloc, dao) = await buildBloc();
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowPreview>().having(
          (s) => s.draft.marcaTexto,
          'marca',
          contains('ConstructING'),
        ),
      ]),
    );
    bloc.add(CapturePhotoRequested());
    await expectation;

    // CU-39 punto de extensión: nota técnica vinculada en memoria temporal.
    bloc.add(const EvidenceNoteChanged(nota: 'Fisura menor en viga V3'));

    final saved = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowSaved>(),
      ]),
    );
    bloc.add(EvidenceSaveRequested());
    await saved;

    final evidences = await dao.listByHito('h1');
    expect(evidences.single.nota, 'Fisura menor en viga V3');
    expect(evidences.single.esSincronizado, isFalse); // encolada (CU-44)
    expect(evidences.single.checksum, isNotEmpty);
    expect(evidences.single.marcaTexto, contains('ConstructING'));
  });

  test('CU-33/CU-38: video corto capturado y guardado en caché', () async {
    final (bloc, dao) = await buildBloc(
      videoDuration: () => 20.0,
    );
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowPreview>(),
      ]),
    );
    bloc.add(RecordVideoRequested());
    await expectation;

    final saved = expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
    );
    bloc.add(EvidenceSaveRequested());
    await saved;

    final evidences = await dao.listByHito('h1');
    expect(evidences.single.tipo, EvidenceType.video);
    expect(evidences.single.duracionSeg, 20.0); // CU-38: metadato real persistido.
    expect(evidences.single.esSincronizado, isFalse);
  });

  test('CU-38 Alt. 4.2: video que supera 30 s → alerta exacta sin guardar',
      () async {
    final (bloc, dao) = await buildBloc(
      videoDuration: () => 40.0,
    );
    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CaptureFlowProcessing>(),
        isA<CaptureFlowFailure>().having(
          (s) => s.message,
          'message',
          'El video supera los 30 segundos o 15 MB permitidos',
        ),
      ]),
    );
    bloc.add(RecordVideoRequested());
    await expectation;

    // Poscondición Alt.: no queda registro persistido.
    expect(await dao.listByHito('h1'), isEmpty);
  });

  test('CU-41: descartar limpia el buffer y retorna a la vista en vivo',
      () async {
    final (bloc, dao) = await buildBloc();
    bloc.add(CapturePhotoRequested());
    await expectLater(
      bloc.stream,
      emitsInOrder([isA<CaptureFlowProcessing>(), isA<CaptureFlowPreview>()]),
    );

    final discarded = expectLater(bloc.stream, emits(isA<CaptureFlowReady>()));
    bloc.add(EvidenceDiscardRequested());
    await discarded;

    // Poscondición CU-41: memoria liberada, sin archivos basura (nada persistido).
    expect(await dao.listByHito('h1'), isEmpty);
  });
}
