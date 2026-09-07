import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/graph/milestone_graph.dart';
import '../blocs/milestones_bloc.dart';
import '../blocs/milestones_event.dart';
import '../blocs/milestones_state.dart';

/// CU-24 pasos 1-3: "Agregar Predecesor" con multi-selección de hitos.
///
/// Valida en vivo (paso 2) que la selección no genere una referencia circular:
/// el tilde que cerraría un ciclo se rechaza con el error exacto de la spec
/// (Alt. 2.2) y el Guardar queda intacto para el resto.
class DependenciesDialog extends StatefulWidget {
  final String obraId;
  final Milestone hito;
  final List<Milestone> milestones;
  final Map<String, Set<String>> allEdges;

  const DependenciesDialog({
    super.key,
    required this.obraId,
    required this.hito,
    required this.milestones,
    required this.allEdges,
  });

  @override
  State<DependenciesDialog> createState() => _DependenciesDialogState();
}

class _DependenciesDialogState extends State<DependenciesDialog> {
  late Set<String> _selected;
  bool _isLoading = false;
  String? _cycleError;

  @override
  void initState() {
    super.initState();
    final candidates = _candidates.map((m) => m.id).toSet();
    _selected = widget.allEdges[widget.hito.id]?.intersection(candidates) ?? {};
  }

  /// Hitos elegibles: los de la obra menos el propio (precondición CU-24:
  /// al menos dos hitos, controlada por quien abre el diálogo).
  List<Milestone> get _candidates =>
      widget.milestones.where((m) => m.id != widget.hito.id).toList();

  void _toggle(String id, bool checked) {
    final tentative = Set<String>.of(_selected);
    if (checked) {
      tentative.add(id);
    } else {
      tentative.remove(id);
    }
    // CU-24 paso 2 / Alt. 2.2: verificación en memoria antes de confirmar.
    if (checked &&
        MilestoneGraph.wouldCreateCycle(
          existing: widget.allEdges,
          hitoId: widget.hito.id,
          newPredecessors: tentative,
        )) {
      setState(() => _cycleError = 'Referencia circular detectada');
      return;
    }
    setState(() {
      _selected = tentative;
      _cycleError = null;
    });
  }

  void _submit() {
    setState(() {
      _isLoading = true;
      _cycleError = null;
    });
    context.read<MilestonesBloc>().add(
          SetDependenciesRequested(
            obraId: widget.obraId,
            hitoId: widget.hito.id,
            predecesorIds: _selected.toList(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MilestonesBloc, MilestonesState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is MilestonesLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Dependencias guardadas.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is MilestonesError) {
          setState(() {
            _isLoading = false;
            _cycleError = state.message;
          });
        }
      },
      child: AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'AGREGAR PREDECESOR',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿De qué hitos depende "${widget.hito.nombre}"?',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (_candidates.isEmpty)
                const Text(
                  'Se necesitan al menos dos hitos en la obra.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              for (final candidate in _candidates)
                CheckboxListTile(
                  value: _selected.contains(candidate.id),
                  onChanged: _isLoading
                      ? null
                      : (checked) => _toggle(candidate.id, checked ?? false),
                  title: Text(candidate.nombre,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    '${candidate.duracionDias} días · ${candidate.estado.label}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  activeColor: AppTheme.accentGold,
                  checkColor: Colors.black,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              if (_cycleError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _cycleError!,
                  style: const TextStyle(
                      color: AppTheme.primaryRed,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed:
                (_isLoading || _candidates.isEmpty) ? null : _submit,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Guardar dependencias',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
