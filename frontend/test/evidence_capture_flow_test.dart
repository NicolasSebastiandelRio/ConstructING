import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/gateway/capture_gateway.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';
import 'package:constructing_mobile/features/evidence/presentation/bloc/capture_flow_bloc.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'milestones_test_helpers.dart';

/// Fakes de hardware para el flujo de captura (cámara aislada CU-37 y
/// GPS CU-34).
class FakeCaptureGateway implements CaptureGateway {
  FakeCaptureGateway({this.onCapture, this.bytes});

  final Future<String> Function(EvidenceType tipo)? onCapture;
  final Uint8List Function()? bytes;

  @override
  Future<String> capture({required EvidenceType tipo}) async {
    final path = await onCapture?.call(tipo);
    return path ?? 'blob://local/fake';
  }

  @override
  Future<List<int>> readBytes(String path) async =>
      bytes?.call() ?? Uint8List.fromList([9, 9, 9]);

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
    );
    addTearDown(bloc.close);
    return (bloc, dao);
  }

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

  test('CU-35 Alt. 4.2: fuera de los límites de la obra aborta el guardado',
      () async {
    final (bloc, _) = await buildBloc(
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
        isA<CaptureFlowFailure>().having(
          (s) => s.message,
          'message',
          'Se encuentra fuera de los límites de la obra',
        ),
      ]),
    );
    bloc.add(CapturePhotoRequested());
    await expectation;
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
    final (bloc, dao) = await buildBloc();
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
    expect(evidences.single.esSincronizado, isFalse);
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
