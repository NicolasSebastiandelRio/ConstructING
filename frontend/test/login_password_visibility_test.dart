import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/theme/app_theme.dart';
import 'package:constructing_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:constructing_mobile/features/auth/data/models/user_model.dart';
import 'package:constructing_mobile/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:constructing_mobile/features/auth/presentation/screens/login_screen.dart';

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

class _FakeAuthDataSource implements AuthRemoteDataSource {
  @override
  Future<Map<String, dynamic>> login(String email, String password, String role) =>
      throw UnimplementedError();

  @override
  Future<UserModel> register({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String? matricula,
    String? invitationCode,
  }) =>
      throw UnimplementedError();
}

Future<void> _pumpLogin(WidgetTester tester, String role) async {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(
          authRemoteDataSource: _FakeAuthDataSource(),
          secureStorage: const FlutterSecureStorage(),
        ),
        child: LoginScreen(initialRole: role),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _isObscured(WidgetTester tester) {
  // El TextFormField delega en un EditableText interno, que sí expone el valor
  // efectivo de obscureText. El campo de contraseña es el segundo del form.
  final editable = find.descendant(
    of: find.byType(TextFormField).at(1),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editable).obscureText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final role in ['Propietario', 'Profesional']) {
    group('LoginScreen ($role) - botón visualizar contraseña', () {
      testWidgets('oculta por defecto y alterna al tocar el icono dorado', (tester) async {
        await _pumpLogin(tester, role);

        // Estado inicial: oculta, con icono de "mostrar" en dorado.
        expect(_isObscured(tester), isTrue);
        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
        expect(
          (tester.widget(find.byIcon(Icons.visibility_outlined)) as Icon).color,
          AppTheme.accentGold,
        );

        // Primer toque: revela la contraseña.
        await tester.tap(find.byIcon(Icons.visibility_outlined));
        await tester.pump();
        expect(_isObscured(tester), isFalse);
        expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
        expect(
          (tester.widget(find.byIcon(Icons.visibility_off_outlined)) as Icon).color,
          AppTheme.accentGold,
        );

        // Segundo toque: vuelve a ocultarla.
        await tester.tap(find.byIcon(Icons.visibility_off_outlined));
        await tester.pump();
        expect(_isObscured(tester), isTrue);
        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      });
    });
  }
}