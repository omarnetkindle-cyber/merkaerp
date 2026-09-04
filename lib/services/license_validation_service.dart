import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

class LicenseValidationService {
  static const String _expectedIssuer = 'MerkaERP-ControlCenter';
  static const String expectedPublisherSpkiSha256 =
      'e3344e9f2e3010c75fcbd64d7bb8f4ddc34eedc5a18f7296b82d914e5df2fb27';

  // Clave publica de produccion. La clave privada permanece exclusivamente
  // en Control Center y nunca debe incorporarse a este repositorio.
  static const String _productionPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA6MMNqdYuBJuZ1vJXUNGK
TWFR+8da59yk3XWfgPJ4RKkkQZfMi5TdCtkj+RrReS9mjUidwIkhohM2/eLiPw7X
K013NqxIArgfQj1e0qOakv5D8lFm9nf2XmRmCk7UWCrV2HR/2pqbZNvnV2f5puVT
5pXiqSpx43Ijfu1rJUaL2EG5RRlZQCFZvJrOEvzZvEKGIp4zwD1MuMP5w+ogx7K4
igESaKkmeQIqPCo0ujiYvyLL6x53kO/933wPhqkEiKOxirHHnltopb6OeM3shs+Z
+wB7t09EI8sTA07XwjalQECl+76j82dH5HW5zeC/njl3BB9PtrpFKlVvHlhYUt3V
g/1+JFobqyc6/ZLRMRMAG31mKqPFGyvNcJxuc5bdzPSDh8uvPkuQgOgZr/950jKL
5QoULr6ZSqZ4BU13HLsjXz6hftiGq5eaLCXlTxfg/StRwJH4Gh9NOc7n4toBwqMi
hjkWm8BQxAfKF7CIy+3PTrOwuEnrgPSiIoX7WohsP+JbAgMBAAE=
-----END PUBLIC KEY-----''';

  static final LicenseValidationService _instance = LicenseValidationService._(
    _productionPublicKeyPem,
    expectedPublisherSpkiSha256,
  );

  factory LicenseValidationService() => _instance;

  LicenseValidationService.withPublicKey(
    String publicKeyPem, {
    String? expectedSpkiSha256,
  }) : _publicKeyPem = publicKeyPem,
       _expectedSpkiSha256 = expectedSpkiSha256;

  LicenseValidationService._(this._publicKeyPem, this._expectedSpkiSha256);

  final String _publicKeyPem;
  final String? _expectedSpkiSha256;

  bool get hasConfiguredPublicKey => _publicKeyPem.trim().isNotEmpty;

  String? get configuredPublicKeySpkiSha256 {
    try {
      final normalized = _publicKeyPem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll(RegExp(r'\s'), '');
      if (normalized.isEmpty) return null;
      return sha256.convert(base64.decode(normalized)).toString();
    } catch (_) {
      return null;
    }
  }

  bool get hasExpectedPublisherKey {
    final expected = _expectedSpkiSha256;
    return expected == null || configuredPublicKeySpkiSha256 == expected;
  }

  int? get configuredPublicKeyBitLength {
    if (!hasConfiguredPublicKey) return null;
    try {
      return CryptoUtils.rsaPublicKeyFromPem(_publicKeyPem).modulus?.bitLength;
    } catch (_) {
      return null;
    }
  }

  /// Verifica primero cabecera y firma RS256. Solo despues procesa claims.
  ///
  /// FAIL-CLOSED: cualquier error de firma, clave ausente o claim inválido
  /// retorna null. Nunca retorna un payload sin firma verificada.
  Map<String, dynamic>? validateOfflineToken(String token) {
    try {
      final parts = token.split('.');
      // Fail-closed: sin clave pública configurada, rechazar todo.
      if (parts.length != 3 ||
          !hasConfiguredPublicKey ||
          !hasExpectedPublisherKey) {
        return null;
      }

      final header = _decodeJsonObject(parts[0]);
      // Requerir alg=RS256 y typ=JWT explícitamente.
      if (header == null ||
          header['alg'] != 'RS256' ||
          header['typ'] != 'JWT') {
        return null;
      }

      // Verificar firma antes de leer el payload — fail-closed en cualquier error.
      final RSAPublicKey publicKey;
      try {
        publicKey = CryptoUtils.rsaPublicKeyFromPem(_publicKeyPem);
      } catch (_) {
        return null;
      }

      final verifier = Signer('SHA-256/RSA')
        ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      final RSASignature signature;
      try {
        signature = RSASignature(_base64UrlDecodeBytes(parts[2]));
      } catch (_) {
        return null;
      }

      final signingInput = Uint8List.fromList(
        ascii.encode('${parts[0]}.${parts[1]}'),
      );

      bool valid;
      try {
        valid = verifier.verifySignature(signingInput, signature);
      } catch (_) {
        valid = false;
      }
      // Fail-closed: firma inválida → null, sin excepción.
      if (!valid) return null;

      // Solo tras verificar la firma se procesa el payload.
      final payload = _decodeJsonObject(parts[1]);
      if (payload == null) return null;

      // Normalizar campos alternativos (compatibilidad con tokens del servidor
      // que pueden usar nombres largos en lugar de abreviaciones).
      payload['hfp'] ??= payload['hardware_fingerprint'];
      payload['lt'] ??= payload['license_type'];
      payload['st'] ??= payload['status'] ?? payload['estado'];
      payload['ed'] ??= payload['expiry_date'] ?? payload['expires_at'];
      payload['md'] ??= payload['modules'];
      payload['pf'] ??= payload['product_family'] ?? payload['productFamily'];
      // iss nunca se rellenará con el esperado si no viene en el token;
      // _validateTokenStructure lo rechazará si falta o es incorrecto.

      if (!_validateTokenStructure(payload)) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Verifica un manifiesto firmado por el publicador (por ejemplo, una
  /// actualización). Comparte la misma clave pública fijada que las licencias,
  /// pero exige un tipo/propósito separado y una expiración JWT válida.
  Map<String, dynamic>? validatePublisherToken(
    String token, {
    required String kind,
    String? installationId,
  }) {
    try {
      final parts = token.split('.');
      if (parts.length != 3 || !hasConfiguredPublicKey) return null;
      final header = _decodeJsonObject(parts[0]);
      if (header == null ||
          header['alg'] != 'RS256' ||
          header['typ'] != 'JWT') {
        return null;
      }

      final RSAPublicKey publicKey;
      try {
        publicKey = CryptoUtils.rsaPublicKeyFromPem(_publicKeyPem);
      } catch (_) {
        return null;
      }
      final verifier = Signer('SHA-256/RSA')
        ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      final RSASignature signature;
      try {
        signature = RSASignature(_base64UrlDecodeBytes(parts[2]));
      } catch (_) {
        return null;
      }
      final signingInput = Uint8List.fromList(
        ascii.encode('${parts[0]}.${parts[1]}'),
      );
      var valid = false;
      try {
        valid = verifier.verifySignature(signingInput, signature);
      } catch (_) {
        valid = false;
      }
      if (!valid) return null;

      final payload = _decodeJsonObject(parts[1]);
      if (payload == null ||
          payload['iss'] != _expectedIssuer ||
          payload['token_type'] != 'publisher_manifest' ||
          payload['kind'] != kind) {
        return null;
      }
      final issuedAt = payload['iat'];
      final expiresAt = payload['exp'];
      if (issuedAt is! int || issuedAt <= 0 || expiresAt is! int) return null;
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (expiresAt <= nowSeconds || issuedAt > nowSeconds + 300) return null;
      if (installationId != null &&
          payload['installation_id']?.toString() != installationId) {
        return null;
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Aplica las validaciones de negocio requeridas para usar el token
  /// en el dispositivo actual (expiración, estado, fingerprint).
  Future<Map<String, dynamic>?> validateOfflineTokenForDevice(
    String token,
    String currentFingerprint,
  ) async {
    final payload = validateOfflineToken(token);
    if (payload == null || isTokenExpired(payload) || !isTokenActive(payload)) {
      return null;
    }
    // Fail-closed: fingerprint obligatorio y debe coincidir.
    final tokenFingerprint = payload['hfp'] as String?;
    if (tokenFingerprint == null ||
        !await verifyHardwareFingerprint(
          tokenFingerprint,
          currentFingerprint,
        )) {
      return null;
    }
    return payload;
  }

  /// Valida un reemplazo remoto de licencia sin confiar en metadatos paralelos
  /// del comando. A diferencia del uso operativo offline, admite estados
  /// suspendidos o expirados para que el cliente pueda persistir el bloqueo.
  Future<Map<String, dynamic>?> validateAgentLicenseUpdate(
    String token, {
    required String currentFingerprint,
    required String expectedInstallationId,
    required String expectedProductFamily,
    DateTime? now,
  }) async {
    final payload = validateOfflineToken(token);
    if (payload == null || payload['token_type'] != 'license') return null;

    if (payload['installation_id']?.toString() != expectedInstallationId) {
      return null;
    }
    if (!await verifyHardwareFingerprint(
      payload['hfp']?.toString() ?? '',
      currentFingerprint,
    )) {
      return null;
    }

    final family = payload['pf']?.toString().toUpperCase();
    if ((family != 'COMMERCIAL' && family != 'PUBLIC') ||
        family != expectedProductFamily.toUpperCase()) {
      return null;
    }

    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final nowSeconds = effectiveNow.millisecondsSinceEpoch ~/ 1000;
    final issuedAt = payload['iat'];
    final expiresAt = payload['exp'];
    if (issuedAt is! int || issuedAt <= 0 || issuedAt > nowSeconds + 300) {
      return null;
    }
    final perpetual = payload['lt'] == 'PERPETUA';
    if ((!perpetual && (expiresAt is! int || expiresAt <= nowSeconds)) ||
        (expiresAt != null && (expiresAt is! int || expiresAt <= nowSeconds))) {
      return null;
    }

    final modules = payload['md'];
    if (modules is! List || modules.length > 256) return null;
    final normalized = modules.map((value) => value.toString().trim()).toList();
    if (normalized.any((value) => value.isEmpty) ||
        normalized.toSet().length != normalized.length) {
      return null;
    }
    payload['md'] = normalized;
    return payload;
  }

  Map<String, dynamic>? _decodeJsonObject(String encoded) {
    try {
      final decoded = utf8.decode(_base64UrlDecodeBytes(encoded));
      final value = jsonDecode(decoded);
      if (value is! Map<String, dynamic>) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  /// Valida la estructura y semántica del payload de un token ya firmado.
  bool _validateTokenStructure(Map<String, dynamic> payload) {
    // Todos los campos requeridos deben existir.
    const requiredFields = ['hfp', 'lt', 'st', 'ed', 'md', 'iat', 'iss'];
    if (requiredFields.any((field) => !payload.containsKey(field))) {
      return false;
    }

    // Issuer estricto.
    if (payload['iss'] != _expectedIssuer) return false;

    final fingerprint = payload['hfp'];
    if (fingerprint is! String || fingerprint.trim().isEmpty) return false;

    final licenseType = payload['lt'];
    if (licenseType != 'SUSCRIPCION' && licenseType != 'PERPETUA') {
      return false;
    }

    final status = payload['st'];
    if (status != 'ACTIVO' && status != 'TRIAL' && status != 'SUSPENDIDO') {
      return false;
    }

    final expiry = payload['ed'];
    if (expiry is! String || DateTime.tryParse(expiry) == null) return false;

    final modules = payload['md'];
    if (modules is! List || modules.any((module) => module is! String)) {
      return false;
    }

    final issuedAt = payload['iat'];
    final validIssuedAt =
        (issuedAt is int && issuedAt > 0) ||
        (issuedAt is String && DateTime.tryParse(issuedAt) != null);
    return validIssuedAt;
  }

  Future<bool> verifyHardwareFingerprint(
    String tokenFingerprint,
    String currentFingerprint,
  ) async {
    return tokenFingerprint == currentFingerprint;
  }

  bool isTokenExpired(Map<String, dynamic> payload) {
    if (payload['lt'] == 'PERPETUA') return false;
    final expiry = payload['ed'];
    if (expiry is! String) return true;
    final expiryDate = DateTime.tryParse(expiry);
    return expiryDate == null || DateTime.now().isAfter(expiryDate);
  }

  bool isTokenActive(Map<String, dynamic> payload) {
    final status = payload['st'];
    return status == 'ACTIVO' || status == 'TRIAL';
  }

  Map<String, dynamic> extractLicenseInfo(String token) {
    final payload = validateOfflineToken(token);
    if (payload == null) return {};

    return {
      'license_type': payload['lt'],
      'status': payload['st'],
      'expiry_date': payload['ed'],
      'modules': payload['md'],
      'hardware_fingerprint': payload['hfp'],
      'issued_at': payload['iat'],
      'issuer': payload['iss'],
      'product_family': payload['pf'],
    };
  }

  Uint8List _base64UrlDecodeBytes(String input) {
    var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder != 0) normalized += '=' * (4 - remainder);
    return Uint8List.fromList(base64.decode(normalized));
  }

  String generateHash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  bool validateLocalIntegrity({
    required String localLicenseType,
    required String localStatus,
    required String localExpiryDate,
    required Map<String, dynamic> tokenData,
  }) {
    return localLicenseType == (tokenData['license_type'] ?? tokenData['lt']) &&
        localStatus == (tokenData['status'] ?? tokenData['st']) &&
        localExpiryDate == (tokenData['expiry_date'] ?? tokenData['ed']);
  }

  int getDaysUntilExpiry(String expiryDateStr) {
    final expiryDate = DateTime.tryParse(expiryDateStr);
    if (expiryDate == null) return -1;
    return expiryDate.difference(DateTime.now()).inDays;
  }

  bool requiresRenewal(String expiryDateStr, {int warningDays = 7}) {
    final daysUntil = getDaysUntilExpiry(expiryDateStr);
    return daysUntil >= 0 && daysUntil <= warningDays;
  }

  bool isModuleEnabled(String module, List<dynamic> enabledModules) {
    return enabledModules.contains(module);
  }

  Map<String, bool> validateLicenseLimits({
    required int currentUsers,
    required int maxUsers,
    required int currentDevices,
    required int maxDevices,
    required int currentBranches,
    required int maxBranches,
  }) {
    return {
      'users_valid': currentUsers <= maxUsers,
      'devices_valid': currentDevices <= maxDevices,
      'branches_valid': currentBranches <= maxBranches,
      'all_valid':
          currentUsers <= maxUsers &&
          currentDevices <= maxDevices &&
          currentBranches <= maxBranches,
    };
  }
}
