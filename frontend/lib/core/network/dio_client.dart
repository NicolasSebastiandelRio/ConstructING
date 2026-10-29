import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DioClient {
  late final Dio _dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// URL del backend. Inyectable por entorno para probar desde un
  /// dispositivo físico:
  /// - Android emulador:  10.0.2.2 apunta al localhost de la PC.
  /// - Teléfono real:     IP LAN de la PC (misma WiFi).
  ///   Ej.: flutter run --dart-define=API_BASE_URL=http://192.168.1.50:3000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  DioClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Interceptor para inyectar JWT y gestionar trazas de red
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Recuperar token de almacenamiento seguro (CU-05)
          String? token = await _secureStorage.read(key: 'jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          // Centralización de manejo de excepciones de red
          return handler.next(e);
        },
      ),
    );
  }

  Dio get dio => _dio;
}