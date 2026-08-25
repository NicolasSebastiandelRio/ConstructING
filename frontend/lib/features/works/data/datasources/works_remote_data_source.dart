import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/dio_client.dart';
import '../models/work_model.dart';

abstract class WorksRemoteDataSource {
  Future<List<WorkModel>> getWorks();
  Future<WorkModel> createWork(Map<String, dynamic> workData);
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

  @override
  Future<List<WorkModel>> getWorks() async {
    try {
      final options = await _getAuthOptions();
      final response = await dioClient.dio.get('/works', options: options);
      final List data = response.data;
      return data.map((json) => WorkModel.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error al obtener las obras.');
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
}