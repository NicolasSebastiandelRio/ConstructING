import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';
import '../../domain/entities/app_notification.dart';

/// Cliente del Servicio de Notificaciones del servidor central (RF_10).
///
/// Best-effort, igual que el resto del offline-first: la bandeja local es la
/// fuente de verdad inmediata y el servidor consolida/despacha el canal
/// externo (CU-67 paso 3). Ante fallo de red se devuelve null y la alerta
/// local permanece.
class NotificationRemoteDataSource {
  NotificationRemoteDataSource({required DioClient dioClient})
      : _dio = dioClient.dio;

  final Dio _dio;

  /// CU-67 paso 4 / CU-68 paso 4: despacha la alerta al servidor.
  Future<AppNotification?> send(AppNotification notification) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/notifications',
        data: notification.toRemoteJson(),
      );
      final data = res.data;
      if (data == null) return null;
      return AppNotification.fromRemoteJson(data);
    } on DioException {
      return null;
    }
  }

  /// CU-70 paso 2: bandeja del usuario en el servidor (descendente).
  Future<List<AppNotification>?> fetchByUsuario(String usuarioId) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/notifications/usuario/$usuarioId',
      );
      final data = res.data;
      if (data == null) return null;
      return [
        for (final item in data)
          if (item is Map) AppNotification.fromRemoteJson(item.cast()),
      ];
    } on DioException {
      return null;
    }
  }

  /// CU-72 paso 2: marca la alerta como leída en el servidor.
  Future<bool> markAsRead(String id) async {
    try {
      await _dio.patch<Map<String, dynamic>>('/notifications/$id/leida');
      return true;
    } on DioException {
      return false;
    }
  }

  /// CU-71 paso 2: persiste la preferencia de canal del usuario.
  Future<NotificationPreferences?> savePreferences(
    NotificationPreferences preferences,
  ) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/notifications/preferencias/${preferences.usuarioId}',
        data: {'recibirPorCorreo': preferences.recibirPorCorreo},
      );
      final data = res.data;
      if (data == null) return null;
      return NotificationPreferences.fromRemoteJson(data);
    } on DioException {
      return null;
    }
  }

  /// CU-69: dispara el chequeo de retrasos del Cron Job en el servidor.
  /// Devuelve cuántas alertas generó (null si no hubo red).
  Future<int?> runOverdueCheck() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/notifications/cron/retrasos',
      );
      final data = res.data;
      if (data == null) return null;
      return (data['generadas'] as num?)?.toInt() ?? 0;
    } on DioException {
      return null;
    }
  }
}
