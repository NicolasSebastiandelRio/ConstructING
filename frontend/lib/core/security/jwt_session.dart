import 'dart:convert';

/// Utilidad mínima de sesión persistente (CU-05 / RNF_S_01).
///
/// Permite verificar la expiración de un token JWT almacenado localmente sin
/// depender de librerías externas. Un token expirado no debe restaurar la
/// sesión para obligar al usuario a re-autenticarse.
class JwtSession {
  /// Decodifica la porción de payload de un JWT (sección central) y retorna
  /// su mapa, o `null` si el token no posee el formato esperado.
  static Map<String, dynamic>? decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// Retorna `true` si el token está expirado según su reclamo `exp`
  /// (segundos desde epoch). Si no posee `exp`, se asume vigente.
  static bool isExpired(String token, {DateTime? now}) {
    final payload = decodePayload(token);
    if (payload == null) return false;
    final exp = payload['exp'];
    if (exp is! num) return false;
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
    return current >= exp.toDouble();
  }
}
