import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';

/// Fallo de red al descargar el acta, con mensaje apto para la UI.
class ActaRemoteException implements Exception {
  final String message;

  const ActaRemoteException(this.message);

  @override
  String toString() => message;
}

/// CU-54 paso 2: localiza el acta en el servidor central (Cloud Storage).
///
/// Endpoint de certificaciones (PT-07). Null = el servidor aún no tiene el
/// acta generada para ese hito (HTTP 404): el flujo informa "no disponible"
/// en lugar de fallar.
class ActaRemoteDataSource {
  ActaRemoteDataSource({required DioClient dioClient}) : _dio = dioClient.dio;

  final Dio _dio;

  Future<Uint8List?> fetchActaPdf({required String hitoId}) async {
    try {
      final response = await _dio.get<List<int>>(
        '/certifications/hito/$hitoId/acta',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw const ActaRemoteException(
          'No se pudo descargar el acta desde el servidor central.');
    }
  }
}
