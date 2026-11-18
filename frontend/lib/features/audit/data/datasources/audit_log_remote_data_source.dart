import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/network/dio_client.dart';

/// Sello del servidor (CU-60 paso 2): registro consolidado con el
/// timestamp exacto emitido por el servidor.
class AuditLogServerRecord extends Equatable {
  final String id;
  final String usuarioId;
  final String accion;
  final String? detalle;
  final String? obraId;
  final String? coordenadas;
  final DateTime createdAt;

  const AuditLogServerRecord({
    required this.id,
    required this.usuarioId,
    required this.accion,
    this.detalle,
    this.obraId,
    this.coordenadas,
    required this.createdAt,
  });

  factory AuditLogServerRecord.fromJson(Map<String, dynamic> json) =>
      AuditLogServerRecord(
        id: json['id'] as String,
        usuarioId: json['usuarioId'] as String,
        accion: json['accion'] as String,
        detalle: json['detalle'] as String?,
        obraId: json['obraId'] as String?,
        coordenadas: json['coordenadas'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  List<Object?> get props =>
      [id, usuarioId, accion, detalle, obraId, coordenadas, createdAt];
}

/// CU-60 paso 2 (RF_08, RNF_S_03): envía la transacción crítica al Servicio
/// de Audit Log del servidor central, que consolida la información con el
/// timestamp exacto emitido por él e inserta el registro inmutable.
class AuditLogRemoteDataSource {
  AuditLogRemoteDataSource({required DioClient dioClient})
      : _dio = dioClient.dio;

  final Dio _dio;

  Future<AuditLogServerRecord?> send({
    required Map<String, dynamic> registro,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/audit-logs',
        data: registro,
      );
      final data = res.data;
      if (data == null) return null;
      return AuditLogServerRecord.fromJson(data);
    } on DioException {
      // Best-effort offline-first: la huella local ya existe; el envío se
      // reintentará en futuras ventanas de conectividad.
      return null;
    }
  }
}
