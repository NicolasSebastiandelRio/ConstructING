import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/security/jwt_session.dart';

/// Encabezado fijo usado en los tokens de prueba.
const _header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'; // {"alg":"HS256","typ":"JWT"}

String _signature() => 'dGVzdC1maXJtYQ'; // firma simulada

/// Construye un JWT con el payload dado (exp en segundos desde epoch).
String _token(Map<String, dynamic> payload) {
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$_header.$encoded.${_signature()}';
}

void main() {
  group('JwtSession.decodePayload', () {
    test('decodifica el payload de un token bien formado', () {
      final token = _token({'sub': '1', 'email': 'a@b.co', 'exp': 9999999999});
      final payload = JwtSession.decodePayload(token);
      expect(payload, isNotNull);
      expect(payload!['sub'], '1');
      expect(payload['email'], 'a@b.co');
    });

    test('retorna null si el token no tiene el formato JWT', () {
      expect(JwtSession.decodePayload('no-es-un-token'), isNull);
      expect(JwtSession.decodePayload('a.b'), isNull);
      expect(JwtSession.decodePayload(''), isNull);
    });

    test('retorna null si el payload no es JSON válido', () {
      final token = '$_header.!!!!.${_signature()}';
      expect(JwtSession.decodePayload(token), isNull);
    });
  });

  group('JwtSession.isExpired (CU-05 / RNF_S_01)', () {
    final now = DateTime.utc(2026, 1, 1);
    final nowSeconds = now.millisecondsSinceEpoch / 1000;

    test('considera expirado un token cuyo exp ya pasó', () {
      final token = _token({'exp': nowSeconds - 60});
      expect(JwtSession.isExpired(token, now: now), isTrue);
    });

    test('considera vigente un token cuyo exp no llegó', () {
      final token = _token({'exp': nowSeconds + 3600});
      expect(JwtSession.isExpired(token, now: now), isFalse);
    });

    test('considera expirado un token que expira exactamente ahora', () {
      final token = _token({'exp': nowSeconds});
      expect(JwtSession.isExpired(token, now: now), isTrue);
    });

    test('asume vigente un token sin reclamo exp', () {
      final token = _token({'sub': '1'});
      expect(JwtSession.isExpired(token, now: now), isFalse);
    });

    test('asume vigente un token malformado (no rompe la app)', () {
      expect(JwtSession.isExpired('no-es-un-token', now: now), isFalse);
    });
  });
}
