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
  // WidgetsBinding es requerido por ControlCenterAgent.handleRemoteAccessConsent
  // que usa GlobalKey.currentContext. Sin esto el test falla con
  // "Binding has not yet been initialized" al correr aislado.
  TestWidgetsFlutterBinding.ensureInitialized();

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
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'control-center-test-key'),
    );
    await _createMinimalSchema(db);
  });

  tearDown(() async {
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  test('activacion online verifica RS256 y guarda licencia cifrada', () async {
    final token = _createToken(keys.privateKey, _validPayload());
    final client = ControlCenterLicenseClient(
      transport: _FakeTransport(
        post: {
          'success': true,
          'license_token': token,
          'license': {
            'client_id': 'client-1',
            'client_name': 'Cliente de prueba',
            'license_type': 'SUSCRIPCION',
            'expires_at': _validPayload()['ed'],
            'modules': ['ventas', 'contabilidad'],
            'max_users': 5,
            'max_devices': 2,
            'max_branches': 1,
            'installation_id': 'inst-1',
            'postgres_credentials': {'host': 'db.example.test'},
          },
        },
      ),
    );

    final activated = await LicenciaService.instance.activarDesdeControlCenter(
      email: 'cliente@example.com',
      password: 'secreto',
      currentHardwareFingerprint: 'HW-TEST-001',
      validationService: validator,
      client: client,
    );

    expect(activated, isTrue);
    final license = await LicenciaService.instance.obtenerLicencia();
    expect(license!.clientId, 'client-1');
    expect(license.installationId, 'inst-1');
    expect(license.postgresCredentials!['host'], 'db.example.test');

    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [LicenseSecureStore.encryptedConfigKey],
    );
    expect(rows, hasLength(1));
    expect(rows.single['valor'].toString(), isNot(contains(token)));
    expect(rows.single['valor'].toString(), contains('AES-256-GCM'));
  });

  test('activacion recupera installation_id desde el JWT firmado', () async {
    final payload = _validPayload()..['installation_id'] = 'INST-FIRMADA-1';
    final token = _createToken(keys.privateKey, payload);

    final activated = await LicenciaService.instance.activarDesdeControlCenter(
      email: 'cliente@example.com',
      password: 'secreto',
      currentHardwareFingerprint: 'HW-TEST-001',
      validationService: validator,
      client: ControlCenterLicenseClient(
        transport: _FakeTransport(
          post: {'success': true, 'license_token': token},
        ),
      ),
    );

    expect(activated, isTrue);
    final license = await LicenciaService.instance.obtenerLicencia();
    expect(license!.installationId, 'INST-FIRMADA-1');
    final config = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['control_center_installation_id'],
    );
    expect(config.single['valor'], 'INST-FIRMADA-1');
  });

  test('repara una licencia previa usando la identidad firmada', () async {
    final payload = _validPayload()..['installation_id'] = 'INST-REPARADA-1';
    final token = _createToken(keys.privateKey, payload);
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'LIC-SIN-INSTALACION',
        plan: TipoPlan.profesional,
        estado: EstadoLicencia.activa,
        fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
        modulosHabilitados: const ['ventas', 'contabilidad'],
        hardwareFingerprint: 'HW-TEST-001',
        offlineToken: token,
      ),
    );

    final installationId = await LicenciaService.instance
        .reconciliarIdentidadInstalacionFirmada(
          validationService: validator,
          currentHardwareFingerprint: 'HW-TEST-001',
        );

    expect(installationId, 'INST-REPARADA-1');
    final repaired = await LicenciaService.instance.obtenerLicencia();
    expect(repaired!.installationId, 'INST-REPARADA-1');
  });

  test(
    'validacion online invalida bloquea y red caida usa gracia firmada',
    () async {
      final token = _createToken(keys.privateKey, _validPayload());
      await LicenciaService.instance.activarDesdeControlCenter(
        email: 'cliente@example.com',
        password: 'secreto',
        currentHardwareFingerprint: 'HW-TEST-001',
        validationService: validator,
        client: ControlCenterLicenseClient(
          transport: _FakeTransport(post: {'success': true, 'token': token}),
        ),
      );

      final invalid = await LicenciaService.instance
          .validarConControlCenterOGracia(
            currentHardwareFingerprint: 'HW-TEST-001',
            validationService: validator,
            client: ControlCenterLicenseClient(
              transport: _FakeTransport(post: {'valid': false}),
            ),
          );
      expect(invalid, isFalse);

      final grace = await LicenciaService.instance
          .validarConControlCenterOGracia(
            currentHardwareFingerprint: 'HW-TEST-001',
            validationService: validator,
            client: const ControlCenterLicenseClient(
              transport: _OfflineTransport(),
            ),
          );
      expect(grace, isTrue);
    },
  );

  test('modo de gracia nunca supera expires_at del JWT firmado', () async {
    final token = _createToken(
      keys.privateKey,
      _validPayload(expiry: DateTime.now().add(const Duration(days: 1))),
    );
    await LicenciaService.instance.activarDesdeControlCenter(
      email: 'cliente@example.com',
      password: 'secreto',
      currentHardwareFingerprint: 'HW-TEST-001',
      validationService: validator,
      client: ControlCenterLicenseClient(
        transport: _FakeTransport(post: {'success': true, 'token': token}),
      ),
    );

    final valid = await LicenciaService.instance.validarConControlCenterOGracia(
      currentHardwareFingerprint: 'HW-TEST-001',
      validationService: validator,
      now: DateTime.now().add(const Duration(days: 2)),
      client: const ControlCenterLicenseClient(transport: _OfflineTransport()),
    );

    expect(valid, isFalse);
  });

  test('manejador de acceso remoto solo crea stub de consentimiento', () async {
    final result = await ControlCenterAgent.handleRemoteAccessConsent({
      'id': 'cmd-ra-1',
      'action': 'solicitar_acceso_remoto',
      'title': 'Acceso remoto',
    });

    expect(result.exito, isTrue);
    final notifications = await db.query('notificaciones');
    expect(notifications, hasLength(1));
    expect(notifications.single['titulo'], 'MERKA solicita acceso remoto');
    expect(notifications.single['detalle'], contains('Stub pendiente Fase RA'));

    final audit = await db.query('auditoria_eventos');
    expect(
      audit.map((row) => row['accion']),
      contains('CONTROL_CENTER_REMOTE_ACCESS_STUB'),
    );
  });
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
  await db.execute('''
    CREATE TABLE notificaciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      tipo TEXT,
      prioridad TEXT,
      titulo TEXT,
      detalle TEXT,
      entidad TEXT,
      entidad_id TEXT,
      leida INTEGER,
      creada_en TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE empresa_config (
      id INTEGER PRIMARY KEY,
      nombre TEXT,
      nit TEXT
    )
  ''');
  await db.insert('empresa_config', {
    'id': 1,
    'nombre': 'Empresa Test',
    'nit': '900000001',
  });
}

