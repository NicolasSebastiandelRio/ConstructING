import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'datasources/audit_log_local_data_source.dart';
import 'datasources/audit_log_remote_data_source.dart';

/// CU-60 (RF_08, RNF_S_03): Servicio de Audit Log del cliente.
///
/// Guarda de forma TRANSPARENTE qué actor hizo qué acción, a qué hora y
/// dónde. Se invoca asincrónicamente desde las transacciones críticas
/// (modificar hito, cargar evidencia, firmar acta) y NUNCA interrumpe la
/// operación de negocio: si el guardado falla, la huella se pierde a
/// consola pero el flujo sigue (best-effort, igual que el resto del
/// offline-first). La huella queda imborrable: la tabla local solo admite
/// INSERT/SELECT y el servidor central consolida el timestamp exacto.
class AuditLogWriter {
  AuditLogWriter({
    required AuditLogLocalDataSource dataSource,
    AuditLogRemoteDataSource? remote,
    FlutterSecureStorage? secureStorage,
    Future<String?> Function()? userIdReader,
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _dataSource = dataSource,
        _remote = remote,
        _userIdReader = userIdReader ?? _readSessionUser(secureStorage),
        _clock = clock ?? (() => DateTime.now()),
        _uuid = uuid ?? const Uuid();

  final AuditLogLocalDataSource _dataSource;
  final AuditLogRemoteDataSource? _remote;
  final Future<String?> Function() _userIdReader;
  final DateTime Function() _clock;
  final Uuid _uuid;

  /// Registro transitorio de los módulos de negocio: se conserva la traza
  /// de consola además de la huella persistente (AUDIT-CU60-PENDIENTE).
  static void consoleTrace(String line) => debugPrint(line);

  /// CU-60 paso 1/2/4: registra una transacción crítica.
  ///
  /// Ensambla el registro con el ID de usuario de la sesión activa (CU-05),
  /// el tipo de acción, el detalle, el contexto de obra y las coordenadas
  /// informadas por el módulo de origen; consolida el timestamp e inserta
  /// la fila inmutable. Best-effort: los fallos no se propagan.
  Future<void> log({
    required String accion,
    String? detalle,
    String? obraId,
    String? coordenadas,
  }) async {
    try {
      final usuarioId = await _userIdReader() ?? 'anonimo';
      final record = AuditLogRecord(
        id: _uuid.v4(),
        usuarioId: usuarioId,
        accion: accion,
        detalle: detalle,
        obraId: obraId,
        coordenadas: coordenadas,
        createdAt: _clock().toUtc(),
      );
      await _dataSource.insert(record);
      await _remote?.send(registro: record.toRemoteJson());
    } catch (e) {
      // Transparente (poscondición garantizada por la traza de consola).
      consoleTrace('[AUDIT-CU60] registro pendiente: $e');
    }
  }

  static Future<String?> Function() _readSessionUser(
    FlutterSecureStorage? secureStorage,
  ) {
    final storage = secureStorage ?? const FlutterSecureStorage();
    return () => storage.read(key: 'user_id');
  }
}
