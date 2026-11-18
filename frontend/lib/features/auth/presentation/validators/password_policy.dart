/// Políticas de seguridad de credenciales (CU-06 / RNF_S_01).
///
/// La especificación exige contraseñas con al menos 8 caracteres y un número:
/// "La contraseña debe tener al menos 8 caracteres y un número".
class PasswordPolicy {
  static const int minLength = 8;
  static const String errorMessage =
      'La contraseña debe tener al menos 8 caracteres y un número';

  /// Retorna `true` si la contraseña cumple la política (>= 8 caracteres y al
  /// menos un dígito).
  static bool isValid(String password) {
    if (password.length < minLength) return false;
    return password.contains(RegExp(r'[0-9]'));
  }
}