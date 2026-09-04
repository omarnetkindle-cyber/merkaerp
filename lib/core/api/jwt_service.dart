// ============================================================
// jwt_service.dart
// Servicio de generación y validación de tokens JWT
// ============================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';

class JWTService {
  static final JWTService instance = JWTService._internal();

  String? _secretKey;

  JWTService._internal();

  /// Establece la clave secreta para firmar tokens
  void setSecretKey(String key) {
    final configuredKey = key.trim();
    if (configuredKey.isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        'La clave JWT no puede estar vacía',
      );
    }
    _secretKey = configuredKey;
  }

  /// Genera un token JWT
  String generateToken(Map<String, dynamic> payload, {Duration? expiresIn}) {
    final header = {'alg': 'HS256', 'typ': 'JWT'};

    final now = DateTime.now();
    final finalPayload = Map<String, dynamic>.from(payload);

    if (expiresIn != null) {
      finalPayload['exp'] = now.add(expiresIn).millisecondsSinceEpoch ~/ 1000;
      finalPayload['iat'] = now.millisecondsSinceEpoch ~/ 1000;
    }

    final encodedHeader = _base64UrlEncode(jsonEncode(header));
    final encodedPayload = _base64UrlEncode(jsonEncode(finalPayload));

    final signature = _sign('$encodedHeader.$encodedPayload');

    return '$encodedHeader.$encodedPayload.$signature';
  }

  /// Valida un token JWT
  bool validateToken(String token) {
    try {
      if (_secretKey == null) return false;
      final parts = token.split('.');
      if (parts.length != 3) return false;

      final signature = _sign('${parts[0]}.${parts[1]}');
      return signature == parts[2];
    } catch (e) {
      return false;
    }
  }

  /// Decodifica un token JWT sin validar
  Map<String, dynamic>? decodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = _base64UrlDecode(parts[1]);
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Decodifica y valida un token JWT
  Map<String, dynamic>? decodeAndValidateToken(String token) {
    if (!validateToken(token)) return null;

    final payload = decodeToken(token);
    if (payload == null) return null;

    // Verificar expiración
    final exp = payload['exp'] as int?;
    if (exp != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now >= exp) return null;
    }

    return payload;
  }

  /// Refresca un token JWT
  String? refreshToken(String token, {Duration? expiresIn}) {
    final payload = decodeAndValidateToken(token);
    if (payload == null) return null;

    // Remover campos de tiempo
    payload.remove('exp');
    payload.remove('iat');

    return generateToken(payload, expiresIn: expiresIn);
  }

  /// Firma una cadena usando HMAC-SHA256
  String _sign(String data) {
    final secretKey = _secretKey;
    if (secretKey == null) {
      throw StateError('JWT secret no configurado');
    }
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);

    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);

    return _base64UrlEncodeBytes(digest.bytes);
  }

  /// Codifica en Base64 URL-safe
  String _base64UrlEncode(String input) {
    final bytes = utf8.encode(input);
    return _base64UrlEncodeBytes(bytes);
  }

  String _base64UrlEncodeBytes(List<int> bytes) {
    final base64 = base64Encode(bytes);
    return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  /// Decodifica desde Base64 URL-safe
  String _base64UrlDecode(String input) {
    final base64 = input.replaceAll('-', '+').replaceAll('_', '/');

    // Añadir padding si es necesario
    while (base64.length % 4 != 0) {
      return '$base64=';
    }

    final bytes = base64Decode(base64);
    return utf8.decode(bytes);
  }

  /// Genera un token de acceso
  String generateAccessToken({
    required String userId,
    required String companyId,
    required String role,
    Duration expiresIn = const Duration(hours: 1),
  }) {
    return generateToken({
      'sub': userId,
      'company_id': companyId,
      'role': role,
      'type': 'access',
    }, expiresIn: expiresIn);
  }

  /// Genera un token de refresco
  String generateRefreshToken({
    required String userId,
    required String companyId,
    Duration expiresIn = const Duration(days: 7),
  }) {
    return generateToken({
      'sub': userId,
      'company_id': companyId,
      'type': 'refresh',
    }, expiresIn: expiresIn);
  }

  /// Verifica si un token es de acceso
  bool isAccessToken(String token) {
    final payload = decodeToken(token);
    return payload?['type'] == 'access';
  }

  /// Verifica si un token es de refresco
  bool isRefreshToken(String token) {
    final payload = decodeToken(token);
    return payload?['type'] == 'refresh';
  }

  /// Extrae el ID de usuario de un token
  String? getUserIdFromToken(String token) {
    final payload = decodeToken(token);
    return payload?['sub'] as String?;
  }

  /// Extrae el ID de empresa de un token
  String? getCompanyIdFromToken(String token) {
    final payload = decodeToken(token);
    return payload?['company_id'] as String?;
  }

  /// Extrae el rol de un token
  String? getRoleFromToken(String token) {
    final payload = decodeToken(token);
    return payload?['role'] as String?;
  }
}
