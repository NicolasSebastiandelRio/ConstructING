import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<Map<String, dynamic>> login(String email, String password);
  Future<UserModel> register({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? matricula,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final DioClient _dioClient;

  AuthRemoteDataSourceImpl({required DioClient dioClient}) : _dioClient = dioClient;

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dioClient.dio.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      // El backend retorna un objeto conteniendo el token JWT y los datos del usuario
      return {
        'access_token': response.data['access_token'],
        'user': UserModel.fromJson(response.data['user']),
      };
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? 'Error al iniciar sesión. Verifique sus credenciales.',
      );
    }
  }

  @override
  Future<UserModel> register({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? matricula,
  }) async {
    try {
      final response = await _dioClient.dio.post(
        '/auth/register',
        data: {
          'nombre': nombre,
          'email': email,
          'password': password,
          'rol': rol,
          if (matricula != null) 'matricula': matricula,
        },
      );

      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? 'Error al registrar el usuario en el sistema.',
      );
    }
  }
}