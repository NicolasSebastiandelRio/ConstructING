import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../../notifications/data/datasources/notification_local_data_source.dart';
import '../../../notifications/data/delay_alert_scheduler.dart';
import '../../../notifications/domain/entities/app_notification.dart';
import '../blocs/dashboard_bloc.dart';
import '../blocs/dashboard_event.dart';
import '../blocs/dashboard_state.dart';
import '../blocs/works_bloc.dart';
import '../blocs/works_state.dart';

/// CU-66 (Sprint 6): Dashboard de Obras.
///
/// Vista de consolidación del estado de las obras activas del usuario:
/// tarjetas resumen (obras activas, hitos pendientes, alertas recientes), un
/// gráfico de barras horizontal con los hitos por obra —sin dependencias
/// externas, solo widgets estándar— y la lista de las últimas alertas.
///
/// Consume el [WorksBloc] ya provisto globalmente (CU-18) para conocer las
/// obras y delega el cálculo en su propio [DashboardBloc]. Los DAOs locales
/// son inyectables (tests); si no se proveen, el consolidado queda en 0
/// (fail-closed).
class DashboardScreen extends StatefulWidget {
  /// Rol del usuario ('Propietario' o 'Profesional').
  final String userRole;

  /// Usuario del que se cuentan las alertas recientes (CU-66 paso 2).
  final String usuarioId;

  /// CU-66: fuente de hitos (inyectable en tests).
  final MilestoneLocalDataSource? milestonesDao;

  /// CU-66 paso 2: fuente de alertas del usuario (inyectable en tests).
  final NotificationLocalDataSource? notificationDao;

  /// CU-69: cron diario de desvíos temporales del cliente. Opcional: cuando
  /// se provee, el Dashboard lo arranca con las obras vigentes y lo detiene
  /// al desmontarse.
  final DelayAlertScheduler? delayScheduler;

