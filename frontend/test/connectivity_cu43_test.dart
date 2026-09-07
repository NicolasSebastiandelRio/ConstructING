import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/connectivity_cubit.dart';
import 'package:constructing_mobile/core/network/connectivity_monitor.dart';

/// Monitor con sondas controladas para probar CU-43 sin red real.
ConnectivityMonitor _buildMonitor({
  required Stream<List<ConnectivityResult>> links,
  required Future<bool> Function() internet,
  Duration heartbeatInterval = const Duration(seconds: 30),
}) {
  return ConnectivityMonitor(
    linkChanges: links,
    hasInternet: internet,
    heartbeatInterval: heartbeatInterval,
  );
}

void main() {
  group('ConnectivityMonitor - CU-43 (Monitorear Estado de Conectividad)', () {
    test('arranca offline y pasa a online si el heartbeat responde', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      final monitor = _buildMonitor(
        links: links.stream,
        internet: () async => true,
      );
      addTearDown(monitor.dispose);

      expect(monitor.current, ConnectivityStatus.offline);

      final expectation = expectLater(
        monitor.onStatusChanged,
        emits(ConnectivityStatus.online),
      );
      await monitor.start();
      await expectation;
      expect(monitor.current, ConnectivityStatus.online);
    });

    test('sin enlace pasa a offline inmediato sin gastar heartbeat', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      var heartbeatCalls = 0;
      final monitor = _buildMonitor(
        links: links.stream,
        internet: () async {
          heartbeatCalls++;
          return true;
        },
      );
      addTearDown(monitor.dispose);

      await monitor.start(); // heartbeat inicial → online
      expect(monitor.current, ConnectivityStatus.online);
      final callsAfterStart = heartbeatCalls;

      links.add([ConnectivityResult.none]);
      await expectLater(monitor.onStatusChanged, emits(ConnectivityStatus.offline));

      expect(monitor.current, ConnectivityStatus.offline);
      expect(heartbeatCalls, callsAfterStart); // no se gastó heartbeat
    });

    test('con enlace pero sin internet real sigue offline (paso 2)', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      final monitor = _buildMonitor(
        links: links.stream,
        internet: () async => false,
      );
      addTearDown(monitor.dispose);

      await monitor.start();

      expect(monitor.current, ConnectivityStatus.offline);
    });

    test('el heartbeat periódico detecta la caída y la vuelta', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      var internetUp = true;
      final monitor = _buildMonitor(
        links: links.stream,
        internet: () async => internetUp,
        heartbeatInterval: const Duration(milliseconds: 50),
      );
      addTearDown(monitor.dispose);

      await monitor.start();
      expect(monitor.current, ConnectivityStatus.online);

      internetUp = false;
      await expectLater(monitor.onStatusChanged, emits(ConnectivityStatus.offline));

      internetUp = true;
      await expectLater(monitor.onStatusChanged, emits(ConnectivityStatus.online));
    });

    test('solo emite ante cambios reales de estado', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      final monitor = _buildMonitor(
        links: links.stream,
        internet: () async => true,
        heartbeatInterval: const Duration(milliseconds: 50),
      );
      addTearDown(monitor.dispose);

      final emitted = <ConnectivityStatus>[];
      final sub = monitor.onStatusChanged.listen(emitted.add);
      addTearDown(sub.cancel);

      await monitor.start();
      await Future.delayed(const Duration(milliseconds: 200));

      // Un solo cambio offline→online aunque haya varios heartbeats.
      expect(emitted, [ConnectivityStatus.online]);
    });
  });

  group('ConnectivityCubit - CU-43 (estado global)', () {
    test('expone online tras el chequeo inicial exitoso', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      final cubit = ConnectivityCubit(
        monitor: _buildMonitor(links: links.stream, internet: () async => true),
      );
      addTearDown(cubit.close);

      expect(cubit.state, ConnectivityStatus.offline);
      await cubit.start();
      expect(cubit.state, ConnectivityStatus.online);
    });

    test('propaga la caída a offline (aviso para CU-44)', () async {
      final links = StreamController<List<ConnectivityResult>>();
      addTearDown(links.close);
      final cubit = ConnectivityCubit(
        monitor: _buildMonitor(links: links.stream, internet: () async => true),
      );
      addTearDown(cubit.close);

      await cubit.start();
      expect(cubit.state, ConnectivityStatus.online);

      links.add([ConnectivityResult.none]);
      await expectLater(cubit.stream, emits(ConnectivityStatus.offline));
      expect(cubit.state, ConnectivityStatus.offline);
    });
  });
}