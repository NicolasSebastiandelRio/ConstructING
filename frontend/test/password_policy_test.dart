import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/auth/presentation/validators/password_policy.dart';

void main() {
  group('PasswordPolicy - CU-06 RNF_S_01', () {
    test('rechaza contraseñas de menos de 8 caracteres', () {
      expect(PasswordPolicy.isValid('abc123'), isFalse);
      expect(PasswordPolicy.isValid('123'), isFalse);
      expect(PasswordPolicy.isValid('1234567'), isFalse);
    });

    test('rechaza contraseñas de 8+ caracteres sin número', () {
      expect(PasswordPolicy.isValid('abcdefgh'), isFalse);
      expect(PasswordPolicy.isValid('sin numeros aqui'), isFalse);
    });

    test('acepta contraseñas de 8 caracteres con al menos un número', () {
      expect(PasswordPolicy.isValid('secreto1'), isTrue);
      expect(PasswordPolicy.isValid('C0nstructING'), isTrue);
      expect(PasswordPolicy.isValid('12345678'), isTrue);
    });

    test('expone el mensaje de error exacto de la especificación', () {
      expect(
        PasswordPolicy.errorMessage,
        'La contraseña debe tener al menos 8 caracteres y un número',
      );
    });

    test('no acepta cadenas vacías', () {
      expect(PasswordPolicy.isValid(''), isFalse);
    });
  });
}