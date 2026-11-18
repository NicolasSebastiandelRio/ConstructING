import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:constructing_mobile/features/notifications/domain/entities/app_notification.dart';
import 'package:constructing_mobile/features/notifications/presentation/bloc/notifications_bloc.dart';
import 'package:constructing_mobile/features/notifications/presentation/bloc/notifications_event.dart';
import 'package:constructing_mobile/features/notifications/presentation/bloc/notifications_state.dart';
import 'package:constructing_mobile/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:constructing_mobile/features/notifications/presentation/screens/notifications_inbox_screen.dart';
import 'package:constructing_mobile/features/notifications/presentation/widgets/notification_bell.dart';

/// BD temporal aislada (ffi) para las pruebas del Sprint 6.
Future<LocalDatabase> _openDb(String prefix) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/nt_${prefix}_'
      '${DateTime.now().microsecondsSinceEpoch}.db';
  await localDb.openLocalDatabase(
    factoryOverride: databaseFactoryFfiNoIsolate,
    nameOverride: path,
  );
  addTearDown(() async {
    await localDb.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
  return localDb;
}

AppNotification _alerta({
  required String id,
  String usuarioId = 'u1',
  NotificationTipo tipo = NotificationTipo.avance,
  String titulo = 'Avance en "Torre"',
  String mensaje = 'Se registró un avance.',
  bool leida = false,
  NotificationPrioridad prioridad = NotificationPrioridad.normal,
  DateTime? createdAt,
}) =>
    AppNotification(
      id: id,
      usuarioId: usuarioId,
      tipo: tipo,
      titulo: titulo,
      mensaje: mensaje,
      obraId: 'w1',
      hitoId: 'h1',
      prioridad: prioridad,
      leida: leida,
      createdAt: createdAt ?? DateTime(2026, 10, 1, 10),
    );

/// Datasource de notificaciones fake para widget tests (no abre BD real).
class _FakeNotificationDao extends NotificationLocalDataSource {
  _FakeNotificationDao() : super(localDatabase: LocalDatabase());

  final List<AppNotification> _store = [];

  void seed(List<AppNotification> alertas) => _store.addAll(alertas);

  @override
  Future<AppNotification> save(AppNotification notification) async {
    _store.removeWhere((n) => n.id == notification.id);
    _store.add(notification);
    return notification;
  }

  @override
  Future<List<AppNotification>> listByUsuario(String usuarioId) async {
    final filas =
        _store.where((n) => n.usuarioId == usuarioId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filas;
  }

  @override
  Future<int> countUnread(String usuarioId) async => _store
      .where((n) => n.usuarioId == usuarioId && !n.leida)
      .length;

  @override
  Future<AppNotification?> markAsRead(String id) async {
    final index = _store.indexWhere((n) => n.id == id);
    if (index < 0) return null;
    _store[index] = _store[index].copyWith(leida: true);
    return _store[index];
  }

  @override
  Future<NotificationPreferences> getPreferences(String usuarioId) async =>
      NotificationPreferences(usuarioId: usuarioId);

  @override
  Future<NotificationPreferences> savePreferences(
    NotificationPreferences preferences,
  ) async =>
      preferences;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-70 bandeja de notificaciones (BD local v8)', () {
    test('consulta las alertas del usuario en orden DESCENDENTE', () async {
      final db = await _openDb('cu70a');
      final dao = NotificationLocalDataSource(localDatabase: db);

      await dao.save(_alerta(
          id: 'n1', createdAt: DateTime(2026, 10, 1, 9)));
      await dao.save(_alerta(
          id: 'n2', createdAt: DateTime(2026, 10, 3, 9)));
      await dao.save(_alerta(
          id: 'n3', createdAt: DateTime(2026, 10, 2, 9)));
      // De otro usuario: no debe aparecer.
      await dao.save(_alerta(
          id: 'otro', usuarioId: 'u2', createdAt: DateTime(2026, 10, 4)));

      final bandeja = await dao.listByUsuario('u1');
      expect(bandeja.map((n) => n.id).toList(), ['n2', 'n3', 'n1']);
      expect(bandeja.first.createdAt.isAfter(bandeja.last.createdAt), isTrue);
    });

    test('countUnread cuenta sólo las no leídas del usuario', () async {
      final db = await _openDb('cu70b');
      final dao = NotificationLocalDataSource(localDatabase: db);
      await dao.save(_alerta(id: 'n1'));
      await dao.save(_alerta(id: 'n2'));
      await dao.save(_alerta(id: 'n3', leida: true));
      await dao.save(_alerta(id: 'ajena', usuarioId: 'u2'));

      expect(await dao.countUnread('u1'), 2);
    });

    test('CU-72: markAsRead cambia el estado y baja el badge', () async {
      final db = await _openDb('cu72a');
      final dao = NotificationLocalDataSource(localDatabase: db);
      await dao.save(_alerta(id: 'n1', createdAt: DateTime(2026, 10, 1, 9)));
      await dao.save(_alerta(id: 'n2', createdAt: DateTime(2026, 10, 2, 9)));
      expect(await dao.countUnread('u1'), 2);

      final actualizada = await dao.markAsRead('n1');
      expect(actualizada!.leida, isTrue);
      expect(await dao.countUnread('u1'), 1);
      // El orden descendente se mantiene (más recientes primero).
      expect((await dao.listByUsuario('u1')).map((n) => n.id).toList(),
          ['n2', 'n1']);
      expect((await dao.listByUsuario('u1')).map((n) => n.leida).toList(),
          [false, true]);
    });

    test('CU-71: preferencias por defecto activas y persistencia del cambio',
        () async {
      final db = await _openDb('cu71a');
      final dao = NotificationLocalDataSource(localDatabase: db);

      final inicial = await dao.getPreferences('u1');
      expect(inicial.recibirPorCorreo, isTrue);

      await dao.savePreferences(
          const NotificationPreferences(usuarioId: 'u1', recibirPorCorreo: false));
      final actual = await dao.getPreferences('u1');
      expect(actual.recibirPorCorreo, isFalse);
    });
  });

  group('NotificationsBloc - CU-70/71/72', () {
    Future<NotificationsBloc> blocSobre(LocalDatabase db) async =>
        NotificationsBloc(dao: NotificationLocalDataSource(localDatabase: db));

    test('CU-70: LoadNotifications emite la bandeja descendente + badge',
        () async {
      final db = await _openDb('b70');
      final dao = NotificationLocalDataSource(localDatabase: db);
      await dao.save(_alerta(id: 'n1', createdAt: DateTime(2026, 10, 1)));
      await dao.save(_alerta(
          id: 'n2', leida: true, createdAt: DateTime(2026, 10, 2)));

      final bloc = await blocSobre(db);
      addTearDown(bloc.close);
      bloc.add(const LoadNotifications(usuarioId: 'u1'));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<NotificationsLoading>(),
          isA<NotificationsLoaded>(),
        ]),
      );
      final estado = bloc.state as NotificationsLoaded;
      expect(estado.inbox.map((n) => n.id).toList(), ['n2', 'n1']);
      expect(estado.noLeidas, 1);
    });

    test('CU-72: marcar leída apaga el indicador de mensaje nuevo', () async {
      final db = await _openDb('b72');
      final dao = NotificationLocalDataSource(localDatabase: db);
      await dao.save(_alerta(id: 'n1'));

      final bloc = await blocSobre(db);
      addTearDown(bloc.close);
      bloc.add(const LoadNotifications(usuarioId: 'u1'));
      await expectLater(bloc.stream, emitsThrough(isA<NotificationsLoaded>()));
      expect((bloc.state as NotificationsLoaded).noLeidas, 1);

      bloc.add(const MarkNotificationAsRead(id: 'n1', usuarioId: 'u1'));
      await expectLater(bloc.stream, emitsThrough(isA<NotificationsLoaded>()));
      final estado = bloc.state as NotificationsLoaded;
      expect(estado.noLeidas, 0);
      expect(estado.inbox.single.leida, isTrue);
    });

    test('CU-71: actualizar la preferencia emite "Preferencias actualizadas"',
        () async {
      final db = await _openDb('b71');
      final bloc = await blocSobre(db);
      addTearDown(bloc.close);

      bloc.add(const UpdateNotificationPreference(
          usuarioId: 'u1', recibirPorCorreo: false));
      await expectLater(bloc.stream, emitsThrough(isA<NotificationsLoaded>()));

      final estado = bloc.state as NotificationsLoaded;
      expect(estado.preferences.recibirPorCorreo, isFalse);
      expect(estado.message, NotificationsMessages.preferenciasActualizadas);
      expect(estado.message, 'Preferencias actualizadas');
    });

    test('CU-72: RefreshUnreadBadge sólo publica el contador', () async {
      final db = await _openDb('b72b');
      final dao = NotificationLocalDataSource(localDatabase: db);
      await dao.save(_alerta(id: 'n1'));
      await dao.save(_alerta(id: 'n2'));

      final bloc = await blocSobre(db);
      addTearDown(bloc.close);
      bloc.add(const RefreshUnreadBadge(usuarioId: 'u1'));
      await expectLater(
        bloc.stream,
        emitsThrough(isA<NotificationsBadgeLoaded>()),
      );
      expect((bloc.state as NotificationsBadgeLoaded).noLeidas, 2);
    });
  });

  group('CU-70/72 widget - bandeja y campana', () {
    testWidgets('la bandeja lista las alertas y marca leída al tocar',
        (tester) async {
      final dao = _FakeNotificationDao()
        ..seed([
          _alerta(
              id: 'n1',
              titulo: 'Acta lista para firmar',
              tipo: NotificationTipo.firma,
              prioridad: NotificationPrioridad.alta,
              createdAt: DateTime(2026, 10, 3, 12)),
          _alerta(
              id: 'n2',
              titulo: 'Avance en "Torre"',
              createdAt: DateTime(2026, 10, 1, 9)),
        ]);

      await tester.pumpWidget(MaterialApp(
        home: NotificationsInboxScreen(
          usuarioId: 'u1',
          notificationDao: dao,
        ),
      ));
      await tester.pumpAndSettle();

      // CU-70 paso 4: ambas alertas visibles, la más reciente primero.
      expect(find.text('Acta lista para firmar'), findsOneWidget);
      expect(find.text('Avance en "Torre"'), findsOneWidget);

      // CU-72 paso 4: indicador de mensaje nuevo en la fila no leída.
      expect(find.byKey(const Key('notification_unread_n1')), findsOneWidget);

      // CU-72 pasos 1-3: tocar marca leída, muestra el contenido y apaga el
      // indicador.
      await tester.tap(find.text('Acta lista para firmar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification_unread_n1')), findsNothing);
      // CU-72 paso 3: el contenido de la alerta queda desplegado (el detalle
      // es el único lugar donde se muestra el enlace a la obra).
      expect(find.text('Obra: w1'), findsOneWidget);
      expect(find.text('Se registró un avance.'), findsWidgets);
    });

    testWidgets('CU-70: bandeja vacía muestra su empty state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: NotificationsInboxScreen(
          usuarioId: 'u1',
          notificationDao: _FakeNotificationDao(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No tiene notificaciones registradas'), findsOneWidget);
    });

    testWidgets('CU-72 paso 4: la campana pinta el badge de no leídas',
        (tester) async {
      final dao = _FakeNotificationDao()
        ..seed([_alerta(id: 'n1'), _alerta(id: 'n2')]);
      final bloc = NotificationsBloc(dao: dao);
      addTearDown(bloc.close);

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<NotificationsBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: NotificationBell(usuarioId: 'u1'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notification_badge')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('CU-71 widget - preferencias', () {
    testWidgets('al cambiar el switch muestra "Preferencias actualizadas"',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: NotificationPreferencesScreen(
          usuarioId: 'u1',
          notificationDao: _FakeNotificationDao(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Recibir por correo'), findsOneWidget);
      expect(find.text('Activado'), findsOneWidget);

      await tester.tap(find.byKey(const Key('preference_recibir_por_correo')));
      await tester.pumpAndSettle();

      // CU-71 paso 4: mensaje EXACTO de la especificación.
      expect(find.text('Preferencias actualizadas'), findsOneWidget);
      expect(find.text('Desactivado'), findsOneWidget);
    });
  });
}
