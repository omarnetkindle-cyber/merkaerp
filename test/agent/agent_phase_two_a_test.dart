import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/agent/agent_contract.dart';
import 'package:merka_erp/agent/agent_store.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/licensing/domain/product_family.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/services/license_validation_service.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installationId = 'INST-PHASE-2A';
  const fingerprint = 'HW-PHASE-2A';
  const commandSecret = 'phase-two-command-secret-32-bytes';
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keys;
  late LicenseValidationService validator;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    keys = _generateTestKeyPair();
    validator = LicenseValidationService.withPublicKey(
      CryptoUtils.encodeRSAPublicKeyToPem(keys.publicKey),
    );
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    await MerkaAgentStore.instance.initialize();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-two-a-test-key'),
    );
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-PHASE-2A',
        plan: TipoPlan.basico,
        estado: EstadoLicencia.activa,
        fechaExpiracion: DateTime.now().add(const Duration(days: 10)),
        modulosHabilitados: const ['ventas'],
        hardwareFingerprint: fingerprint,
        installationId: installationId,
        signedTokenIssuedAt: DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        ),
      ),
    );
    ControlCenterSecretStore.instance.configureCommandSecretForTests(
      commandSecret,
    );
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test('la clave pública de producción coincide con el SPKI del contrato', () {
    final production = LicenseValidationService();
    expect(production.hasExpectedPublisherKey, isTrue);
    expect(
      production.configuredPublicKeySpkiSha256,
      LicenseValidationService.expectedPublisherSpkiSha256,
    );
  });

  test('actualizar_modulos usa solo módulos del JWT RS256', () async {
    final token = _createLicenseToken(
      keys.privateKey,
      modules: const ['inventario', 'contabilidad'],
    );
    final command = _signedCommand(
      id: 'CMD-MODULES-SIGNED',
      type: TipoComando.actualizar_modulos,
      nonce: 'NONCE-MODULES-SIGNED',
      params: {
        'license_token': token,
        'modules': ['powershell', 'modulo_no_firmado'],
      },
    );

    final result = await CCCommandsProcessor.instance.procesarComando(
      command,
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isTrue);
    expect(result.datos?['product_family'], 'COMMERCIAL');
    final stored = await LicenciaService.instance.obtenerLicencia();
    expect(stored!.modulosHabilitados, ['inventario', 'contabilidad']);
    expect(stored.modulosHabilitados, isNot(contains('modulo_no_firmado')));
    expect(stored.offlineToken, token);
    expect(
      (await MerkaAgentStore.instance.pendingAcks()).single.status,
      'completed',
    );
    expect(
      MerkaAgentContract.phaseOneCapabilities,
      containsAll(['actualizar_modulos', 'actualizar_licencia']),
    );
  });

  test('rechaza módulos sueltos sin license_token', () async {
    final result = await CCCommandsProcessor.instance.procesarComando(
      _signedCommand(
        id: 'CMD-MODULES-RAW',
        type: TipoComando.actualizar_modulos,
        nonce: 'NONCE-MODULES-RAW',
        params: const {
          'modules': ['inventario'],
        },
      ),
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isFalse);
    expect(result.datos?['error_code'], 'SIGNED_LICENSE_TOKEN_REQUIRED');
    expect(
      (await LicenciaService.instance.obtenerLicencia())!.modulosHabilitados,
      ['ventas'],
    );
  });

  test('rechaza token RS256 destinado a otra instalación', () async {
    final token = _createLicenseToken(
      keys.privateKey,
      installation: 'INST-OTHER',
      modules: const ['inventario'],
    );
    final result = await CCCommandsProcessor.instance.procesarComando(
      _signedCommand(
        id: 'CMD-WRONG-INSTALL',
        type: TipoComando.actualizar_licencia,
        nonce: 'NONCE-WRONG-INSTALL',
        params: {'license_token': token},
      ),
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isFalse);
    expect(result.datos?['error_code'], 'LICENSE_TOKEN_INVALID');
    expect(
      (await LicenciaService.instance.obtenerLicencia())!.modulosHabilitados,
      ['ventas'],
    );
  });

  test('rechaza cambio remoto de familia COMMERCIAL a PUBLIC', () async {
    final token = _createLicenseToken(
      keys.privateKey,
      family: 'PUBLIC',
      modules: const ['presupuesto_publico'],
    );
    final result = await CCCommandsProcessor.instance.procesarComando(
      _signedCommand(
        id: 'CMD-WRONG-FAMILY',
        type: TipoComando.actualizar_licencia,
        nonce: 'NONCE-WRONG-FAMILY',
        params: {'license_token': token},
      ),
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isFalse);
    expect(result.datos?['error_code'], 'LICENSE_TOKEN_INVALID');
    expect(
      (await LicenciaService.instance.obtenerLicencia())!.productFamily,
      ProductFamily.commercial,
    );
  });

  test(
    'persiste una suspensión auténtica y bloquea la licencia local',
    () async {
      final token = _createLicenseToken(
        keys.privateKey,
        status: 'SUSPENDIDO',
        modules: const ['ventas'],
      );
      final result = await CCCommandsProcessor.instance.procesarComando(
        _signedCommand(
          id: 'CMD-SUSPEND',
          type: TipoComando.actualizar_licencia,
          nonce: 'NONCE-SUSPEND',
          params: {'license_token': token},
        ),
        licenseValidationService: validator,
        currentHardwareFingerprint: fingerprint,
      );

      expect(result.exito, isTrue);
      final stored = await LicenciaService.instance.obtenerLicencia();
      expect(stored!.estado, EstadoLicencia.suspendida);
      expect(stored.esValida, isFalse);
    },
  );

  test('acepta licencia perpetua auténtica sin claim exp', () async {
    final token = _createLicenseToken(
      keys.privateKey,
      licenseType: 'PERPETUA',
      includeJwtExpiry: false,
      modules: const ['ventas', 'inventario'],
    );
    final result = await CCCommandsProcessor.instance.procesarComando(
      _signedCommand(
        id: 'CMD-PERPETUAL',
        type: TipoComando.actualizar_licencia,
        nonce: 'NONCE-PERPETUAL',
        params: {'license_token': token},
      ),
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isTrue);
    final stored = await LicenciaService.instance.obtenerLicencia();
    expect(stored!.tipoLicencia, TipoLicencia.perpetua);
    expect(stored.estaExpirada, isFalse);
  });

  test('rechaza una firma RS256 creada por otro publicador', () async {
    final foreignKeys = _generateTestKeyPair();
    final token = _createLicenseToken(
      foreignKeys.privateKey,
      modules: const ['inventario'],
    );
    final result = await CCCommandsProcessor.instance.procesarComando(
      _signedCommand(
        id: 'CMD-FOREIGN-PUBLISHER',
        type: TipoComando.actualizar_licencia,
        nonce: 'NONCE-FOREIGN-PUBLISHER',
        params: {'license_token': token},
      ),
      licenseValidationService: validator,
      currentHardwareFingerprint: fingerprint,
    );

    expect(result.exito, isFalse);
    expect(result.datos?['error_code'], 'LICENSE_TOKEN_INVALID');
  });
}

