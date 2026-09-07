/// Ruta crítica CPM (CU-29, RF_01/RF_02) + base de QA-04.
///
/// Cómputo puro en memoria (offline-first): pasada adelante y pasada atrás
/// sobre el grafo de dependencias para calcular fechas y holguras (paso 2).
/// Los hitos con holgura cero son críticos: cualquier demora en ellos retrasa
/// la obra (paso 4 + poscondición).
///
/// Convención de aristas: `predecesores[h]` = hitos que deben certificarse
/// antes de iniciar `h`. Duraciones en días enteros, inicio del proyecto = 0.
class CriticalPathException implements Exception {
  final String message;

  const CriticalPathException(this.message);

  @override
  String toString() => 'CriticalPathException: $message';
}

/// Cronograma calculado de un hito: inicios/fines tempranos y tardíos.
class CpmNodeSchedule {
  final int earlyStart;
  final int earlyFinish;
  final int lateStart;
  final int lateFinish;

  /// Holgura en días (lateStart - earlyStart). Cero ⇒ crítico.
  int get slack => lateStart - earlyStart;

  bool get isCritical => slack == 0;

  const CpmNodeSchedule({
    required this.earlyStart,
    required this.earlyFinish,
    required this.lateStart,
    required this.lateFinish,
  });
}

/// Resultado del cálculo: cronograma por hito + duración total.
class CriticalPathResult {
  final Map<String, CpmNodeSchedule> schedules;

  /// Duración total del proyecto en días (máximo earlyFinish).
  final int projectDuration;

  const CriticalPathResult({
    required this.schedules,
    required this.projectDuration,
  });

  /// IDs con holgura cero (paso 4: se marcan críticos en la BD).
  Set<String> get criticalIds => {
        for (final entry in schedules.entries)
          if (entry.value.isCritical) entry.key,
      };
}

class CriticalPath {
  /// Ejecuta el CPM sobre [durations] (id → días) y [predecessors].
  /// Lanza [CriticalPathException] si el grafo tiene un ciclo.
  static CriticalPathResult calculate({
    required Map<String, int> durations,
    required Map<String, Set<String>> predecessors,
  }) {
    final nodes = <String>{...durations.keys};
    for (final entry in predecessors.entries) {
      nodes.add(entry.key);
      nodes.addAll(entry.value);
    }
    if (nodes.isEmpty) {
      return const CriticalPathResult(schedules: {}, projectDuration: 0);
    }

    // Sucesores (invertir aristas) para la pasada atrás y el orden.
    final successors = <String, Set<String>>{for (final n in nodes) n: {}};
    for (final entry in predecessors.entries) {
      for (final predecessor in entry.value) {
        successors[predecessor]?.add(entry.key);
      }
    }

    // Orden topológico (Kahn). Sin orden total hay ciclo.
    final inDegree = <String, int>{
      for (final n in nodes) n: predecessors[n]?.length ?? 0,
    };
    final queue = nodes.where((n) => inDegree[n] == 0).toList();
    final topo = <String>[];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      topo.add(node);
      for (final successor in successors[node] ?? const <String>{}) {
        inDegree[successor] = (inDegree[successor] ?? 1) - 1;
        if (inDegree[successor] == 0) queue.add(successor);
      }
    }
    if (topo.length != nodes.length) {
      throw const CriticalPathException(
        'Referencia circular detectada en los hitos: no se pudo calcular la ruta crítica.',
      );
    }

    // Pasada adelante: inicios/fines tempranos.
    final earlyStart = <String, int>{};
    final earlyFinish = <String, int>{};
    for (final node in topo) {
      var start = 0;
      for (final predecessor in predecessors[node] ?? const <String>{}) {
        final finish = earlyFinish[predecessor] ?? 0;
        if (finish > start) start = finish;
      }
      earlyStart[node] = start;
      earlyFinish[node] = start + (durations[node] ?? 0);
    }
    final projectDuration = earlyFinish.values.fold(0, (a, b) => a > b ? a : b);

    // Pasada atrás: inicios/fines tardíos.
    final lateFinish = <String, int>{};
    final lateStart = <String, int>{};
    for (final node in topo.reversed) {
      var finish = projectDuration;
      final succs = successors[node] ?? const <String>{};
      if (succs.isNotEmpty) {
        finish = succs.map((s) => lateStart[s]!).reduce((a, b) => a < b ? a : b);
      }
      lateFinish[node] = finish;
      lateStart[node] = finish - (durations[node] ?? 0);
    }

    return CriticalPathResult(
      schedules: {
        for (final node in nodes)
          node: CpmNodeSchedule(
            earlyStart: earlyStart[node] ?? 0,
            earlyFinish: earlyFinish[node] ?? 0,
            lateStart: lateStart[node] ?? 0,
            lateFinish: lateFinish[node] ?? 0,
          ),
      },
      projectDuration: projectDuration,
    );
  }
}
