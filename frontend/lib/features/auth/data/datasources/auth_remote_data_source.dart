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

      // Programación defensiva: aseguramos extraer el objeto 'user' o crearlo de forma segura
      final rawUser = response.data['user'] ?? response.data;
      final Map<String, dynamic> userData = (rawUser is Map<String, dynamic>)
          ? rawUser
          : {
              'id': response.data['sub'] ?? 'temp-id',
              'nombre': 'Usuario ConstructING',
              'email': email,
              'rol': response.data['role'] ?? 'Propietario',
            };

      return {
        'access_token': response.data['access_token'],
        'user': UserModel.fromJson(userData),
      };
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al iniciar sesión. Verifique sus credenciales.');
      throw Exception(errorMessage);
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
          'role': rol, // Alineado con NestJS
          if (matricula != null) 'matricula': matricula,
        },
      );

      // Programación defensiva para el registro
      final rawUser = response.data['user'] ?? response.data;
      final Map<String, dynamic> userData = (rawUser is Map<String, dynamic>)
          ? rawUser
          : {
              'id': response.data['userId'] ?? response.data['id'] ?? 'temp-id',
              'nombre': nombre,
              'email': email,
              'rol': rol,
              'matricula': matricula,
            };

      return UserModel.fromJson(userData);
    } on DioException catch (e) {
      final dynamic msg = e.response?.data['message'];
      final errorMessage = msg is List ? msg.join(', ') : (msg ?? 'Error al registrar el usuario en el sistema.');
      throw Exception(errorMessage);
    }
  }
}