import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/sync_engine.dart';
import '../../domain/sync_run_result.dart';

/// Estado del panel de sincronización (CU-48: RNF_U_04 — Feedback de
/// Sincronización).
class SyncStatusState {
  /// false = en reposo (nube tildada); true = sincronizando (nube con
  /// flecha, paso 2 del CU-48).
  final bool syncing;

  /// Evidencias pendientes de subida (paso 4 del CU-48).
  final int evidenciasPendientes;

  /// Hitos pendientes de subida.
  final int hitosPendientes;

  /// Último mensaje de resultado para el usuario.
  final String? ultimoMensaje;

  const SyncStatusState({
    required this.evidenciasPendientes,
    required this.hitosPendientes,
    this.syncing = false,
    this.ultimoMensaje,
  });

  int get pendientes => evidenciasPendientes + hitosPendientes;

  /// Texto del panel de detalle (paso 4 del CU-48).
  String get detalle {
    final partes = <String>[
      if (evidenciasPendientes > 0)
        '$evidenciasPendientes ${evidenciasPendientes == 1 ? 'evidencia pendiente' : 'evidencias pendientes'} de subida',
      if (hitosPendientes > 0)
        '$hitosPendientes ${hitosPendientes == 1 ? 'hito pendiente' : 'hitos pendientes'} de subida',
    ];
    return partes.isEmpty ? 'Todo sincronizado con la nube' : partes.join(' · ');
  }

  SyncStatusState copyWith({
    int? evidenciasPendientes,
    int? hitosPendientes,
    bool? syncing,
    String? ultimoMensaje,
    bool clearMensaje = false,
  }) {
    return SyncStatusState(
      evidenciasPendientes: evidenciasPendientes ?? this.evidenciasPendientes,
      hitosPendientes: hitosPendientes ?? this.hitosPendientes,
      syncing: syncing ?? this.syncing,
      ultimoMensaje: clearMensaje ? null : (ultimoMensaje ?? this.ultimoMensaje),
    );
  }
}

/// Cubit global del estado de sincronización (CU-48/CU-49).
///
/// Escucha las transiciones a online del CU-43 (precondición del CU-44:
/// "El CU-43 confirma que hay conectividad estable") y dispara el volcado;
/// expone el panel de detalle y el botón "Sincronizar Ahora" (CU-49).
class SyncStatusCubit extends Cubit<SyncStatusState> {
  SyncStatusCubit({
    required this.engine,
    required this.isOnline,
  }) : super(
          const SyncStatusState(
            evidenciasPendientes: 0,
            hitosPendientes: 0,
          ),
        );

  /// Motor de sincronización (CU-44).
  final SyncEngine engine;

  /// Verificación de conectividad actual (CU-43 paso 4).
  final bool Function() isOnline;

  Timer? _retryTimer;
  StreamSubscription<void>? _onlineSubscription;
  bool _running = false;

  /// CU-48: refresca el contador de pendientes (panel de detalle).
  Future<void> refresh() async {
    final evidencias = await engine.evidences.listPendingSync();
    final hitos = await engine.milestones.listPendingSync();
    emit(SyncStatusState(
      evidenciasPendientes: evidencias.length,
      hitosPendientes: hitos.length,
      syncing: _running,
      ultimoMensaje: state.ultimoMensaje,
    ));
  }

  /// CU-49: "Sincronizar Ahora" — ejecuta el CU-43 ignorando las esperas
  /// programadas (chequeo inmediato) y el CU-44 si hay red; notifica el
  /// resultado (paso 4).
  Future<void> syncNow() async {
    if (_running) return;
    if (!isOnline()) {
      // CU-49 Alt.: sin red en el chequeo forzado → el panel lo informa.
      emit(state.copyWith(
        ultimoMensaje: 'Sin conexión: reintente cuando haya red.',
      ));
      return;
    }
    await _runEngine();
  }

  /// Dispara el motor al detectar red estable (aviso del CU-43 al CU-44).
  void listenOnline(Stream<void> onlineTransitions) {
    _onlineSubscription?.cancel();
    _onlineSubscription = onlineTransitions.listen((_) => runIfIdle());
  }

  /// Corre si hay red y no hay una corrida en curso.
  Future<void> runIfIdle() async {
    if (_running) return;
    if (!isOnline()) return;
    await _runEngine();
  }

  Future<void> _runEngine() async {
    _running = true;
    emit(state.copyWith(
      syncing: true,
      ultimoMensaje: null,
      clearMensaje: true,
    ));
    final result = await engine.run();
    _running = false;
    final evidencias = await engine.evidences.listPendingSync();
    final hitos = await engine.milestones.listPendingSync();
    emit(SyncStatusState(
      evidenciasPendientes: evidencias.length,
      hitosPendientes: hitos.length,
      syncing: false,
      ultimoMensaje: _messageOf(result),
    ));
    // CU-44 Alt. 2.2: mantiene el registro pendiente y programa reintento.
    if (!result.exitoTotal) _scheduleRetry();
  }

  String _messageOf(SyncRunResult result) {
    if (result.exitoTotal) {
      final subidos = result.hitosSubidos + result.evidenciasSubidas;
      return subidos > 0
          ? 'Sincronización completa: $subidos registros subidos a la nube.'
          : 'Todo sincronizado con la nube.';
    }
    return 'Sincronización parcial: ${result.pendientes} registros quedaron '
        'pendientes y se reintentarán.';
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (isOnline()) _runEngine();
    });
  }

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    await _onlineSubscription?.cancel();
    return super.close();
  }
}
