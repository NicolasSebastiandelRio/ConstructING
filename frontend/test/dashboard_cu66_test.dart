import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/core/theme/app_theme.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:constructing_mobile/features/notifications/domain/entities/app_notification.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/dashboard_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/dashboard_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/dashboard_state.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/screens/dashboard_screen.dart';

import 'milestones_test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// CU-66 paso 2: bandeja de alertas en memoria. Extiende el DAO real para
/// heredar la firma y anula el acceso a datos: nunca se abre una BD real
/// (abrirla dentro de `testWidgets` cuelga la finalización del test).
class _FakeNotificationDao extends NotificationLocalDataSource {
  _FakeNotificationDao(this._inbox) : super(localDatabase: LocalDatabase());

  final List<AppNotification> _inbox;

  @override
  Future<List<AppNotification>> listByUsuario(String usuarioId) async {
    final propias = _inbox.where((n) => n.usuarioId == usuarioId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return propias;
  }

  @override
  Future<int> countUnread(String usuarioId) async => _inbox
      .where((n) => n.usuarioId == usuarioId && !n.leida)
      .length;
}

/// Data source de obras con el listado fijo del escenario (CU-18/CU-66).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource(this.works);

  final List<WorkModel> works;

  @override
  Future<List<WorkModel>> getWorks({
    String? propietarioId,
    bool archivedOnly = false,
  }) async =>
      works;

