import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../auth/domain/entities/user_entity.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../auth/presentation/bloc/auth_event.dart';
import '../../auth/presentation/screens/welcome_screen.dart';
import '../bloc/works_bloc.dart';
import '../bloc/works_event.dart';
import '../bloc/works_state.dart';
import '../widgets/new_work_modal.dart';

class WorksDashboardScreen extends StatefulWidget {
  final UserEntity user;

  const WorksDashboardScreen({super.key, required this.user});

  @override
  State<WorksDashboardScreen> createState() => _WorksDashboardScreenState();
}

class _WorksDashboardScreenState extends State<WorksDashboardScreen> {
  bool get _isProfesional => widget.user.rol == 'Profesional';

  @override
  void initState() {
    super.initState();
    context.read<WorksBloc>().add(FetchWorksEvent());
  }

  void _openCreateWorkModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<WorksBloc>(),
        child: const NewWorkModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text(
              'ConstructING',
              style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () {
              context.read<AuthBloc>().add(LogoutRequested());
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de Usuario
              Text(
                widget.user.nombre,
                style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                widget.user.rol,
                style: const TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 13,
                  color: AppTheme.accentGold,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MIS PROYECTOS',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentGold,
                        ),
                      ),
                      Text(
                        _isProfesional
                            ? 'Gestiona tus construcciones'
                            : 'Seguimiento de tus construcciones',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                  if (_isProfesional)
                    IconButton(
                      onPressed: _openCreateWorkModal,
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryRed, size: 32),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              Expanded(
                child: BlocBuilder<WorksBloc, WorksState>(
                  builder: (context, state) {
                    if (state is WorksLoading) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.accentGold),
                      );
                    }

                    if (state is WorksError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(state.message, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () =>
                                  context.read<WorksBloc>().add(FetchWorksEvent()),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (state is WorksLoaded) {
                      if (state.works.isEmpty) {
                        return Center(
                          child: Text(
                            _isProfesional
                                ? 'No tienes proyectos creados. Presiona "+" para iniciar uno.'
                                : 'Aún no tienes obras asignadas.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: state.works.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final work = state.works[index];
                          final isCompleted = work.progreso >= 100 || work.estado == 'Finalizado';

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
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
                                          fontFamily: 'Cinzel',
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? Colors.green.withOpacity(0.2)
                                            : Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isCompleted ? 'Finalizado' : 'En progreso',
                                        style: TextStyle(
                                          color: isCompleted ? Colors.green : Colors.orange,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  work.direccion,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Inicio: ${work.fechaInicio}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Progreso', style: TextStyle(fontSize: 11, color: Colors.white70)),
                                    Text('${work.progreso.toInt()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentGold)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: (work.progreso / 100.0).clamp(0.0, 1.0),
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isCompleted ? Colors.green : AppTheme.primaryRed,
                                  ),
                                ),
                              ],
                            ),
                          );
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
    );
  }
}