ComandoRemoto _signedCommand({
  required String id,
  required TipoComando type,
  required String nonce,
  required Map<String, dynamic> params,
}) {
  const installationId = 'INST-PHASE-2A';
  const secret = 'phase-two-command-secret-32-bytes';
  final timestamp = DateTime.now().toUtc();
  final expiresAt = timestamp.add(const Duration(minutes: 5));
  final timestampRaw = timestamp.toIso8601String();
  final expiresAtRaw = expiresAt.toIso8601String();
  final canonical = MerkaAgentContract.canonicalCommandPayload(
    id: id,
    action: type.name,
    installationId: installationId,
    timestamp: timestampRaw,
    expiresAt: expiresAtRaw,
    nonce: nonce,
    params: params,
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(canonical)).toString();
  return ComandoRemoto(
    id: id,
    tipo: type,
    parametros: params,
    timestamp: timestamp,
    installationId: installationId,
    expiresAt: expiresAt,
    nonce: nonce,
    timestampRaw: timestampRaw,
    expiresAtRaw: expiresAtRaw,
    firmaHmac: signature,
  );
}

String _createLicenseToken(
  RSAPrivateKey privateKey, {
  String installation = 'INST-PHASE-2A',
  String family = 'COMMERCIAL',
  String status = 'ACTIVO',
  String licenseType = 'SUSCRIPCION',
  bool includeJwtExpiry = true,
  required List<String> modules,
}) {
  final issuedAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final payload = <String, dynamic>{
    'token_type': 'license',
    'hfp': 'HW-PHASE-2A',
    'lt': licenseType,
    'st': status,
    'ed': DateTime.now()
        .toUtc()
        .add(const Duration(days: 30))
        .toIso8601String(),
    'md': modules,
    'pf': family,
    'installation_id': installation,
    'client_id': 'CLIENT-2A',
    'client_name': 'Cliente firmado',
    'iat': issuedAt,
    'iss': 'MerkaERP-ControlCenter',
  };
  if (includeJwtExpiry) {
    payload['exp'] = issuedAt + const Duration(hours: 1).inSeconds;
  }
  final header = _encodePart({'alg': 'RS256', 'typ': 'JWT'});
  final body = _encodePart(payload);
  final input = Uint8List.fromList(ascii.encode('$header.$body'));
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final signature = signer.generateSignature(input) as RSASignature;
  return '$header.$body.${_base64Url(signature.bytes)}';
}

String _encodePart(Map<String, dynamic> value) =>
    _base64Url(utf8.encode(jsonEncode(value)));

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

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

Future<void> _createMinimalSchema(Database db) async {
  await db.execute(
    'CREATE TABLE app_config (clave TEXT PRIMARY KEY, valor TEXT)',
  );
  await db.insert('app_config', {'clave': 'company_active_id', 'valor': '1'});
  await db.execute('''
    CREATE TABLE auditoria_eventos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      fecha TEXT,
      accion TEXT,
      entidad TEXT,
      entidad_id INTEGER,
      detalle TEXT,
      usuario TEXT,
      old_values TEXT,
      new_values TEXT,
      ip_address TEXT,
      device_id TEXT
    )
  ''');
}