  @override
  Future<WorkModel> getWorkById(String id) async =>
      works.firstWhere((w) => w.id == id);

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const String _usuarioId = 'u-1';

WorkModel _obra({required String id, required String nombre}) => WorkModel(
      id: id,
      nombre: nombre,
      direccion: 'Calle 123',
      fechaInicio: '2026-09-01',
      estado: 'En progreso',
      latitud: -34.6,
      longitud: -58.4,
      progreso: 0.4,
      profesionalId: 'prof-1',
      propietarioId: _usuarioId,
    );

Milestone _hito({
  required String id,
  required String obraId,
  required MilestoneStatus estado,
}) =>
    Milestone(
      id: id,
      obraId: obraId,
      nombre: 'Hito $id',
      duracionDias: 5,
      estado: estado,
    );

/// Escenario base del CU-66: 2 obras activas con 5 hitos mezclados.
///
/// Obra w1: 1 Pendiente + 1 En Ejecución + 1 Certificado.
/// Obra w2: 1 Pendiente + 1 Certificado.
/// Total: 3 pendientes (no certificados) y 2 certificados.
FakeMilestoneDao _seedHitos() {
  return FakeMilestoneDao()
    ..seed([
      _hito(id: 'h1', obraId: 'w1', estado: MilestoneStatus.pendiente),
      _hito(id: 'h2', obraId: 'w1', estado: MilestoneStatus.enEjecucion),
      _hito(id: 'h3', obraId: 'w1', estado: MilestoneStatus.certificado),
      _hito(id: 'h4', obraId: 'w2', estado: MilestoneStatus.pendiente),
      _hito(id: 'h5', obraId: 'w2', estado: MilestoneStatus.certificado),
    ]);
}

/// Bandeja con 3 alertas NO leídas (la más reciente de prioridad alta) y 1
/// leída más antigua que no debe entrar en "Últimas alertas".
_FakeNotificationDao _seedAlertas() {
  AppNotification alerta({
    required String id,
    required DateTime createdAt,
    bool leida = false,
    NotificationPrioridad prioridad = NotificationPrioridad.normal,
    String? titulo,
  }) =>
      AppNotification(
        id: id,
        usuarioId: _usuarioId,
        tipo: NotificationTipo.avance,
        titulo: titulo ?? 'Alerta $id',
        mensaje: 'Detalle $id',
        obraId: 'w1',
        prioridad: prioridad,
        leida: leida,
        createdAt: createdAt,
      );

  return _FakeNotificationDao([
    alerta(
      id: 'n1',
      createdAt: DateTime(2026, 9, 4, 10),
      prioridad: NotificationPrioridad.alta,
      titulo: 'Acta lista para firmar',
    ),
    alerta(id: 'n2', createdAt: DateTime(2026, 9, 3, 10)),
    alerta(id: 'n3', createdAt: DateTime(2026, 9, 2, 10)),
    alerta(id: 'n4', createdAt: DateTime(2026, 9, 1, 10), leida: true),
  ]);
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FakeMilestoneDao milestones,
  required _FakeNotificationDao notifications,
}) async {
  // Superficie amplia: el Dashboard es un ListView y las aserciones cubren
  // tarjetas, gráfico y alertas sin depender del viewport por defecto.
  await tester.binding.setSurfaceSize(const Size(1080, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final worksDataSource = _FakeWorksDataSource([
    _obra(id: 'w1', nombre: 'Torre A'),
    _obra(id: 'w2', nombre: 'Torre B'),
  ]);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<WorksBloc>(
          create: (_) => WorksBloc(worksRemoteDataSource: worksDataSource)
            ..add(const FetchWorksEvent(propietarioId: _usuarioId)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: DashboardScreen(
          userRole: 'Propietario',
          usuarioId: _usuarioId,
          milestonesDao: milestones,
          notificationDao: notifications,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DashboardBloc - CU-66 (consolidado del Dashboard de Obras)', () {
    test('con 2 obras e hitos mezclados reporta los totales y las alertas '
        'no leídas', () async {
      final bloc = DashboardBloc(
        milestonesDao: _seedHitos(),
        notificationDao: _seedAlertas(),
      );
      addTearDown(bloc.close);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<DashboardLoading>(), isA<DashboardLoaded>()]),
      );
      bloc.add(const LoadDashboard(
        usuarioId: _usuarioId,
        obraIds: ['w1', 'w2'],
      ));
      await expectation;

      final state = bloc.state as DashboardLoaded;
      // CU-66 paso 2: obras activas.
      expect(state.obrasActivas, 2);
      // CU-66 paso 2: pendientes = NO certificados (Pendiente + En Ejecución).
      expect(state.hitosPendientes, 3);
      expect(state.hitosCertificados, 2);
      expect(state.hitosTotales, 5);
      // CU-66 paso 2: alertas recientes = notificaciones NO leídas.
      expect(state.alertasRecientes, 3);
      // Insumos del gráfico (CU-66 paso 4).
      expect(state.hitosPorObra, {'w1': 3, 'w2': 2});
      expect(state.certificadosPorObra, {'w1': 1, 'w2': 1});
    });

    test('las últimas alertas son las 3 más recientes y no incluyen las '
        'leídas', () async {
      final bloc = DashboardBloc(
        milestonesDao: _seedHitos(),
        notificationDao: _seedAlertas(),
      );
      addTearDown(bloc.close);

      bloc.add(const LoadDashboard(
        usuarioId: _usuarioId,
        obraIds: ['w1', 'w2'],
      ));
      final state = await bloc.stream
          .firstWhere((s) => s is DashboardLoaded) as DashboardLoaded;

      expect(state.ultimasAlertas.map((n) => n.id).toList(), ['n1', 'n2', 'n3']);
      expect(state.ultimasAlertas.first.prioridad, NotificationPrioridad.alta);
      expect(state.ultimasAlertas.first.titulo, 'Acta lista para firmar');
    });

    test('sin DAOs inyectados no explota: consolidado fail-closed en 0',
        () async {
      final bloc = DashboardBloc();
      addTearDown(bloc.close);

      bloc.add(const LoadDashboard(
        usuarioId: _usuarioId,
        obraIds: ['w1', 'w2'],
      ));
      final state = await bloc.stream
          .firstWhere((s) => s is DashboardLoaded) as DashboardLoaded;

      expect(state.obrasActivas, 2);
      expect(state.hitosPendientes, 0);
      expect(state.hitosCertificados, 0);
      expect(state.hitosTotales, 0);
      expect(state.alertasRecientes, 0);
      expect(state.ultimasAlertas, isEmpty);
      expect(state.hitosPorObra.values.every((v) => v == 0), isTrue);
      expect(state.certificadosPorObra.values.every((v) => v == 0), isTrue);
      expect(state.progresoDeObra('w1'), 0.0);
    });
  });

  group('DashboardScreen - CU-66 paso 4', () {
    testWidgets('muestra las 3 tarjetas resumen con los números del '
        'consolidado', (tester) async {
      await _pumpDashboard(
        tester,
        milestones: _seedHitos(),
        notifications: _seedAlertas(),
      );

      final obrasActivas = find.byKey(const Key('dashboard_card_obras_activas'));
      final hitosPendientes =
          find.byKey(const Key('dashboard_card_hitos_pendientes'));
      final alertasRecientes =
          find.byKey(const Key('dashboard_card_alertas_recientes'));

      expect(obrasActivas, findsOneWidget);
      expect(hitosPendientes, findsOneWidget);
      expect(alertasRecientes, findsOneWidget);

      expect(find.descendant(of: obrasActivas, matching: find.text('2')),
          findsOneWidget);
      expect(find.descendant(of: hitosPendientes, matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: alertasRecientes, matching: find.text('3')),
          findsOneWidget);
    });

    testWidgets('dibuja el gráfico de hitos por obra (sin dependencias)',
        (tester) async {
      await _pumpDashboard(
        tester,
        milestones: _seedHitos(),
        notifications: _seedAlertas(),
      );

      expect(find.byKey(const Key('dashboard_grafico_hitos')), findsOneWidget);
      expect(find.text('HITOS POR OBRA'), findsOneWidget);
      // Las obras del WorksBloc rotulan las barras.
      expect(find.text('Torre A'), findsOneWidget);
      expect(find.text('Torre B'), findsOneWidget);
      expect(find.text('3 hitos'), findsOneWidget);
      expect(find.text('2 hitos'), findsOneWidget);
      // Progreso de certificación por obra (barra de progreso estándar).
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('lista las 3 últimas alertas con título y fecha',
        (tester) async {
      await _pumpDashboard(
        tester,
        milestones: _seedHitos(),
        notifications: _seedAlertas(),
      );

      expect(find.text('ÚLTIMAS ALERTAS'), findsOneWidget);
      expect(find.text('Acta lista para firmar'), findsOneWidget);
      expect(find.text('Alerta n2'), findsOneWidget);
      expect(find.text('Alerta n3'), findsOneWidget);
      // La alerta leída (más antigua) queda fuera del top 3.
      expect(find.text('Alerta n4'), findsNothing);
      expect(find.text('04/09/2026 10:00'), findsOneWidget);
    });
  });
}
