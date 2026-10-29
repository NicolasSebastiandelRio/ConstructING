import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_event.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_state.dart';
import 'package:constructing_mobile/features/works/presentation/screens/work_detail_screen.dart';

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => store[key];

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    store[key] = value;
  }

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(store);

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      store.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => store.clear();
}

class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDioClient extends DioClient {
  _FakeDioClient(this.dioOverride);

  final Dio dioOverride;

  @override
  Dio get dio => dioOverride;
}

Dio _buildDio(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
  dio.httpClientAdapter = _FakeHttpAdapter(handler);
  return dio;
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

const _enEjecucionJson = {
  'id': 'w1',
  'nombre': 'Obra Faseable',
  'direccion': 'Calle 123',
  'fechaInicio': '2026-09-01',
  'estado': 'En Ejecución',
  'propietarioId': 'prop-1',
};

WorkModel _snapshot() => const WorkModel(
      id: 'w1',
      nombre: 'Obra Faseable',
      direccion: 'Calle 123',
      fechaInicio: '2026-09-01',
      estado: 'En Planificación',
      latitud: null,
      longitud: null,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'prop-1',
    );

/// Data source en memoria para el bloc y el diálogo (CU-20).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failStatusWith});

  final Exception? failStatusWith;
  String? lastStatusId;
  String? lastStatus;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => const [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> getWorkById(String id) async => _snapshot();

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) async {
    lastStatusId = id;
    lastStatus = estado;
    if (failStatusWith != null) throw failStatusWith!;
    return WorkModel.fromJson(_enEjecucionJson);
  }

  @override
  Future<void> archiveWork(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.updateWorkStatus (CU-20)', () {
    test('envía PATCH a /works/:id/status con el nuevo estado', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json(_enEjecucionJson, 200);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final work = await dataSource.updateWorkStatus('w1', 'En Ejecución');

      expect(captured.method, 'PATCH');
      expect(captured.path, '/works/w1/status');
      expect(captured.data, {'estado': 'En Ejecución'});
      expect(work.estado, 'En Ejecución');
    });

    test('propaga el 400 ante un estado inválido', () async {
      final dio = _buildDio(
        (options) async => _json({'message': 'Estado de obra inválido.'}, 400),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.updateWorkStatus('w1', 'En Otro Lado'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Estado de obra inválido'),
          ),
        ),
      );
    });
  });

  group('WorksBloc UpdateWorkStatusEvent (CU-20 poscondición)', () {
    test('emite Loading y luego Loaded tras cambiar la fase y refrescar', () async {
      final dataSource = _FakeWorksDataSource();
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);

      final expectation = expectLater(
        bloc.stream,
        emitsInOrder([isA<WorksLoading>(), isA<WorksLoaded>()]),
      );

      bloc.add(const UpdateWorkStatusEvent(id: 'w1', estado: 'En Ejecución'));
      await expectation;
      expect(dataSource.lastStatusId, 'w1');
      expect(dataSource.lastStatus, 'En Ejecución');
      await bloc.close();
    });
  });

  group('Diálogo Actualizar Estado (CU-20 paso 1)', () {
    Future<void> pumpFicha(WidgetTester tester, _FakeWorksDataSource dataSource) async {
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WorksBloc>.value(
            value: bloc,
            child: WorkDetailScreen(work: _snapshot(), userRole: 'Profesional'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar Estado'));
      await tester.pumpAndSettle();
    }

    testWidgets('ofrece las fases válidas sin el archivado y confirma el cambio',
        (tester) async {
      final dataSource = _FakeWorksDataSource();
      await pumpFicha(tester, dataSource);
      await openDialog(tester);

      expect(find.text('ACTUALIZAR ESTADO'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text('En Planificación')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('En Ejecución')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Completado')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Archivado')), findsNothing);

      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('En Ejecución')),
      );
      await tester.pump();
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();

      expect(dataSource.lastStatusId, 'w1');
      expect(dataSource.lastStatus, 'En Ejecución');
      expect(find.text('Estado actualizado a "En Ejecución".'), findsOneWidget);
      expect(find.text('ACTUALIZAR ESTADO'), findsNothing);
    });

    testWidgets('ante un error del backend permanece abierto mostrando el mensaje',
        (tester) async {
      final dataSource = _FakeWorksDataSource(
        failStatusWith: Exception('No se puede cambiar el estado de una obra archivada.'),
      );
      await pumpFicha(tester, dataSource);
      await openDialog(tester);

      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Completado')),
      );
      await tester.pump();
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('obra archivada'), findsOneWidget);
      expect(find.text('ACTUALIZAR ESTADO'), findsOneWidget);
    });
  });
}