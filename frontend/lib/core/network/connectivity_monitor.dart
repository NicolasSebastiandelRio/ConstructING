import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Estado global de conectividad (CU-43 paso 4: Online/Offline).
enum ConnectivityStatus { online, offline }

/// Verifica internet REAL con un heartbeat (CU-43 paso 2: no basta estar
/// conectado a un router sin salida). Inyectable para tests.
typedef InternetProbe = Future<bool> Function();

/// Monitorea la conectividad (CU-43: RF_06).
///
/// Combina los eventos del sistema operativo con heartbeats periódicos:
/// - Sin enlace (link `none`) → Offline inmediato, sin gastar heartbeat.
/// - Con enlace → el heartbeat decide (solo hay Online si responde).
/// Emite únicamente ante cambios de estado. El aviso para despertar el
/// motor de sincronización (CU-44, Sprint 4) saldrá de este stream.
class ConnectivityMonitor {
  ConnectivityMonitor({
    required Stream<List<ConnectivityResult>> linkChanges,
    required InternetProbe hasInternet,
    this.heartbeatInterval = const Duration(seconds: 30),
  })  : _linkChanges = linkChanges,
        _hasInternet = hasInternet;

  final Stream<List<ConnectivityResult>> _linkChanges;
  final InternetProbe _hasInternet;
  final Duration heartbeatInterval;

  final _controller = StreamController<ConnectivityStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _linkSubscription;
  Timer? _heartbeatTimer;
  ConnectivityStatus _current = ConnectivityStatus.offline;
  bool _started = false;

  /// Último estado conocido (arranca offline hasta probar lo contrario).
  ConnectivityStatus get current => _current;

  /// Cambios de estado (solo emite cuando el estado realmente cambia).
  Stream<ConnectivityStatus> get onStatusChanged => _controller.stream;

  /// Inicia la escucha del SO + el heartbeat periódico, con chequeo inicial.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _evaluate();
    _linkSubscription = _linkChanges.listen(_evaluate);
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _evaluate());
  }

  Future<void> _evaluate([List<ConnectivityResult>? link]) async {
    if (link != null &&
        (link.isEmpty || link.contains(ConnectivityResult.none))) {
      _emit(ConnectivityStatus.offline);
      return;
    }
    final online = await _hasInternet();
    _emit(online ? ConnectivityStatus.online : ConnectivityStatus.offline);
  }

  void _emit(ConnectivityStatus next) {
    if (next == _current || _controller.isClosed) return;
    _current = next;
    _controller.add(next);
  }

  Future<void> dispose() async {
    _started = false;
    _heartbeatTimer?.cancel();
    await _linkSubscription?.cancel();
    await _controller.close();
  }
}
