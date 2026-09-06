import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/dio_client.dart';
import '../models/work_model.dart';
import '../models/work_invitation.dart';

abstract class WorksRemoteDataSource {
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false});
  Future<WorkModel> getWorkById(String id);
  Future<WorkModel> createWork(Map<String, dynamic> workData);
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData);
  Future<WorkModel> updateWorkStatus(String id, String estado);
  Future<void> archiveWork(String id);
  Future<WorkInvitation> inviteOwner(String workId, String email);
}

class WorksRemoteDataSourceImpl implements WorksRemoteDataSource {
  final DioClient dioClient;
  final FlutterSecureStorage secureStorage;

  WorksRemoteDataSourceImpl({
    required this.dioClient,
    required this.secureStorage,
  });

  Future<Options> _getAuthOptions() async {
    final token = await secureStorage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// CU-18 (+ CU-21 paso 4: Historial): con `propietarioId` trae "Mis Obras";
  /// sin él, el listado general. Con `archivedOnly`, sólo las archivadas.
  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.get(
        '/works',
        queryParameters: {
          if (propietarioId != null) 'propietarioId': propietarioId,
          if (archivedOnly) 'archived': 'true',
        },
        options: options,
      );
      final List data = response.data;
      return data.map((json) => WorkModel.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error al obtener las obras.');
    }
  }

  /// CU-19: recupera los datos maestros de una obra desde la BD.
  @override
  Future<WorkModel> getWorkById(String id) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.get('/works/$id', options: options);
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al consultar la obra.');
      }
      return WorkModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al consultar la obra.');
      throw Exception(errorMessage);
    }
  }

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.post(
        '/works',
        data: workData,
        options: options,
      );
      return WorkModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error al crear la obra.');
    }
  }

  /// CU-21: archiva una obra completada (DELETE /works/:id → 204).
  @override
  Future<void> archiveWork(String id) async {
    try {
      final options = await _getAuthOptions();
      await dioClient.dio.delete('/works/$id', options: options);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage =
          msg is List ? msg.join(', ') : (msg ?? 'Error al archivar la obra.');
      throw Exception(errorMessage);
    }
  }

  /// CU-22 pasos 1-2: genera el código de invitación para un correo no
  /// registrado, asociado a la obra.
  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.post(
        '/works/$workId/invitations',
        data: {'email': email},
        options: options,
      );
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al generar la invitación.');
      }
      return WorkInvitation.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage =
          msg is List ? msg.join(', ') : (msg ?? 'Error al generar la invitación.');
      throw Exception(errorMessage);
    }
  }

  /// CU-20: cambia la fase global de la obra.
  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.patch(
        '/works/$id/status',
        data: {'estado': estado},
        options: options,
      );
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al actualizar el estado.');
      }
      return WorkModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage =
          msg is List ? msg.join(', ') : (msg ?? 'Error al actualizar el estado.');
      throw Exception(errorMessage);
    }
  }

  /// CU-17: edita los datos administrativos de la obra.
  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.patch(
        '/works/$id',
        data: workData,
        options: options,
      );
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al actualizar la obra.');
      }
      return WorkModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al actualizar la obra.');
      throw Exception(errorMessage);
    }
  }
}