  const DashboardScreen({
    super.key,
    required this.userRole,
    required this.usuarioId,
    this.milestonesDao,
    this.notificationDao,
    this.delayScheduler,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Firma del último consolidado disparado: evita re-emitir `LoadDashboard`
  /// en cada rebuild del `WorksBloc` con las mismas obras.
  String? _lastSignature;

  /// Nombres legibles por obra (solo para rotular el gráfico).
  Map<String, String> _nombresPorObra = const {};

  bool get _isProfesional =>
      widget.userRole.toLowerCase().contains('profesional');

  @override
  void dispose() {
    // CU-69: el cron del cliente se detiene al desmontar el Dashboard.
    widget.delayScheduler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardBloc>(
      create: (_) => DashboardBloc(
        milestonesDao: widget.milestonesDao,
        notificationDao: widget.notificationDao,
      ),
      child: Builder(
        builder: (context) {
          // CU-66 paso 1: el Dashboard parte de las obras activas que el
          // WorksBloc global ya emitió (CU-18).
          final worksState = context.watch<WorksBloc>().state;
          if (worksState is WorksLoaded) {
            _dispatchLoad(context, worksState);
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'DASHBOARD DE OBRAS',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: AppTheme.accentGold,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: AppTheme.darkSurface,
            ),
            body: SafeArea(
              child: BlocBuilder<DashboardBloc, DashboardState>(
                builder: (context, state) {
                  if (state is DashboardLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentGold),
                    );
                  }
                  if (state is DashboardError) {
                    return _buildError(context, state);
                  }
                  if (state is DashboardLoaded) {
                    return _buildLoaded(context, state);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// CU-66 paso 2: dispara el consolidado cuando las obras activas cambian.
  void _dispatchLoad(BuildContext context, WorksLoaded works) {
    final signature =
        '${widget.usuarioId}|${works.works.map((w) => w.id).join(',')}';
    if (_lastSignature == signature) return;
    _lastSignature = signature;
    _nombresPorObra = {for (final w in works.works) w.id: w.nombre};
    final obraIds = works.works.map((w) => w.id).toList();
    final obraNombres = _nombresPorObra;
    // CU-69: el cron diario de retrasos se arranca con las obras vigentes
    // (idempotente: `start()` es no-op si ya está corriendo). El proveedor
    // relee el `WorksBloc` en cada tick para no quedar con datos viejos.
    widget.delayScheduler?.start(obras: () async {
      final state = context.read<WorksBloc>().state;
      if (state is! WorksLoaded) return const [];
      return [
        for (final w in state.works)
          (
            obraId: w.id,
            obraNombre: w.nombre,
            profesionalId: widget.usuarioId,
            fechaInicio: w.fechaInicio,
          ),
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardBloc>().add(LoadDashboard(
            usuarioId: widget.usuarioId,
            obraIds: obraIds,
            obraNombres: obraNombres,
          ));
    });
  }

  /// Reintento del CU-66: recalcula con las obras vigentes del `WorksBloc`.
  void _reload(BuildContext context) {
    final worksState = context.read<WorksBloc>().state;
    if (worksState is! WorksLoaded) return;
    _nombresPorObra = {for (final w in worksState.works) w.id: w.nombre};
    context.read<DashboardBloc>().add(LoadDashboard(
          usuarioId: widget.usuarioId,
          obraIds: worksState.works.map((w) => w.id).toList(),
          obraNombres: _nombresPorObra,
        ));
  }

  /// CU-66 Alt.: error de consolidación + "Reintentar" (patrón del CU-18).
  Widget _buildError(BuildContext context, DashboardError state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              onPressed: () => _reload(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CU-66 paso 4: tarjetas resumen + gráfico + últimas alertas.
  Widget _buildLoaded(BuildContext context, DashboardLoaded state) {
    return ListView(
      // Convención de la app: el scroll no rebota ni estira el contenido.
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _isProfesional
              ? 'Consolidado de tus obras en desarrollo'
              : 'Consolidado de tus construcciones',
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontFamily: 'Cinzel'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                key: const Key('dashboard_card_obras_activas'),
                icon: Icons.location_city_outlined,
                value: state.obrasActivas,
                label: 'Obras\nactivas',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                key: const Key('dashboard_card_hitos_pendientes'),
                icon: Icons.pending_actions_outlined,
                value: state.hitosPendientes,
                label: 'Hitos\npendientes',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                key: const Key('dashboard_card_alertas_recientes'),
                icon: Icons.notifications_active_outlined,
                value: state.alertasRecientes,
                label: 'Alertas\nrecientes',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildGrafico(state),
        const SizedBox(height: 20),
        _buildUltimasAlertas(state),
      ],
    );
  }

  /// CU-66 paso 4: gráfico de barras horizontal "Hitos por obra" (widgets
  /// estándar, sin dependencias) + progreso de certificación por obra.
  Widget _buildGrafico(DashboardLoaded state) {
    final entries = state.hitosPorObra.entries.toList();
    final maxTotal =
        entries.fold<int>(0, (max, e) => e.value > max ? e.value : max);
    return Container(
      key: const Key('dashboard_grafico_hitos'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart,
                  color: AppTheme.accentGold, size: 18),
              SizedBox(width: 6),
              Text(
                'HITOS POR OBRA',
                style: TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'Sin obras activas para graficar.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            for (final entry in entries)
              _buildBarraObra(state, entry.key, entry.value, maxTotal),
        ],
      ),
    );
  }

  /// Una barra del gráfico: total de hitos (proporcional al máximo) y el
  /// progreso de certificación de la obra.
  Widget _buildBarraObra(
    DashboardLoaded state,
    String obraId,
    int total,
    int maxTotal,
  ) {
    final certificados = state.certificadosPorObra[obraId] ?? 0;
    final nombre = _nombresPorObra[obraId] ?? _shortId(obraId);
    final factor = maxTotal <= 0 ? 0.0 : (total / maxTotal).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$total hito${total == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Barra horizontal proporcional (Container + FractionallySizedBox).
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: factor,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.accentGold,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: state.progresoDeObra(obraId),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.greenAccent),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$certificados/$total certificados',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// CU-66 paso 4: las 3 alertas más recientes; las de prioridad alta se
  /// resaltan en rojo institucional (RF_10).
  Widget _buildUltimasAlertas(DashboardLoaded state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_outlined,
                  color: AppTheme.accentGold, size: 18),
              SizedBox(width: 6),
              Text(
                'ÚLTIMAS ALERTAS',
                style: TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cinzel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.ultimasAlertas.isEmpty)
            const Text(
              'No hay alertas recientes.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            for (final alerta in state.ultimasAlertas)
              _buildAlertaCard(alerta),
        ],
      ),
    );
  }

  Widget _buildAlertaCard(AppNotification alerta) {
    final esAlta = alerta.prioridad == NotificationPrioridad.alta;
    final color = esAlta ? AppTheme.primaryRed : Colors.white24;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esAlta
            ? AppTheme.primaryRed.withValues(alpha: 0.12)
            : AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            alerta.titulo,
            style: TextStyle(
              color: esAlta ? AppTheme.primaryRed : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('dd/MM/yyyy HH:mm').format(alerta.createdAt),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Rótulo de respaldo cuando la obra no tiene nombre disponible.
  String _shortId(String obraId) =>
      obraId.length <= 8 ? obraId : '${obraId.substring(0, 8)}…';
}

/// CU-66 paso 4: tarjeta resumen del consolidado.
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _SummaryCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accentGold, size: 20),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(
              color: AppTheme.accentGold,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
