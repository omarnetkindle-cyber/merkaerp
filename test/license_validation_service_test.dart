import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_validation_service.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> signingKeys;
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> otherKeys;
  late LicenseValidationService validator;

  setUpAll(() {
    signingKeys = _generateTestKeyPair();
    otherKeys = _generateTestKeyPair();
    validator = LicenseValidationService.withPublicKey(
      CryptoUtils.encodeRSAPublicKeyToPem(signingKeys.publicKey),
    );
  });

  test('acepta firma RS256 valida y claims validos', () async {
    final token = _createToken(signingKeys.privateKey, _validPayload());

    final payload = await validator.validateOfflineTokenForDevice(
      token,
      'HW-TEST-001',
    );

    expect(payload, isNotNull);
    expect(payload!['iss'], 'MerkaERP-ControlCenter');
    expect(payload['md'], ['ventas', 'contabilidad']);
  });

  test('rechaza payload alterado despues de firmar', () {
    final token = _createToken(signingKeys.privateKey, _validPayload());
    final parts = token.split('.');
    final payload = _decodeJsonPart(parts[1])..['lt'] = 'PERPETUA';
    final altered = '${parts[0]}.${_encodeJsonPart(payload)}.${parts[2]}';

    expect(validator.validateOfflineToken(altered), isNull);
  });

  test('rechaza firma alterada', () {
    final token = _createToken(signingKeys.privateKey, _validPayload());
    final parts = token.split('.');
    final signature = _decodeBase64Url(parts[2]);
    signature[signature.length - 1] ^= 0x01;
    final altered = '${parts[0]}.${parts[1]}.${_encodeBase64Url(signature)}';

    expect(validator.validateOfflineToken(altered), isNull);
  });

  test('rechaza token verificado con clave publica equivocada', () {
    final token = _createToken(signingKeys.privateKey, _validPayload());
    final wrongValidator = LicenseValidationService.withPublicKey(
      CryptoUtils.encodeRSAPublicKeyToPem(otherKeys.publicKey),
    );

    expect(wrongValidator.validateOfflineToken(token), isNull);
  });

  test('rechaza algoritmo distinto de RS256 aunque tenga firma RSA valida', () {
    final token = _createToken(
      signingKeys.privateKey,
      _validPayload(),
      algorithm: 'HS256',
    );

    expect(validator.validateOfflineToken(token), isNull);
  });

  test('rechaza tipo de token distinto de JWT', () {
    final token = _createToken(
      signingKeys.privateKey,
      _validPayload(),
      type: 'JWS',
    );

    expect(validator.validateOfflineToken(token), isNull);
  });

  test('rechaza issuer incorrecto', () {
    final payload = _validPayload()..['iss'] = 'otro-emisor';
    final token = _createToken(signingKeys.privateKey, payload);

    expect(validator.validateOfflineToken(token), isNull);
  });

  test('rechaza token expirado para activacion local', () async {
    final payload = _validPayload()
      ..['ed'] = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String();
    final token = _createToken(signingKeys.privateKey, payload);

    expect(
      await validator.validateOfflineTokenForDevice(token, 'HW-TEST-001'),
      isNull,
    );
  });

  test('rechaza hardware fingerprint no coincidente', () async {
    final token = _createToken(signingKeys.privateKey, _validPayload());

    expect(
      await validator.validateOfflineTokenForDevice(token, 'HW-DISTINTO'),
      isNull,
    );
  });

  test('validador de prueba sin clave rechaza todos los tokens', () {
    final token = _createToken(signingKeys.privateKey, _validPayload());
    final missingKeyValidator = LicenseValidationService.withPublicKey('');

    expect(missingKeyValidator.hasConfiguredPublicKey, isFalse);
    expect(missingKeyValidator.validateOfflineToken(token), isNull);
  });

  test('clave publica de produccion es PEM RSA valida de 3072 bits', () {
    final productionValidator = LicenseValidationService();

    expect(productionValidator.hasConfiguredPublicKey, isTrue);
    expect(productionValidator.configuredPublicKeyBitLength, 3072);
  });

  group('validacion de licencia persistida', () {
    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseHelper.setTestDatabase(db);
      await db.execute('''
        CREATE TABLE app_config (
          clave TEXT PRIMARY KEY,
          valor TEXT NOT NULL
        )
      ''');
      await LicenciaService.instance.limpiarCache();
    });

    tearDown(() async {
      await LicenciaService.instance.limpiarCache();
      await DatabaseHelper.resetForTests();
    });

    test('validarLicenciaLocal vuelve a verificar el token guardado', () async {
      final payload = _validPayload();
      final token = _createToken(signingKeys.privateKey, payload);
      final license = LicenciaInfo(
        uuid: 'LIC-TEST-1',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: DateTime.parse(payload['ed'] as String),
        modulosHabilitados: (payload['md'] as List).cast<String>(),
        tipoLicencia: TipoLicencia.suscripcion,
        hardwareFingerprint: payload['hfp'] as String,
        offlineToken: token,
      );
      final db = await DatabaseHelper.instance.database;
      await db.insert('app_config', {
        'clave': 'licencia_info',
        'valor': jsonEncode(license.toMap()),
      });

      expect(
        await LicenciaService.instance.validarLicenciaLocal(
          validationService: validator,
          currentHardwareFingerprint: 'HW-TEST-001',
        ),
        isTrue,
      );

      final parts = token.split('.');
      final signature = _decodeBase64Url(parts[2]);
      signature[0] ^= 0x01;
      final alteredToken =
          '${parts[0]}.${parts[1]}.${_encodeBase64Url(signature)}';
      await db.update(
        'app_config',
        {
          'valor': jsonEncode(
            LicenciaInfo(
              uuid: license.uuid,
              plan: license.plan,
              estado: license.estado,
              fechaExpiracion: license.fechaExpiracion,
              modulosHabilitados: license.modulosHabilitados,
              tipoLicencia: license.tipoLicencia,
              hardwareFingerprint: license.hardwareFingerprint,
              offlineToken: alteredToken,
            ).toMap(),
          ),
        },
        where: 'clave = ?',
        whereArgs: ['licencia_info'],
      );
      await LicenciaService.instance.limpiarCache();

      expect(
        await LicenciaService.instance.validarLicenciaLocal(
          validationService: validator,
          currentHardwareFingerprint: 'HW-TEST-001',
        ),
        isFalse,
      );
    });
  });
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateTestKeyPair() {
  final random = FortunaRandom();
  final source = Random.secure();
  random.seed(
    KeyParameter(
      Uint8List.fromList(List<int>.generate(32, (_) => source.nextInt(256))),
    ),
  );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
    pair.publicKey as RSAPublicKey,
    pair.privateKey as RSAPrivateKey,
  );
}

