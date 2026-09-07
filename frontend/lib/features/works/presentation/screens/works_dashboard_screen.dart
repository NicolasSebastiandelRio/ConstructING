import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/screens/welcome_screen.dart';
import '../../domain/entities/work_entity.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_event.dart';
import '../blocs/works_state.dart';
import '../widgets/new_work_modal.dart';
import 'work_detail_screen.dart'; // <--- EL IMPORT QUE FALTABA

class WorksDashboardScreen extends StatefulWidget {
  final String userRole; // 'Propietario' o 'Profesional'

  const WorksDashboardScreen({super.key, required this.userRole});

  @override
  State<WorksDashboardScreen> createState() => _WorksDashboardScreenState();
}

class _WorksDashboardScreenState extends State<WorksDashboardScreen> {
  /// CU-21 paso 4: vista activa vs historial de archivadas.
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  /// CU-18: consulta las obras vinculadas al rol del usuario actual.
  /// El Propietario ve "Mis Obras" (filtradas por su ID); el Profesional,
  /// el listado general. Con `_showArchived`, el historial (CU-21).
  Future<void> _loadWorks() async {
    String? propietarioId;
    if (!_isProfesional) {
      propietarioId = await const FlutterSecureStorage().read(key: 'user_id');
    }
    if (!mounted) return;
    context.read<WorksBloc>().add(FetchWorksEvent(
          propietarioId: propietarioId,
          archivedOnly: _showArchived,
        ));
  }

  bool get _isProfesional => widget.userRole.toLowerCase().contains('profesional');

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthInitial) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isProfesional ? 'GESTIÓN DE OBRAS' : 'MIS PROYECTOS',
            style: const TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.darkSurface,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppTheme.accentGold),
              onPressed: () {
                // Navegación a Notificaciones (Mockup 6)
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle_outlined, color: AppTheme.accentGold),
              color: AppTheme.darkSurface,
              onSelected: (value) {
                if (value == 'logout') {
                  _confirmLogout(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout, color: AppTheme.primaryRed),
                    title: Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                _isProfesional ? 'Propiedades en desarrollo activo' : 'Seguimiento de tus construcciones',
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Cinzel'),
              ),
              const SizedBox(height: 12),
              // CU-21 paso 4: alterna entre el listado activo y el historial.
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Activas'),
                    selected: !_showArchived,
                    selectedColor: AppTheme.accentGold,
                    labelStyle: TextStyle(
                      color: !_showArchived ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      if (_showArchived) {
                        setState(() => _showArchived = false);
                        _loadWorks();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Historial'),
                    selected: _showArchived,
                    selectedColor: AppTheme.accentGold,
                    labelStyle: TextStyle(
                      color: _showArchived ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      if (!_showArchived) {
                        setState(() => _showArchived = true);
                        _loadWorks();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: BlocBuilder<WorksBloc, WorksState>(
                  // CU-19: los estados de la ficha técnica no deben redibujar
                  // (ni vaciar) el listado que queda debajo de la ficha.
                  buildWhen: (previous, current) =>
                      current is WorksLoading ||
                      current is WorksLoaded ||
                      current is WorksError,
                  builder: (context, state) {
                    if (state is WorksLoading) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.accentGold));
                    } else if (state is WorksError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.message,
                              style: const TextStyle(color: AppTheme.primaryRed),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _loadWorks,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGold, foregroundColor: Colors.black),
                            ),
                          ],
                        ),
                      );
                    } else if (state is WorksLoaded) {
                      if (state.works.isEmpty) {
                        // CU-18 Alt. 2.2 / CU-21 Historial vacío.
                        return Center(
                          child: Text(
                            _showArchived
                                ? 'No hay obras archivadas en el historial'
                                : 'Aún no tienes obras asignadas',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: state.works.length,
                        itemBuilder: (context, index) {
                          final work = state.works[index];
                          return _buildWorkCard(context, work);
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              ],
            ),
          ),
        ),
        // Solo el rol Profesional tiene habilitado el alta de nuevos proyectos (Mockup 11 / CU-13)
        floatingActionButton: _isProfesional
            ? FloatingActionButton(
                backgroundColor: AppTheme.accentGold,
                child: const Icon(Icons.add, color: Colors.black),
                onPressed: () => _showNewWorkModal(context),
              )
            : null,
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Desea finalizar la sesión actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      context.read<AuthBloc>().add(LogoutRequested());
    }
  }

  Widget _buildWorkCard(BuildContext context, WorkEntity work) {
    return InkWell(
        onTap: () {
        // Navegación hacia la Ficha Técnica de la Obra (CU-19 / Mockup 7).
        // Al volver se recarga el listado (CU-30 paso 4 y mutaciones de la
        // ficha: edición, estado, archivado).
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WorkDetailScreen(
              work: work,
              userRole: widget.userRole, 
            ),
          ),
        ).then((_) {
          if (context.mounted) _loadWorks();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      work.nombre,
                      style: const TextStyle(
                        color: AppTheme.accentGold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cinzel',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: work.estado == 'Finalizado' ? Colors.green.shade800 : AppTheme.lightBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      work.estado,
                      style: TextStyle(
                        color: work.estado == 'Finalizado' ? Colors.white : AppTheme.lightBlue,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(work.direccion, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Inicio: ${work.fechaInicio}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 12),
              // Barra de Progreso porcentual (Mockup 5)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Progreso', style: TextStyle(color: Colors.white60, fontSize: 11)),
                      Text('${(work.progreso * 100).toInt()}%', style: const TextStyle(color: AppTheme.accentGold, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: work.progreso,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentGold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewWorkModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BlocProvider.value(
        value: BlocProvider.of<WorksBloc>(context),
        child: const NewWorkModal(),
      ),
    );
  }
}