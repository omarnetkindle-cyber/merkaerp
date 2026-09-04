import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

class SyncAuthException implements Exception {
  const SyncAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncAuthContext {
  const SyncAuthContext({
    required this.tenantKind,
    required this.tenantId,
    required this.deviceId,
    this.userId,
    this.subject,
  });

  final String tenantKind;
  final String tenantId;
  final String deviceId;
  final String? userId;
  final String? subject;
}

abstract class SyncAuthVerifier {
  Future<SyncAuthContext> verify(String? authorizationHeader);
}

class JwtRs256SyncAuthVerifier implements SyncAuthVerifier {
  JwtRs256SyncAuthVerifier({
    required String publicKeyPem,
    this.expectedIssuer = 'MerkaERP-ControlCenter',
    DateTime Function()? now,
  })  : _publicKeyPem = publicKeyPem,
        _now = now ?? (() => DateTime.now().toUtc());

  final String _publicKeyPem;
  final String expectedIssuer;
  final DateTime Function() _now;

  @override
  Future<SyncAuthContext> verify(String? authorizationHeader) async {
    final token = _bearerToken(authorizationHeader);
    if (token == null) {
      throw const SyncAuthException('Authorization Bearer requerido.');
    }
    final payload = _verifyJwt(token);
    _validateClaims(payload);
    return SyncAuthContext(
      tenantKind: _tenantKind(payload),
      tenantId: _tenantId(payload),
      deviceId: _requiredString(
          payload,
          const [
            'installation_id',
            'installationId',
            'device_id',
            'deviceId',
          ],
          'installation_id'),
      userId: _firstString(payload, const ['user_id', 'userId', 'client_id']),
      subject: _firstString(payload, const ['sub']),
    );
  }

  Map<String, Object?> _verifyJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const SyncAuthException('JWT inválido.');
    }
    if (_publicKeyPem.trim().isEmpty) {
      throw const SyncAuthException('Llave pública JWT no configurada.');
    }

    final header = _decodePart(parts[0]);
    if (header['alg'] != 'RS256' || header['typ'] != 'JWT') {
      throw const SyncAuthException('JWT debe usar RS256 y typ JWT.');
    }

    final publicKey = CryptoUtils.rsaPublicKeyFromPem(_publicKeyPem);
    final verifier = Signer('SHA-256/RSA')
      ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    final signature = RSASignature(_base64UrlDecode(parts[2]));
    final signingInput = Uint8List.fromList(
      ascii.encode('${parts[0]}.${parts[1]}'),
    );
    if (!verifier.verifySignature(signingInput, signature)) {
      throw const SyncAuthException('Firma JWT inválida.');
    }

    return _decodePart(parts[1]);
  }

  void _validateClaims(Map<String, Object?> payload) {
    if (payload['iss'] != expectedIssuer) {
      throw const SyncAuthException('Issuer JWT inválido.');
    }
    final tokenType = payload['token_type']?.toString();
    if (tokenType != 'license' && tokenType != 'sync_access') {
      throw const SyncAuthException('Tipo de token no autorizado para sync.');
    }

    final status =
        _firstString(payload, const ['st', 'status', 'estado'])?.toUpperCase();
    if (status != 'ACTIVO' && status != 'TRIAL') {
      throw const SyncAuthException('Licencia no activa para sync.');
    }

    final exp = payload['exp'];
    if (exp is num) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      if (!expiresAt.isAfter(_now())) {
        throw const SyncAuthException('Token expirado.');
      }
    } else {
      final expiryText = _firstString(payload, const [
        'ed',
        'expiry_date',
        'expires_at',
      ]);
      final licenseType =
          _firstString(payload, const ['lt', 'license_type'])?.toUpperCase();
      if (licenseType != 'PERPETUA') {
        final expiresAt = DateTime.tryParse(expiryText ?? '')?.toUtc();
        if (expiresAt == null || !expiresAt.isAfter(_now())) {
          throw const SyncAuthException('Licencia expirada o sin expiración.');
        }
      }
    }

    _tenantKind(payload);
    _tenantId(payload);
    _requiredString(
        payload,
        const [
          'installation_id',
          'installationId',
          'device_id',
          'deviceId',
        ],
        'installation_id');
  }

  String _tenantKind(Map<String, Object?> payload) {
    final raw = _firstString(payload, const [
      'tenant_kind',
      'tenantKind',
      'pf',
      'product_family',
      'productFamily',
    ])?.toUpperCase();
    if (raw == 'COMMERCIAL' || raw == 'PRIVATE' || raw == 'COMERCIAL') {
      return 'commercial';
    }
    if (raw == 'PUBLIC' || raw == 'PUBLIC_SECTOR' || raw == 'PUBLICO') {
      return 'public_sector';
    }
    throw const SyncAuthException('Familia/tenant_kind no autorizada.');
  }

  String _tenantId(Map<String, Object?> payload) {
    final explicit = _firstString(payload, const ['tenant_id', 'tenantId']);
    if (explicit != null) return explicit;

    final companyId = _firstString(payload, const ['company_id', 'companyId']);
    if (companyId != null) return 'company:$companyId';

    final clientId = _firstString(payload, const ['client_id', 'clientId']);
    if (clientId != null) return 'client:$clientId';

    final entidadId = _firstString(payload, const ['entidad_id', 'entidadId']);
    if (entidadId != null) return 'entity:$entidadId';

    throw const SyncAuthException('tenant_id no encontrado en JWT.');
  }

  static String? _bearerToken(String? header) {
    if (header == null) return null;
    final parts = header.trim().split(RegExp(r'\s+'));
    if (parts.length != 2 || parts.first.toLowerCase() != 'bearer') {
      return null;
    }
    return parts.last;
  }

  static Map<String, Object?> _decodePart(String encoded) {
    final decoded = utf8.decode(_base64UrlDecode(encoded));
    final jsonValue = jsonDecode(decoded);
    if (jsonValue is Map<String, dynamic>) return jsonValue;
    if (jsonValue is Map) {
      return jsonValue.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const SyncAuthException('JWT contiene JSON inválido.');
  }

  static Uint8List _base64UrlDecode(String input) {
    var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 0:
        break;
      case 2:
        normalized += '==';
      case 3:
        normalized += '=';
      default:
        throw const SyncAuthException('Base64Url inválido.');
    }
    return Uint8List.fromList(base64.decode(normalized));
  }

  static String _requiredString(
    Map<String, Object?> map,
    List<String> keys,
    String label,
  ) {
    final value = _firstString(map, keys);
    if (value == null) throw SyncAuthException('$label requerido en JWT.');
    return value;
  }

  static String? _firstString(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
