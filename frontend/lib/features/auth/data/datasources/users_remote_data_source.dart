import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../models/user_model.dart';

/// Contrato de acceso remoto para usuarios.
/// Cubre CU-07 (Modificar), CU-08 (Inhabilitar) y CU-09 (Listar).
abstract class UsersRemoteDataSource {
  Future<List<UserModel>> getUsers();
  Future<UserModel> updateUser(String id, {String? nombre, String? email, String? password});
  Future<void> deleteUser(String id);
  Future<UserModel> restoreUser(String id);
}

class UsersRemoteDataSourceImpl implements UsersRemoteDataSource {
  final DioClient _dioClient;

  UsersRemoteDataSourceImpl({required DioClient dioClient}) : _dioClient = dioClient;

  @override
  Future<List<UserModel>> getUsers() async {
    try {
      final response = await _dioClient.dio.get('/users');
      final data = response.data;
      if (data is! List) {
        throw Exception('Respuesta inválida al consultar usuarios.');
      }
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserModel.fromJson)
          .toList();
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al consultar los usuarios.');
      throw Exception(errorMessage);
    }
  }

  @override
  Future<UserModel> updateUser(
    String id, {
    String? nombre,
    String? email,
    String? password,
  }) async {
    try {
      final response = await _dioClient.dio.patch(
        '/users/$id',
        data: {
          if (nombre != null) 'nombre': nombre,
          if (email != null) 'email': email,
          if (password != null) 'password': password,
        },
      );

      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al actualizar el usuario.');
      }
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al actualizar el usuario.');
      throw Exception(errorMessage);
    }
  }

  @override
  Future<void> deleteUser(String id) async {
    try {
      await _dioClient.dio.delete('/users/$id');
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al inhabilitar el usuario.');
      throw Exception(errorMessage);
    }
  }

  /// CU-08 (complemento operativo): habilita un usuario inhabilitado.
  @override
  Future<UserModel> restoreUser(String id) async {
    try {
      final response = await _dioClient.dio.post('/users/$id/restore');
      if (response.data is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al habilitar el usuario.');
      }
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al habilitar el usuario.');
      throw Exception(errorMessage);
    }
  }
}