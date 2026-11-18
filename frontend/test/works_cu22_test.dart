import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/network/dio_client.dart';
import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/datasources/works_remote_data_source.dart';
import 'package:constructing_mobile/features/works/data/models/work_invitation.dart';
import 'package:constructing_mobile/features/works/data/models/work_model.dart';
import 'package:constructing_mobile/features/works/presentation/blocs/works_bloc.dart';
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

const _invitationJson = {
  'id': 'i1',
  'code': 'CNG-7K2P9Q',
  'workId': 'w1',
  'email': 'nuevo@gmail.com',
  'expiresAt': '2026-09-12T00:00:00.000Z',
  'usedAt': null,
};

WorkModel _obraCompletada() => const WorkModel(
      id: 'w1',
      nombre: 'Obra Invitable',
      direccion: 'Calle 123',
      fechaInicio: '2026-09-01',
      estado: 'Completado',
      latitud: null,
      longitud: null,
      progreso: 0.0,
      profesionalId: 'prof-1',
      propietarioId: 'prop-1',
    );

/// Data source en memoria para el diálogo (CU-22).
class _FakeWorksDataSource implements WorksRemoteDataSource {
  _FakeWorksDataSource({this.failInviteWith});

  final Exception? failInviteWith;
  String? lastInviteWorkId;
  String? lastInviteEmail;
  int inviteCalls = 0;

  @override
  Future<List<WorkModel>> getWorks({String? propietarioId, bool archivedOnly = false}) async => const [];

  @override
  Future<WorkModel> createWork(Map<String, dynamic> workData) => throw UnimplementedError();

  @override
  Future<WorkModel> updateWork(String id, Map<String, dynamic> workData) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> updateWorkStatus(String id, String estado) =>
      throw UnimplementedError();

  @override
  Future<WorkModel> getWorkById(String id) async => _obraCompletada();

  @override
  Future<void> archiveWork(String id) => throw UnimplementedError();

  @override
  Future<WorkInvitation> inviteOwner(String workId, String email) async {
    inviteCalls++;
    lastInviteWorkId = workId;
    lastInviteEmail = email;
    if (failInviteWith != null) throw failInviteWith!;
    return WorkInvitation.fromJson(_invitationJson);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();

  group('WorksRemoteDataSource.inviteOwner (CU-22 pasos 1-2)', () {
    test('envía POST a /works/:id/invitations con el correo y parsea el código', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json(_invitationJson, 201);
      });

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      final invitation = await dataSource.inviteOwner('w1', 'nuevo@gmail.com');

      expect(captured.method, 'POST');
      expect(captured.path, '/works/w1/invitations');
      expect(captured.data, {'email': 'nuevo@gmail.com'});
      expect(invitation.code, 'CNG-7K2P9Q');
      expect(invitation.email, 'nuevo@gmail.com');
      expect(invitation.usedAt, isNull);
    });

    test('propaga el 409 cuando el correo ya está registrado (CU-14)', () async {
      final dio = _buildDio(
        (options) async => _json(
          {'message': 'El correo ya se encuentra registrado. Vincule al propietario directamente con su correo (CU-14).'},
          409,
        ),
      );

      final dataSource = WorksRemoteDataSourceImpl(
        dioClient: _FakeDioClient(dio),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        dataSource.inviteOwner('w1', 'reg@gmail.com'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('ya se encuentra registrado'),
          ),
        ),
      );
    });
  });

  group('AuthRemoteDataSource.register con invitationCode (CU-22 reclamo)', () {
    test('incluye el código normalizado cuando se informa', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({'id': 'u9', 'nombre': 'Invitado', 'email': 'nuevo@gmail.com', 'rol': 'Propietario'}, 201);
      });

      final dataSource = AuthRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await dataSource.register(
        nombre: 'Invitado',
        email: 'nuevo@gmail.com',
        password: 'claveSegura1',
        rol: 'Propietario',
        invitationCode: 'cng-7k2p9q',
      );

      expect((captured.data as Map)['invitationCode'], 'CNG-7K2P9Q');
    });

    test('omite el código cuando no se informa (registro clásico CU-06)', () async {
      late RequestOptions captured;
      final dio = _buildDio((options) async {
        captured = options;
        return _json({'id': 'u9', 'nombre': 'Ana', 'email': 'ana@gmail.com', 'rol': 'Propietario'}, 201);
      });

      final dataSource = AuthRemoteDataSourceImpl(dioClient: _FakeDioClient(dio));

      await dataSource.register(
        nombre: 'Ana',
        email: 'ana@gmail.com',
        password: 'claveSegura1',
        rol: 'Propietario',
      );

      expect((captured.data as Map).containsKey('invitationCode'), isFalse);
    });
  });

  group('Diálogo Invitar Propietario (CU-22 paso 1)', () {
    Future<void> pumpFicha(WidgetTester tester, _FakeWorksDataSource dataSource) async {
      final bloc = WorksBloc(worksRemoteDataSource: dataSource);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WorksBloc>.value(
            value: bloc,
            child: WorkDetailScreen(work: _obraCompletada(), userRole: 'Profesional'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openInviteDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invitar Propietario'));
      await tester.pumpAndSettle();
    }

    testWidgets('genera el código y lo muestra para compartir', (tester) async {
      final dataSource = _FakeWorksDataSource();
      await pumpFicha(tester, dataSource);
      await openInviteDialog(tester);

      expect(find.text('INVITAR PROPIETARIO'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'nuevo@gmail.com');
      await tester.tap(find.text('Generar Invitación'));
      await tester.pumpAndSettle();

      expect(dataSource.inviteCalls, 1);
      expect(dataSource.lastInviteWorkId, 'w1');
      expect(dataSource.lastInviteEmail, 'nuevo@gmail.com');
      expect(find.text('CNG-7K2P9Q'), findsOneWidget);
    });

    testWidgets('valida el correo antes de enviar (sin llamadas)', (tester) async {
      final dataSource = _FakeWorksDataSource();
      await pumpFicha(tester, dataSource);
      await openInviteDialog(tester);

      await tester.enterText(find.byType(TextFormField), 'no-es-correo');
      await tester.tap(find.text('Generar Invitación'));
      await tester.pump();

      expect(find.text('Ingrese un correo electrónico válido.'), findsOneWidget);
      expect(dataSource.inviteCalls, 0);
    });

    testWidgets('ante un error del backend permanece abierto mostrando el mensaje',
        (tester) async {
      final dataSource = _FakeWorksDataSource(
        failInviteWith: Exception('El correo ya se encuentra registrado. Vincule al propietario directamente con su correo (CU-14).'),
      );
      await pumpFicha(tester, dataSource);
      await openInviteDialog(tester);

      await tester.enterText(find.byType(TextFormField), 'reg@gmail.com');
      await tester.tap(find.text('Generar Invitación'));
      await tester.pumpAndSettle();

      expect(dataSource.inviteCalls, 1);
      expect(find.textContaining('ya se encuentra registrado'), findsOneWidget);
      expect(find.text('INVITAR PROPIETARIO'), findsOneWidget);
    });
  });
}