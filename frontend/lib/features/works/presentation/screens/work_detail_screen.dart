import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/work_entity.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_event.dart';
import '../blocs/works_state.dart';
import '../widgets/edit_work_modal.dart';

class WorkDetailScreen extends StatefulWidget {
  final WorkEntity work;
  final String userRole; // <-- Agregado para Control de Acceso (RBAC)

  const WorkDetailScreen(
      {super.key, required this.work, required this.userRole});

  @override
  State<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends State<WorkDetailScreen> {
  bool get _isProfesional =>
      widget.userRole.toLowerCase().contains('profesional');

  @override
  void initState() {
    super.initState();
    // CU-19 paso 2: al abrir la ficha se recuperan los datos maestros desde
    // la BD (no sólo la foto que traía el listado).
    context.read<WorksBloc>().add(FetchWorkDetailEvent(id: widget.work.id));
  }

  /// CU-17 paso 4 + CU-19: fuente de verdad en orden de frescura. Tras una
  /// edición el bloc emite WorksLoaded con la lista actualizada; si no, la
  /// ficha recién traída; si no, el snapshot recibido por parámetro.
  /// (Búsqueda manual en lugar de firstWhere/orElse: la lista en runtime es
  /// List<WorkModel> y el orElse tipado con WorkEntity rompería.)
  WorkEntity _currentWork(WorksState state) {
    if (state is WorksLoaded) {
      for (final w in state.works) {
        if (w.id == widget.work.id) return w;
      }
    }
    if (state is WorkDetailLoaded) return state.work;
    return widget.work;
  }

  void _openEditSheet(BuildContext context) {
    final bloc = context.read<WorksBloc>();
    final current = _currentWork(bloc.state);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: EditWorkModal(work: current),
      ),
    );
  }

  /// CU-20 paso 1: despliega el menú de estado con las fases válidas.
  /// El archivado no se ofrece aquí (pertenece a CU-21).
  void _openStatusDialog(BuildContext context) {
    final bloc = context.read<WorksBloc>();
    final current = _currentWork(bloc.state);
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: _StatusDialog(work: current),
      ),
    );
  }

  /// CU-21 paso 1: solicita confirmación antes de archivar. Al confirmarse,
  /// se vuelve al dashboard (la obra sale del listado activo).
  Future<void> _openArchiveDialog(BuildContext context) async {
    final bloc = context.read<WorksBloc>();
    final current = _currentWork(bloc.state);
    final archived = await showDialog<bool>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: _ArchiveDialog(work: current),
      ),
    );
    if (archived == true && context.mounted) {
      Navigator.pop(context);
    }
  }

  /// CU-22 paso 1: invita a un propietario no registrado a la obra.
  void _openInviteDialog(BuildContext context) {
    final bloc = context.read<WorksBloc>();
    final current = _currentWork(bloc.state);
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: _InviteDialog(work: current),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CU-19: si la recuperación desde la BD falla se informa sin romper la
    // vista (se conserva el snapshot recibido por parámetro).
    return BlocListener<WorksBloc, WorksState>(
      listenWhen: (previous, current) => current is WorksError,
      listener: (listenerContext, state) {
        if (state is WorksError) {
          ScaffoldMessenger.of(listenerContext).showSnackBar(
            SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.primaryRed),
          );
        }
      },
      child: BlocBuilder<WorksBloc, WorksState>(
        builder: (context, state) {
          final current = _currentWork(state);
          return Scaffold(
            appBar: AppBar(
              title: Text(
                current.nombre,
                style: const TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppTheme.darkSurface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.accentGold),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                // Renderizado condicional: Solo el Profesional ve las opciones
                // operativas (CU-17, CU-20, CU-21). En archivadas se ocultan:
                // la obra es inalterable (poscondición CU-21).
                if (_isProfesional && current.estado != 'Archivado')
                  PopupMenuButton<String>(
                    icon:
                        const Icon(Icons.more_vert, color: AppTheme.accentGold),
                    color: AppTheme.darkSurface,
                    onSelected: (value) {
                      if (value == 'edit') {
                        // CU-17: abre la edición con los datos actuales precargados.
                        _openEditSheet(context);
                      } else if (value == 'status') {
                        // CU-20: despliega el menú de estado (paso 1).
                        _openStatusDialog(context);
                      } else if (value == 'invite') {
                        // CU-22: invita a un propietario no registrado a la obra.
                        _openInviteDialog(context);
                      } else if (value == 'archive') {
                        // CU-21 paso 1: solicita confirmación antes de archivar.
                        _openArchiveDialog(context);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined,
                              color: AppTheme.accentGold),
                          title: Text('Editar Obra',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'status',
                        child: ListTile(
                          leading:
                              Icon(Icons.update, color: AppTheme.lightBlue),
                          title: Text('Actualizar Estado',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'invite',
                        child: ListTile(
                          leading: Icon(Icons.mail_outline,
                              color: AppTheme.accentGold),
                          title: Text('Invitar Propietario',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      const PopupMenuItem<String>(
                        value: 'archive',
                        child: ListTile(
                          leading: Icon(Icons.archive_outlined,
                              color: AppTheme.primaryRed),
                          title: Text('Archivar Proyecto',
                              style: TextStyle(
                                  color: AppTheme.primaryRed, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabecera con Ubicación y Estado
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.accentGold.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Estado Actual',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: current.estado == 'Finalizado'
                                      ? Colors.green.shade800
                                      : AppTheme.lightBlue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(current.estado,
                                    style: const TextStyle(
                                        color: AppTheme.lightBlue,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Ubicación',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: AppTheme.accentGold, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(current.direccion,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 14))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Fecha de Inicio',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(current.fechaInicio,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                          // CU-19: resto de los datos maestros de la obra.
                          if (current.descripcion != null &&
                              current.descripcion!.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Descripción',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(current.descripcion!,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ],
                          const SizedBox(height: 12),
                          const Text('Propietario',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            current.propietarioNombre ??
                                current.propietarioEmail ??
                                'Sin propietario vinculado',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                          if (current.propietarioEmail != null &&
                              current.propietarioNombre != null) ...[
                            const SizedBox(height: 2),
                            Text(current.propietarioEmail!,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                          const SizedBox(height: 12),
                          const Text('Ubicación GPS',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            current.latitud != null && current.longitud != null
                                ? '${current.latitud}, ${current.longitud}'
                                : 'Sin ancla geográfica registrada',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Sección de Línea de Tiempo / Hitos (Mockup 7)
                    const Text(
                      'LÍNEA DE TIEMPO DEL PROYECTO',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        color: AppTheme.accentGold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay hitos registrados en este proyecto todavía.\n(Módulo de Hitos - Sprint 3)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// CU-20 paso 1: menú de estado con las fases válidas del enum.
/// El archivado se excluye a propósito (CU-21 exige obra completada y sin
/// hitos en ejecución, con confirmación propia).
class _StatusDialog extends StatefulWidget {
  final WorkEntity work;

  const _StatusDialog({required this.work});

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  static const List<String> _phases = [
    'En Planificación',
    'En Ejecución',
    'Completado',
  ];

  late String _selected;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selected = _phases.contains(widget.work.estado) ? widget.work.estado : _phases.first;
  }

  void _submit() {
    setState(() => _isLoading = true);
    context
        .read<WorksBloc>()
        .add(UpdateWorkStatusEvent(id: widget.work.id, estado: _selected));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorksBloc, WorksState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is WorksLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text('Estado actualizado a "$_selected".'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is WorksError) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(listenerContext).showSnackBar(
            SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.primaryRed),
          );
        }
      },
      child: AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'ACTUALIZAR ESTADO',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final phase in _phases)
                ListTile(
                  leading: Icon(
                    _selected == phase
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: AppTheme.accentGold,
                  ),
                  title: Text(phase, style: const TextStyle(color: Colors.white)),
                  onTap: _isLoading
                      ? null
                      : () => setState(() => _selected = phase),
                ),
              const SizedBox(height: 8),
              const Text(
                'El archivado se realiza desde "Archivar Proyecto" (CU-21).',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGold),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Actualizar',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// CU-21 paso 1: solicita confirmación antes de archivar. Cancelar cierra sin
/// modificar la BD (flujo alterno, mismo patrón que CU-08).
class _ArchiveDialog extends StatefulWidget {
  final WorkEntity work;

  const _ArchiveDialog({required this.work});

  @override
  State<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends State<_ArchiveDialog> {
  bool _isLoading = false;

  void _submit() {
    setState(() => _isLoading = true);
    context.read<WorksBloc>().add(ArchiveWorkEvent(id: widget.work.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WorksBloc, WorksState>(
      listener: (listenerContext, state) {
        if (!_isLoading) return;
        if (state is WorksLoaded) {
          setState(() => _isLoading = false);
          final messenger = ScaffoldMessenger.of(listenerContext);
          Navigator.pop(listenerContext, true);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Obra archivada. Se movió al historial.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state is WorksError) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(listenerContext).showSnackBar(
            SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.primaryRed),
          );
        }
      },
      child: AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'ARCHIVAR PROYECTO',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Archivar "${widget.work.nombre}"?\n\nSaldrá del listado activo y pasará al historial como inalterable. Sólo puede archivarse una obra completada.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Archivar',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// CU-22 paso 1: invita a un propietario no registrado a la obra. Al generarse
/// el código se muestra en pantalla para compartirlo (además del correo que
/// despacha el backend en el paso 4).
class _InviteDialog extends StatefulWidget {
  final WorkEntity work;

  const _InviteDialog({required this.work});

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _generatedCode;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dataSource = context.read<WorksBloc>().worksRemoteDataSource;
      final invitation = await dataSource.inviteOwner(
        widget.work.id,
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _generatedCode = invitation.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppTheme.primaryRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text(
        'INVITAR PROPIETARIO',
        style: TextStyle(
            fontFamily: 'Cinzel',
            color: AppTheme.accentGold,
            fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: _generatedCode != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Código generado. Compartilo con el propietario para que se una al registrarse:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _generatedCode!,
                    style: const TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Correo del propietario',
                    hintText: 'propietario@ejemplo.com',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())) {
                      return 'Ingrese un correo electrónico válido.';
                    }
                    return null;
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(_generatedCode != null ? 'Cerrar' : 'Cancelar',
              style: const TextStyle(color: Colors.white70)),
        ),
        if (_generatedCode == null)
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGold),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Generar Invitación',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
