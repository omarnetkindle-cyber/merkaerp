import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/control_center_agent.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/control_center_license_client.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/services/license_validation_service.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fingerprint = 'HW-PHASE-2B';
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keys;
  late LicenseValidationService validator;
  late DateTime clock;
  late DateTime expiry;
  late String token;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    keys = _generateTestKeyPair();
    validator = LicenseValidationService.withPublicKey(
      CryptoUtils.encodeRSAPublicKeyToPem(keys.publicKey),
    );
  });

  setUp(() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    await _createMinimalSchema(db);
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'agent-phase-two-b-test-key'),
    );
    clock = DateTime.now().toUtc();
    expiry = clock.add(const Duration(days: 30));
    token = _createLicenseToken(keys.privateKey, expiry: expiry);
    await _saveLicense(
      token: token,
      expiry: expiry,
      lastValidation: clock.subtract(const Duration(days: 2)),
    );
  });

  tearDown(() async {
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test('reconcilia online al iniciar y persiste onlineValid', () async {
    final result = await ControlCenterAgent.reconcileLicenseState(
      client: _clientWithResponse(_validServerResponse(expiry)),
      validationService: validator,
      currentHardwareFingerprint: fingerprint,
      now: clock,
    );

    expect(result, isNotNull);
    expect(result!.state, LicenseOperationalState.onlineValid);
    expect(result.allowsOperation, isTrue);
    expect(
      await LicenciaService.instance.obtenerEstadoOperativo(),
      LicenseOperationalState.onlineValid,
    );
    expect(
      (await LicenciaService.instance.obtenerLicencia())!
          .lastSuccessfulValidationAt,
      clock,
    );
  });

  test(
    'detecta cambio del servidor pero no aplica módulos sin JWT nuevo',
    () async {
      final response = _validServerResponse(expiry);
      (response['license'] as Map<String, dynamic>)['modules'] = [
        'ventas',
        'nomina',
      ];

      final result = await LicenciaService.instance.reconciliarEstadoOperativo(
        client: _clientWithResponse(response),
        validationService: validator,
        currentHardwareFingerprint: fingerprint,
        now: clock,
      );

      expect(result.state, LicenseOperationalState.refreshRequired);
      expect(result.allowsOperation, isTrue);
      expect(result.requiresSignedRefresh, isTrue);
      expect(
        (await LicenciaService.instance.obtenerLicencia())!.modulosHabilitados,
        ['ventas'],
      );
    },
  );

  test('sin red conserva operación dentro de la gracia firmada', () async {
    final result = await LicenciaService.instance.reconciliarEstadoOperativo(
      client: _clientWithError(const ControlCenterNetworkException('sin red')),
      validationService: validator,
      currentHardwareFingerprint: fingerprint,
      now: clock,
    );

    expect(result.state, LicenseOperationalState.offlineGrace);
    expect(result.allowsOperation, isTrue);
    expect(
      await LicenciaService.instance.permiteOperacionLocal(now: clock),
      isTrue,
    );
  });

  test('bloquea nuevas operaciones cuando vence la gracia', () async {
    await _saveLicense(
      token: token,
      expiry: expiry,
      lastValidation: clock.subtract(const Duration(days: 8)),
    );
    final result = await LicenciaService.instance.reconciliarEstadoOperativo(
      client: _clientWithError(const ControlCenterNetworkException('sin red')),
      validationService: validator,
      currentHardwareFingerprint: fingerprint,
      now: clock,
    );

    expect(result.state, LicenseOperationalState.graceExpired);
    expect(result.allowsOperation, isFalse);
    expect(await LicenciaService.instance.validarModulo('ventas'), isFalse);
  });

  test(
    'HTTP 403 marca denegación online sin alterar claims firmados',
    () async {
      final result = await LicenciaService.instance.reconciliarEstadoOperativo(
        client: _clientWithError(
          const ControlCenterHttpException(403, message: 'HTTP 403'),
        ),
        validationService: validator,
        currentHardwareFingerprint: fingerprint,
        now: clock,
      );

      expect(result.state, LicenseOperationalState.onlineDenied);
      expect(result.allowsOperation, isFalse);
      final stored = await LicenciaService.instance.obtenerLicencia();
      expect(stored!.estado, EstadoLicencia.activa);
      expect(stored.modulosHabilitados, ['ventas']);
      expect(await LicenciaService.instance.validarModulo('ventas'), isFalse);
    },
  );

  test('recuperar conectividad limpia una denegación transitoria', () async {
    await LicenciaService.instance.reconciliarEstadoOperativo(
      client: _clientWithError(
        const ControlCenterHttpException(403, message: 'HTTP 403'),
      ),
      validationService: validator,
      currentHardwareFingerprint: fingerprint,
      now: clock,
    );

    final recovered = await LicenciaService.instance.reconciliarEstadoOperativo(
      client: _clientWithResponse(_validServerResponse(expiry)),
      validationService: validator,
      currentHardwareFingerprint: fingerprint,
      now: clock.add(const Duration(minutes: 5)),
    );

    expect(recovered.state, LicenseOperationalState.onlineValid);
    expect(recovered.allowsOperation, isTrue);
    expect(await LicenciaService.instance.validarModulo('ventas'), isTrue);
  });

  test('estado activo no permite operar después del vencimiento firmado', () {
    final expired = LicenciaInfo(
      uuid: 'LIC-EXPIRED',
      plan: TipoPlan.basico,
      estado: EstadoLicencia.activa,
      fechaExpiracion: DateTime.now().subtract(const Duration(minutes: 1)),
      modulosHabilitados: const ['ventas'],
    );

    expect(expired.esValida, isFalse);
  });
}

Future<void> _saveLicense({
  required String token,
  required DateTime expiry,
  required DateTime lastValidation,
}) {
  return LicenciaService.instance.guardarLicencia(
    LicenciaInfo(
      uuid: 'LIC-PHASE-2B',
      plan: TipoPlan.basico,
      estado: EstadoLicencia.activa,
      fechaExpiracion: expiry,
      modulosHabilitados: const ['ventas'],
      hardwareFingerprint: 'HW-PHASE-2B',
      offlineToken: token,
      clientId: 'CLIENT-2B',
      installationId: 'INST-PHASE-2B',
      lastSuccessfulValidationAt: lastValidation,
      signedTokenIssuedAt: lastValidation,
    ),
  );
}

Map<String, dynamic> _validServerResponse(DateTime expiry) => {
  'valid': true,
  'installation_id': 'INST-PHASE-2B',
  'license': {
    'status': 'active',
    'expires_at': expiry.toIso8601String(),
    'modules': ['ventas'],
    'license_type': 'SUSCRIPCION',
    'product_family': 'COMMERCIAL',
  },
};

ControlCenterLicenseClient _clientWithResponse(Map<String, dynamic> response) =>
    ControlCenterLicenseClient(transport: _FakeTransport(response: response));

ControlCenterLicenseClient _clientWithError(Object error) =>
    ControlCenterLicenseClient(transport: _FakeTransport(error: error));

class _FakeTransport implements ControlCenterHttpTransport {
  const _FakeTransport({this.response = const {}, this.error});

  final Map<String, dynamic> response;
  final Object? error;

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) async {
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) async => const {};
}

String _createLicenseToken(
  RSAPrivateKey privateKey, {
  required DateTime expiry,
}) {
  final issuedAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final payload = <String, dynamic>{
    'token_type': 'license',
    'hfp': 'HW-PHASE-2B',
    'lt': 'SUSCRIPCION',
    'st': 'ACTIVO',
    'ed': expiry.toIso8601String(),
    'md': ['ventas'],
    'pf': 'COMMERCIAL',
    'installation_id': 'INST-PHASE-2B',
    'license_id': 'LICENSE-2B',
    'client_id': 'CLIENT-2B',
    'iat': issuedAt,
    'exp': issuedAt + const Duration(days: 30).inSeconds,
    'iss': 'MerkaERP-ControlCenter',
  };
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
