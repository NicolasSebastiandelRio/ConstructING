import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../milestones/domain/cpm/critical_path.dart';
import '../../milestones/domain/schedule/milestone_schedule.dart';
import '../domain/notification_catalog.dart';
import '../domain/overdue_critical_detector.dart';
import 'datasources/notification_local_data_source.dart';
import 'datasources/notification_remote_data_source.dart';
import 'notification_dispatcher.dart';

/// Obra a evaluar por el cron del CU-69: identificador, nombre legible, el
/// Profesional Responsable destinatario de la alerta y la fecha de inicio que
/// ancla el cronograma (CU-30).
typedef ObraParaAlerta = ({
  String obraId,
  String obraNombre,
  String profesionalId,
  String? fechaInicio,
});

/// CU-69 (RF_10, RF_02): Cron Job diario de desvíos temporales.
///
/// Paso 1: detecta los hitos de **Ruta Crítica** que superaron su fecha de
/// fin estimada sin certificarse. Pasos 2-3: redacta y solicita el envío.
/// Paso 4: la alerta queda en la bandeja del Profesional Responsable.
///
/// Offline-first: el cron corre en el cliente sobre el cronograma local
/// (CU-29), que es la fuente autoritativa de la "fecha de fin estimada"
/// —el servidor no replica las aristas de dependencia—, y complementa al
/// cron del backend (`POST /notifications/cron/retrasos`).
class DelayAlertScheduler {
  DelayAlertScheduler({
    required this.notificationDao,
    required this.dispatcher,
    required this.milestonesDao,
    required this.obraFechaInicio,
    this.remote,
    this.clock,
    this.interval = const Duration(hours: 24),
  });

  final NotificationLocalDataSource notificationDao;
  final NotificationDispatcher dispatcher;
  final MilestoneLocalDataSource milestonesDao;

  /// Inicio de la obra (yyyy-MM-dd) que ancla el cronograma (CU-30).
  final Future<String?> Function(String obraId) obraFechaInicio;

  /// Disparo del mismo chequeo en el servidor (best-effort).
  final NotificationRemoteDataSource? remote;

  final DateTime Function()? clock;

  /// Cadencia del cron (diaria por especificación; inyectable en tests).
  final Duration interval;

  Timer? _timer;
  bool _disposed = false;

  /// Obras a evaluar en cada tick (se reconsulta en cada ejecución: los
  /// hitos y las obras cambian entre ticks).
  Future<List<ObraParaAlerta>> Function()? _obras;

  DateTime get _now => (clock ?? DateTime.now)();

  /// Arranca la ejecución diaria. No-op si ya está corriendo.
  void start({Future<List<ObraParaAlerta>> Function()? obras}) {
    if (_disposed || _timer != null) return;
    _obras = obras;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  /// Un tick del cron: reevalúa las obras y corre el chequeo de cada una.
  /// Devuelve cuántas alertas nuevas generó.
  Future<int> tick() async {
    final proveedor = _obras;
    if (proveedor == null) return 0;
    var generadas = 0;
    try {
      for (final obra in await proveedor()) {
        generadas += await runForObra(
          obraId: obra.obraId,
          obraNombre: obra.obraNombre,
          profesionalId: obra.profesionalId,
          fechaInicio: obra.fechaInicio,
        );
      }
    } catch (e) {
      debugPrint('CU-69: tick del cron no evaluable: $e');
    }
    return generadas;
  }

  /// Detiene el cron (cierre de la app / tests).
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Paso 1-3: ejecuta el chequeo para una obra. Devuelve cuántas alertas
  /// nuevas generó. Idempotente dentro de la ventana de [interval]: no repite
  /// la alerta de retraso de una obra ya avisada.
  Future<int> runForObra({
    required String obraId,
    required String obraNombre,
    required String profesionalId,
    String? fechaInicio,
  }) async {
    final inicioRaw = fechaInicio ?? await obraFechaInicio(obraId);
    final obraStart = _parseFecha(inicioRaw);
    if (obraStart == null) return 0;

    final hoy = _now;
    final desde = hoy.subtract(interval);
    if (await notificationDao.existsRetrasoSince(obraId, desde)) return 0;

    final hitos = await milestonesDao.listByObra(obraId);
    if (hitos.isEmpty) return 0;
    final edges = await milestonesDao.dependencyMap(obraId);

    final Map<String, CpmNodeSchedule> schedules;
    try {
      schedules = CriticalPath.calculate(
        durations: {for (final h in hitos) h.id: h.duracionDias},
        predecessors: edges,
      ).schedules;
    } catch (e) {
      // Grafo circular: el cron no puede evaluar el cronograma.
      debugPrint('CU-69: cronograma no evaluable en la obra $obraId: $e');
      return 0;
    }

    final vencidos = OverdueCriticalDetector.detect(
      hitos: hitos,
      schedules: schedules,
      obraStart: obraStart,
      today: hoy,
    );
    if (vencidos.isEmpty) return 0;

    var generadas = 0;
    for (final vencido in vencidos) {
      await dispatcher.publish(NotificationCatalog.retrasoDeHitoCritico(
        id: 'retraso-${vencido.hito.id}-${_dayKey(hoy)}',
        profesionalId: profesionalId,
        obraId: obraId,
        obraNombre: obraNombre,
        hitoNombre: vencido.hito.nombre,
        fechaFinEstimada:
            MilestoneScheduleView.format(vencido.fechaFinEstimada),
        diasDeDesvio: vencido.diasDeDesvio,
        hitoId: vencido.hito.id,
        ahora: hoy,
      ));
      generadas++;
    }
    // Espeja el chequeo en el servidor (best-effort, CU-69).
    await remote?.runOverdueCheck();
    return generadas;
  }

  static String _dayKey(DateTime fecha) =>
      '${fecha.year}${fecha.month.toString().padLeft(2, '0')}'
      '${fecha.day.toString().padLeft(2, '0')}';

  static DateTime? _parseFecha(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final iso = DateTime.tryParse(raw.trim());
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final partes = raw.trim().split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      final y = int.tryParse(partes[2]);
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }
    return null;
  }
}
