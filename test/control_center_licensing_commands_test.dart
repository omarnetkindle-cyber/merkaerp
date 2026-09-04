import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/services/control_center_license_client.dart';
import 'package:merka_erp/services/control_center_secret_store.dart';
import 'package:merka_erp/services/hardware_fingerprint_service.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/services/license_validation_service.dart';
import 'package:merka_erp/control_center_agent.dart';
import 'package:merka_erp/services/cc_commands_processor.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockControlCenterTransport implements ControlCenterHttpTransport {
  MockControlCenterTransport({this.postHandler, this.getHandler});

  Future<Map<String, dynamic>> Function(
    String url,
    Map<String, Object?> payload,
  )?
  postHandler;
  Future<Map<String, dynamic>> Function(String url)? getHandler;

  final List<Map<String, dynamic>> postedCalls = [];

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, Object?> payload,
  ) async {
    postedCalls.add({'url': url, 'payload': payload});
    if (postHandler != null) {
      return postHandler!(url, payload);
    }
    return {'valid': true, 'success': true};
  }

  @override
  Future<Map<String, dynamic>> getJson(String url) async {
    if (getHandler != null) {
      return getHandler!(url);
    }
    return {'commands': <Map<String, dynamic>>[]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> signingKeys;
  late LicenseValidationService validator;

  setUpAll(() {
    signingKeys = _generateTestKeyPair();
    validator = LicenseValidationService.withPublicKey(
      CryptoUtils.encodeRSAPublicKeyToPem(signingKeys.publicKey),
    );
  });

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
        leida INTEGER DEFAULT 0,
        creada_en TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE auditoria (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER,
        accion TEXT NOT NULL,
        entidad TEXT,
        entidad_id TEXT,
        detalle TEXT,
        creada_en TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE auditoria_eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT,
        accion TEXT NOT NULL,
        entidad TEXT,
        entidad_id TEXT,
        detalle TEXT,
        usuario TEXT,
        old_values TEXT,
        new_values TEXT,
        ip_address TEXT,
        device_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE empresas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        nit TEXT,
        activa INTEGER DEFAULT 1
      )
    ''');
    await db.insert('empresas', {
      'id': 1,
      'nombre': 'Empresa de Prueba SAS',
      'nit': '900123456-7',
      'activa': 1,
    });

    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'test_secret_key_32_bytes_long_!'),
    );
    await LicenciaService.instance.limpiarCache();
  });

  tearDown(() async {
    ControlCenterSecretStore.instance.configureCommandSecretForTests(null);
    await LicenciaService.instance.limpiarCache();
    await DatabaseHelper.resetForTests();
  });

  group('PASO 1 & 2: Activación y Validación RS256 de Licencia', () {
    test(
      'activación online guarda token cifrado y metadatos del cliente',
      () async {
        final hwService = HardwareFingerprintService();
        final fingerprint = await hwService.generateFingerprint();
        final tokenPayload = _validPayload(fingerprint: fingerprint);
        final token = _createToken(signingKeys.privateKey, tokenPayload);

        final transport = MockControlCenterTransport(
          postHandler: (url, payload) async {
            expect(url, contains('/licenses/activate'));
            expect(payload['email'], 'cliente@prueba.com');
            expect(payload['password'], 'secret123');
            expect(payload['hardware_fingerprint'], fingerprint);

            return {
              'license_token': token,
              'client_id': 'CLI-1001',
              'client_name': 'Cliente Ejemplo SAS',
              'license_type': 'SUSCRIPCION',
              'expires_at': tokenPayload['ed'],
              'modules': ['ventas', 'contabilidad', 'inventario'],
              'max_users': 5,
              'max_devices': 10,
              'max_branches': 2,
              'installation_id': 'INST-999',
              'postgres_credentials': {'host': 'pg.merkaerp.com', 'port': 5432},
            };
          },
        );

        final client = ControlCenterLicenseClient(transport: transport);
        final success = await LicenciaService.instance
            .activarDesdeControlCenter(
              email: 'cliente@prueba.com',
              password: 'secret123',
              client: client,
              validationService: validator,
              fingerprintService: hwService,
            );

        expect(success, isTrue);

        final stored = await LicenciaService.instance.obtenerLicencia();
        expect(stored, isNotNull);
        expect(stored!.offlineToken, equals(token));
        expect(stored.clientId, equals('CLI-1001'));
        expect(stored.clientName, equals('Cliente Ejemplo SAS'));
        expect(stored.maxUsers, equals(5));
        expect(stored.maxDevices, equals(10));
        expect(stored.maxBranches, equals(2));
        expect(stored.installationId, equals('INST-999'));
        expect(stored.postgresCredentials?['host'], equals('pg.merkaerp.com'));
      },
    );

    test(
      'validación al iniciar falla cerrado si la firma RS256 es inválida',
      () async {
        final hwService = HardwareFingerprintService();
        final fingerprint = await hwService.generateFingerprint();
        final invalidToken = _createToken(
          signingKeys.privateKey,
          _validPayload(fingerprint: fingerprint),
          type: 'INVALID',
        );

        final license = LicenciaInfo(
          uuid: 'LIC-INVALID',
          plan: TipoPlan.profesional,
          estado: EstadoLicencia.activa,
          fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
          modulosHabilitados: ['ventas'],
          tipoLicencia: TipoLicencia.suscripcion,
          hardwareFingerprint: fingerprint,
          offlineToken: invalidToken,
        );

        await LicenciaService.instance.guardarLicencia(license);

        final valid = await LicenciaService.instance
            .validarConControlCenterOGracia(
              validationService: validator,
              fingerprintService: hwService,
            );

        expect(valid, isFalse);
      },
    );

    test(
      'modo de gracia respeta la fecha expires_at del token RS256 y vence si pasa el límite',
      () async {
        final hwService = HardwareFingerprintService();
        final fingerprint = await hwService.generateFingerprint();

        final tokenExpiry = DateTime.now().toUtc().add(const Duration(days: 3));
        final payload = _validPayload(
          fingerprint: fingerprint,
          expiry: tokenExpiry,
        );
        final token = _createToken(signingKeys.privateKey, payload);

        final license = LicenciaInfo(
          uuid: 'LIC-GRACE-TEST',
          plan: TipoPlan.profesional,
          estado: EstadoLicencia.activa,
          fechaExpiracion: tokenExpiry,
          modulosHabilitados: ['ventas', 'contabilidad', 'inventario'],
          tipoLicencia: TipoLicencia.suscripcion,
          hardwareFingerprint: fingerprint,
          installationId: 'INST-999',
          offlineToken: token,
          lastSuccessfulValidationAt: DateTime.now().toUtc().subtract(
            const Duration(days: 1),
          ),
        );

        await LicenciaService.instance.guardarLicencia(license);

        final offlineClient = MockControlCenterTransport(
          postHandler: (url, payload) async {
            throw const ControlCenterNetworkException('Sin conexión');
          },
        );

        final validWithinGrace = await LicenciaService.instance
            .validarConControlCenterOGracia(
              client: ControlCenterLicenseClient(transport: offlineClient),
              validationService: validator,
              fingerprintService: hwService,
              now: DateTime.now().toUtc().add(const Duration(days: 2)),
            );
        expect(validWithinGrace, isTrue);

        final validAfterExpiry = await LicenciaService.instance
            .validarConControlCenterOGracia(
              client: ControlCenterLicenseClient(transport: offlineClient),
              validationService: validator,
              fingerprintService: hwService,
              now: DateTime.now().toUtc().add(const Duration(days: 5)),
            );
        expect(validAfterExpiry, isFalse);
      },
    );
  });

  group('PASO 4 & 5: Polling de Comandos y Stub de Acceso Remoto', () {
    test(
      'manejador de acceso remoto registra stub sin captura ni streaming',
      () async {
        final commandData = {
          'id': 'CMD-REMOTE-001',
          'action': 'solicitar_acceso_remoto',
          'requested_by': 'Soporte Control Center',
          'timestamp': DateTime.now().toIso8601String(),
        };

        final result = await ControlCenterAgent.handleRemoteAccessConsent(
          commandData,
        );

        expect(result.exito, isTrue);
        expect(result.mensaje, contains('stub'));

        final db = await DatabaseHelper.instance.database;
        final notifications = await db.query('notificaciones');
        expect(notifications, isNotEmpty);
        expect(
          notifications.first['titulo'],
          equals('MERKA solicita acceso remoto'),
        );
        expect(
          notifications.first['detalle'],
          contains('Stub pendiente Fase RA'),
        );

        final audit = await db.query('auditoria_eventos');
        expect(audit, isNotEmpty);
        expect(audit.first['accion'], contains('REMOTE_ACCESS_STUB'));
      },
    );

    test(
      'CCCommandsProcessor procesa solo comandos firmados para la instalación licenciada',
      () async {
        const installationId = 'INST-CMD-TEST';
        const commandSecret = 'test-command-hmac-secret-32-bytes!!';

        await LicenciaService.instance.guardarLicencia(
          LicenciaInfo(
            uuid: 'LIC-CMD-TEST',
            plan: TipoPlan.profesional,
            estado: EstadoLicencia.activa,
            fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
            modulosHabilitados: const ['ventas'],
            tipoLicencia: TipoLicencia.suscripcion,
            installationId: installationId,
          ),
        );
        ControlCenterSecretStore.instance.configureCommandSecretForTests(
          commandSecret,
        );

        final msgCmd = _signedRemoteCommand(
          id: 'CMD-MSG-01',
          tipo: TipoComando.mensaje_admin,
          parametros: const {
            'titulo': 'Mensaje urgente',
            'detalle': 'Actualizar datos',
          },
          installationId: installationId,
          secret: commandSecret,
          nonce: 'nonce-msg-01',
        );
        final resMsg = await CCCommandsProcessor.instance.procesarComando(
          msgCmd,
        );
        expect(resMsg.exito, isTrue);

        final lockCmd = _signedRemoteCommand(
          id: 'CMD-LOCK-01',
          tipo: TipoComando.bloquear_instalacion,
          parametros: const {},
          installationId: installationId,
          secret: commandSecret,
          nonce: 'nonce-lock-01',
        );
        final resLock = await CCCommandsProcessor.instance.procesarComando(
          lockCmd,
        );
        expect(resLock.exito, isTrue);

        final isLocked = await CCCommandsProcessor.instance
            .verificarInstalacionBloqueada();
        expect(isLocked, isTrue);

        final unlockCmd = _signedRemoteCommand(
          id: 'CMD-UNLOCK-01',
          tipo: TipoComando.activar_instalacion,
          parametros: const {},
          installationId: installationId,
          secret: commandSecret,
          nonce: 'nonce-unlock-01',
        );
        final resUnlock = await CCCommandsProcessor.instance.procesarComando(
          unlockCmd,
        );
        expect(resUnlock.exito, isTrue);

        final isLockedAfterUnlock = await CCCommandsProcessor.instance
            .verificarInstalacionBloqueada();
        expect(isLockedAfterUnlock, isFalse);
      },
    );
  });
}

ComandoRemoto _signedRemoteCommand({
  required String id,
  required TipoComando tipo,
  required Map<String, dynamic> parametros,
  required String installationId,
  required String secret,
  required String nonce,
}) {
  final timestamp = DateTime.now().toUtc();
  final expiresAt = timestamp.add(const Duration(minutes: 5));
  final timestampRaw = timestamp.toIso8601String();
  final expiresAtRaw = expiresAt.toIso8601String();
  final payload = jsonEncode(
    _stableCommandValue({
      'action': tipo.name,
      'expires_at': expiresAtRaw,
      'id': id,
      'installation_id': installationId,
      'nonce': nonce,
      'params': parametros,
      'timestamp': timestampRaw,
    }),
  );
  final signature = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();

  return ComandoRemoto(
    id: id,
    tipo: tipo,
    parametros: parametros,
    timestamp: timestamp,
    installationId: installationId,
    expiresAt: expiresAt,
    nonce: nonce,
    timestampRaw: timestampRaw,
    expiresAtRaw: expiresAtRaw,
    firmaHmac: signature,
  );
}

dynamic _stableCommandValue(dynamic value) {
  if (value is List) return value.map(_stableCommandValue).toList();
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _stableCommandValue(value[key]),
    };
  }
  return value;
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

Map<String, dynamic> _validPayload({
  required String fingerprint,
  DateTime? expiry,
}) {
  final issuedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'token_type': 'license',
    'hfp': fingerprint,
    'lt': 'SUSCRIPCION',
    'st': 'ACTIVO',
    'ed': (expiry ?? DateTime.now().add(const Duration(days: 30)))
        .toUtc()
        .toIso8601String(),
    'md': ['ventas', 'contabilidad', 'inventario'],
    'pf': 'COMMERCIAL',
    'installation_id': 'INST-999',
    'iat': issuedAt,
    'exp': issuedAt + const Duration(days: 30).inSeconds,
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

String _encodeBase64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