Map<String, dynamic> _validPayload() {
  return {
    'hfp': 'HW-TEST-001',
    'lt': 'SUSCRIPCION',
    'st': 'ACTIVO',
    'ed': DateTime.now()
        .add(const Duration(days: 30))
        .toUtc()
        .toIso8601String(),
    'md': ['ventas', 'contabilidad'],
    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'iss': 'MerkaERP-ControlCenter',
  };
}

String _createToken(
  RSAPrivateKey privateKey,
  Map<String, dynamic> payload, {
  String algorithm = 'RS256',
  String type = 'JWT',
}) {
  final header = _encodeJsonPart({'alg': algorithm, 'typ': type});
  final encodedPayload = _encodeJsonPart(payload);
  final signingInput = Uint8List.fromList(
    ascii.encode('$header.$encodedPayload'),
  );
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final signature = signer.generateSignature(signingInput) as RSASignature;
  return '$header.$encodedPayload.${_encodeBase64Url(signature.bytes)}';
}

String _encodeJsonPart(Map<String, dynamic> value) {
  return _encodeBase64Url(utf8.encode(jsonEncode(value)));
}

Map<String, dynamic> _decodeJsonPart(String value) {
  return jsonDecode(utf8.decode(_decodeBase64Url(value)))
      as Map<String, dynamic>;
}

String _encodeBase64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _decodeBase64Url(String value) {
  var normalized = value;
  final remainder = normalized.length % 4;
  if (remainder != 0) normalized += '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(normalized));
}
