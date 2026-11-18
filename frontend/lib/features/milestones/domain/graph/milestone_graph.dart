/// Grafo de dependencias de hitos (CU-24, CU-28, CU-29).
///
/// Convención: `predecesores[h]` = conjunto de hitos que deben certificarse
/// antes de que `h` pueda iniciar (arista predecesor → hito). Todo es
/// cómputo puro en memoria (CU-24 paso 2: "Verifica internamente en la
/// memoria"), sin tocar la BD.
class MilestoneGraph {
  /// `true` si el grafo contiene al menos un ciclo (referencia circular).
  static bool hasCycle(Map<String, Set<String>> predecessors) {
    const white = 0; // no visitado
    const gray = 1; // en la pila actual (ciclo si se revisita)
    const black = 2; // procesado
    final color = <String, int>{};

    bool visit(String node) {
      color[node] = gray;
      for (final predecessor in predecessors[node] ?? const <String>{}) {
        final predecessorColor = color[predecessor] ?? white;
        if (predecessorColor == gray) return true;
        if (predecessorColor == white && visit(predecessor)) return true;
      }
      color[node] = black;
      return false;
    }

    final nodes = <String>{...predecessors.keys};
    for (final edges in predecessors.values) {
      nodes.addAll(edges);
    }
    for (final node in nodes) {
      if ((color[node] ?? white) == white && visit(node)) return true;
    }
    return false;
  }

  /// `true` si reemplazar los predecesores de [hitoId] por
  /// [newPredecessors] generaría un ciclo (CU-24 Alt. 2.1).
  static bool wouldCreateCycle({
    required Map<String, Set<String>> existing,
    required String hitoId,
    required Set<String> newPredecessors,
  }) {
    final merged = <String, Set<String>>{
      for (final entry in existing.entries) entry.key: Set.of(entry.value),
      hitoId: Set.of(newPredecessors),
    };
    return hasCycle(merged);
  }
}
