/// Resumen de una corrida del motor de sincronización (para el panel CU-48).
class SyncRunResult {
  /// Hitos confirmados con HTTP 200 (CU-44 paso 4).
  final int hitosSubidos;

  /// Evidencias confirmadas e íntegras (CU-45).
  final int evidenciasSubidas;

  /// Registros que quedaron pendientes (CU-44 Alt. 2.2) programados para
  /// reintento.
  final int pendientes;

  /// Retransmisiones tras fallar la integridad (CU-45 Alt. 2.2).
  final int retransmisiones;

  const SyncRunResult({
    required this.hitosSubidos,
    required this.evidenciasSubidas,
    required this.pendientes,
    this.retransmisiones = 0,
  });

  bool get exitoTotal => pendientes == 0;
}
