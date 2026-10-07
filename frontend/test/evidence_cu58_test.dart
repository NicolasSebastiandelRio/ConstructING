import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/crypto/evidence_hash_service.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/gateway/capture_gateway.dart';
import 'package:constructing_mobile/features/evidence/gateway/location_gateway.dart';
import 'package:constructing_mobile/features/evidence/presentation/bloc/capture_flow_bloc.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'milestones_test_helpers.dart';

/// PNG 1x1 válido: la captura de prueba produce bytes reales en memoria.
const pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class FakeCaptureGateway implements CaptureGateway {
  @override
  Future<String> capture({required EvidenceType tipo}) async =>
      'blob://local/fake';

  @override
  Future<List<int>> readBytes(String path) async =>
      Uint8List.fromList(base64Decode(pngBase64));

  @override
  Future<String> persistFinal(
    List<int> bytes, {
    required String originalPath,
  }) async =>
      'blob://local/persisted/0';

  @override
  Future<void> releaseTempFile(String path) async {}
}

class FakeLocationGateway implements LocationGateway {
  const FakeLocationGateway();

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

/// Motor espía: delega el cálculo real y registra las invocaciones para
/// probar que el hash se computa durante el almacenamiento (CU-58).
class SpyHashService implements EvidenceHashService {
  SpyHashService();

  int calls = 0;

  @override
  Future<String> hashBytes(Uint8List bytes) async {
    calls++;
    return const EvidenceHashService().hashBytes(bytes);
  }
}

/// CU-58 (Calcular Hash SHA-256, RF_08/RNF_S_03).
void main() {
  group('EvidenceHashService - Motor Criptográfico (pasos 2+4)', () {
    test('vector conocido: SHA-256 de "abc"', () async {
      final hash = await const EvidenceHashService()
          .hashBytes(Uint8List.fromList(utf8.encode('abc')));
      expect(
        hash,
        'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
      );
    });

    test('formato: cadena alfanumérica de 64 hex en mayúsculas', () async {
      final hash = await const EvidenceHashService()
          .hashBytes(Uint8List.fromList([1, 2, 3]));
      expect(hash, hasLength(64));
      expect(hash, matches(RegExp(r'^[0-9A-F]{64}$')));
    });

    test('determinista: mismos bytes, mismo hash', () async {
      const service = EvidenceHashService();
      final bytes = Uint8List.fromList(base64Decode(pngBase64));
      expect(await service.hashBytes(bytes), await service.hashBytes(bytes));
    });

    test('poscondición: alterar un solo píxel cambia radicalmente el hash',
        () async {
      const service = EvidenceHashService();
      final original = Uint8List.fromList(base64Decode(pngBase64));
      final alterado = Uint8List.fromList(original)..[10] ^= 0x01;
      final hashOriginal = await service.hashBytes(original);
      final hashAlterado = await service.hashBytes(alterado);
      expect(hashAlterado, isNot(hashOriginal));
      expect(hashAlterado, hasLength(64));
    });

    test('entrada vacía: hash SHA-256 válido del vacío', () async {
      final hash =
          await const EvidenceHashService().hashBytes(Uint8List(0));
      expect(
        hash,
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
      );
    });
  });

  group('CU-58 invocado durante el almacenamiento (CU-32/CU-33 → CU-42)',
      () {
    test(
        'el registro guardado lleva el hash del motor calculado sobre el '
        'binario en memoria', () async {
      final dao = await openEvidenceDao('cu58');
      final spy = SpyHashService();
      final bloc = CaptureFlowBloc(
      auditLog: await openTestAuditLogWriter('auch2'),
        captureGateway: FakeCaptureGateway(),
        locationGateway: const FakeLocationGateway(),
        evidences: dao,
        hito: const Milestone(
          id: 'h1',
          obraId: 'w1',
          nombre: 'Estructura',
          duracionDias: 10,
        ),
        obraId: 'w1',
        obraLatitud: -34.6037,
        obraLongitud: -58.3816,
        videoDurationReader: (_) async => null,
        hashService: spy,
      );
      addTearDown(bloc.close);

      bloc.add(CapturePhotoRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder(
            [isA<CaptureFlowProcessing>(), isA<CaptureFlowPreview>()]),
      );
      final draft =
          (bloc.state as CaptureFlowPreview).draft;

      bloc.add(EvidenceSaveRequested());
      await expectLater(
        bloc.stream,
        emitsInOrder(
            [isA<CaptureFlowProcessing>(), isA<CaptureFlowSaved>()]),
      );

      // Paso 2: el motor se invocó durante el almacenamiento.
      expect(spy.calls, 1);
      // Paso 4: el hash asociado al registro es el del binario en memoria.
      final guardadas = await dao.listByHito('h1');
      expect(guardadas, hasLength(1));
      final esperado = await const EvidenceHashService()
          .hashBytes(Uint8List.fromList(draft.bytes));
      expect(guardadas.single.checksum, esperado);
      expect(guardadas.single.checksum, draft.checksum);
    });
  });
}