class _FakeTransport implements ControlCenterHttpTransport {
  const _FakeTransport({this.post = const {}});

  final Map<String, dynamic> post;

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) async {
    return post;
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) async => const {};
}

class _OfflineTransport implements ControlCenterHttpTransport {
  const _OfflineTransport();

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) {
    throw const ControlCenterNetworkException('offline');
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) {
    throw const ControlCenterNetworkException('offline');
  }
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

Map<String, dynamic> _validPayload({DateTime? expiry}) {
  final issuedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'token_type': 'license',
    'hfp': 'HW-TEST-001',
    'lt': 'SUSCRIPCION',
    'st': 'ACTIVO',
    'ed': (expiry ?? DateTime.now().add(const Duration(days: 30)))
        .toUtc()
        .toIso8601String(),
    'md': ['ventas', 'contabilidad'],
    'pf': 'COMMERCIAL',
    'installation_id': 'inst-1',
    'iat': issuedAt,
    'exp': issuedAt + const Duration(days: 30).inSeconds,
    'iss': 'MerkaERP-ControlCenter',
  };
}

String _createToken(RSAPrivateKey privateKey, Map<String, dynamic> payload) {
  final header = _encodeJsonPart({'alg': 'RS256', 'typ': 'JWT'});
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

String _encodeBase64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
