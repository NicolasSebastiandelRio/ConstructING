import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/milestones/data/datasources/milestone_local_data_source.dart';
import 'package:constructing_mobile/features/milestones/domain/cpm/critical_path.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:constructing_mobile/features/notifications/data/delay_alert_scheduler.dart';
import 'package:constructing_mobile/features/notifications/data/notification_dispatcher.dart';
import 'package:constructing_mobile/features/notifications/domain/entities/app_notification.dart';
import 'package:constructing_mobile/features/notifications/domain/overdue_critical_detector.dart';

Future<LocalDatabase> _openDb(String prefix) async {
  sqfliteFfiInit();
  final localDb = LocalDatabase();
  final path = '${Directory.systemTemp.path}/dl_${prefix}_'
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

Milestone _hito({
  required String id,
  bool critico = true,
  MilestoneStatus estado = MilestoneStatus.enEjecucion,
  int duracion = 5,
}) =>
    Milestone(
      id: id,
      obraId: 'w1',
      nombre: 'Hito $id',
      duracionDias: duracion,
      estado: estado,
      esCritico: critico,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CU-69 paso 1 - detección de desvíos (función pura)', () {
    final obraStart = DateTime(2026, 1, 1);
    final schedules = CriticalPath.calculate(
      durations: {'h1': 5, 'h2': 5},
      predecessors: const {'h1': <String>{}, 'h2': <String>{}},
    ).schedules;

    test('detecta el hito de ruta crítica que superó su fecha de fin', () {
      final vencidos = OverdueCriticalDetector.detect(
        hitos: [_hito(id: 'h1')],
        schedules: schedules,
        obraStart: obraStart,
        today: DateTime(2026, 1, 20),
      );
      expect(vencidos, hasLength(1));
      expect(vencidos.single.hito.id, 'h1');
      expect(vencidos.single.fechaFinEstimada, DateTime(2026, 1, 6));
      expect(vencidos.single.diasDeDesvio, 14);
    });

    test('no reporta hitos NO críticos', () {
      final vencidos = OverdueCriticalDetector.detect(
        hitos: [_hito(id: 'h2', critico: false)],
        schedules: schedules,
        obraStart: obraStart,
        today: DateTime(2026, 1, 20),
      );
      expect(vencidos, isEmpty);
    });

    test('no reporta hitos certificados', () {
      final vencidos = OverdueCriticalDetector.detect(
        hitos: [_hito(id: 'h1', estado: MilestoneStatus.certificado)],
        schedules: schedules,
        obraStart: obraStart,
        today: DateTime(2026, 1, 20),
      );
      expect(vencidos, isEmpty);
    });

    test('no reporta hitos todavía en plazo', () {
      final vencidos = OverdueCriticalDetector.detect(
        hitos: [_hito(id: 'h1')],
        schedules: schedules,
        obraStart: obraStart,
        today: DateTime(2026, 1, 3),
      );
      expect(vencidos, isEmpty);
    });

    test('ignora hitos sin cronograma calculado', () {
      final vencidos = OverdueCriticalDetector.detect(
        hitos: [_hito(id: 'sin-cpm')],
        schedules: schedules,
        obraStart: obraStart,
        today: DateTime(2026, 1, 20),
      );
      expect(vencidos, isEmpty);
    });
  });

  group('CU-69 - DelayAlertScheduler (cron diario)', () {
    test(
        'genera UNA alerta de retraso al Profesional y no la duplica el mismo '
        'día', () async {
      final db = await _openDb('cron');
      final notificationDao = NotificationLocalDataSource(localDatabase: db);
      final milestonesDao = MilestoneLocalDataSource(localDatabase: db);

      final hito = await milestonesDao.create(
          obraId: 'w1', nombre: 'Fundaciones', duracionDias: 5);
      await milestonesDao.setCritical(obraId: 'w1', criticalIds: {hito.id});

      final scheduler = DelayAlertScheduler(
        notificationDao: notificationDao,
        dispatcher: NotificationDispatcher(local: notificationDao),
        milestonesDao: milestonesDao,
        obraFechaInicio: (obraId) async => '2026-01-01',
        clock: () => DateTime(2026, 2, 1),
      );
      addTearDown(scheduler.dispose);

      final generadas = await scheduler.runForObra(
        obraId: 'w1',
        obraNombre: 'Torre Aurora',
        profesionalId: 'prof-1',
      );
      expect(generadas, 1);

      final bandeja = await notificationDao.listByUsuario('prof-1');
      expect(bandeja, hasLength(1));
      final alerta = bandeja.single;
      // CU-69 paso 4: la alerta queda en la bandeja del Profesional.
      expect(alerta.tipo, NotificationTipo.retraso);
      expect(alerta.prioridad, NotificationPrioridad.alta);
      expect(alerta.titulo, 'Alerta de retraso');
      expect(alerta.mensaje, contains('Fundaciones'));
      expect(alerta.mensaje, contains('ruta crítica'));
      expect(alerta.mensaje, contains('06/01/2026'));
      expect(alerta.obraId, 'w1');
      expect(alerta.hitoId, hito.id);

      // Idempotencia del cron: el mismo día no vuelve a avisar.
      final repetido = await scheduler.runForObra(
        obraId: 'w1',
        obraNombre: 'Torre Aurora',
        profesionalId: 'prof-1',
      );
      expect(repetido, 0);
      expect(await notificationDao.listByUsuario('prof-1'), hasLength(1));
    });

    test('no genera alertas si la obra no tiene fecha de inicio', () async {
      final db = await _openDb('cron2');
      final notificationDao = NotificationLocalDataSource(localDatabase: db);
      final milestonesDao = MilestoneLocalDataSource(localDatabase: db);
      final hito = await milestonesDao.create(
          obraId: 'w1', nombre: 'Fundaciones', duracionDias: 5);
      await milestonesDao.setCritical(obraId: 'w1', criticalIds: {hito.id});

      final scheduler = DelayAlertScheduler(
        notificationDao: notificationDao,
        dispatcher: NotificationDispatcher(local: notificationDao),
        milestonesDao: milestonesDao,
        obraFechaInicio: (obraId) async => null,
        clock: () => DateTime(2026, 2, 1),
      );
      addTearDown(scheduler.dispose);

      expect(
        await scheduler.runForObra(
            obraId: 'w1', obraNombre: 'X', profesionalId: 'prof-1'),
        0,
      );
    });

    test('sin hitos no genera nada', () async {
      final db = await _openDb('cron3');
      final notificationDao = NotificationLocalDataSource(localDatabase: db);
      final milestonesDao = MilestoneLocalDataSource(localDatabase: db);
      final scheduler = DelayAlertScheduler(
        notificationDao: notificationDao,
        dispatcher: NotificationDispatcher(local: notificationDao),
        milestonesDao: milestonesDao,
        obraFechaInicio: (obraId) async => '2026-01-01',
        clock: () => DateTime(2026, 2, 1),
      );
      addTearDown(scheduler.dispose);

      expect(
        await scheduler.runForObra(
            obraId: 'w1', obraNombre: 'X', profesionalId: 'prof-1'),
        0,
      );
    });

    test('start() programa el chequeo periódico y dispose() lo detiene',
        () async {
      final db = await _openDb('cron4');
      final notificationDao = NotificationLocalDataSource(localDatabase: db);
      final milestonesDao = MilestoneLocalDataSource(localDatabase: db);
      final hito = await milestonesDao.create(
          obraId: 'w1', nombre: 'Fundaciones', duracionDias: 5);
      await milestonesDao.setCritical(obraId: 'w1', criticalIds: {hito.id});

      final scheduler = DelayAlertScheduler(
        notificationDao: notificationDao,
        dispatcher: NotificationDispatcher(local: notificationDao),
        milestonesDao: milestonesDao,
        obraFechaInicio: (obraId) async => '2026-01-01',
        clock: () => DateTime(2026, 2, 1),
        interval: const Duration(milliseconds: 30),
      );
      scheduler.start(obras: () async => [
            (
              obraId: 'w1',
              obraNombre: 'Torre',
              profesionalId: 'prof-1',
              fechaInicio: '2026-01-01'
            ),
          ]);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      scheduler.dispose();

      // El tick ya corrió al menos una vez y dejó la alerta.
      expect(await notificationDao.listByUsuario('prof-1'), isNotEmpty);
    });

    test('tick() sin proveedor de obras no hace nada', () async {
      final db = await _openDb('cron5');
      final notificationDao = NotificationLocalDataSource(localDatabase: db);
      final milestonesDao = MilestoneLocalDataSource(localDatabase: db);
      final scheduler = DelayAlertScheduler(
        notificationDao: notificationDao,
        dispatcher: NotificationDispatcher(local: notificationDao),
        milestonesDao: milestonesDao,
        obraFechaInicio: (obraId) async => '2026-01-01',
      );
      addTearDown(scheduler.dispose);
      expect(await scheduler.tick(), 0);
    });
  });
}
