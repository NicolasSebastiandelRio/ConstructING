import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'connectivity_monitor.dart';

/// Estado global de conectividad como Cubit (CU-43 paso 4).
///
/// Expone `ConnectivityStatus.online/offline` a toda la app. El Sprint 4
/// (CU-44) escuchará las transiciones a online para despertar la
/// sincronización.
class ConnectivityCubit extends Cubit<ConnectivityStatus> {
  ConnectivityCubit({
    required ConnectivityMonitor monitor,
  })  : _monitor = monitor,
        super(monitor.current);

  final ConnectivityMonitor _monitor;
  StreamSubscription<ConnectivityStatus>? _subscription;

  /// Inicia el monitoreo (escucha del SO + heartbeat). Idempotente.
  Future<void> start() async {
    await _subscription?.cancel();
    _subscription = _monitor.onStatusChanged.listen(emit);
    await _monitor.start();
    if (state != _monitor.current) emit(_monitor.current);
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _monitor.dispose();
    return super.close();
  }
}

/// Construye el monitor de producción: eventos del SO + heartbeat HTTP
/// contra el backend (`GET /health`, timeout corto).
ConnectivityMonitor buildProductionMonitor(Dio dio) {
  return ConnectivityMonitor(
    linkChanges: Connectivity().onConnectivityChanged,
    hasInternet: () async {
      try {
        final response = await dio.get(
          '/health',
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        return (response.statusCode ?? 500) < 500;
      } catch (_) {
        return false;
      }
    },
  );
}
